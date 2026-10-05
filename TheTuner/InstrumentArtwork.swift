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
    var artHeight: CGFloat { instrument == .ukulele ? 340 : 400 }
    var artScale: CGFloat { min(size.width / (360 * breadth), size.height / artHeight) }
    var artOrigin: CGPoint { CGPoint(x: (size.width - 400 * artScale * breadth) / 2, y: (size.height - artHeight * artScale) * 0.35) }
    var nutY: CGFloat { instrument.bowed ? 0.9225 : shortDrone ? 0.78 : 0.92 }
    func artPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: artOrigin.x + x * artScale * breadth, y: artOrigin.y + y * artScale)
    }
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { artPoint(x * 400, y * artHeight) }
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
            let row = CGFloat(count - 1 - i) / CGFloat(max(1, count - 1))
            return point(0.56 - row * 0.15, 0.18 + row * 0.58)
        }
        let side = left(i)
        let row: Int
        let rows: Int
        if shortDrone { row = side ? 2 - i : i - 3; rows = 2 }
        else { row = side ? half - 1 - i : i - half; rows = side ? half : count - half }
        let paired = instrument == .mandolin
        let physicalRow = paired ? row * 2 + member : row
        let physicalRows = paired ? rows * 2 : rows
        let top: CGFloat = instrument.bowed ? 0.40 : instrument == .mandolin ? 0.28 : instrument == .ukulele ? 0.27 : 0.22
        let span: CGFloat = instrument.bowed ? 0.42 : shortDrone ? 0.36 : instrument == .mandolin ? 0.43 : instrument == .ukulele ? 0.40 : 0.52
        let y = top + CGFloat(physicalRow) * span / CGFloat(max(1, physicalRows - 1))
        if instrument.bowed {
            // Follow the slanted pegbox walls, including custom string counts.
            let x = side ? 0.40 + (y - 0.40) * 0.14 : 0.50 + (y - 0.40) * 0.27
            return point(x, y)
        }
        return point(side ? 0.38 : 0.62, y)
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
    // The shaft follows the normal of the inline bass rail, rather than a separate tilt.
    var machineTilt: CGFloat { inlineBass ? atan2(0.15, 0.69) : 0 }
    func machineHandle(_ i: Int, member: Int = 0) -> CGPoint {
        let post = post(i, member: member)
        if instrument.bowed { return target(i) }
        if shortDrone && i == 0 { return point(0.29, 0.94) }
        if inlineBass {
            return CGPoint(x: post.x - 82 * cos(machineTilt) * artScale,
                           y: post.y - 82 * sin(machineTilt) * artScale)
        }
        // Leave the whole button outside the widest part of the headstock.
        let leftX: CGFloat = instrument == .bass ? 0.25 : 0.24
        return CGPoint(x: point(left(i) ? leftX : 1 - leftX, 0).x, y: post.y)
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
                    // Slanted tuner rail, rounded crown and scooped treble shoulder.
                    outline.move(to: p(0.41, layout.nutY))
                    outline.addCurve(to: p(0.32, 0.83), control1: p(0.41, 0.85), control2: p(0.30, 0.88))
                    outline.addLine(to: p(0.47, 0.14))
                    outline.addCurve(to: p(0.60, 0.045), control1: p(0.49, 0.065), control2: p(0.53, 0.025))
                    outline.addCurve(to: p(0.70, 0.19), control1: p(0.69, 0.055), control2: p(0.75, 0.13))
                    outline.addCurve(to: p(0.62, 0.35), control1: p(0.67, 0.24), control2: p(0.61, 0.26))
                    outline.addCurve(to: p(0.69, 0.70), control1: p(0.62, 0.48), control2: p(0.71, 0.60))
                    outline.addCurve(to: p(0.59, layout.nutY), control1: p(0.68, 0.79), control2: p(0.59, 0.80))
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
                    case .bass:
                        outline.addQuadCurve(to: p(0.36, 0.055), control: p(0.295, 0.045))
                        outline.addLine(to: p(0.64, 0.055))
                        outline.addQuadCurve(to: p(0.71, 0.13), control: p(0.705, 0.045))
                    default:
                        outline.addCurve(to: p(0.71, 0.13), control1: p(0.47, 0.015), control2: p(0.53, 0.015))
                    }
                    outline.addLine(to: p(0.67, layout.nutY - 0.20))
                    outline.addCurve(to: p(0.59, layout.nutY), control1: p(0.665, layout.nutY - 0.12), control2: p(0.59, layout.nutY - 0.08))
                }
                outline.addLine(to: p(0.59, 1)); outline.addLine(to: p(0.41, 1))
                outline.addLine(to: p(0.41, layout.nutY))
                if !layout.inlineBass {
                    outline.addCurve(to: p(0.33, layout.nutY - 0.20), control1: p(0.41, layout.nutY - 0.08), control2: p(0.335, layout.nutY - 0.12))
                }
                outline.closeSubpath(); stroke(outline)
            }
            if !instrument.bowed {
                let nutStart = p(0.40, layout.nutY)
                let nut = Path(CGRect(x: nutStart.x, y: nutStart.y, width: 80 * layout.artScale, height: 4 * layout.artScale))
                stroke(nut, style.ink.opacity(0.8), 0.9)
            }
            if instrument == .ukulele {
                var flower = context
                UkuleleFlowerArtwork.draw(in: &flower, layout: layout, style: style)
            }
            for i in 0..<layout.count {
                let color = selected == i ? (inTune ? style.tuned : style.orange) : completed.contains(i) ? style.tuned.opacity(0.7) : style.ink.opacity(0.7)
                let copies = instrument == .mandolin ? 2 : 1
                for member in 0..<copies {
                    let post = layout.post(i, member: member)
                    let drone = layout.shortDrone && i == 0
                    let side = layout.inlineBass || layout.left(i)
                    let handle = layout.machineHandle(i, member: member)
                    if !instrument.bowed {
                        var axle = Path(); axle.move(to: post); axle.addLine(to: handle); stroke(axle, style.muted, 1)
                    }
                    if instrument.bowed {
                        let radius = 25 * layout.artScale
                        let shaftEnd = CGPoint(x: handle.x + (side ? radius * 0.8 : -radius * 0.8), y: handle.y)
                        let referenceY = (post.y - layout.artOrigin.y) / layout.artScale
                        let upperWall = BowedHeadstockArtwork.wallPoint(at: referenceY - 4, left: side)
                        let lowerWall = BowedHeadstockArtwork.wallPoint(at: referenceY + 4, left: side)
                        var shaft = Path()
                        shaft.move(to: layout.artPoint(upperWall.x, upperWall.y))
                        shaft.addLine(to: CGPoint(x: shaftEnd.x, y: shaftEnd.y - 5 * layout.artScale))
                        shaft.addLine(to: CGPoint(x: shaftEnd.x, y: shaftEnd.y + 5 * layout.artScale))
                        shaft.addLine(to: layout.artPoint(lowerWall.x, lowerWall.y)); shaft.closeSubpath()
                        context.fill(shaft, with: .color(style.ink.opacity(0.14))); stroke(shaft, style.ink.opacity(0.8), 0.8)
                        let knob = Path(ellipseIn: CGRect(x: handle.x - radius, y: handle.y - radius * 0.91,
                                                        width: radius * 2, height: radius * 1.82))
                        context.fill(knob, with: .color(style.face))
                        context.fill(knob, with: .linearGradient(Gradient(colors: [style.ink.opacity(0.04), style.ink.opacity(0.16), style.ink.opacity(0.04)]),
                                                              startPoint: CGPoint(x: handle.x - radius, y: handle.y), endPoint: CGPoint(x: handle.x + radius, y: handle.y)))
                        stroke(knob, color, selected == i ? 1.5 : 0.9)
                    } else if instrument != .bass {
                        let knob = Path(roundedRect: CGRect(x: handle.x - 12 * layout.artScale, y: handle.y - 14 * layout.artScale,
                                                           width: 24 * layout.artScale, height: 28 * layout.artScale), cornerRadius: 7 * layout.artScale)
                        context.fill(knob, with: .color(style.face)); stroke(knob, color, selected == i ? 1.4 : 1)
                    }
                    if instrument == .bass {
                        var clover = Path()
                        func c(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                            let mirroredX = x * (side ? 1 : -1)
                            let angle = layout.machineTilt
                            return CGPoint(x: handle.x + (mirroredX * cos(angle) - y * sin(angle)) * layout.artScale,
                                           y: handle.y + (mirroredX * sin(angle) + y * cos(angle)) * layout.artScale)
                        }
                        // Top and bottom lobes mirror exactly about the shaft's centerline.
                        clover.move(to: c(16, -5))
                        clover.addCurve(to: c(5, -19), control1: c(10, -5), control2: c(10, -14))
                        clover.addCurve(to: c(-18, -16), control1: c(-2, -29), control2: c(-18, -28))
                        clover.addCurve(to: c(-16, -9), control1: c(-18, -13), control2: c(-17, -10))
                        clover.addCurve(to: c(-16, 9), control1: c(-38, -14), control2: c(-38, 14))
                        clover.addCurve(to: c(-18, 16), control1: c(-17, 10), control2: c(-18, 13))
                        clover.addCurve(to: c(5, 19), control1: c(-18, 28), control2: c(-2, 29))
                        clover.addCurve(to: c(16, 5), control1: c(10, 14), control2: c(10, 5))
                        clover.closeSubpath()
                        context.fill(clover, with: .color(style.face)); stroke(clover, color, selected == i ? 1.4 : 1)

                    }
                    let endX = layout.stringX(i, member: member)
                    var string = Path()
                    if instrument.bowed {
                        // Strings wind around the pegs inside the box, not around its outer wall.
                        string.move(to: post)
                        let referenceX = (endX - layout.artOrigin.x) / (layout.artScale * layout.breadth)
                        let nutY = 369 - 4 * (referenceX - 190) / 79
                        string.addLine(to: layout.artPoint(referenceX, nutY))
                        string.addLine(to: layout.artPoint(referenceX + 4, 400))
                    } else {
                        string.move(to: post)
                        // The drone starts at the fifth fret; it never reaches the nut or peghead.
                        if !drone { string.addLine(to: CGPoint(x: endX, y: p(0, layout.nutY).y + 4 * layout.artScale)) }
                        string.addLine(to: CGPoint(x: endX, y: p(0, 1).y))
                    }
                    if selected == i {
                        context.drawLayer { glow in
                            glow.addFilter(.blur(radius: 3)); glow.stroke(string, with: .color(color.opacity(0.2)), lineWidth: 4)
                        }
                    }
                    stroke(string, color, widths[i])
                    if instrument.bowed {
                        let radius = 2.3 * layout.artScale
                        let winding = Path(ellipseIn: CGRect(x: post.x - radius, y: post.y - radius,
                                                            width: radius * 2, height: radius * 2))
                        context.fill(winding, with: .color(style.face))
                        stroke(winding, color, 0.75)
                    }
                    if !instrument.bowed && !drone {
                        let circle = Path(ellipseIn: CGRect(x: post.x - 7, y: post.y - 7, width: 14, height: 14))
                        context.fill(circle, with: .color(style.face)); stroke(circle, color, selected == i ? 1.6 : 0.8)
                        stroke(Path(ellipseIn: CGRect(x: post.x - 4, y: post.y - 4, width: 8, height: 8)), color, 0.7)
                    }
                }
                let target = layout.target(i)
                if completed.contains(i) {
                    if !instrument.bowed && !(layout.shortDrone && i == 0) {
                        let circle = Path(ellipseIn: CGRect(x: target.x - 9, y: target.y - 9, width: 18, height: 18))
                        context.fill(circle, with: .color(style.face)); stroke(circle, style.tuned, 1.5)
                    }
                    var check = Path(); check.move(to: CGPoint(x: target.x - 4, y: target.y))
                    check.addLine(to: CGPoint(x: target.x - 1, y: target.y + 3)); check.addLine(to: CGPoint(x: target.x + 4, y: target.y - 3))
                    stroke(check, style.tuned, 1.6)
                }
                if !instrument.bowed {
                    var guide = Path()
                    let side = layout.left(i)
                    let outerKeyX = layout.machineHandle(i).x
                    let endpoint = instrument == .mandolin ? p(side ? 0.18 : 0.82, 0).x : layout.inlineBass ? p(0.72, 0).x
                        : outerKeyX + (side ? -1 : 1) * (instrument == .bass ? 39 : 20) * layout.artScale
                    guide.move(to: CGPoint(x: p(side ? 0.16 : 0.84, 0).x, y: target.y))
                    guide.addLine(to: CGPoint(x: endpoint, y: target.y))
                    // The wide bass keys already sit next to their labels; a tiny leader adds clutter.
                    if instrument != .bass || layout.inlineBass {
                        stroke(guide, style.muted.opacity(0.7), 0.7)
                    }
                    if instrument == .mandolin {
                        // A quiet bracket groups two physical strings under one course label.
                        let bracketX = p(side ? 0.18 : 0.82, 0).x
                        let first = layout.post(i), second = layout.post(i, member: 1)
                        let arm = (side ? 1.0 : -1.0) * 4 * layout.artScale
                        var bracket = Path()
                        bracket.move(to: CGPoint(x: bracketX + arm, y: first.y))
                        bracket.addLine(to: CGPoint(x: bracketX, y: first.y))
                        bracket.addLine(to: CGPoint(x: bracketX, y: second.y))
                        bracket.addLine(to: CGPoint(x: bracketX + arm, y: second.y))
                        stroke(bracket, style.muted.opacity(0.5), 0.65)
                    }
                }

            }
        }.accessibilityHidden(true)
    }
}

