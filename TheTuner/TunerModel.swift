import SwiftUI
import AVFoundation

private final class AnalysisPipeline {
    private let gate = DispatchSemaphore(value: 1)
    private let queue = DispatchQueue(label: "clean.tuner.pitch", qos: .userInitiated)
    private var history: [Float] = []
    private var expectedFrame: AVAudioFramePosition?
    func submit(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime, completion: @escaping (PitchReading?, Double) -> Void) {
        guard let channel = buffer.floatChannelData?[0], gate.wait(timeout: .now()) == .success else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let rate = buffer.format.sampleRate, frame = time.sampleTime
        queue.async { [self] in
            defer { gate.signal() }
            // Never concatenate non-contiguous audio if the analysis queue fell behind.
            if let expectedFrame, expectedFrame != frame { history.removeAll(keepingCapacity: true) }
            expectedFrame = frame + AVAudioFramePosition(samples.count)
            history.append(contentsOf: samples)
            if history.count > 8192 { history.removeFirst(history.count - 8192) }
            let rms = sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, samples.count)))
            let reading = rms >= 0.003 && history.count >= 8192 ? PitchDetector().detect(history, rate: rate) : nil
            completion(reading, rms)
        }
    }
}

/// All audio hardware setup/teardown is serialized off the UI thread. In
/// particular, RemoteIO initialization must not block the main run loop.
private final class AudioDriver {
    private let queue = DispatchQueue(label: "clean.tuner.hardware", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private func tearDown() {
        engine?.stop(); engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func stop() { queue.async { self.tearDown() } }
    func listen(receive: @escaping (PitchReading?, Double) -> Void, completion: @escaping (String?) -> Void) {
        queue.async {
            self.tearDown()
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
                try session.setPreferredSampleRate(48000)
                try session.setActive(true)
                let engine = AVAudioEngine()
                self.engine = engine
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else {
                    throw NSError(domain: "No audio input", code: 1)
                }
                let pipeline = AnalysisPipeline()
                input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, time in
                    pipeline.submit(buffer, at: time, completion: receive)
                }
                try engine.start()
                completion(nil)
            } catch {
                self.tearDown()
                completion("Audio input could not start. Check the microphone connection and choose Retry.")
            }
        }
    }
    func reference(_ hz: Double, completion: @escaping (String?) -> Void) {
        queue.async {
            self.tearDown()
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                let next = AVAudioEngine()
                self.engine = next
                let rate = session.sampleRate
                guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
                    throw NSError(domain: "No audio output", code: 1)
                }
                var phase = 0.0, elapsed = 0
                let source = AVAudioSourceNode { _, _, frames, list -> OSStatus in
                    let buffers = UnsafeMutableAudioBufferListPointer(list)
                    for frame in 0..<Int(frames) {
                        let fade = min(1.0, Double(elapsed) / (rate * 0.02))
                        let value = Float(sin(phase) * 0.12 * fade)
                        for buffer in buffers { buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value }
                        phase += 2 * .pi * hz / rate
                        if phase >= 2 * .pi { phase -= 2 * .pi }
                        elapsed += 1
                    }
                    return noErr
                }
                next.attach(source)
                next.connect(source, to: next.mainMixerNode, format: format)
                try next.start()
                completion(nil)
            } catch {
                self.tearDown()
                completion("Reference tone could not start. Check audio output and retry.")
            }
        }
    }
}

