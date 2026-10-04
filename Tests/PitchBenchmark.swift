import Foundation

@main struct Benchmark {
    static func main() {
        let detector = PitchDetector()
        var failures = 0, total = 0
        func check(_ condition: Bool, _ message: String) {
            if !condition { failures += 1; print("FAIL: \(message)") }
        }
        let started = Date()
        for kind in ["sine", "harmonic", "weak-fundamental", "decay", "noise-30dB"] {
            var errors: [Double] = []; var misses = 0
            for rate in [44100.0, 48000.0] {
                for midi in 21...89 {
                    for cents in [-30.0, 0.0, 30.0] {
                        let hz = PitchMath.frequency(midi) * pow(2, cents / 1200)
                        var rng: UInt64 = UInt64(midi + 1)
                        let input = (0..<8192).map { i -> Float in
                            let phase = 2 * Double.pi * hz * Double(i) / rate
                            let harmonic = 0.15*sin(phase)+0.25*sin(2*phase)+0.1*sin(3*phase)
                            switch kind {
                            case "harmonic": return Float(harmonic)
                            case "weak-fundamental": return Float(0.015*sin(phase)+0.3*sin(2*phase)+0.18*sin(3*phase))
                            case "decay": return Float(harmonic * exp(-Double(i)/rate * 5))
                            case "noise-30dB":
                                rng = rng &* 6364136223846793005 &+ 1
                                let noise = (Double(rng >> 11) / 9007199254740992.0 * 2 - 1) * 0.012
                                return Float(harmonic + noise)
                            default: return Float(0.3*sin(phase))
                            }
                        }
                        total += 1
                        if let reading = detector.detect(input, rate: rate) {
                            let error = abs(1200 * log2(reading.frequency / hz))
                            errors.append(error)
                            check(error < (kind == "decay" ? 1.0 : 0.5), "\(kind), MIDI \(midi), \(rate) Hz, error \(error) ct")
                        } else { misses += 1 }
                    }
                }
            }
            check(misses == 0, "\(kind) missed \(misses)")
            errors.sort()
            if !errors.isEmpty {
                print(String(format: "%@: 414 cases, %d misses; median %.5f ct, p95 %.5f ct, max %.5f ct", kind, misses, errors[errors.count/2], errors[Int(Double(errors.count-1)*0.95)], errors.last!))
            }
        }
        check(detector.detect([Float](repeating: 0, count: 8192), rate: 48000) == nil, "silence")
        check(detector.detect([Float](repeating: 0.2, count: 8192), rate: 48000) == nil, "DC")
        check(detector.detect([Float](repeating: .nan, count: 8192), rate: 48000) == nil, "NaN")
        check(detector.detect([1,2,3], rate: 48000) == nil, "short input")
        check(detector.detect([Float](repeating: 0.1, count: 8192), rate: 0) == nil, "invalid rate")
        var seed: UInt64 = 17
        let noise: [Float] = (0..<8192).map { _ in
            seed = seed &* 6364136223846793005 &+ 1
            return Float(Double(seed >> 11) / 9007199254740992.0 - 0.5)
        }
        check(detector.detect(noise, rate: 48000) == nil, "broadband noise rejection")
        for reference in [420.0, 432, 440, 442, 460] {
            for note in 21...89 {
                check(abs(PitchMath.midi(PitchMath.frequency(note, reference: reference), reference: reference) - Double(note)) < 1e-9, "calibration round trip")
            }
        }
        let highG = Instrument.ukulele.tunings[0].notes
        check(highG == [67,60,64,69], "reentrant high G physical ordering")
        check(PitchMath.target(frequency: PitchMath.frequency(67), reference: 440, notes: highG, locked: nil, previous: nil) == 67, "high G auto detection")
        check(PitchMath.target(frequency: 440, reference: 440, notes: [], locked: 60, previous: nil) == 60, "manual target stays locked")
        let edge = PitchMath.frequency(69) * pow(2, 52.0/1200)
        check(PitchMath.target(frequency: edge, reference: 440, notes: [], locked: nil, previous: 69) == 69, "boundary hysteresis")
        let crossed = PitchMath.frequency(69) * pow(2, 58.0/1200)
        check(PitchMath.target(frequency: crossed, reference: 440, notes: [], locked: nil, previous: 69) == 70, "confirmed new note")
        check(PitchMath.name(55) == "G" && PitchMath.label(60) == "C4", "note spelling")
        for instrument in Instrument.allCases {
            for tuning in instrument.tunings {
                check(tuning.isValid, "valid preset: \(instrument.rawValue) \(tuning.name)")
                for note in tuning.notes {
                    check(PitchMath.target(frequency: PitchMath.frequency(note), reference: 440, notes: tuning.notes, locked: nil, previous: nil) == note, "preset target \(tuning.name)")
                }
            }
        }
        var feedback = TuningFeedback()
        check(!feedback.update(cents: 0, target: 45, now: 0), "no reward on a transient")
        check(feedback.update(cents: 1, target: 45, now: 0.3), "reward after settling")
        check(!feedback.update(cents: 2, target: 45, now: 1), "no repeated reward on sustained note")
        check(!feedback.update(cents: 4, target: 45, now: 1.2) && feedback.inTune, "green hysteresis")
        check(!feedback.update(cents: 9, target: 45, now: 1.3) && !feedback.inTune, "out of tune exits green")
        _ = feedback.update(cents: 9, target: 45, now: 1.8)
        _ = feedback.update(cents: 0, target: 45, now: 2)
        check(feedback.update(cents: 0, target: 45, now: 2.3), "reward when deliberately retuned")
        _ = feedback.update(cents: 0, target: 50, now: 4)
        feedback.gap()
        check(!feedback.update(cents: 0, target: 50, now: 4.3), "gap interrupts qualification")
        check(feedback.update(cents: 0, target: 50, now: 4.6), "new string can succeed")
        check(ReadingAge.state(elapsed: 0.1) == .live, "short gap bridged")
        check(ReadingAge.state(elapsed: 1) == .held, "reading retained without zeroing")
        check(ReadingAge.state(elapsed: 3) == .expired, "stale reading eventually clears")
        let quiet: [Float] = (0..<8192).map { Float(0.002 * sin(2 * Double.pi * 110 * Double($0) / 48000)) }
        check(detector.detect(quiet, rate: 48000) == nil, "quiet input cannot acquire from silence")
        let tail = detector.detect(quiet, rate: 48000, minimumRMS: 0.0008)
        check(tail != nil && abs(1200 * log2(tail!.frequency / 110)) < 0.5, "quiet periodic tail remains measurable")
        print(String(format: "%d signal cases in %.2f seconds. Failures: %d", total, Date().timeIntervalSince(started), failures))
        print("Scope: deterministic synthetic monophonic signals, 27–1421 Hz, 8192 samples. Not a microphone or competitor accuracy measurement.")
        if failures > 0 { exit(1) }
    }
}
