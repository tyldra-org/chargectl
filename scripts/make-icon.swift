// Draws the Chargectl app icon and writes every size the asset catalog needs.
// Usage: swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// The charge ring on a dark tile: a green arc filled to 80% with a light tick marking the limit.
func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
        bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = size / 1024
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)

    // macOS icon grid: an 824 pt tile centred in 1024, corner radius about 185.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.addPath(tilePath)
    context.setFillColor(NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1).cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let background = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            NSColor(srgbRed: 0.20, green: 0.22, blue: 0.25, alpha: 1).cgColor,
            NSColor(srgbRed: 0.08, green: 0.09, blue: 0.10, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // A faint top highlight.
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
    context.setLineWidth(4)
    context.addPath(CGPath(roundedRect: tile.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
    context.strokePath()
    context.restoreGState()

    let center = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 255
    let width: CGFloat = 64
    context.setLineCap(.round)

    // Track.
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.09).cgColor)
    context.setLineWidth(width)
    context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()

    // Charge arc, clockwise from the top to 80%.
    let start = CGFloat.pi / 2
    let end = start - 2 * .pi * 0.8
    let arc = CGMutablePath()
    arc.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    let stroked = arc.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
    context.saveGState()
    context.addPath(stroked)
    context.clip()
    let green = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            NSColor(srgbRed: 0.45, green: 0.90, blue: 0.62, alpha: 1).cgColor,
            NSColor(srgbRed: 0.16, green: 0.66, blue: 0.40, alpha: 1).cgColor,
        ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(green, start: CGPoint(x: 512, y: 800), end: CGPoint(x: 512, y: 224), options: [])
    context.restoreGState()

    // Limit tick just past the end of the arc.
    let tickAngle = end - 0.16
    let inner = radius - width / 2 - 26
    let outer = radius + width / 2 + 26
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    context.setLineWidth(18)
    context.move(to: CGPoint(x: center.x + inner * cos(tickAngle), y: center.y + inner * sin(tickAngle)))
    context.addLine(to: CGPoint(x: center.x + outer * cos(tickAngle), y: center.y + outer * sin(tickAngle)))
    context.strokePath()

    // Bolt in the middle.
    let configuration = NSImage.SymbolConfiguration(pointSize: 230, weight: .semibold)
    if let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
        let tinted = NSImage(size: bolt.size, flipped: false) { rect in
            bolt.draw(in: rect)
            NSColor.white.withAlphaComponent(0.94).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let size = tinted.size
        tinted.draw(in: CGRect(x: 512 - size.width / 2, y: 512 - size.height / 2, width: size.width, height: size.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let data = drawIcon(size: CGFloat(pixels)).representation(using: .png, properties: [:])!
        try data.write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icons to \(output.path)")
