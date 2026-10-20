import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let model: AppModel
    @AppStorage(PreferenceKey.showPercentage) private var showPercentage = true

    var body: some View {
        let percent = model.battery?.percent
        HStack(spacing: 4) {
            Image(nsImage: RingIcon.image(fraction: Double(percent ?? 0) / 100))
            if showPercentage, let percent {
                Text("\(percent)%")
            }
        }
        .accessibilityLabel(percent.map { "Battery \($0) percent, \(model.activitySummary)" } ?? "Chargectl")
    }
}

/// A thin ring that fills clockwise from the top. Template image, so it follows the menu bar tint.
enum RingIcon {
    static func image(fraction: Double, size: CGFloat = 14) -> NSImage {
        let fraction = min(max(fraction, 0), 1)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let lineWidth: CGFloat = size / 8.75
            let circle = rect.insetBy(dx: lineWidth, dy: lineWidth)
            let track = NSBezierPath(ovalIn: circle)
            track.lineWidth = lineWidth
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()
            if fraction > 0 {
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: circle.width / 2, startAngle: 90,
                    endAngle: 90 - 360 * fraction, clockwise: true)
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
