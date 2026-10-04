import SwiftUI

enum TunerTheme: String, CaseIterable, Identifiable {
    case blue, chalk, graphite
    var id: String { rawValue }
    var title: String { switch self { case .blue: "Ultramarine"; case .chalk: "Chalk"; case .graphite: "Graphite" } }
    var style: CleanStyle {
        switch self {
        case .blue: CleanStyle(background: 0x2449D8, foreground: 0xFFFBEF, secondary: 0xC4CEF5, accent: 0xFFD0B8, success: 0xB4F3C7)
        case .chalk: CleanStyle(background: 0xF7F6F0, foreground: 0x202321, secondary: 0x636760, accent: 0xBE3024, success: 0x247457)
        case .graphite: CleanStyle(background: 0x202624, foreground: 0xF5F3E8, secondary: 0xB5BEB7, accent: 0xF6BF83, success: 0xAAF0CC)
        }
    }
}
struct CleanStyle {
    let background: UInt32
    let foreground: UInt32
    let secondary: UInt32
    let accent: UInt32
    let success: UInt32
    var shell: Color { Color(hex: background) }
    var face: Color { shell }
    var ink: Color { Color(hex: foreground) }
    var muted: Color { Color(hex: secondary) }
    var orange: Color { Color(hex: accent) }
    var tuned: Color { Color(hex: success) }
    var tunedInk: Color { tuned }
    var silver: Color { ink.opacity(0.18) }
}
private struct TunerThemeKey: EnvironmentKey { static let defaultValue = TunerTheme.blue }
extension EnvironmentValues {
    var tunerTheme: TunerTheme {
        get { self[TunerThemeKey.self] }
        set { self[TunerThemeKey.self] = newValue }
    }
}
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
extension View {
    func technical(_ size: CGFloat = 11, spacing: CGFloat = 1.8) -> some View {
        font(.system(size: size, weight: .medium, design: .monospaced)).tracking(spacing)
    }
}
struct StatusLight: View {
    @Environment(\.tunerTheme) private var theme
    private var style: CleanStyle { theme.style }
    var on: Bool
    var body: some View {
        Circle().fill(on ? style.orange : Color.gray.opacity(0.35))
            .overlay(Circle().fill(.white.opacity(on ? 0.85 : 0)).padding(3))
            .frame(width: 12, height: 12)
            .shadow(color: style.orange.opacity(on ? 0.45 : 0), radius: 6)
            .accessibilityHidden(true)
    }
}
/// Three equal, 100-cent bands; boundaries sit halfway between note centers.
struct PitchRuler: View {
    @Environment(\.tunerTheme) private var theme
    private var style: CleanStyle { theme.style }
    let note: Int?
    let cents: Double
    let active: Bool
    var inTune = false
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - 32
            let markerX = 16 + width * (0.5 + max(-149, min(149, cents)) / 300)
            let proximity = TuningProximity.closeness(cents)
            let accent = inTune ? style.tuned : style.orange
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(0..<3) { index in
                        Text(note.map { PitchMath.name($0 + index - 1) } ?? "—")
                            .font(.system(size: 16, weight: index == 1 ? .medium : .regular))
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .background(style.ink.opacity(index == 1 ? 0.12 : 0.055))
                    }
                }.padding(.horizontal, 16).offset(y: 26)
                Text("−").font(.system(size: 20, weight: .light)).offset(x: -4, y: -2)
                Text("+").font(.system(size: 20, weight: .light)).offset(x: geo.size.width - 12, y: -2)
                // Sparse graduation marks are kept outside the note bands.
                Path { path in
                    for tick in 0...30 {
                        let x = 16 + width * CGFloat(tick) / 30
                        path.move(to: CGPoint(x: x, y: tick % 5 == 0 ? 4 : 10))
                        path.addLine(to: CGPoint(x: x, y: 21))
                    }
                }.stroke(style.ink.opacity(0.35), lineWidth: 0.7)
                if active {
                    Capsule().fill(accent.opacity(0.25 + proximity * 0.25))
                        .frame(width: 18 - 8 * proximity, height: 45)
                        .blur(radius: 7 - proximity * 3).position(x: markerX, y: 20)
                    Rectangle().fill(accent).frame(width: 3, height: 32)
                        .position(x: markerX, y: 10)
                    if abs(cents) > 150 {
                        Text(cents < 0 ? "‹" : "›").foregroundStyle(accent)
                            .position(x: markerX, y: 47)
                    }
                }
            }
        }.frame(height: 70).accessibilityHidden(true)
    }
}

