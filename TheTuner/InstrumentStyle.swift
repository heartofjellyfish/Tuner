import SwiftUI

enum CleanStyle {
    static let shell = Color(hex: 0xEEF0EE)
    static let face = Color(hex: 0xF8F9F7)
    static let ink = Color(hex: 0x242826)
    static let muted = Color(hex: 0x686F6B)
    static let orange = Color(hex: 0xFF941A)
    static let silver = Color(hex: 0xDADDD9)
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
    var on: Bool
    var body: some View {
        Circle().fill(on ? CleanStyle.orange : Color.gray.opacity(0.35))
            .overlay(Circle().fill(.white.opacity(on ? 0.85 : 0)).padding(3))
            .frame(width: 12, height: 12)
            .shadow(color: CleanStyle.orange.opacity(on ? 0.45 : 0), radius: 6)
            .accessibilityHidden(true)
    }
}
struct Surface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(LinearGradient(colors: [CleanStyle.face, Color(hex: 0xF0F2EF)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.9), lineWidth: 1).offset(y: 1))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.black.opacity(0.15), lineWidth: 0.8))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 15).stroke(.black.opacity(0.08), lineWidth: 2).blur(radius: 2).padding(1).allowsHitTesting(false)
            }
    }
}

/// Each semitone owns a 100-cent sector. Boundaries are halfway between labels.
/// The marker is linear in cents, rather than copied from a generated mockup.
struct PitchArc: View {
    let note: Int?
    let cents: Double
    let active: Bool
    var body: some View {
        Canvas { context, size in
            let radius = min(size.width * 0.50, 170)
            let origin = CGPoint(x: size.width / 2, y: radius + 52)
            func point(_ angle: Double, _ r: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + cos(angle * .pi / 180) * r, y: origin.y + sin(angle * .pi / 180) * r)
            }
            for zone in 0..<3 {
                let start = -150.0 + Double(zone) * 40 + 0.65
                let end = start + 38.7
                var path = Path()
                path.addArc(center: origin, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
                context.stroke(path, with: .color(Color(hex: 0xDFE2DE).opacity(zone == 1 ? 0.8 : 0.6)), lineWidth: 24)
                if let note {
                    let value = note + zone - 1
                    let label = Text(PitchMath.name(value)).font(.system(size: zone == 1 ? 25 : 19, weight: .medium)).foregroundColor(CleanStyle.ink)
                        + Text(zone == 1 ? "\(PitchMath.octave(value))" : "").font(.system(size: 12)).baselineOffset(-4).foregroundColor(CleanStyle.ink)
                    let location = point(-130 + Double(zone) * 40, radius + 32)
                    context.draw(label, at: location)

                }
            }
            if active {
                let angle = -90 + max(-148, min(148, cents)) * 0.4
                var glow = Path()
                glow.addArc(center: origin, radius: radius, startAngle: .degrees(max(-150, angle - 12)), endAngle: .degrees(min(-30, angle + 12)), clockwise: false)
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 12))
                    layer.stroke(glow, with: .color(CleanStyle.orange.opacity(0.4)), lineWidth: 23)
                }
                var marker = Path()
                marker.move(to: point(angle, radius - 24)); marker.addLine(to: point(angle, radius + 17))
                context.stroke(marker, with: .color(CleanStyle.orange), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                if abs(cents) > 150 {
                    context.draw(Text(cents < 0 ? "‹" : "›").font(.system(size: 25)).foregroundColor(CleanStyle.orange), at: point(cents < 0 ? -153 : -27, radius))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct Headstock: View {
    let instrument: Instrument
    let notes: [Int]
    let selected: Int?
    let locked: Int?
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
        return CGPoint(x: size.width * (left ? 0.32 : 0.68), y: size.height * y)
    }
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { context, _ in
                    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: size.width * x, y: size.height * y) }
                    var shape = Path()
                    shape.move(to: p(0.32, 0.02))
                    if guitar {
                        shape.addLine(to: p(0.68, 0.02)); shape.addLine(to: p(0.74, 0.09))
                    } else {
                        shape.addLine(to: p(0.68, 0.02))
                        shape.addQuadCurve(to: p(0.74, 0.10), control: p(0.74, 0.02))
                    }
                    shape.addLine(to: p(0.71, 0.77)); shape.addLine(to: p(0.65, 0.88))
                    shape.addLine(to: p(0.65, 1)); shape.addLine(to: p(0.35, 1))
                    shape.addLine(to: p(0.35, 0.88)); shape.addLine(to: p(0.29, 0.77))
                    shape.addLine(to: p(0.26, 0.10))
                    if guitar { shape.addLine(to: p(0.32, 0.02)) }
                    else { shape.addQuadCurve(to: p(0.32, 0.02), control: p(0.26, 0.02)) }
                    shape.closeSubpath()
                    context.fill(shape, with: .linearGradient(Gradient(colors: [Color(hex: 0xE3E5E2), Color(hex: 0xD5D9D5)]), startPoint: .zero, endPoint: p(1,1)))
                    if instrument.bowed {
                        let scroll = Path(ellipseIn: CGRect(x: size.width * 0.43, y: 0, width: size.width * 0.14, height: size.height * 0.14))
                        context.fill(scroll, with: .color(CleanStyle.silver))
                        context.stroke(scroll, with: .color(CleanStyle.muted), lineWidth: 1.3)
                        context.stroke(Path(ellipseIn: CGRect(x: size.width * 0.47, y: size.height * 0.04, width: size.width * 0.06, height: size.height * 0.06)), with: .color(CleanStyle.muted), lineWidth: 1)
                    }
                    context.stroke(shape, with: .color(CleanStyle.ink.opacity(0.8)), lineWidth: 1.1)
                    context.fill(Path(CGRect(x: size.width * 0.35, y: size.height * 0.9, width: size.width * 0.30, height: size.height * 0.10)), with: .color(Color(hex: 0x505652)))
                    let nut = CGRect(x: size.width * 0.35, y: size.height * 0.86, width: size.width * 0.30, height: 7)
                    context.fill(Path(nut), with: .color(.white.opacity(0.85)))
                    context.stroke(Path(nut), with: .color(CleanStyle.muted), lineWidth: 0.7)
                    for i in notes.indices {
                        let post = peg(i, size: size)
                        let isLeft = i < half
                        let outerX = size.width * (isLeft ? 0.20 : 0.80)
                        var stem = Path(); stem.move(to: post); stem.addLine(to: CGPoint(x: outerX, y: post.y))
                        context.stroke(stem, with: .color(CleanStyle.muted), lineWidth: 1)
                        let endX = size.width * (0.37 + CGFloat(i) / CGFloat(notes.count - 1) * 0.26)
                        var string = Path(); string.move(to: post)
                        string.addLine(to: CGPoint(x: endX, y: size.height * 0.87))
                        string.addLine(to: CGPoint(x: endX, y: size.height))
                        context.stroke(string, with: .color(.black.opacity(0.20)), lineWidth: 3)
                        if selected == i {
                            context.drawLayer { glow in
                                glow.addFilter(.blur(radius: 4))
                                glow.stroke(string, with: .color(CleanStyle.orange.opacity(0.3)), lineWidth: 4)
                            }
                        }
                        context.stroke(string, with: .color(selected == i ? CleanStyle.orange : .white.opacity(0.85)), lineWidth: selected == i ? 1.6 : 1.2)
                        if instrument == .mandolin {
                            context.stroke(string.offsetBy(dx: 3, dy: 0), with: .color(selected == i ? CleanStyle.orange : .white.opacity(0.85)), lineWidth: 1)
                        }
                        let circle = Path(ellipseIn: CGRect(x: post.x - 5.5, y: post.y - 5.5, width: 11, height: 11))
                        context.fill(circle, with: .color(CleanStyle.face))
                        context.stroke(circle, with: .color(CleanStyle.ink), lineWidth: 0.9)
                        context.fill(Path(ellipseIn: CGRect(x: post.x - 3, y: post.y - 3, width: 6, height: 6)), with: .color(selected == i ? CleanStyle.orange : CleanStyle.muted))
                    }
                }.accessibilityHidden(true)
                ForEach(notes.indices, id: \.self) { i in
                    let isLeft = i < half
                    let post = peg(i, size: size)
                    Button { select(i) } label: {
                        HStack(spacing: 5) {
                            if isLeft { stringLabel(i) }
                            Circle()
                                .fill(selected == i ? CleanStyle.orange : CleanStyle.face.opacity(0.6))
                                .overlay(Circle().stroke(CleanStyle.ink, lineWidth: 1.1))
                                .frame(width: 28, height: 28)
                            if !isLeft { stringLabel(i) }
                        }.frame(width: size.width * 0.29, height: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .position(x: size.width * (isLeft ? 0.125 : 0.875), y: post.y)
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
            Text("\(notes.count - i)").font(.system(size: 10, design: .monospaced)).foregroundStyle(CleanStyle.muted)
            Text(PitchMath.name(notes[i])).font(.system(size: 14))
            Text("\(PitchMath.octave(notes[i]))").font(.system(size: 9)).baselineOffset(-3)
        }.foregroundStyle(CleanStyle.ink).fixedSize()
    }
}
