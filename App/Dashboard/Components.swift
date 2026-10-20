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

/// A quiet rounded panel with an optional caption.
struct Card<Content: View>: View {
    var title: String?
    var symbol: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title)
                } icon: {
                    if let symbol { Image(systemName: symbol) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.cardStroke)
        }
    }
}

/// A hairline meter for one power figure.
struct PowerMeter: View {
    let fraction: Double
    var tint: Color = .secondary

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.chipFill)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.4), value: fraction)
        .accessibilityHidden(true)
    }
}

/// The charge track: current charge as a bar, the limit as a tick and the sailing band as a
/// faint wash. Drag or click anywhere on it to set the limit.
struct ChargeBar: View {
    let percent: Int
    let limit: Int?
    let lowerBound: Int?
    let isDraining: Bool
    var onSetLimit: ((Int) -> Void)?
    @State private var draggedLimit: Int?

    var body: some View {
        let shownLimit = draggedLimit ?? limit
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let x = { (value: Int) in width * CGFloat(value) / 100 }
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.chipFill).frame(height: 6)
                    if let shownLimit, let lowerBound, lowerBound < shownLimit, draggedLimit == nil {
                        Capsule()
                            .fill(Theme.amber.opacity(0.18))
                            .frame(width: x(shownLimit) - x(lowerBound), height: 6)
                            .offset(x: x(lowerBound))
                    }
                    Capsule()
                        .fill(isDraining ? Theme.amber : Theme.green)
                        .frame(width: max(x(percent), 6), height: 6)
                    if let shownLimit {
                        Capsule()
                            .fill(Color.primary)
                            .frame(width: 2, height: 16)
                            .offset(x: x(shownLimit) - 1)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            // Only a drag that starts on the limit tick moves it, so a stray click
                            // on the bar never changes the limit.
                            guard let limit, draggedLimit != nil || abs(drag.startLocation.x - x(limit)) <= 14 else {
                                return
                            }
                            draggedLimit = clamp(drag.location.x / max(width, 1) * 100)
                        }
                        .onEnded { _ in
                            if let draggedLimit { onSetLimit?(draggedLimit) }
                            draggedLimit = nil
                        },
                    including: onSetLimit == nil ? .none : .all)
            }
            .frame(height: 18)

            if let shownLimit {
                GeometryReader { geometry in
                    Text("Limit \(shownLimit)%")
                        .font(.caption)
                        .foregroundStyle(draggedLimit == nil ? .secondary : .primary)
                        .monospacedDigit()
                        .fixedSize()
                        .position(x: labelX(shownLimit, width: geometry.size.width), y: 7)
                }
                .frame(height: 14)
            }
        }
        .onHover { hovering in
            guard onSetLimit != nil else { return }
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityElement()
        .accessibilityLabel("Charge limit")
        .accessibilityValue(
            shownLimit.map { "limit \($0) percent, battery at \(percent) percent" } ?? "\(percent) percent"
        )
        .accessibilityAdjustableAction { direction in
            guard let limit, let onSetLimit else { return }
            switch direction {
            case .increment: onSetLimit(min(limit + 1, ChargeSettings.limitRange.upperBound))
            case .decrement: onSetLimit(max(limit - 1, ChargeSettings.limitRange.lowerBound))
            @unknown default: break
            }
        }
    }

    private func clamp(_ value: CGFloat) -> Int {
        let range = ChargeSettings.limitRange
        return min(max(Int(value.rounded()), range.lowerBound), range.upperBound)
    }

    private func labelX(_ value: Int, width: CGFloat) -> CGFloat {
        min(max(width * CGFloat(value) / 100, 30), width - 30)
    }
}

/// Shown in place of a page that needs the control service.
struct ServiceRequired: View {
    let model: AppModel
    let description: String

    var body: some View {
        ContentUnavailableView {
            Label("Charge control is not running", systemImage: "bolt.slash")
        } description: {
            Text(description)
        } actions: {
            switch model.service {
            case .notInstalled:
                Button(model.isInstallingService ? "Installing…" : "Install Helper") { model.installService() }
                    .disabled(model.isInstallingService)
            case .needsApproval:
                Button("Open Login Items") { ServiceInstaller.openLoginItems() }
            default:
                EmptyView()
            }
        }
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
                .contentTransition(.numericText())
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
