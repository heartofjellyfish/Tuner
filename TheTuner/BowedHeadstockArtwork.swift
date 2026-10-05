import SwiftUI

/// Reference-space contours traced from the approved three-quarter scroll illustration.
/// The pegbox, carved scroll faces and peg handles are separate surfaces, not a spiral icon.
enum BowedHeadstockArtwork {
    struct Surface {
        let path: Path
        let light: Double
        init(_ data: String, _ light: Double = 0) { self.path = contour(data); self.light = light }
    }
    // Absolute M/L/C/Q/Z coordinates on a 400 × 400 artboard. Keeping these as contours
    // makes the approved silhouette editable without a raster background or baked-in strings.
    private static func contour(_ data: String) -> Path {
        let scanner = Scanner(string: data)
        scanner.charactersToBeSkipped = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        func point() -> CGPoint {
            guard let x = scanner.scanDouble(), let y = scanner.scanDouble() else { preconditionFailure("Invalid artwork coordinate") }
            return CGPoint(x: x, y: y)
        }
        var path = Path()
        while !scanner.isAtEnd {
            guard let command = scanner.scanCharacters(from: CharacterSet(charactersIn: "MLCQZ")) else { preconditionFailure("Invalid artwork contour") }
            switch command {
            case "M": path.move(to: point())
            case "L": path.addLine(to: point())
            case "C": let a = point(), b = point(), end = point(); path.addCurve(to: end, control1: a, control2: b)
            case "Q": let control = point(), end = point(); path.addQuadCurve(to: end, control: control)
            case "Z": path.closeSubpath()
            default: preconditionFailure("Unsupported artwork command")
            }
        }
        return path
    }

    // Shared endpoints and continuous curves keep the scroll, heel and pegbox
    // connected. Shaded faces use those same boundaries rather than old carved slices.
    static let box: [Surface] = [
        Surface("M 151 118 C 143 170 161 299 190 369 L 194 400 L 274 400 L 269 369 C 263 284 241 184 210 137 Z", 0.035),
        Surface("M 210 137 C 241 184 263 284 269 369 L 258 370 C 251 286 232 188 210 137 Z", 0.10)
    ]
    static let scroll: [Surface] = [
        Surface("M 134 68 C 145 61 153 53 158 36 C 164 16 169 8 182 11 C 191 13 198 19 204 26 C 227 48 241 78 241 101 C 241 128 226 145 205 145 C 181 145 158 128 139 116 Z", 0.075),
        Surface("M 182 11 C 191 13 198 19 204 26 C 227 48 241 78 241 101 C 241 128 226 145 205 145 C 184 145 165 133 151 123 C 172 135 193 123 199 101 C 205 76 197 48 182 27 Z", 0.14),
        Surface("M 134 68 C 124 69 122 80 124 96 C 126 111 131 119 139 116 C 149 113 153 100 150 86 C 148 73 143 67 134 68 Z", 0.035)
    ]
    private static let leftWall = (start: CGPoint(x: 151, y: 118), c1: CGPoint(x: 143, y: 170),
                                   c2: CGPoint(x: 161, y: 299), end: CGPoint(x: 190, y: 369))
    private static let rightWall = (start: CGPoint(x: 210, y: 137), c1: CGPoint(x: 241, y: 184),
                                    c2: CGPoint(x: 263, y: 284), end: CGPoint(x: 269, y: 369))
    private static var boxOutline: Path {
        var path = Path()
        path.move(to: leftWall.start)
        path.addCurve(to: leftWall.end, control1: leftWall.c1, control2: leftWall.c2)
        path.addLine(to: CGPoint(x: 194, y: 400)); path.addLine(to: CGPoint(x: 274, y: 400))
        path.addLine(to: rightWall.end)
        path.addCurve(to: rightWall.start, control1: rightWall.c2, control2: rightWall.c1)
        return path
    }
    // Peg shafts emerge at the visible wall; their hidden ends must not cross the face.
    static func wallPoint(at y: CGFloat, left: Bool) -> CGPoint {
        let wall = left ? leftWall : rightWall
        func sample(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u*u*u*wall.start.x + 3*u*u*t*wall.c1.x + 3*u*t*t*wall.c2.x + t*t*t*wall.end.x,
                           y: u*u*u*wall.start.y + 3*u*u*t*wall.c1.y + 3*u*t*t*wall.c2.y + t*t*t*wall.end.y)
        }
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if sample(middle).y < y { low = middle } else { high = middle }
        }
        return sample((low + high) / 2)
    }
    static let boxEdges: [Path] = [
        boxOutline,
        contour("M 190 369 L 269 365 L 270 374 L 191 378 Z")
    ]
    static let scrollEdges: [Path] = [
        contour("M 134 68 C 145 61 153 53 158 36 C 164 16 169 8 182 11 C 191 13 198 19 204 26 C 227 48 241 78 241 101 C 241 128 226 145 205 145 C 181 145 158 128 139 116"),
        contour("M 182 27 C 197 48 205 76 199 101 C 193 123 172 135 151 123 C 157 120 164 115 168 109 C 178 92 176 73 166 62 C 162 58 158 57 154 58"),
        contour("M 134 68 C 124 69 122 80 124 96 C 126 111 131 119 139 116 C 149 113 153 100 150 86 C 148 73 143 67 134 68 Z"),
        contour("M 132 77 C 129 84 131 99 135 103 C 140 108 144 100 140 95")
    ]

    static func draw(in context: inout GraphicsContext, layout: InstrumentHeadLayout, style: CleanStyle) {
        let origin = layout.artOrigin
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: layout.artScale * layout.breadth, y: layout.artScale)
        func render(_ surface: Surface) {
            context.fill(surface.path, with: .color(style.face))
            context.fill(surface.path, with: .linearGradient(Gradient(stops: [
                .init(color: style.ink.opacity(surface.light * 0.12), location: 0),
                .init(color: style.ink.opacity(surface.light), location: 0.52),
                .init(color: style.ink.opacity(surface.light * 0.3), location: 1)
            ]), startPoint: CGPoint(x: 120, y: 100), endPoint: CGPoint(x: 269, y: 130)))

        }
        for surface in box { render(surface) }
        for path in boxEdges {
            context.stroke(path, with: .color(style.ink.opacity(0.76)), style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))
        }
        for surface in scroll { render(surface) }
        for path in scrollEdges {
            context.stroke(path, with: .color(style.ink.opacity(0.86)), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
        }
    }
}