@MainActor final class TunerModel: ObservableObject {
    @Published var reference: Double = 440 {
        didSet { UserDefaults.standard.set(reference, forKey: "reference"); recalculate(); if tone { playTone() } }
    }
    @Published private(set) var instrument: Instrument = .guitar
    @Published private(set) var tuningID = "standard"
    @Published private(set) var lockedIndex: Int?
    @Published private(set) var selectedIndex: Int?
    @Published private(set) var lockedPitch: Int?
    @Published private(set) var listening = false
    @Published private(set) var requesting = false
    @Published private(set) var tone = false
    @Published private(set) var frequency: Double?
    @Published private(set) var note: Int?
    @Published private(set) var cents: Double = 0
    @Published private(set) var level = 0.0
    @Published var error: String?
    @Published var permissionDenied = false
    private let audio = AudioDriver()
    private var generation = UUID()
    private var lastGood = Date.distantPast
    private var recent: [Double] = []
    private var observers: [NSObjectProtocol] = []
    private var resumeListening = false
    private var appeared = false
    private(set) var demo = false
    private var signalFixture = false
    private var fixtureTask: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.double(forKey: "reference")
        reference = saved.isFinite && (420...460).contains(saved) ? saved : 440
        instrument = Instrument(rawValue: UserDefaults.standard.string(forKey: "instrument") ?? "") ?? .guitar
        tuningID = UserDefaults.standard.string(forKey: "tuning-\(instrument.rawValue)") ?? instrument.tunings.first?.id ?? ""
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor [weak self] in self?.audioChanged(notification) }
            })
        }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--reset") {
            instrument = .guitar; tuningID = "standard"; reference = 440
            for value in Instrument.allCases { UserDefaults.standard.removeObject(forKey: "tuning-\(value.rawValue)") }
        }
        if args.contains("--preview") {
            demo = true
            if args.contains("--ukulele") { instrument = .ukulele; tuningID = "high-g" }
            if args.contains("--chromatic") { instrument = .chromatic }
            let target = instrument == .ukulele ? 60 : instrument == .chromatic ? 69 : 45
            frequency = PitchMath.frequency(target) * pow(2, (instrument == .ukulele ? 0 : -8) / 1200.0)
            recalculate()
        }
        if args.contains("--silent") { demo = true; clearReading() }
        if args.contains("--denied") { demo = true; denied() }
        if args.contains("--signal-test") { demo = true; signalFixture = true; clearReading() }
        #endif
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    var tuning: Tuning? { instrument.tunings.first(where: { $0.id == tuningID }) ?? instrument.tunings.first }
    var notes: [Int] { tuning?.notes ?? [] }
    var displayNote: Int? { lockedPitch ?? lockedIndex.flatMap { notes.indices.contains($0) ? notes[$0] : nil } ?? note }
    var status: String {
        if tone { return "REFERENCE TONE" }
        guard frequency != nil else { return "PLAY A NOTE" }
        if abs(cents) <= 3 { return "IN TUNE" }
        return cents < 0 ? "FLAT" : "SHARP"
    }
    var inputStatus: String {
        if signalFixture { return "TEST INPUT" }
        if demo { return "PREVIEW" }
        if tone { return "REFERENCE TONE" }
        if requesting { return "MICROPHONE ACCESS" }
        if permissionDenied { return "MICROPHONE OFF" }
        return listening ? "LISTENING" : "PAUSED"
    }
    func selectInstrument(_ value: Instrument) {
        lockedIndex = nil; lockedPitch = nil; selectedIndex = nil; note = nil
        instrument = value
        tuningID = UserDefaults.standard.string(forKey: "tuning-\(value.rawValue)") ?? value.tunings.first?.id ?? ""
        lockedIndex = nil; selectedIndex = nil; note = nil
        UserDefaults.standard.set(value.rawValue, forKey: "instrument")
        recalculate()
    }
    func selectTuning(_ value: Tuning) {
        guard instrument.tunings.contains(value) else { return }
        tuningID = value.id; lockedIndex = nil; selectedIndex = nil; note = nil
        UserDefaults.standard.set(value.id, forKey: "tuning-\(instrument.rawValue)")
        recalculate()
    }
    func selectString(_ index: Int) {
        guard notes.indices.contains(index) else { return }
        lockedIndex = lockedIndex == index ? nil : index
        recalculate()
    }
    func automatic() { lockedIndex = nil; lockedPitch = nil; recalculate() }
    func holdPitch() {
        guard instrument == .chromatic else { return }
        lockedPitch = lockedPitch == nil ? note : nil
        recalculate()
    }
    func calibrate(_ delta: Double) { reference = min(460, max(420, reference + delta)) }
    func begin() {
        guard !appeared else { return }
        appeared = true
        if !demo { start() }
        #if DEBUG
        if signalFixture { runSignalFixture() }
        #endif
    }
    #if DEBUG
    /// Integration fixture goes through the same PCM pipeline as the microphone.
    /// It never plays sound, requests microphone access, or ships in Release.
    private func runSignalFixture() {
        let pipeline = AnalysisPipeline(), token = generation
        fixtureTask = Task { [weak self] in
            let rate = 48000.0, count = 2048
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            let hz = 110.0 * pow(2, -8.0 / 1200)
            for frame in 0..<200 {
                guard !Task.isCancelled else { return }
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
                buffer.frameLength = AVAudioFrameCount(count)
                Self.fillFixture(buffer, frame: frame, frequency: hz)
                pipeline.submit(buffer, at: AVAudioTime(sampleTime: AVAudioFramePosition(frame * count), atRate: rate)) { [weak self] reading, rms in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        self.receive(reading, rms: rms)
                    }
                }
                try? await Task.sleep(for: .milliseconds(43))
            }
        }
    }
    private static func fillFixture(_ buffer: AVAudioPCMBuffer, frame: Int, frequency: Double) {
        let count = Int(buffer.frameLength)
        for i in 0..<count {
            let time = Double(frame * count + i) / 48000.0
            let phase = 2.0 * Double.pi * frequency * time
            let fundamental = 0.15 * sin(phase)
            let second = 0.25 * sin(phase * 2.0)
            let third = 0.1 * sin(phase * 3.0)
            buffer.floatChannelData![0][i] = frame < 140 ? Float(fundamental + second + third) : 0
        }
    }
    #endif
    func start() {
        guard !listening, !requesting, !demo else { return }
        stop()
        permissionDenied = false
        switch AVAudioApplication.shared.recordPermission {
        case .granted: startListening()
        case .denied: denied()
        default:
            requesting = true
            let token = generation
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.requesting = false
                    if granted { self.startListening() } else { self.denied() }
                }
            }
        }
    }
    private func denied() {
        permissionDenied = true
        error = "Allow microphone access in iOS Settings to tune. Audio is analyzed on this device and is never recorded."
    }
    private func startListening() {
        requesting = true
        let token = generation
        audio.listen(receive: { [weak self] reading, rms in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.listening else { return }
                self.receive(reading, rms: rms)
            }
        }, completion: { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.requesting = false
                self.listening = error == nil
                self.error = error
                UIApplication.shared.isIdleTimerDisabled = error == nil
            }
        })
    }
    private func receive(_ reading: PitchReading?, rms: Double) {
        level = min(1, max(0, (20 * log10(max(rms, 0.00001)) + 60) / 50))
        guard let reading else {
            if Date().timeIntervalSince(lastGood) > 0.3 { clearReading() }
            return
        }
        lastGood = Date()
        if let previous = recent.last, abs(1200 * log2(reading.frequency / previous)) > 70 { recent.removeAll() }
        recent.append(reading.frequency)
        if recent.count > 3 { recent.removeFirst() }
        frequency = recent.sorted()[recent.count / 2]
        recalculate()
    }
    private func recalculate() {
        if let lockedIndex { selectedIndex = lockedIndex }
        guard let frequency else { note = nil; cents = 0; return }
        note = PitchMath.target(frequency: frequency, reference: reference, notes: notes,
                                locked: lockedPitch ?? lockedIndex.map { notes[$0] }, previous: note)
        selectedIndex = lockedIndex ?? notes.firstIndex(of: note!)
        cents = PitchMath.cents(frequency, target: note!, reference: reference)
    }
    private func clearReading() {
        frequency = nil; note = nil; cents = 0; recent.removeAll()
        selectedIndex = lockedIndex
    }
    func stop() {
        generation = UUID()
        fixtureTask?.cancel(); fixtureTask = nil
        if !demo || tone { audio.stop() }
        listening = false; requesting = false; tone = false; level = 0
        clearReading()
        UIApplication.shared.isIdleTimerDisabled = false
    }
    func toggleTone() { if tone { stop(); start() } else { playTone() } }
    private func playTone() {
        stop()
        let token = generation
        tone = true
        audio.reference(reference) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if let error { self.tone = false; self.error = error }
            }
        }
    }
    func background() { resumeListening = listening || requesting; stop() }
    func foreground() {
        guard !demo else { return }
        if resumeListening { resumeListening = false; start() }
        else if permissionDenied && AVAudioApplication.shared.recordPermission == .granted { error = nil; start() }
    }
    private func audioChanged(_ notification: Notification) {
        if notification.name == AVAudioSession.interruptionNotification {
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue { resumeListening = listening || requesting; stop() }
            else if let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                    AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { foreground() }
        } else if notification.name == AVAudioSession.routeChangeNotification,
                  (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.categoryChange.rawValue {
            return
        } else if listening { stop(); start() }
        else if tone { stop() }
    }
}
