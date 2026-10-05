import SwiftUI
import AVFoundation

private final class AnalysisPipeline {
    private let gate = DispatchSemaphore(value: 1)
    private let queue = DispatchQueue(label: "clean.tuner.pitch", qos: .userInitiated)
    private var history: [Float] = []
    private let suppressionLock = NSLock()
    private var suppressedUntil = -Double.infinity
    func suppress(until: Double) {
        suppressionLock.lock(); suppressedUntil = max(suppressedUntil, until); suppressionLock.unlock()
    }
    private var suppressed: Bool {
        suppressionLock.lock(); defer { suppressionLock.unlock() }
        return ProcessInfo.processInfo.systemUptime < suppressedUntil
    }
    private var expectedFrame: AVAudioFramePosition?
    private var tailFrequency: Double?
    private var tailFrame: AVAudioFramePosition?
    func submit(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime, completion: @escaping (PitchReading?, Double, [Double]) -> Void) {
        guard let channel = buffer.floatChannelData?[0], gate.wait(timeout: .now()) == .success else { return }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let rate = buffer.format.sampleRate, frame = time.sampleTime
        queue.async { [self] in
            defer { gate.signal() }
            // Never concatenate non-contiguous audio if the analysis queue fell behind.
            if let expectedFrame, expectedFrame != frame { history.removeAll(keepingCapacity: true); tailFrequency = nil; tailFrame = nil }
            expectedFrame = frame + AVAudioFramePosition(samples.count)
            history.append(contentsOf: samples)
            let windowSize = max(8192, Int(ceil(rate * 0.18)))
            if history.count > windowSize { history.removeFirst(history.count - windowSize) }
            let rms = sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, samples.count)))
            if suppressed {
                history.removeAll(keepingCapacity: true); tailFrequency = nil; tailFrame = nil
            }
            let trackingTail = tailFrame.map { Double(frame - $0) / rate < 0.8 } ?? false
            let threshold = trackingTail ? 0.0008 : 0.003
            var reading = rms >= threshold && history.count >= windowSize ? PitchDetector().detect(history, rate: rate, minimumRMS: threshold) : nil
            // Weak input can continue an established note, but cannot acquire a new
            // pitch from background noise at the lower sustain threshold.
            if rms < 0.003, let value = reading {
                if let prior = tailFrequency, abs(1200 * log2(value.frequency / prior)) <= 45 { }
                else { reading = nil }
            }
            if let reading { tailFrequency = reading.frequency; tailFrame = frame }
            // Short real PCM slices retain texture that whole-buffer RMS averages away.
            let envelope = (0..<9).map { index -> Double in
                let start = samples.count * index / 9, end = samples.count * (index + 1) / 9
                return sqrt(samples[start..<end].reduce(0.0) { $0 + Double($1 * $1) } / Double(max(1, end - start)))
            }
            completion(reading, rms, envelope)
        }
    }
}

