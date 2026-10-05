import SwiftUI

/// One source of geometry for the drawing, string targets and completion feedback.
struct InstrumentHeadLayout {
    let instrument: Instrument
    let count: Int
    let size: CGSize
    var shortDrone: Bool { instrument == .banjo && count == 5 }
    var inlineBass: Bool { instrument == .bass && count <= 4 }
    var half: Int { (count + 1) / 2 }
    var nutY: CGFloat { shortDrone ? 0.62 : 0.80 }
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }
    func left(_ i: Int) -> Bool {
        if inlineBass { return false } // Labels opposite the inline keys.
        if shortDrone { return i < 3 }
        return i < half
    }
    func post(_ i: Int, member: Int = 0) -> CGPoint {
        if shortDrone && i == 0 { return point(0.39, 0.88) }
        if inlineBass {
            return point(0.53, 0.17 + CGFloat(count - 1 - i) * 0.48 / CGFloat(max(1, count - 1)))
        }
        let side = left(i)
        let row: Int
        let rows: Int
        if shortDrone { row = side ? 2 - i : i - 3; rows = 2 }
        else { row = side ? half - 1 - i : i - half; rows = side ? half : count - half }
        let paired = instrument == .mandolin
        let physicalRow = paired ? row * 2 + member : row
        let physicalRows = paired ? rows * 2 : rows
        let top: CGFloat = instrument.bowed ? 0.40 : 0.20
        let span: CGFloat = instrument.bowed ? 0.24 : shortDrone ? 0.27 : 0.46
        let y = top + CGFloat(physicalRow) * span / CGFloat(max(1, physicalRows - 1))
        return point(side ? (instrument.bowed ? 0.44 : 0.38) : (instrument.bowed ? 0.59 : 0.62), y)
    }
    func target(_ i: Int) -> CGPoint {
        let post = post(i)
        if instrument.bowed { return point(left(i) ? 0.29 : 0.76, post.y / size.height) }
        if shortDrone && i == 0 { return point(0.29, 0.88) }
        if instrument == .mandolin {
            return CGPoint(x: post.x, y: (post.y + self.post(i, member: 1).y) / 2)
        }
        return post
    }
    func stringX(_ i: Int, member: Int = 0) -> CGFloat {
        let base = size.width * (0.407 + CGFloat(i) * 0.186 / CGFloat(max(1, count - 1)))
        return base + (instrument == .mandolin ? (member == 0 ? -1.7 : 1.7) : 0)
    }
}

