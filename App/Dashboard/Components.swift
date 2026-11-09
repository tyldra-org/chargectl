import AppKit
import SwiftUI

/// Colours that keep their contrast in both light and dark appearance.
enum Theme {
    /// Charging, healthy, on.
    static let green = adaptive(light: (0.07, 0.52, 0.27), dark: (0.36, 0.82, 0.54))
    /// Discharging, warnings.
    static let amber = adaptive(light: (0.70, 0.38, 0.02), dark: (0.98, 0.70, 0.32))
    /// Card surface: white on the light window, a lifted grey on the dark one.
    static let cardFill = adaptive(light: (1, 1, 1), dark: (1, 1, 1), lightAlpha: 0.85, darkAlpha: 0.045)
    static let cardStroke = adaptive(light: (0, 0, 0), dark: (1, 1, 1), lightAlpha: 0.08, darkAlpha: 0.07)
    /// Fill behind a quiet control or chip.
    static let chipFill = adaptive(light: (0, 0, 0), dark: (1, 1, 1), lightAlpha: 0.06, darkAlpha: 0.08)

    private static func adaptive(
        light: (Double, Double, Double), dark: (Double, Double, Double), lightAlpha: Double = 1, darkAlpha: Double = 1
    ) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let (r, g, b) = isDark ? dark : light
                return NSColor(srgbRed: r, green: g, blue: b, alpha: isDark ? darkAlpha : lightAlpha)
            })
    }
}

/// A title and value pair, value bold on the right of a fixed label column.
struct InfoRow: View {
    let title: String
    let value: String
    var tint: Color?

    var body: some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(tint ?? .primary)
                .rollingNumber(value)
                .gridColumnAlignment(.trailing)
        }
    }
}

enum TimeText {
    /// "1 h 41 min", "12 min".
    static func minutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

/// The one button look used for quick toggles and actions: a soft rounded tile that turns green
/// when its setting is on.
struct TileButtonStyle: ButtonStyle {
    var isOn = false
    var minHeight: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        Tile(configuration: configuration, isOn: isOn, minHeight: minHeight)
    }

    private struct Tile: View {
        let configuration: Configuration
        let isOn: Bool
        let minHeight: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            configuration.label
                .font(.callout.weight(isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? Theme.green : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(shape.fill(isOn ? Theme.green.opacity(0.16) : Theme.chipFill))
                .overlay {
                    shape.fill(
                        Color.primary.opacity(configuration.isPressed ? 0.08 : isHovered && isEnabled ? 0.04 : 0))
                }
                .overlay { shape.strokeBorder(isOn ? Theme.green.opacity(0.45) : Theme.cardStroke) }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { isHovered = $0 }
        }
    }
}
