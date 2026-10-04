import Foundation
import Accelerate

struct PitchReading {
    let frequency: Double
    let confidence: Double
    let rms: Double
}

/// YIN locates a period on an averaged, reduced-rate signal. Refinement measures
/// several periods in the original samples, avoiding high-note decimation bias.
struct PitchDetector {
    func detect(_ samples: [Float], rate: Double) -> PitchReading? {
        guard rate.isFinite, rate >= 8000, rate <= 192000, samples.count >= 2048,
              samples.allSatisfy({ $0.isFinite }) else { return nil }
        let stride = max(1, Int(rate / 12000))
        let count = samples.count / stride
        var signal = [Double](repeating: 0, count: count)
        for i in 0..<count {
            for k in 0..<stride { signal[i] += Double(samples[i * stride + k]) / Double(stride) }
        }
        let mean = signal.reduce(0, +) / Double(count)
        var energy = 0.0
        for i in signal.indices { signal[i] -= mean; energy += signal[i] * signal[i] }
        let rms = sqrt(energy / Double(count))
        guard rms > 0.003 else { return nil }
        let sampleRate = rate / Double(stride)
        let minLag = max(2, Int(sampleRate / 1500))
        let maxLag = min(count / 2 - 1, Int(sampleRate / 25))
        guard maxLag > minLag else { return nil }
        let window = count - maxLag
        var difference = [Double](repeating: 1, count: maxLag + 1)
        var cumulative = 0.0
        signal.withUnsafeBufferPointer { buffer in
            let base = buffer.baseAddress!
            for lag in 1...maxLag {
                var sum = 0.0
                vDSP_distancesqD(base, 1, base + lag, 1, &sum, vDSP_Length(window))
                cumulative += sum
                difference[lag] = cumulative > 0 ? sum * Double(lag) / cumulative : 1
            }
        }
        let original = samples.map(Double.init)
        func vectorLoss(_ lag: Int, count: Int, normalized: Bool) -> Double {
            original.withUnsafeBufferPointer { buffer in
                let base = buffer.baseAddress!
                var sum = 0.0
                vDSP_distancesqD(base, 1, base + lag, 1, &sum, vDSP_Length(count))
                if !normalized { return sum }
                var a = 0.0, b = 0.0
                vDSP_svesqD(base, 1, &a, vDSP_Length(count))
                vDSP_svesqD(base + lag, 1, &b, vDSP_Length(count))
                return sum / max(a + b, 1e-20)
            }
        }
        var lag = minLag
        while lag < maxLag {
            if difference[lag] < 0.08 {
                while lag + 1 <= maxLag && difference[lag + 1] < difference[lag] { lag += 1 }
                break
            }
            lag += 1
        }
        guard lag < maxLag, difference[lag] < 0.08 else { return nil }
        let left = difference[lag - 1], center = difference[lag], right = difference[lag + 1]
        let denominator = left - 2 * center + right
        let offset = abs(denominator) > 1e-12 ? 0.5 * (left - right) / denominator : 0
        let coarsePeriod = (Double(lag) + max(-1, min(1, offset))) * Double(stride)
        // Check plausible octave/harmonic alternatives at the original sample rate.
        // Reduced-rate minima alone are unreliable for short, overtone-rich periods.
        var candidates: [(period: Double, loss: Double)] = []
        for factor in [1.0 / 3, 0.5, 1.0, 2.0, 3.0] {
            let guess = coarsePeriod * factor
            guard guess >= rate / 1500, guess <= rate / 25 else { continue }
            let lo = max(2, Int(guess) - stride * 2)
            let hi = min(samples.count / 2 - 2, Int(guess) + stride * 2)
            let n = samples.count - hi - 1
            let values = ((lo - 1)...(hi + 1)).map { vectorLoss($0, count: n, normalized: true) }
            let k = (1..<(values.count - 1)).min(by: { values[$0] < values[$1] })!
            let d = values[k-1] - 2 * values[k] + values[k+1]
            guard d > 1e-12, k > 1, k < values.count - 2 else { continue }
            let offset = 0.5 * (values[k-1] - values[k+1]) / d
            guard abs(offset) <= 1 else { continue }
            let candidatePeriod = Double(lo - 1 + k) + offset
            let integer = Int(candidatePeriod), fraction = candidatePeriod - Double(integer)
            var error = 0.0, power = 0.0
            for i in 0..<n {
                let a = Double(samples[i])
                let b = Double(samples[i + integer]) * (1-fraction) + Double(samples[i + integer + 1]) * fraction
                error += (a-b)*(a-b); power += a*a+b*b
            }
            candidates.append((candidatePeriod, error / max(power, 1e-20)))
        }
        guard let minimum = candidates.map(\.loss).min(), minimum < 0.08,
              let chosen = candidates.filter({ $0.loss <= max(0.001, minimum * 2) }).min(by: { $0.period < $1.period }) else { return nil }
        let period = chosen.period
        // Long-baseline interpolation is far more precise than rounding a short period.
        let multiples = max(1, min(8, Int(1200 / period)))
        let estimated = Int((period * Double(multiples)).rounded())
        let radius = max(3, stride * multiples)
        let lower = max(2, estimated - radius)
        let upper = min(samples.count / 2 - 2, estimated + radius)
        guard upper > lower else { return nil }
        let originalWindow = samples.count - upper - 1
        var raw = [Double]()
        for t in (lower - 1)...(upper + 1) { raw.append(vectorLoss(t, count: originalWindow, normalized: false)) }
        guard let best = (1..<(raw.count - 1)).min(by: { raw[$0] < raw[$1] }) else { return nil }
        let d = raw[best - 1] - 2 * raw[best] + raw[best + 1]
        let adjustment = abs(d) > 1e-12 ? 0.5 * (raw[best - 1] - raw[best + 1]) / d : 0
        let refined = Double(lower - 1 + best) + max(-1, min(1, adjustment))
        let frequency = rate * Double(multiples) / refined
        guard frequency >= 25, frequency <= 1500 else { return nil }
        return PitchReading(frequency: frequency, confidence: 1 - center, rms: rms)
    }
}