struct Headstock: View {
    @Environment(\.tunerTheme) private var theme
    private var style: CleanStyle { theme.style }
    let instrument: Instrument
    let notes: [Int]
    let selected: Int?
    let locked: Int?
    var inTune = false
    let select: (Int) -> Void
    private var guitar: Bool { instrument == .guitar || instrument == .bass }
    private var half: Int { (notes.count + 1) / 2 }
    private func peg(_ index: Int, size: CGSize) -> CGPoint {
        let half = self.half
        let left = index < half
        let row = left ? half - 1 - index : index - half
        let rows = left ? half : notes.count - half
        let y = rows == 1 ? 0.46 : 0.20 + CGFloat(row) * 0.52 / CGFloat(rows - 1)
        if instrument == .banjo && notes.count == 5 && index == 0 {
            return CGPoint(x: size.width * 0.32, y: size.height * 0.81)
        }
        return CGPoint(x: size.width * (left ? 0.40 : 0.60), y: size.height * y)
    }
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { context, _ in
                    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: size.width * x, y: size.height * y) }
                    var shape = Path()
                    shape.move(to: p(0.34, 0.10))
                    if guitar {
                        shape.addCurve(to: p(0.66, 0.10), control1: p(0.49, -0.01), control2: p(0.51, -0.01))
                    } else {
                        shape.addQuadCurve(to: p(0.39, 0.03), control: p(0.34, 0.03))
                        shape.addLine(to: p(0.61, 0.03))
                        shape.addQuadCurve(to: p(0.66, 0.10), control: p(0.66, 0.03))
                    }
                    shape.addLine(to: p(0.64, 0.77))
                    shape.addQuadCurve(to: p(0.60, 0.89), control: p(0.60, 0.83))
                    shape.addLine(to: p(0.60, 1)); shape.addLine(to: p(0.40, 1))
                    shape.addLine(to: p(0.40, 0.89))
                    shape.addQuadCurve(to: p(0.36, 0.77), control: p(0.40, 0.83))
                    shape.addLine(to: p(0.34, 0.10))
                    shape.closeSubpath()

                    if instrument.bowed {
                        let scroll = Path(ellipseIn: CGRect(x: size.width * 0.43, y: 0, width: size.width * 0.14, height: size.height * 0.14))
                        context.fill(scroll, with: .color(style.silver))
                        context.stroke(scroll, with: .color(style.muted), lineWidth: 1.3)
                        context.stroke(Path(ellipseIn: CGRect(x: size.width * 0.47, y: size.height * 0.04, width: size.width * 0.06, height: size.height * 0.06)), with: .color(style.muted), lineWidth: 1)
                    }
                    context.stroke(shape, with: .color(style.ink.opacity(0.8)), lineWidth: 1.1)

                    let nut = CGRect(x: size.width * 0.40, y: size.height * 0.89, width: size.width * 0.20, height: 7)

                    context.stroke(Path(nut), with: .color(style.muted), lineWidth: 0.7)
                    for i in notes.indices {
                        let post = peg(i, size: size)
                        let isLeft = i < half
                        let outerX = size.width * (isLeft ? 0.16 : 0.84)
                        var stem = Path(); stem.move(to: post); stem.addLine(to: CGPoint(x: outerX, y: post.y))
                        context.stroke(stem, with: .color(style.muted), lineWidth: 1)
                        let endX = size.width * (0.41 + CGFloat(i) / CGFloat(notes.count - 1) * 0.18)
                        var string = Path(); string.move(to: post)
                        string.addLine(to: CGPoint(x: endX, y: size.height * 0.89))
                        string.addLine(to: CGPoint(x: endX, y: size.height))

                        if selected == i {
                            context.drawLayer { glow in
                                glow.addFilter(.blur(radius: 4))
                                glow.stroke(string, with: .color((inTune ? style.tuned : style.orange).opacity(0.3)), lineWidth: 4)
                            }
                        }
                        context.stroke(string, with: .color(selected == i ? (inTune ? style.tuned : style.orange) : style.ink.opacity(0.65)), lineWidth: selected == i ? 1.6 : 1.2)
                        if instrument == .mandolin {
                            context.stroke(string.offsetBy(dx: 3, dy: 0), with: .color(selected == i ? (inTune ? style.tuned : style.orange) : style.ink.opacity(0.65)), lineWidth: 1)
                        }
                        let circle = Path(ellipseIn: CGRect(x: post.x - 9, y: post.y - 9, width: 18, height: 18))
                        context.fill(circle, with: .color(style.face))
                        context.stroke(circle, with: .color(style.ink), lineWidth: 0.9)
                        context.stroke(Path(ellipseIn: CGRect(x: post.x - 6, y: post.y - 6, width: 12, height: 12)), with: .color(selected == i ? (inTune ? style.tuned : style.orange) : style.ink.opacity(0.7)), lineWidth: selected == i ? 2 : 0.8)
                    }
                }.accessibilityHidden(true)
                ForEach(notes.indices, id: \.self) { i in
                    let isLeft = i < half
                    let post = peg(i, size: size)
                    Button { select(i) } label: {
                        HStack(spacing: 5) {
                            if isLeft { stringLabel(i) }
                            Spacer(minLength: 0)
                            if !isLeft { stringLabel(i) }
                        }.frame(width: size.width * 0.48, height: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .position(x: size.width * (isLeft ? 0.24 : 0.76), y: post.y)
                        .accessibilityIdentifier("string-\(notes.count - i)")
                        .accessibilityLabel("\(instrument == .mandolin ? "Course" : "String") \(notes.count - i), \(PitchMath.label(notes[i]))")
                        .accessibilityValue(locked == i ? "Locked" : selected == i ? "Detected" : "Automatic")
                        .accessibilityAddTraits(selected == i ? .isSelected : [])
                }
            }
        }
    }
    private func stringLabel(_ i: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(notes.count - i)").font(.system(size: 10, design: .monospaced)).foregroundStyle(style.muted)
            Text(PitchMath.name(notes[i])).font(.system(size: 14))
            Text("\(PitchMath.octave(notes[i]))").font(.system(size: 9)).baselineOffset(-3)
        }.foregroundStyle(style.ink).fixedSize()
    }
}