struct InstrumentHeadDrawing: View {
    let layout: InstrumentHeadLayout
    let style: CleanStyle
    let selected: Int?
    let inTune: Bool
    let completed: Set<Int>
    let widths: [CGFloat]
    var body: some View {
        Canvas { context, _ in
            let instrument = layout.instrument
            let size = layout.size
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { layout.point(x, y) }
            func stroke(_ path: Path, _ color: Color? = nil, _ width: CGFloat = 1.1) {
                context.stroke(path, with: .color(color ?? style.ink.opacity(0.85)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            var outline = Path()
            if instrument.bowed {
                // Open pegbox viewed slightly from the side, not a guitar head with a circle on top.
                outline.move(to: p(0.45, 0.28))
                outline.addCurve(to: p(0.61, 0.78), control1: p(0.59, 0.33), control2: p(0.63, 0.59))
                outline.addLine(to: p(0.61, 1)); outline.addLine(to: p(0.41, 1))
                outline.addLine(to: p(0.41, 0.78))
                outline.addCurve(to: p(0.45, 0.28), control1: p(0.39, 0.50), control2: p(0.38, 0.35))
                stroke(outline)
                var box = Path()
                box.move(to: p(0.46, 0.34)); box.addLine(to: p(0.56, 0.37))
                box.addQuadCurve(to: p(0.58, 0.77), control: p(0.61, 0.56))
                box.addLine(to: p(0.44, 0.77)); box.closeSubpath()
                context.fill(box, with: .color(style.silver.opacity(0.22))); stroke(box, style.muted, 0.7)
                let breadth: CGFloat = instrument == .cello ? 1.16 : instrument == .viola ? 1.05 : 1
                // Offset carved cheeks and a continuous spiral volute.
                for layer in (0...2).reversed() {
                    let rect = CGRect(x: size.width * (0.38 + CGFloat(layer) * 0.018), y: size.height * 0.022,
                                      width: size.width * 0.20 * breadth, height: size.height * 0.29)
                    let cheek = Path(ellipseIn: rect)
                    context.fill(cheek, with: .color(style.face)); stroke(cheek, style.ink.opacity(layer == 0 ? 0.95 : 0.45), layer == 0 ? 1.2 : 0.8)
                }
                var spiral = Path()
                for step in 0...100 {
                    let t = CGFloat(step) / 100
                    let angle = Double(t) * .pi * 3.7 - .pi / 2
                    let radius = 1 - t * 0.88
                    let pt = p(0.477 + CGFloat(cos(angle)) * 0.085 * breadth * radius,
                               0.167 + CGFloat(sin(angle)) * 0.128 * radius)
                    if step == 0 { spiral.move(to: pt) } else { spiral.addLine(to: pt) }
                }
                stroke(spiral, style.ink, 1.2)
            } else {
                if layout.inlineBass {
                    outline.move(to: p(0.43, 0.72))
                    outline.addCurve(to: p(0.50, 0.07), control1: p(0.34, 0.44), control2: p(0.42, 0.06))
                    outline.addCurve(to: p(0.66, 0.23), control1: p(0.68, 0.02), control2: p(0.72, 0.14))
                    outline.addCurve(to: p(0.59, 0.76), control1: p(0.55, 0.38), control2: p(0.66, 0.56))
                } else {
                    outline.move(to: p(0.35, 0.13))
                    switch instrument {
                    case .ukulele:
                        outline.addQuadCurve(to: p(0.40, 0.055), control: p(0.34, 0.055))
                        outline.addQuadCurve(to: p(0.60, 0.055), control: p(0.50, 0.025))
                        outline.addQuadCurve(to: p(0.65, 0.13), control: p(0.66, 0.055))
                    case .banjo, .mandolin:
                        outline.addQuadCurve(to: p(0.40, 0.08), control: p(0.40, 0.15))
                        outline.addQuadCurve(to: p(0.50, 0.015), control: p(0.46, 0.07))
                        outline.addQuadCurve(to: p(0.60, 0.08), control: p(0.54, 0.07))
                        outline.addQuadCurve(to: p(0.65, 0.13), control: p(0.60, 0.15))
                    default:
                        outline.addCurve(to: p(0.65, 0.13), control1: p(0.49, 0.005), control2: p(0.51, 0.005))
                    }
                    outline.addLine(to: p(0.64, layout.nutY - 0.14))
                    outline.addQuadCurve(to: p(0.59, layout.nutY), control: p(0.60, layout.nutY - 0.07))
                }
                outline.addLine(to: p(0.59, 1)); outline.addLine(to: p(0.41, 1))
                outline.addLine(to: p(0.41, layout.nutY))
                if !layout.inlineBass {
                    outline.addQuadCurve(to: p(0.36, layout.nutY - 0.14), control: p(0.40, layout.nutY - 0.07))
                }
                outline.closeSubpath(); stroke(outline)
            }
            let nut = Path(CGRect(x: size.width * 0.40, y: size.height * layout.nutY, width: size.width * 0.20, height: 5))
            stroke(nut, style.muted, 0.8)
            if !instrument.bowed {
                for y: CGFloat in [layout.nutY + 0.085, layout.nutY + 0.16] where y < 1 {
                    var fret = Path(); fret.move(to: p(0.41, y)); fret.addLine(to: p(0.59, y)); stroke(fret, style.muted, 0.6)
                }
            }
            for i in 0..<layout.count {
                let color = selected == i ? (inTune ? style.tuned : style.orange) : completed.contains(i) ? style.tuned.opacity(0.7) : style.ink.opacity(0.7)
                let copies = instrument == .mandolin ? 2 : 1
                for member in 0..<copies {
                    let post = layout.post(i, member: member)
                    let drone = layout.shortDrone && i == 0
                    let side = layout.inlineBass || layout.left(i)
                    let handleX: CGFloat = drone ? 0.29 : side ? (instrument.bowed ? 0.29 : layout.inlineBass ? 0.34 : 0.28) : (instrument.bowed ? 0.76 : 0.72)
                    let handle = CGPoint(x: size.width * handleX, y: post.y)
                    var axle = Path(); axle.move(to: post); axle.addLine(to: handle); stroke(axle, style.muted, 1)
                    let knob = Path(roundedRect: CGRect(x: handle.x - size.width * 0.032, y: handle.y - size.height * 0.022,
                                                       width: size.width * 0.064, height: size.height * 0.044), cornerRadius: instrument.bowed ? size.height * 0.02 : 5)
                    context.fill(knob, with: .color(style.face)); stroke(knob, instrument.bowed ? color : style.ink.opacity(0.8), 1)
                    if instrument == .bass {
                        var clover = Path()
                        let r: CGFloat = 8
                        for angle: Double in [0, 120, 240] {
                            let center = CGPoint(x: handle.x + CGFloat(cos(angle * .pi / 180)) * r * 0.7, y: handle.y + CGFloat(sin(angle * .pi / 180)) * r * 0.7)
                            clover.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                        }
                        context.fill(clover, with: .color(style.face)); stroke(clover, style.ink.opacity(0.8), 0.8)
                    }
                    let endX = layout.stringX(i, member: member)
                    var string = Path(); string.move(to: post)
                    // The drone starts at the fifth fret; it never reaches the nut or peghead.
                    if !drone { string.addLine(to: CGPoint(x: endX, y: size.height * layout.nutY + 5)) }
                    string.addLine(to: CGPoint(x: endX, y: size.height))
                    if selected == i {
                        context.drawLayer { glow in
                            glow.addFilter(.blur(radius: 3)); glow.stroke(string, with: .color(color.opacity(0.2)), lineWidth: 4)
                        }
                    }
                    stroke(string, color, widths[i])
                    if !instrument.bowed && !drone {
                        let circle = Path(ellipseIn: CGRect(x: post.x - 7, y: post.y - 7, width: 14, height: 14))
                        context.fill(circle, with: .color(style.face)); stroke(circle, color, selected == i ? 1.6 : 0.8)
                        stroke(Path(ellipseIn: CGRect(x: post.x - 4, y: post.y - 4, width: 8, height: 8)), color, 0.7)
                    }
                }
                let target = layout.target(i)
                if completed.contains(i) {
                    let circle = Path(ellipseIn: CGRect(x: target.x - 9, y: target.y - 9, width: 18, height: 18))
                    context.fill(circle, with: .color(style.face)); stroke(circle, style.tuned, 1.5)
                    var check = Path(); check.move(to: CGPoint(x: target.x - 4, y: target.y))
                    check.addLine(to: CGPoint(x: target.x - 1, y: target.y + 3)); check.addLine(to: CGPoint(x: target.x + 4, y: target.y - 3))
                    stroke(check, style.tuned, 1.6)
                } else if selected == i && instrument.bowed {
                    stroke(Path(ellipseIn: CGRect(x: target.x - 11, y: target.y - 11, width: 22, height: 22)), color, 1.3)
                }
                // Label guide ends before the peg, so it never resembles another string.
                var guide = Path()
                let side = layout.left(i)
                guide.move(to: CGPoint(x: size.width * (side ? 0.16 : 0.84), y: target.y))
                guide.addLine(to: CGPoint(x: target.x + (side ? -13 : 13), y: target.y))
                stroke(guide, style.muted.opacity(0.7), 0.7)
            }
        }.accessibilityHidden(true)
    }
}

/// Full silhouettes are reserved for selecting an instrument, never the tuning meter.
struct InstrumentIcon: View {
    @Environment(\.tunerTheme) private var theme
    let instrument: Instrument
    var body: some View {
        Canvas { context, size in
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * size.width, y: y * size.height) }
            func line(_ path: Path, _ width: CGFloat = 1.1) { context.stroke(path, with: .color(theme.style.ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)) }
            if instrument == .chromatic {
                line(Path(ellipseIn: CGRect(x: 5, y: 12, width: size.width - 10, height: size.width - 10)))
                context.fill(Path(ellipseIn: CGRect(x: size.width / 2 - 2, y: size.height / 2 - 2, width: 4, height: 4)), with: .color(theme.style.ink)); return
            }
            let bowed = instrument.bowed
            let bodyTop: CGFloat = instrument == .banjo ? 0.59 : bowed ? 0.39 : instrument == .bass ? 0.56 : instrument == .ukulele ? 0.37 : 0.44
            var neck = Path(); neck.move(to: p(0.46, 0.18)); neck.addLine(to: p(0.46, 0.69)); neck.addLine(to: p(0.54, 0.69)); neck.addLine(to: p(0.54, 0.18)); line(neck, 0.8)
            if instrument == .banjo {
                line(Path(ellipseIn: CGRect(x: size.width * 0.19, y: size.height * 0.59, width: size.width * 0.62, height: size.height * 0.32)))
                var fifth = Path(); fifth.move(to: p(0.36, 0.38)); fifth.addLine(to: p(0.46, 0.38)); line(fifth)
            } else if instrument == .mandolin {
                var body = Path(); body.move(to: p(0.46, 0.43))
                body.addCurve(to: p(0.5, 0.94), control1: p(0.08, 0.73), control2: p(0.08, 0.93))
                body.addCurve(to: p(0.54, 0.43), control1: p(0.92, 0.93), control2: p(0.92, 0.73)); line(body)
            } else {
                let wide: CGFloat = instrument == .cello ? 0.38 : instrument == .viola ? 0.34 : 0.31
                var body = Path(); body.move(to: p(0.46, bodyTop))
                if instrument == .bass {
                    body.addCurve(to: p(0.30, 0.47), control1: p(0.34, 0.66), control2: p(0.38, 0.43))
                    body.addCurve(to: p(0.24, 0.74), control1: p(0.20, 0.48), control2: p(0.38, 0.64))
                } else {
                    body.addCurve(to: p(0.5 - wide * 0.57, 0.66), control1: p(0.5 - wide, bodyTop), control2: p(0.5 - wide, 0.58))
                    body.addQuadCurve(to: p(0.5 - wide * 0.82, 0.76), control: p(0.43, 0.70))
                }
                body.addCurve(to: p(0.5, 0.93), control1: p(0.08, 0.85), control2: p(0.22, 0.93))
                body.addCurve(to: p(0.5 + wide * 0.82, 0.76), control1: p(0.78, 0.93), control2: p(0.92, 0.85))
                body.addQuadCurve(to: p(0.5 + wide * 0.57, 0.66), control: p(0.57, 0.70))
                body.addCurve(to: p(0.54, bodyTop), control1: p(0.5 + wide, 0.58), control2: p(0.5 + wide, bodyTop)); line(body)
                if !bowed && instrument != .bass {
                    line(Path(ellipseIn: CGRect(x: size.width * 0.42, y: size.height * 0.63, width: size.width * 0.16, height: size.height * 0.085)), 0.8)
                }
            }
            line(Path(roundedRect: CGRect(x: size.width * 0.43, y: size.height * 0.03, width: size.width * 0.14, height: size.height * 0.16), cornerRadius: 2))
            if bowed {
                line(Path(ellipseIn: CGRect(x: size.width * 0.43, y: size.height * 0.02, width: size.width * 0.14, height: size.height * 0.07)), 0.8)
                for x: CGFloat in [0.34, 0.66] {
                    var f = Path(); f.move(to: p(x + 0.03, 0.64)); f.addCurve(to: p(x - 0.03, 0.79), control1: p(x - 0.07, 0.62), control2: p(x + 0.06, 0.81)); line(f, 0.8)
                }
            }
            var bridge = Path(); bridge.move(to: p(0.37, 0.82)); bridge.addLine(to: p(0.63, 0.82)); line(bridge, 0.8)
            if instrument == .cello { var pin = Path(); pin.move(to: p(0.5, 0.93)); pin.addLine(to: p(0.5, 1)); line(pin) }
            for y: CGFloat in [0.08, 0.14] {
                var peg = Path(); peg.move(to: p(0.35, y)); peg.addLine(to: p(0.65, y)); line(peg, 0.8)
            }
        }.frame(width: 30, height: 50).accessibilityHidden(true)
    }
}

struct InstrumentPickerRow: View {
    @Environment(\.tunerTheme) private var theme
    let instrument: Instrument
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 22) {
                InstrumentIcon(instrument: instrument)
                Text(instrument.rawValue).font(.system(size: 17))
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(theme.style.tuned).font(.system(size: 18, weight: .medium)) }
            }.padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, minHeight: 68)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) { Rectangle().fill(theme.style.silver).frame(height: 0.5) }
        }.buttonStyle(.plain).accessibilityLabel(instrument.rawValue).accessibilityValue(selected ? "Selected" : "")
    }
}
