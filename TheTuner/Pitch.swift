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
        let maxLag = min(count / 2 - 1, Int(sampleRate / 40))
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
            guard guess >= rate / 1500, guess <= rate / 40 else { continue }
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
        guard frequency >= 40, frequency <= 1500 else { return nil }
        return PitchReading(frequency: frequency, confidence: 1 - center, rms: rms)
    }
}

enum Instrument: String, CaseIterable, Identifiable {
    case chromatic = "Chromatic", guitar = "Guitar", ukulele = "Ukulele"
    var id: String { rawValue }
    var tunings: [Tuning] {
        switch self {
        case .chromatic: return []
        case .guitar: return [
            Tuning(id: "standard", name: "Standard", notes: [40,45,50,55,59,64]),
            Tuning(id: "drop-d", name: "Drop D", notes: [38,45,50,55,59,64]),
            Tuning(id: "half-down", name: "Half step down", notes: [39,44,49,54,58,63]),
            Tuning(id: "dadgad", name: "DADGAD", notes: [38,45,50,55,57,62]),
            Tuning(id: "open-g", name: "Open G", notes: [38,43,50,55,59,62]),
            Tuning(id: "open-d", name: "Open D", notes: [38,45,50,54,57,62])]
        case .ukulele: return [
            Tuning(id: "high-g", name: "High G", notes: [67,60,64,69]),
            Tuning(id: "low-g", name: "Low G", notes: [55,60,64,69]),
            Tuning(id: "baritone", name: "Baritone", notes: [50,55,59,64]),
            Tuning(id: "d-tuning", name: "D tuning", notes: [69,62,66,71])]
        }
    }
}
struct Tuning: Identifiable, Equatable {
    let id: String
    let name: String
    /// Physical string order, not pitch order (high-G ukulele is reentrant).
    let notes: [Int]
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
