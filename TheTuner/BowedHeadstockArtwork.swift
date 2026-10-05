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

    static let box: [Surface] = [
        // Rear wall, carved heel and the short fingerboard emerging below the nut.
        Surface("M 150 118 C 170 116 195 131 214 153 C 237 190 257 267 265 348 L 268 377 L 279 400 L 194 400 L 186 370 C 178 346 164 291 158 243 L 145 159 Z", 0.07),
        Surface("M 204 151 C 230 169 252 237 263 307 L 269 369 L 254 370 C 252 301 235 218 204 173 Z", 0.19),
        // Open trough. The strings and axles remain separate, interactive paths.
        Surface("M 158 153 L 184 167 C 211 188 237 272 248 356 L 198 361 C 181 301 168 224 158 153 Z", 0.025),
        Surface("M 145 142 L 158 153 C 170 230 181 300 198 361 L 186 369 C 168 314 155 235 145 166 Z", 0.15),
        Surface("M 186 369 L 269 364 L 270 373 L 190 378 Z", 0.30),
        Surface("M 193 378 L 270 374 L 274 400 L 194 400 Z", 0.04)
    ]
    static let scroll: [Surface] = [
        // Far cheek and the back ridge lean away from the player.
        Surface("M 205 15 C 219 2 230 25 237 50 C 246 78 249 105 242 124 L 226 145 L 207 131 C 218 113 219 91 214 67 C 211 42 208 25 205 15 Z", 0.13),
        Surface("M 225 41 C 239 52 246 78 247 98 C 253 95 257 98 257 110 C 257 123 252 132 246 132 L 238 127 C 239 100 233 70 225 41 Z", 0.035),
        Surface("M 195 12 C 207 5 216 24 225 47 C 236 78 239 104 230 128 C 226 140 218 146 211 144 L 197 132 C 211 103 210 63 195 31 Z", 0.24),
        Surface("M 184 11 C 199 1 211 31 216 56 C 223 86 222 115 208 133 C 201 144 190 148 179 143 L 175 132 C 193 125 200 104 201 84 C 201 54 193 30 184 11 Z", 0.085),
        // Front carved cheek: the rolled termination projects from a tall, sculpted face.
        Surface("M 178 11 C 163 8 160 33 153 48 C 149 55 141 58 139 69 C 133 74 130 84 131 99 C 131 115 144 125 157 121 C 166 119 172 114 175 105 C 178 119 173 132 163 137 C 173 149 190 146 199 132 C 212 112 211 85 207 61 C 203 37 190 8 178 11 Z", 0.095),
        Surface("M 177 19 C 184 38 189 62 187 85 C 185 107 174 124 159 127 C 155 132 157 138 164 141 C 182 138 195 120 198 99 C 201 70 192 38 180 18 Z", 0.22),
        Surface("M 152 51 C 163 48 171 55 174 66 C 179 84 174 104 166 112 L 151 117 C 159 104 163 89 160 74 C 158 62 154 58 152 51 Z", 0.13),
        // Cylindrical eye, front ellipse and recessed carved curl.
        Surface("M 138 68 C 149 65 158 71 161 82 C 165 96 160 110 151 115 L 134 116 C 144 107 148 93 144 80 Z", 0.25),
        Surface("M 134 68 C 124 69 122 80 124 96 C 126 111 131 119 139 116 C 149 113 153 100 150 86 C 148 73 143 67 134 68 Z", 0.035)
    ]
    // Only silhouette and construction edges are inked. The carved faces below are
    // shading, not a stack of outlined slices competing with the live strings.
    static let boxEdges: [Path] = [
        contour("M 150 118 C 170 116 195 131 214 153 C 237 190 257 267 265 348 L 268 377 L 279 400 L 194 400 L 186 370 C 178 346 164 291 158 243 L 145 159 Z"),
        contour("M 158 153 L 184 167 C 211 188 237 272 248 356 M 158 153 C 170 230 181 300 198 361"),
        contour("M 186 369 L 269 364 L 270 373 L 190 378 Z")
    ]
    static let scrollEdges: [Path] = [
        contour("M 134 68 C 134 60 148 55 153 48 C 160 33 163 8 178 11 C 190 5 196 9 205 15 C 219 2 230 25 237 50 C 246 78 249 90 247 98 C 253 95 257 98 257 110 C 257 123 252 132 246 132 L 238 127 L 226 145 C 214 139 209 141 199 142 C 184 150 168 143 157 121 L 139 116"),
        contour("M 178 11 C 195 31 209 72 204 103 C 201 128 186 144 170 139"),
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