enum Instrument: String, CaseIterable, Identifiable, Codable {
    case chromatic = "Chromatic", guitar = "Guitar", ukulele = "Ukulele"
    case bass = "Bass", violin = "Violin", viola = "Viola", cello = "Cello"
    case banjo = "Banjo", mandolin = "Mandolin"
    var id: String { rawValue }
    var bowed: Bool { [.violin, .viola, .cello].contains(self) }
    var tunings: [Tuning] {
        func t(_ id: String, _ name: String, _ notes: [Int]) -> Tuning { Tuning(id: id, name: name, notes: notes) }
        switch self {
        case .chromatic: return []
        case .guitar: return [
            t("standard", "Standard", [40,45,50,55,59,64]),
            t("drop-d", "Drop D", [38,45,50,55,59,64]),
            t("half-down", "Half step down", [39,44,49,54,58,63]),
            t("dadgad", "DADGAD", [38,45,50,55,57,62]),
            t("open-g", "Open G", [38,43,50,55,59,62]),
            t("open-d", "Open D", [38,45,50,54,57,62]),
            t("whole-down", "D standard", [38,43,48,53,57,62]),
            t("drop-c", "Drop C", [36,43,48,53,57,62]),
            t("open-e", "Open E", [40,47,52,56,59,64]),
            t("open-c", "Open C", [36,43,48,55,60,64]),
            t("double-drop-d", "Double Drop D", [38,45,50,55,59,62]),
            t("seven", "7-string", [35,40,45,50,55,59,64]),
            t("eight", "8-string", [30,35,40,45,50,55,59,64])]
        case .ukulele: return [
            t("high-g", "High G", [67,60,64,69]), t("low-g", "Low G", [55,60,64,69]),
            t("baritone", "Baritone", [50,55,59,64]), t("d-tuning", "D tuning", [69,62,66,71]),
            t("low-a", "Low A · D tuning", [57,62,66,71]),
            t("slack-key", "Slack key", [67,60,64,67]),
            t("half-down", "Half step down", [66,59,63,68])]
        case .bass: return [
            t("standard", "4-string", [28,33,38,43]), t("five", "5-string", [23,28,33,38,43]),
            t("six", "6-string", [23,28,33,38,43,48]), t("drop-d", "Drop D", [26,33,38,43]),
            t("half-down", "Half step down", [27,32,37,42]),
            t("d-standard", "D standard", [26,31,36,41]), t("drop-c", "Drop C", [24,31,36,41]),
            t("drop-a", "5-string Drop A", [21,28,33,38,43])]
        case .violin: return [t("standard", "Standard", [55,62,69,76]),
            t("cross-a", "Cross A · AEAE", [57,64,69,76]), t("cross-g", "Cross G · GDGD", [55,62,67,74]),
            t("calico", "Calico · AEAC♯", [57,64,69,73]), t("five", "5-string", [48,55,62,69,76])]
        case .viola: return [t("standard", "Standard", [48,55,62,69]),
            t("half-down", "Half step down", [47,54,61,68]), t("whole-down", "Whole step down", [46,53,60,67])]
        case .cello: return [t("standard", "Standard", [36,43,50,57]),
            t("bach", "Bach Suite 5 · CGDG", [36,43,50,55]),
            t("half-down", "Half step down", [35,42,49,56]), t("whole-down", "Whole step down", [34,41,48,55])]
        case .banjo: return [t("open-g", "Open G", [67,50,55,59,62]),
            t("double-c", "Double C", [67,48,55,60,62]), t("sawmill", "Sawmill", [67,50,55,60,62]),
            t("open-d", "Open D", [66,50,54,57,62]), t("standard-c", "Standard C", [67,48,55,59,62]),
            t("tenor", "Tenor · CGDA", [48,55,62,69]), t("irish", "Irish tenor · GDAE", [43,50,57,64])]
        case .mandolin: return [t("standard", "Standard · GDAE", [55,62,69,76]),
            t("cross-g", "Cross G · GDGD", [55,62,67,74]), t("cross-a", "Cross A · AEAE", [57,64,69,76]),
            t("octave", "Octave mandolin", [43,50,57,64]), t("mandola", "Mandola · CGDA", [48,55,62,69])]
        }
    }
}
struct Tuning: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    /// Physical order, last numbered string to first; mandolin uses paired courses.
    let notes: [Int]
    var isCustom: Bool { id.hasPrefix("custom-") }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 32 &&
        (4...8).contains(notes.count) && notes.allSatisfy { (21...89).contains($0) }
    }
}