/// A small hibiscus inlay above the strings, drawn in the same fine-line language.
private enum UkuleleFlowerArtwork {
    static func draw(in context: inout GraphicsContext, layout: InstrumentHeadLayout, style: CleanStyle) {
        let center = layout.point(0.5, 0.145)
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: layout.artScale, y: layout.artScale)
        func polar(_ degrees: CGFloat, _ radius: CGFloat) -> CGPoint {
            let angle = degrees * .pi / 180
            return CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        }
        var petals = Path()
        petals.move(to: polar(-126, 6))
        for petal in 0..<5 {
            let angle = CGFloat(petal) * 72 - 90
            petals.addCurve(to: polar(angle + 36, 6),
                            control1: polar(angle - 27, 22), control2: polar(angle + 27, 22))
        }
        petals.closeSubpath()
        context.fill(petals, with: .color(style.orange.opacity(0.08)))
        let line = StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
        context.stroke(petals, with: .color(style.orange.opacity(0.85)), style: line)
        var stamen = Path()
        stamen.move(to: .zero)
        stamen.addCurve(to: CGPoint(x: 10, y: -12), control1: CGPoint(x: 5, y: -1), control2: CGPoint(x: 10, y: -7))
        context.stroke(stamen, with: .color(style.orange.opacity(0.85)), style: line)
        context.fill(Path(ellipseIn: CGRect(x: 8.7, y: -13.3, width: 2.6, height: 2.6)), with: .color(style.orange))
        context.fill(Path(ellipseIn: CGRect(x: -1.5, y: -1.5, width: 3, height: 3)), with: .color(style.orange))
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
