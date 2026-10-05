import SwiftUI

/// One source of geometry for the drawing, string targets and completion feedback.
struct InstrumentHeadLayout {
    let instrument: Instrument
    let count: Int
    let size: CGSize
    var shortDrone: Bool { instrument == .banjo && count == 5 }
    var inlineBass: Bool { instrument == .bass && count <= 4 }
    var half: Int { (count + 1) / 2 }
    var breadth: CGFloat { instrument == .cello ? 1.08 : instrument == .viola ? 1.025 : 1 }
    var artScale: CGFloat { min(size.width / (360 * breadth), size.height / 400) }
    var artOrigin: CGPoint { CGPoint(x: (size.width - 400 * artScale * breadth) / 2, y: (size.height - 400 * artScale) * 0.25) }
    var nutY: CGFloat { instrument.bowed ? 0.9225 : shortDrone ? 0.78 : 0.92 }
    func artPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: artOrigin.x + x * artScale * breadth, y: artOrigin.y + y * artScale)
    }
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { artPoint(x * 400, y * 400) }
    func left(_ i: Int) -> Bool {
        if inlineBass { return false } // Labels opposite the inline keys.
        if shortDrone { return i < 3 }
        return i < half
    }
    func post(_ i: Int, member: Int = 0) -> CGPoint {
        if instrument.bowed, count == 4 {
            let posts: [CGPoint] = [CGPoint(x: 180, y: 299), CGPoint(x: 162, y: 205), CGPoint(x: 204, y: 180), CGPoint(x: 229, y: 278)]
            return artPoint(posts[i].x, posts[i].y)
        }
        if shortDrone && i == 0 { return point(0.39, 0.94) }
        if inlineBass {
            return point(0.53, 0.18 + CGFloat(count - 1 - i) * 0.58 / CGFloat(max(1, count - 1)))
        }
        let side = left(i)
        let row: Int
        let rows: Int
        if shortDrone { row = side ? 2 - i : i - 3; rows = 2 }
        else { row = side ? half - 1 - i : i - half; rows = side ? half : count - half }
        let paired = instrument == .mandolin
        let physicalRow = paired ? row * 2 + member : row
        let physicalRows = paired ? rows * 2 : rows
        let top: CGFloat = instrument.bowed ? 0.37 : instrument == .mandolin ? 0.28 : 0.22
        let span: CGFloat = instrument.bowed ? 0.44 : shortDrone ? 0.36 : instrument == .mandolin ? 0.43 : 0.52
        let y = top + CGFloat(physicalRow) * span / CGFloat(max(1, physicalRows - 1))
        return point(side ? (instrument.bowed ? 0.44 : 0.38) : (instrument.bowed ? 0.59 : 0.62), y)
    }
    func target(_ i: Int) -> CGPoint {
        if instrument.bowed, count == 4 {
            let handles: [CGPoint] = [CGPoint(x: 95, y: 299), CGPoint(x: 95, y: 205), CGPoint(x: 295, y: 178), CGPoint(x: 316, y: 277)]
            return artPoint(handles[i].x, handles[i].y)
        }
        let post = post(i)
        if instrument.bowed { return CGPoint(x: point(left(i) ? 0.24 : 0.79, 0).x, y: post.y) }
        if shortDrone && i == 0 { return point(0.29, 0.94) }
        if instrument == .mandolin { return CGPoint(x: post.x, y: (post.y + self.post(i, member: 1).y) / 2) }
        return post
    }
    func stringX(_ i: Int, member: Int = 0) -> CGFloat {
        if instrument.bowed { return artPoint(194 + CGFloat(i) * 57 / CGFloat(max(1, count - 1)), 369).x }
        return point(0.407 + CGFloat(i) * 0.186 / CGFloat(max(1, count - 1)), 0).x
            + (instrument == .mandolin ? (member == 0 ? -1.7 : 1.7) * artScale : 0)
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
                var carved = context
                BowedHeadstockArtwork.draw(in: &carved, layout: layout, style: style)
            } else {
                if layout.inlineBass {
                    outline.move(to: p(0.43, 0.72))
                    outline.addCurve(to: p(0.50, 0.07), control1: p(0.34, 0.44), control2: p(0.42, 0.06))
                    outline.addCurve(to: p(0.66, 0.23), control1: p(0.68, 0.02), control2: p(0.72, 0.14))
                    outline.addCurve(to: p(0.59, 0.76), control1: p(0.55, 0.38), control2: p(0.66, 0.56))
                } else {
                    outline.move(to: p(0.29, 0.13))
                    switch instrument {
                    case .ukulele:
                        outline.addQuadCurve(to: p(0.36, 0.055), control: p(0.28, 0.055))
                        outline.addQuadCurve(to: p(0.64, 0.055), control: p(0.50, 0.015))
                        outline.addQuadCurve(to: p(0.71, 0.13), control: p(0.72, 0.055))
                    case .banjo, .mandolin:
                        outline.addQuadCurve(to: p(0.37, 0.08), control: p(0.36, 0.16))
                        outline.addQuadCurve(to: p(0.50, 0.015), control: p(0.46, 0.07))
                        outline.addQuadCurve(to: p(0.63, 0.08), control: p(0.54, 0.07))
                        outline.addQuadCurve(to: p(0.71, 0.13), control: p(0.64, 0.16))
                    default:
                        outline.addCurve(to: p(0.71, 0.13), control1: p(0.47, 0.015), control2: p(0.53, 0.015))
                    }
                    outline.addLine(to: p(0.67, layout.nutY - 0.17))
                    outline.addQuadCurve(to: p(0.59, layout.nutY), control: p(0.60, layout.nutY - 0.07))
                }
                outline.addLine(to: p(0.59, 1)); outline.addLine(to: p(0.41, 1))
                outline.addLine(to: p(0.41, layout.nutY))
                if !layout.inlineBass {
                    outline.addQuadCurve(to: p(0.33, layout.nutY - 0.17), control: p(0.40, layout.nutY - 0.07))
                }
                outline.closeSubpath(); stroke(outline)
            }
            if !instrument.bowed {
                let nutStart = p(0.40, layout.nutY)
                let nut = Path(CGRect(x: nutStart.x, y: nutStart.y, width: 80 * layout.artScale, height: 4 * layout.artScale))
                stroke(nut, style.ink.opacity(0.8), 0.9)
            }
            for i in 0..<layout.count {
                let color = selected == i ? (inTune ? style.tuned : style.orange) : completed.contains(i) ? style.tuned.opacity(0.7) : style.ink.opacity(0.7)
                let copies = instrument == .mandolin ? 2 : 1
                for member in 0..<copies {
                    let post = layout.post(i, member: member)
                    let drone = layout.shortDrone && i == 0
                    let side = layout.inlineBass || layout.left(i)
                    let handleX: CGFloat = drone ? 0.29 : side ? (instrument.bowed ? 0.29 : layout.inlineBass ? 0.34 : 0.28) : (instrument.bowed ? 0.76 : 0.72)
                    let handle = instrument.bowed ? layout.target(i) : CGPoint(x: p(handleX, 0).x, y: post.y)
                    var axle = Path(); axle.move(to: post); axle.addLine(to: handle); stroke(axle, style.muted, 1)
                    if instrument.bowed {
                        let radius = 25 * layout.artScale
                        let shaftEnd = CGPoint(x: handle.x + (side ? radius * 0.8 : -radius * 0.8), y: handle.y)
                        var shaft = Path()
                        shaft.move(to: CGPoint(x: post.x, y: post.y - 4 * layout.artScale))
                        shaft.addLine(to: CGPoint(x: shaftEnd.x, y: shaftEnd.y - 5 * layout.artScale))
                        shaft.addLine(to: CGPoint(x: shaftEnd.x, y: shaftEnd.y + 5 * layout.artScale))
                        shaft.addLine(to: CGPoint(x: post.x, y: post.y + 4 * layout.artScale)); shaft.closeSubpath()
                        context.fill(shaft, with: .color(style.ink.opacity(0.14))); stroke(shaft, style.ink.opacity(0.8), 0.8)
                        let rim = Path(ellipseIn: CGRect(x: handle.x - radius - 2, y: handle.y - radius * 0.91 - 1,
                                                       width: radius * 2 + 4, height: radius * 1.82 + 2))
                        context.fill(rim, with: .color(style.face)); stroke(rim, color, 1)
                        let knob = Path(ellipseIn: CGRect(x: handle.x - radius, y: handle.y - radius * 0.91,
                                                        width: radius * 2, height: radius * 1.82))
                        context.fill(knob, with: .linearGradient(Gradient(colors: [style.ink.opacity(0.04), style.ink.opacity(0.16), style.ink.opacity(0.04)]),
                                                              startPoint: CGPoint(x: handle.x - radius, y: handle.y), endPoint: CGPoint(x: handle.x + radius, y: handle.y)))
                        stroke(knob, style.ink.opacity(0.9), 0.9)
                    } else if instrument != .bass {
                        let knob = Path(roundedRect: CGRect(x: handle.x - 12 * layout.artScale, y: handle.y - 14 * layout.artScale,
                                                           width: 24 * layout.artScale, height: 28 * layout.artScale), cornerRadius: 7 * layout.artScale)
                        context.fill(knob, with: .color(style.face)); stroke(knob, style.ink.opacity(0.85), 1)
                        stroke(knob.offsetBy(dx: -2 * layout.artScale, dy: 0), style.ink.opacity(0.35), 0.7)
                    }
                    if instrument == .bass {
                        var clover = Path()
                        func c(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: handle.x + x * layout.artScale, y: handle.y + y * layout.artScale) }
                        clover.move(to: c(0, -12))
                        clover.addCurve(to: c(-13, -3), control1: c(-12, -21), control2: c(-24, -8))
                        clover.addCurve(to: c(-3, 13), control1: c(-25, 8), control2: c(-13, 24))
                        clover.addCurve(to: c(13, 3), control1: c(8, 26), control2: c(25, 13))
                        clover.addCurve(to: c(0, -12), control1: c(25, -9), control2: c(12, -23))
                        clover.closeSubpath()
                        context.fill(clover, with: .color(style.face)); stroke(clover, style.ink.opacity(0.9), 1)

                    }
                    let endX = layout.stringX(i, member: member)
                    var string = Path(); string.move(to: post)
                    // The drone starts at the fifth fret; it never reaches the nut or peghead.
                    if !drone { string.addLine(to: CGPoint(x: endX, y: p(0, layout.nutY).y + 4 * layout.artScale)) }
                    string.addLine(to: CGPoint(x: endX + (instrument.bowed ? 3 * layout.artScale : 0), y: p(0, 1).y))
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
                    stroke(Path(ellipseIn: CGRect(x: target.x - 28 * layout.artScale, y: target.y - 25 * layout.artScale, width: 56 * layout.artScale, height: 50 * layout.artScale)), color, 1.3)
                }
                if !instrument.bowed {
                    var guide = Path()
                    let side = layout.left(i)
                    guide.move(to: CGPoint(x: p(side ? 0.16 : 0.84, 0).x, y: target.y))
                    guide.addLine(to: CGPoint(x: target.x + (side ? -13 : 13), y: target.y))
                    stroke(guide, style.muted.opacity(0.7), 0.7)
                }

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
