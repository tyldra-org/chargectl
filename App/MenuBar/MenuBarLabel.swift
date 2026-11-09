import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let model: AppModel
    @AppStorage(PreferenceKey.showPercentage) private var showPercentage = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let percent = model.battery?.percent
        HStack(spacing: 4) {
            Image(nsImage: RingIcon.image(for: model))
            if showPercentage, let percent {
                Text("\(percent)%")
            }
        }
        .accessibilityLabel(percent.map { "Battery \($0) percent, \(model.activitySummary)" } ?? "Chargectl")
        .onAppear { Dashboard.openWindow = openWindow }
    }
}

/// The menu bar icon: a ring that fills clockwise from the top. Its track ends at the charge
/// limit, so a closed ring means the battery is held there, and a small glyph in the middle says
/// what is happening. Template image, so it follows the menu bar tint.
enum RingIcon {
    enum Glyph: Equatable {
        case none
        case charging
        case holding
        case discharging
        case attention
    }

    static func image(for model: AppModel, size: CGFloat = 16) -> NSImage {
        let fraction = Double(model.battery?.percent ?? 0) / 100
        guard model.service == .running, let status = model.status else {
            return image(fraction: fraction, limit: nil, glyph: .attention, dashed: true, size: size)
        }
        let limit = status.settings.isEnabled ? Double(status.settings.limit) / 100 : nil
        return image(fraction: fraction, limit: limit, glyph: glyph(for: status.activity), size: size)
    }

    static func glyph(for activity: ChargeActivity) -> Glyph {
        switch activity {
        case .charging, .toppingUp, .calibrating(.charging), .chargingFull: .charging
        case .holding, .holdingAbove, .full, .sailingHold, .heatPaused, .calibrating(.holding): .holding
        case .discharging, .aboveLimit, .stoppedOvercharge, .sailing, .calibrating(.draining): .discharging
        case .onBattery, .off, .starting: .none
        }
    }

    /// - Parameters:
    ///   - limit: Where the track ends, 0…1; nil draws the whole ring.
    ///   - dashed: A dotted ring, for "the helper isn't running".
    static func image(
        fraction: Double, limit: Double? = nil, glyph: Glyph = .none, dashed: Bool = false, size: CGFloat = 16
    ) -> NSImage {
        let fraction = min(max(fraction, 0), 1)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let unit = rect.width / 16
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = 6.15 * unit
            let lineWidth = 1.9 * unit

            func arc(to end: Double) -> NSBezierPath {
                let path = NSBezierPath()
                // Flipped: angles run clockwise on screen.
                path.appendArc(
                    withCenter: center, radius: radius, startAngle: -90, endAngle: -90 + 360 * min(end, 0.9999),
                    clockwise: false)
                path.lineWidth = lineWidth
                path.lineCapStyle = .round
                return path
            }

            if dashed {
                let track = NSBezierPath(
                    ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                track.lineWidth = lineWidth
                track.setLineDash([1.6 * unit, 2.1 * unit], count: 2, phase: 0)
                NSColor.black.withAlphaComponent(0.45).setStroke()
                track.stroke()
            } else {
                NSColor.black.withAlphaComponent(0.32).setStroke()
                arc(to: max(limit ?? 1, fraction)).stroke()
                if fraction > 0 {
                    NSColor.black.setStroke()
                    arc(to: fraction).stroke()
                }
            }

            NSColor.black.setFill()
            NSColor.black.setStroke()
            func p(_ x: Double, _ y: Double) -> NSPoint { NSPoint(x: x * unit, y: y * unit) }
            switch glyph {
            case .none:
                break
            case .charging:
                let bolt = NSBezierPath()
                bolt.move(to: p(8.75, 4.4))
                bolt.line(to: p(5.7, 8.75))
                bolt.line(to: p(7.9, 8.75))
                bolt.line(to: p(7.25, 11.6))
                bolt.line(to: p(10.3, 7.25))
                bolt.line(to: p(8.1, 7.25))
                bolt.close()
                bolt.fill()
            case .holding:
                NSBezierPath(
                    roundedRect: NSRect(origin: p(6.15, 5.9), size: NSSize(width: 1.3 * unit, height: 4.2 * unit)),
                    xRadius: 0.5 * unit, yRadius: 0.5 * unit
                ).fill()
                NSBezierPath(
                    roundedRect: NSRect(origin: p(8.55, 5.9), size: NSSize(width: 1.3 * unit, height: 4.2 * unit)),
                    xRadius: 0.5 * unit, yRadius: 0.5 * unit
                ).fill()
            case .discharging:
                let arrow = NSBezierPath()
                arrow.move(to: p(8, 5.4))
                arrow.line(to: p(8, 10.3))
                arrow.move(to: p(6.1, 8.5))
                arrow.line(to: p(8, 10.4))
                arrow.line(to: p(9.9, 8.5))
                arrow.lineWidth = 1.3 * unit
                arrow.lineCapStyle = .round
                arrow.lineJoinStyle = .round
                arrow.stroke()
            case .attention:
                NSBezierPath(
                    roundedRect: NSRect(origin: p(7.35, 4.9), size: NSSize(width: 1.3 * unit, height: 4 * unit)),
                    xRadius: 0.55 * unit, yRadius: 0.55 * unit
                ).fill()
                NSBezierPath(ovalIn: NSRect(origin: p(7.2, 9.9), size: NSSize(width: 1.6 * unit, height: 1.6 * unit)))
                    .fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
