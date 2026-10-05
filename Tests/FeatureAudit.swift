import Foundation

@main struct FeatureAudit {
    static func main() {
        var failures = 0, cases = 0
        func check(_ pass: Bool, _ message: String) {
            cases += 1
            if !pass { failures += 1; print("FAIL: \(message)") }
        }
        let detector = PitchDetector()
        for rate in [8000.0, 16000, 44100, 48000, 96000, 192000] {
            for hz in [25.0, 26.25, 30.867706, 41.203445, 110, 440, 1460.471, 1500] {
                let count = max(8192, Int(rate * 0.18))
                let input = (0..<count).map { Float(0.2 * sin(2 * Double.pi * hz * Double($0) / rate)) }
                let reading = detector.detect(input, rate: rate)
                check(reading != nil, "range: \(hz) Hz at \(rate)")
                if let reading { check(abs(1200 * log2(reading.frequency / hz)) < 1, "accuracy: \(hz) at \(rate): \(reading.frequency)") }
            }
        }
        for rate in [8000.0, 16000, 44100, 48000, 96000, 192000] {
            for hz in [25.0, 26.25, 1460.471, 1500] {
                for phase in [0.3, 1.1, 2.7, 4.0] {
                    let input = (0..<max(8192, Int(rate * 0.18))).map {
                        Float(0.2 * sin(2 * Double.pi * hz * Double($0) / rate + phase))
                    }
                    let reading = detector.detect(input, rate: rate)
                    check(reading.map { abs(1200 * log2($0.frequency / hz)) < 1 } ?? false,
                          "boundary phase: \(hz), \(rate), \(phase)")
                }
            }
        }
        for instrument in Instrument.allCases {
            check(Set(instrument.tunings.map(\.id)).count == instrument.tunings.count, "unique preset IDs \(instrument)")
            for tuning in instrument.tunings {
                check(tuning.isValid, "valid preset \(instrument)/\(tuning.name)")
                for reference in [420.0, 440, 460] {
                    for note in tuning.notes {
                        let hz = PitchMath.frequency(note, reference: reference)
                        check((25...1500).contains(hz), "target within detector range")
                        check(abs(PitchMath.cents(hz, target: note, reference: reference)) < 1e-6, "reference semantics")
                    }
                }
            }
        }
        for (name, notes, valid) in [("", [40,45,50,55], false), ("   ", [40,45,50,55], false),
            (String(repeating: "x", count: 33), [40,45,50,55], false), ("Short", [40,45,50], false),
            ("Low", [20,45,50,55], false), ("High", [40,45,50,90], false),
            ("Unison", [40,40,40,40], true), ("Reentrant", [67,60,64,69], true),
            ("Range", [21,45,50,89], true)] {
            let item = Tuning(id: "custom-test", name: name, notes: notes)
            check(item.isValid == valid, "custom validity: \(name)")
            let data = try! JSONEncoder().encode(item)
            check(try! JSONDecoder().decode(Tuning.self, from: data) == item, "custom roundtrip")
        }
        check(Instrument.allCases.flatMap(\.tunings).count == 52, "catalogue count")
        check(Instrument.bass.tunings[1].notes == [23,28,33,38,43], "bass BEADG octaves")
        check(Instrument.banjo.tunings[0].notes == [67,50,55,59,62], "banjo short drone gDGBD")
        check(Instrument.cello.tunings[1].notes == [36,43,50,55], "Bach fifth suite CGDG")
        // Invalid buffers must fail quietly, including a short high-rate window.
        for rate in [Double.nan, Double.infinity, 0, 7999, 192001] {
            check(detector.detect([Float](repeating: 0.1, count: 2048), rate: rate) == nil, "invalid rate")
        }
        for count in [0, 1024, 2047, 2048, 2049] {
            let samples = (0..<count).map { Float(sin(Double($0) * 0.4)) }
            _ = detector.detect(samples, rate: 192000)
            check(true, "short buffer does not trap")
        }
        check(detector.detect([Float](repeating: .nan, count: 8192), rate: 48000) == nil, "NaN PCM rejected")
        check(detector.detect([Float](repeating: 0.2, count: 8192), rate: 48000) == nil, "DC rejected")
        check(detector.detect([Float](repeating: 0, count: 8192), rate: 48000) == nil, "silence rejected")
        // Moving nearer must never reverse the proximity cue or depend on direction.
        var previous = -1.0
        for cents in stride(from: 150.0, through: 0, by: -0.5) {
            let value = TuningProximity.closeness(cents)
            check(value >= previous && (0...1).contains(value), "monotonic proximity")
            check(value == TuningProximity.closeness(-cents), "symmetric proximity")
            previous = value
        }
        check(TuningProximity.closeness(.nan) == 0, "invalid proximity")
        var intent = AudioResumeState()
        intent.interrupted = true; intent.suspend(active: true)
        intent.suspend(active: false) // Background follows interruption.
        check(!intent.resume(isActive: true), "cannot restart during interruption")
        intent.endInterruption(shouldResume: true)
        check(!intent.resume(isActive: false), "cannot restart in background")
        check(intent.resume(isActive: true), "resume original listening intent")
        check(!intent.resume(isActive: true), "resume only once")
        intent.suspend(active: true); intent.pause()
        check(!intent.resume(isActive: true), "explicit pause cancels pending restart")
        intent.suspend(active: true); intent.endInterruption(shouldResume: false)
        check(!intent.resume(isActive: true), "respect interruption no-resume")
        intent.beginTone(active: false)
        check(!intent.finishTone(), "tone does not unpause mic")
        intent.beginTone(active: true); intent.beginTone(active: false)
        check(intent.finishTone(), "calibration preserves pre-tone mic intent")
        intent.beginTone(active: true); intent.suspend(active: false)
        check(intent.resume(isActive: true), "tone background restores mic, never tone")
        var voiceFeedback = TuningFeedback(), fineFeedback = TuningFeedback()
        for frame in 0..<50 {
            let cents = frame % 2 == 0 ? 6.0 : -6.0
            let now = Double(frame) * 0.043
            _ = voiceFeedback.update(cents: cents, target: 69, now: now, tolerance: 8, releaseTolerance: 12, settlingTime: 0.35)
            _ = fineFeedback.update(cents: cents, target: 69, now: now)
        }
        check(voiceFeedback.inTune, "voice tolerance accepts modest variation")
        check(!fineFeedback.inTune, "fine feedback retains strict tolerance")
        _ = voiceFeedback.update(cents: 25, target: 69, now: 3, tolerance: 8, releaseTolerance: 12, settlingTime: 0.35)
        check(!voiceFeedback.inTune, "voice still rejects clear pitch error")
        _ = voiceFeedback.update(cents: 0, target: 70, now: 4, tolerance: 8, releaseTolerance: 12, settlingTime: 0.35)
        check(!voiceFeedback.inTune, "changing note requalifies voice feedback")
        var progress = StringTuningProgress()
        check(!progress.update(index: 0, cents: 0, stable: false, now: 0), "single sample cannot complete string")
        for index in 0..<6 {
            check(progress.update(index: index, cents: 1, stable: true, now: Double(index)), "new qualified string rewards once")
            check(!progress.update(index: index, cents: 0, stable: true, now: Double(index) + 0.1), "sustain never repeats reward")
        }
        check(progress.completed.count == 6, "all strings remembered")
        _ = progress.update(index: 0, cents: 12, stable: false, now: 7)
        _ = progress.update(index: 1, cents: 0, stable: true, now: 8)
        _ = progress.update(index: 0, cents: 12, stable: false, now: 9)
        check(progress.completed.contains(0), "switching strings breaks invalidation streak")
        progress.gap()
        _ = progress.update(index: 0, cents: 12, stable: false, now: 10)
        _ = progress.update(index: 0, cents: 12, stable: false, now: 10.4)
        check(progress.completed.contains(0), "brief deviation keeps mark")
        progress.gap()
        _ = progress.update(index: 0, cents: 12, stable: false, now: 12)
        check(progress.completed.contains(0), "silence breaks invalidation streak")
        _ = progress.update(index: 0, cents: 12, stable: false, now: 12.6)
        check(!progress.completed.contains(0), "sustained drift clears only that mark")
        check(progress.completed.count == 5, "other marks retained")
        check(progress.update(index: 0, cents: 0, stable: true, now: 13), "retuning rewards again")
        _ = progress.update(index: 0, cents: 700, stable: false, now: 14)
        _ = progress.update(index: 0, cents: 700, stable: false, now: 15)
        check(progress.completed.contains(0), "different note does not clear locked string")
        progress.reset()
        check(progress.completed.isEmpty, "progress resets")
        print("Feature data and DSP audit: \(cases) assertions; \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