/// All audio hardware setup/teardown is serialized off the UI thread. In
/// particular, RemoteIO initialization must not block the main run loop.
private final class AudioDriver {
    private let queue = DispatchQueue(label: "clean.tuner.hardware", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var pipeline: AnalysisPipeline?
    func suppressInput(until: Double) { queue.async { self.pipeline?.suppress(until: until) } }
    private func tearDown() {
        engine?.stop(); engine = nil; pipeline = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func stop() { queue.async { self.tearDown() } }
    func listen(receive: @escaping (PitchReading?, Double, [Double]) -> Void, completion: @escaping (String?) -> Void) {
        queue.async {
            self.tearDown()
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
                try session.setPreferredSampleRate(48000)
                try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
                try session.setActive(true)
                let engine = AVAudioEngine()
                self.engine = engine
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else {
                    throw NSError(domain: "No audio input", code: 1)
                }
                let pipeline = AnalysisPipeline()
                self.pipeline = pipeline
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
        didSet { resetProgress(); feedback.reset(); inTune = false; UserDefaults.standard.set(reference, forKey: "reference"); recalculate(); if tone { playTone() } }
    }
    @Published private(set) var instrument: Instrument = .guitar
    @Published private(set) var customTunings: [String: [Tuning]] = [:]
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
    @Published private(set) var visualCents: Double = 0
    @Published private(set) var isHeld = false
    @Published private(set) var inTune = false
    @Published private(set) var successCount = 0
    @Published private(set) var progress = StringTuningProgress()
    @Published private(set) var lastCompletedIndex: Int?
    @Published var successSoundEnabled = UserDefaults.standard.object(forKey: "success-sound") as? Bool ?? true {
        didSet { UserDefaults.standard.set(successSoundEnabled, forKey: "success-sound") }
    }
    var allStringsTuned: Bool { !notes.isEmpty && progress.completed.count == notes.count }
    func resetProgress() { progress.reset(); lastCompletedIndex = nil }
    private let successSound = SuccessSound()
    private var feedbackMutedUntil = -Double.infinity
    private var feedback = TuningFeedback()
    @Published var chromaticResponse = ChromaticResponse(rawValue: UserDefaults.standard.string(forKey: "chromatic-response") ?? "voice") ?? .voice {
        didSet {
            UserDefaults.standard.set(chromaticResponse.rawValue, forKey: "chromatic-response")
            feedback.reset(); inTune = false; recalculate()
        }
    }
    private var visualTime: Double = 0
    @Published private(set) var level = 0.0
    @Published private(set) var inputEnvelope = Array(repeating: 0.0, count: 9)
    @Published var error: String?
    @Published var permissionDenied = false
    private let audio = AudioDriver()
    private var generation = UUID()
    private var lastGood = -Double.infinity
    private var recent: [Double] = []
    private var observers: [NSObjectProtocol] = []
    private var resumeState = AudioResumeState()
    private var appeared = false
    private(set) var demo = false
    private var signalFixture = false
    private var feedbackFixture = false
    private var fixtureTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: "custom-tunings-v1"),
           let decoded = try? JSONDecoder().decode([String: [Tuning]].self, from: data) {
            customTunings = decoded.mapValues { values in
                var ids = Set<String>()
                return values.filter { $0.isCustom && $0.isValid && ids.insert($0.id).inserted }
            }
        }
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
            customTunings = [:]
            UserDefaults.standard.removeObject(forKey: "custom-tunings-v1")
            UserDefaults.standard.set(instrument.rawValue, forKey: "instrument")
            UserDefaults.standard.removeObject(forKey: "show-cents")
            successSoundEnabled = true
            chromaticResponse = .voice
            for value in Instrument.allCases { UserDefaults.standard.removeObject(forKey: "tuning-\(value.rawValue)") }
        }
        if args.contains("--preview") {
            demo = true
            if let index = args.firstIndex(of: "--instrument"), index + 1 < args.count,
               let value = Instrument(rawValue: args[index + 1]) {
                instrument = value; tuningID = value.tunings.first?.id ?? "standard"
            }
            if args.contains("--ukulele") { instrument = .ukulele; tuningID = "high-g" }
            if args.contains("--chromatic") { instrument = .chromatic }
            let target = args.firstIndex(of: "--midi").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? (instrument == .ukulele ? 60 : instrument == .chromatic ? 69 : 45)
            let previewCents = args.firstIndex(of: "--cents").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? (instrument == .ukulele ? 0 : -8)
            frequency = PitchMath.frequency(target) * pow(2, previewCents / 1200.0)
            recalculate()
        }
        if args.contains("--fine-response") { chromaticResponse = .fine }
        if args.contains("--completed"), instrument != .chromatic {
            for index in notes.indices { _ = progress.update(index: index, cents: 0, stable: true, now: 0) }
        }
        if args.contains("--silent") { demo = true; clearReading() }
        if args.contains("--denied") { demo = true; denied() }
        if args.contains("--voice-test") || args.contains("--progress-test") || args.contains("--signal-test") || args.contains("--feedback-test") || args.contains("--weak-input") || args.contains("--noise-floor") {
            demo = true; signalFixture = true; feedbackFixture = args.contains("--feedback-test"); clearReading()
        }
        #endif
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    var availableTunings: [Tuning] { instrument.tunings + (customTunings[instrument.rawValue] ?? []) }
    var tuning: Tuning? { availableTunings.first(where: { $0.id == tuningID }) ?? availableTunings.first }
    func saveCustom(id: String?, name: String, notes: [Int]) {
        guard instrument != .chromatic else { return }
        let item = Tuning(id: id ?? "custom-" + UUID().uuidString,
                          name: name.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes)
        guard item.isValid, item.isCustom else { return }
        var list = customTunings[instrument.rawValue] ?? []
        if let index = list.firstIndex(where: { $0.id == item.id }) { list[index] = item }
        else { list.append(item) }
        customTunings[instrument.rawValue] = list
        persistCustom()
        selectTuning(item)
    }
    func deleteCustom(_ id: String) {
        customTunings[instrument.rawValue]?.removeAll { $0.id == id }
        persistCustom()
        if tuningID == id, let first = instrument.tunings.first { selectTuning(first) }
    }
    private func persistCustom() {
        if let data = try? JSONEncoder().encode(customTunings) { UserDefaults.standard.set(data, forKey: "custom-tunings-v1") }
    }
    var notes: [Int] { tuning?.notes ?? [] }
    var displayNote: Int? { lockedPitch ?? lockedIndex.flatMap { notes.indices.contains($0) ? notes[$0] : nil } ?? note }
    var status: String {
        if tone { return "REFERENCE TONE" }
        guard frequency != nil else { return "PLAY A NOTE" }
        if isHeld { return "LAST READING" }
        if inTune { return "IN TUNE" }
        if abs(cents) <= 3 { return "SETTLING" }
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
        resetProgress()
        feedback.reset(); inTune = false
        if isHeld { clearReading() }
        lockedIndex = nil; lockedPitch = nil; selectedIndex = nil; note = nil
        instrument = value
        tuningID = UserDefaults.standard.string(forKey: "tuning-\(value.rawValue)") ?? value.tunings.first?.id ?? ""
        lockedIndex = nil; selectedIndex = nil; note = nil
        UserDefaults.standard.set(value.rawValue, forKey: "instrument")
        recalculate()
    }
    func selectTuning(_ value: Tuning) {
        guard availableTunings.contains(value) else { return }
        resetProgress()
        feedback.reset(); inTune = false
        if isHeld { clearReading() }
        tuningID = value.id; lockedIndex = nil; selectedIndex = nil; note = nil
        UserDefaults.standard.set(value.id, forKey: "tuning-\(instrument.rawValue)")
        recalculate()
    }
    func selectString(_ index: Int) {
        feedback.reset(); inTune = false
        guard notes.indices.contains(index) else { return }
        lockedIndex = lockedIndex == index ? nil : index
        recalculate()
    }
    func automatic() { feedback.reset(); inTune = false; lockedIndex = nil; lockedPitch = nil; recalculate() }
    func holdPitch() {
        feedback.reset(); inTune = false
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
        let feedbackScenario = feedbackFixture
        let weakInput = ProcessInfo.processInfo.arguments.contains("--weak-input")
        let noiseFloor = ProcessInfo.processInfo.arguments.contains("--noise-floor")
        fixtureTask = Task { [weak self] in
            let rate = 48000.0, count = 2048
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            let hz = 110.0 * pow(2, -8.0 / 1200)
            let progressScenario = ProcessInfo.processInfo.arguments.contains("--progress-test")
            for frame in 0..<(progressScenario ? 360 : feedbackScenario ? 490 : 250) {
                guard !Task.isCancelled else { return }
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
                buffer.frameLength = AVAudioFrameCount(count)
                if ProcessInfo.processInfo.arguments.contains("--voice-test") {
                    Self.fillVoiceFixture(buffer, frame: frame)
                } else if progressScenario {
                    let guitarNotes = [40,45,50,55,59,64]
                    let target = frame < 210 ? guitarNotes[min(5, frame / 35)] : 40
                    let gain = frame >= 210 && frame < 245 ? 0.0 : 1.0
                    let offset = frame >= 245 && frame < 300 ? 12.0 : 0.0
                    Self.fillFixture(buffer, frame: frame, frequency: PitchMath.frequency(target) * pow(2, offset / 1200), gain: gain)
                } else if feedbackScenario {
                    let value = frame < 320 ? 110.0 : PitchMath.frequency(50)
                    let gain: Double = frame < 160 ? 1 : frame < 280 ? 0.006 : frame < 320 ? 0 : frame < 390 ? 1 : 0
                    Self.fillFixture(buffer, frame: frame, frequency: value, gain: gain)
                } else {
                    Self.fillFixture(buffer, frame: frame, frequency: hz, gain: frame < 140 ? (noiseFloor ? 0.00008 : weakInput ? 0.0008 : 1) : 0)
                }
                pipeline.submit(buffer, at: AVAudioTime(sampleTime: AVAudioFramePosition(frame * count), atRate: rate)) { [weak self] reading, rms, envelope in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        self.receive(reading, rms: rms, envelope: envelope)
                    }
                }
                try? await Task.sleep(for: .milliseconds(43))
            }
        }
    }
    private static func fillVoiceFixture(_ buffer: AVAudioPCMBuffer, frame: Int) {
        let count = Int(buffer.frameLength)
        let depth = pow(2.0, 12.0 / 1200.0) - 1.0
        for i in 0..<count {
            let time = Double(frame * count + i) / 48000.0
            let carrier = 2.0 * Double.pi * 440.0 * time
            let modulation = 440.0 * depth / 2.0 * (1.0 - cos(4.0 * Double.pi * time))
            let phase = carrier + modulation
            let value = 0.15 * sin(phase) + 0.08 * sin(phase * 2.0)
            buffer.floatChannelData![0][i] = Float(value)
        }
    }
    private static func fillFixture(_ buffer: AVAudioPCMBuffer, frame: Int, frequency: Double, gain: Double) {
        let count = Int(buffer.frameLength)
        for i in 0..<count {
            let time = Double(frame * count + i) / 48000.0
            let phase = 2.0 * Double.pi * frequency * time
            let fundamental = 0.15 * sin(phase)
            let second = 0.25 * sin(phase * 2.0)
            let third = 0.1 * sin(phase * 3.0)
            buffer.floatChannelData![0][i] = Float((fundamental + second + third) * gain)
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
        audio.listen(receive: { [weak self] reading, rms, envelope in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.listening else { return }
                self.receive(reading, rms: rms, envelope: envelope)
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
    private func receive(_ reading: PitchReading?, rms: Double, envelope: [Double]) {
        // Absolute input level only: quiet noise must remain visually quiet.
        func magnitude(_ amplitude: Double) -> Double {
            guard amplitude.isFinite, amplitude > 0 else { return 0 }
            let normalized = min(1, max(0, (20 * log10(amplitude) + 85) / 70))
            return pow(normalized, 1.3)
        }
        let target = magnitude(rms)
        level += (target - level) * (target > level ? 0.35 : 0.18)
        if level < 0.002 { level = 0 }
        inputEnvelope = envelope.enumerated().map { index, amplitude in
            let target = magnitude(amplitude)
            let previous = inputEnvelope.indices.contains(index) ? inputEnvelope[index] : 0
            let value = previous + (target - previous) * (target > previous ? 0.35 : 0.18)
            return value < 0.002 ? 0 : value
        }
        let now = ProcessInfo.processInfo.systemUptime
        if now < feedbackMutedUntil {
            recent.removeAll(); lastGood = now
            return
        }
        guard let reading else {
            progress.gap()
            feedback.gap()
            switch ReadingAge.state(elapsed: now - lastGood) {
            case .expired: clearReading()
            case .held: if frequency != nil { isHeld = true }
            case .live: break
            }
            return
        }
        let returning = isHeld
        if now - lastGood > 0.2 { recent.removeAll() }
        lastGood = now; isHeld = false
        if let previous = recent.last, abs(1200 * log2(reading.frequency / previous)) > 70 { recent.removeAll() }
        recent.append(reading.frequency)
        if recent.count > 3 { recent.removeFirst() }
        let previousNote = note
        frequency = recent.sorted()[recent.count / 2]
        recalculate(preserveVisual: true)
        if previousNote != note || returning { visualCents = cents }
        else {
            let timeConstant = instrument == .chromatic ? chromaticResponse.smoothingTime : 0.09
            let alpha = 1 - exp(-max(0, now - visualTime) / timeConstant)
            visualCents += alpha * (cents - visualCents)
        }
        visualTime = now
        if let note {
            let rewarded: Bool
            if instrument == .chromatic {
                // Voice feedback evaluates the displayed short-term average, but
                // substantial instantaneous drift still breaks the green state.
                let evaluated = chromaticResponse == .voice && abs(cents) <= 20 ? visualCents : cents
                rewarded = feedback.update(cents: evaluated, target: note, now: now,
                                           tolerance: chromaticResponse.tolerance,
                                           releaseTolerance: chromaticResponse.releaseTolerance,
                                           settlingTime: chromaticResponse.settlingTime)
            } else {
                rewarded = feedback.update(cents: cents, target: note, now: now)
            }
            inTune = feedback.inTune
            if instrument == .chromatic {
                if rewarded { successCount += 1 }
            } else if let index = selectedIndex,
                      progress.update(index: index, cents: cents, stable: inTune, now: now) {
                lastCompletedIndex = index
                successCount += 1
                playSuccessSound(now: now)
            }
        }
    }
    private func playSuccessSound(now: Double) {
        guard successSoundEnabled, !demo, !tone, listening else { return }
        let token = generation
        // Covers playback, room decay and a fresh 180 ms analysis window.
        feedbackMutedUntil = now + (allStringsTuned ? 0.9 : 0.75)
        audio.suppressInput(until: feedbackMutedUntil)
        let played = successSound.play(complete: allStringsTuned) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.feedbackMutedUntil = max(self.feedbackMutedUntil, ProcessInfo.processInfo.systemUptime + 0.45)
                self.audio.suppressInput(until: self.feedbackMutedUntil)
            }
        }
        if !played { feedbackMutedUntil = now }
    }

    private func recalculate(preserveVisual: Bool = false) {
        selectedIndex = lockedIndex
        guard let frequency else { note = nil; cents = 0; visualCents = 0; return }
        note = PitchMath.target(frequency: frequency, reference: reference, notes: notes,
                                locked: lockedPitch ?? lockedIndex.map { notes[$0] }, previous: note)
        selectedIndex = lockedIndex ?? notes.firstIndex(of: note!)
        cents = PitchMath.cents(frequency, target: note!, reference: reference)
        if !preserveVisual { visualCents = cents }
        if demo && !signalFixture { inTune = abs(cents) <= (instrument == .chromatic ? chromaticResponse.tolerance : 3) }
    }
    private func clearReading() {
        frequency = nil; note = nil; cents = 0; visualCents = 0; recent.removeAll()
        isHeld = false; inTune = false; feedback.reset()
        selectedIndex = lockedIndex
    }
    func stop(preserveResume: Bool = false) {
        if !preserveResume { resumeState.pause() }
        generation = UUID()
        fixtureTask?.cancel(); fixtureTask = nil
        if !demo || tone { audio.stop() }
        listening = false; requesting = false; tone = false; level = 0
        feedbackMutedUntil = -Double.infinity
        progress.gap()
        inputEnvelope = Array(repeating: 0, count: 9)
        clearReading()
        UIApplication.shared.isIdleTimerDisabled = false
    }
    func toggleTone() {
        if tone {
            let resume = resumeState.finishTone()
            stop()
            if resume { start() }
        } else { playTone() }
    }
    private func playTone() {
        resumeState.beginTone(active: listening || requesting)
        stop(preserveResume: true)
        let token = generation
        tone = true
        audio.reference(reference) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if let error { self.tone = false; self.error = error }
            }
        }
    }
    func background() {
        resumeState.suspend(active: listening || requesting)
        stop(preserveResume: true)
    }
    func foreground() {
        guard !demo, UIApplication.shared.applicationState == .active else { return }
        if resumeState.resume(isActive: UIApplication.shared.applicationState == .active) { start() }
        else if permissionDenied && AVAudioApplication.shared.recordPermission == .granted { error = nil; start() }
    }
    private func audioChanged(_ notification: Notification) {
        if notification.name == AVAudioSession.interruptionNotification {
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue {
                resumeState.interrupted = true
                background()
            } else {
                let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                resumeState.endInterruption(shouldResume: AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume))
                foreground()
            }
        } else if notification.name == AVAudioSession.routeChangeNotification,
                  (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.categoryChange.rawValue {
            return
        } else if listening || requesting { stop(); start() }
        else if tone { stop() }
    }
}
