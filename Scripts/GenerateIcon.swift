import AppKit
// Original vector app icon: the three note regions and one illuminated marker.
let size = 1024
let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
c.setFillColor(NSColor(calibratedWhite: 0.93, alpha: 1).cgColor)
c.fill(CGRect(x: 0, y: 0, width: size, height: size))
let panel = NSBezierPath(roundedRect: NSRect(x: 90, y: 90, width: 844, height: 844), xRadius: 90, yRadius: 90)
NSColor(calibratedWhite: 0.98, alpha: 1).setFill(); panel.fill()
NSColor(calibratedWhite: 0.78, alpha: 1).setStroke(); panel.lineWidth = 2; panel.stroke()
let origin = CGPoint(x: 512, y: 335)
for i in 0..<3 {
    let start = CGFloat(30 + i * 40 + 1) * .pi / 180
    let end = CGFloat(70 + i * 40 - 1) * .pi / 180
    c.beginPath(); c.addArc(center: origin, radius: 300, startAngle: start, endAngle: end, clockwise: false)
    c.setStrokeColor(NSColor(calibratedWhite: i == 1 ? 0.84 : 0.89, alpha: 1).cgColor)
    c.setLineWidth(55); c.strokePath()
}
let orange = NSColor(calibratedRed: 1, green: 0.58, blue: 0.10, alpha: 1)
c.saveGState(); c.setShadow(offset: .zero, blur: 32, color: orange.withAlphaComponent(0.65).cgColor)
c.setStrokeColor(orange.cgColor); c.setLineWidth(12); c.setLineCap(.round)
c.move(to: CGPoint(x: 512, y: 573)); c.addLine(to: CGPoint(x: 512, y: 705)); c.strokePath(); c.restoreGState()
c.setFillColor(orange.cgColor); c.fillEllipse(in: CGRect(x: 499, y: 269, width: 26, height: 26))
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: c.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "TheTuner/Assets.xcassets/AppIcon.appiconset/AppIcon.png"))