enum PitchMath {
    static let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    static func frequency(_ midi: Int, reference: Double = 440) -> Double {
        reference * pow(2, Double(midi - 69) / 12)
    }
    static func midi(_ frequency: Double, reference: Double = 440) -> Double {
        69 + 12 * log2(frequency / reference)
    }
    static func cents(_ frequency: Double, target: Int, reference: Double) -> Double {
        1200 * log2(frequency / self.frequency(target, reference: reference))
    }
    static func name(_ midi: Int) -> String { names[((midi % 12) + 12) % 12] }
    static func octave(_ midi: Int) -> Int { Int(floor(Double(midi) / 12)) - 1 }
    static func label(_ midi: Int) -> String { "\(name(midi))\(octave(midi))" }
    static func target(frequency: Double, reference: Double, notes: [Int], locked: Int?, previous: Int?) -> Int {
        if let locked { return locked }
        let value = midi(frequency, reference: reference)
        let nearest = notes.min(by: { abs(Double($0) - value) < abs(Double($1) - value) }) ?? Int(value.rounded())
        // Six cents of boundary hysteresis keeps neighboring labels from flickering.
        if let previous, (notes.isEmpty || notes.contains(previous)), previous != nearest,
           abs(value - Double(previous)) <= abs(value - Double(nearest)) + 0.12 { return previous }
        return nearest
    }
}
