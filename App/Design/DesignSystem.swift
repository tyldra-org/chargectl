import AppKit
import SwiftUI

// The look shared by the dashboard and the menu bar panel: calm cards with a hairline edge that
// lights up near the pointer, one green accent, quiet secondary text, rolling numbers.

extension Theme {
    /// Fills, glows and the slider: brighter than `green`, which is tuned for text.
    static let accent = hex(light: 0x22A447, dark: 0x32D74B)
    static let accentSoft = hex(light: 0x22A447, dark: 0x32D74B, lightAlpha: 0.11, darkAlpha: 0.13)
    static let glow = hex(light: 0x22A447, dark: 0x32D74B, lightAlpha: 0.45, darkAlpha: 0.55)
    static let warn = hex(light: 0xC76A00, dark: 0xFFB340)
    static let warnSoft = hex(light: 0xC76A00, dark: 0xFFB340, lightAlpha: 0.09, darkAlpha: 0.12)
    static let danger = hex(light: 0xD70015, dark: 0xFF6961)
    /// The Mac's share of power in charts and splits.
    static let mac = hex(light: 0xAEAEB2, dark: 0x8E8E93)
    static let line = hex(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.065)
    static let lineStrong = hex(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.11, darkAlpha: 0.11)
    static let track = hex(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.065, darkAlpha: 0.07)
    static let hover = hex(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.04, darkAlpha: 0.05)
    static let cardTop = hex(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.04)
    static let cardBottom = hex(light: 0xFDFDFD, dark: 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.012)
    static let cardHighlight = hex(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 1, darkAlpha: 0.06)
    static let window = hex(light: 0xF6F6F7, dark: 0x0F0F11)
    static let dot = hex(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.09)
    /// The status island stays black in both appearances, like the Dynamic Island.
    static let island = Color(red: 0, green: 0, blue: 0)

    static func hex(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        func rgb(_ value: UInt32) -> (Double, Double, Double) {
            (Double(value >> 16 & 0xFF) / 255, Double(value >> 8 & 0xFF) / 255, Double(value & 0xFF) / 255)
        }
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let (r, g, b) = rgb(isDark ? dark : light)
                return NSColor(srgbRed: r, green: g, blue: b, alpha: isDark ? darkAlpha : lightAlpha)
            })
    }
}

// MARK: Motion

extension View {
    /// Digits roll whenever the value changes, also when the change came from a background
    /// refresh rather than an animated action.
    func rollingNumber<Value: Equatable>(_ value: Value) -> some View {
        contentTransition(.numericText()).animation(.smooth(duration: 0.45), value: value)
    }
}

// MARK: Panel

/// The card every page is built from. The edge brightens around the pointer (Aceternity's
/// glowing effect, toned down); an optional soft light sits in the top-left corner.
struct Panel<Content: View>: View {
    var padding: CGFloat = 18
    var spotlight = false
    var tint: Color?
    @ViewBuilder var content: Content
    @State private var pointer: CGPoint?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    shape.fill(
                        LinearGradient(colors: [Theme.cardTop, Theme.cardBottom], startPoint: .top, endPoint: .bottom))
                    if spotlight {
                        RadialGradient(
                            colors: [Color.white.opacity(scheme == .dark ? 0.07 : 0.6), .clear], center: .topLeading,
                            startRadius: 0, endRadius: 420
                        )
                        .clipShape(shape)
                    }
                    if let pointer {
                        // A soft light centred on the pointer, inside the card's own frame so it
                        // has no edges.
                        GeometryReader { geometry in
                            RadialGradient(
                                colors: [Color.primary.opacity(scheme == .dark ? 0.035 : 0.02), .clear],
                                center: UnitPoint(
                                    x: pointer.x / max(geometry.size.width, 1),
                                    y: pointer.y / max(geometry.size.height, 1)),
                                startRadius: 0, endRadius: 260)
                        }
                        .clipShape(shape)
                        .allowsHitTesting(false)
                    }
                }
            }
            .overlay {
                shape.strokeBorder(tint.map { $0.opacity(0.3) } ?? Theme.line)
                shape.strokeBorder(
                    LinearGradient(colors: [Theme.cardHighlight, .clear], startPoint: .top, endPoint: .center),
                    lineWidth: 1
                )
                .opacity(scheme == .dark ? 1 : 0)
                if let pointer {
                    GeometryReader { geometry in
                        shape.strokeBorder(
                            RadialGradient(
                                colors: [Theme.accent.opacity(0.55), Color.primary.opacity(0.12), .clear],
                                center: UnitPoint(
                                    x: pointer.x / max(geometry.size.width, 1),
                                    y: pointer.y / max(geometry.size.height, 1)),
                                startRadius: 0, endRadius: 220),
                            lineWidth: 1)
                    }
                    .allowsHitTesting(false)
                }
            }
            .shadow(
                color: .black.opacity(scheme == .dark ? 0.12 : 0.05), radius: scheme == .dark ? 1 : 12,
                y: scheme == .dark ? 1 : 6
            )
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location): pointer = location
                case .ended: withAnimation(.easeOut(duration: 0.3)) { pointer = nil }
                }
            }
    }
}

/// A card's caption: a small icon and a label, with optional content on the right.
struct PanelHeader<Trailing: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 15)
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailing
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, symbol: String) {
        self.init(title: title, symbol: symbol) { EmptyView() }
    }
}

// MARK: Controls

/// The switch used across the app: a capsule that turns green with a soft glow, and a knob
/// that stretches while pressed.
struct GlowSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SwitchBody(configuration: configuration)
    }

    private struct SwitchBody: View {
        let configuration: Configuration
        @State private var isPressed = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let on = configuration.isOn
            HStack(spacing: 12) {
                configuration.label
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule()
                        .fill(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(on ? Color.black.opacity(0.12) : Theme.lineStrong))
                        .shadow(color: on ? Theme.glow.opacity(0.6) : .clear, radius: 7)
                    Capsule()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .frame(width: isPressed ? 22 : 18, height: 18)
                        .padding(2)
                }
                .frame(width: 38, height: 22)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: on)
                .animation(.easeOut(duration: 0.15), value: isPressed)
                .opacity(isEnabled ? 1 : 0.45)
                .onTapGesture { configuration.isOn.toggle() }
                .onLongPressGesture(minimumDuration: 0, maximumDistance: 20) {
                } onPressingChanged: {
                    isPressed = $0
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
        }
    }
}

/// − value + in a capsule; the buttons dim at the ends of the range.
struct CapsuleStepper: View {
    let value: String
    let canDecrement: Bool
    let canIncrement: Bool
    let accessibilityLabel: String
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            step("minus", enabled: canDecrement, action: decrement)
            Text(value)
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .rollingNumber(value)
                .frame(minWidth: 52)
                .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
            step("plus", enabled: canIncrement, action: increment)
        }
        .frame(height: 28)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.lineStrong))
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(value)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrement { increment() }
            case .decrement: if canDecrement { decrement() }
            @unknown default: break
            }
        }
    }

    private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .secondary : .quaternary)
        .disabled(!enabled)
    }
}

/// A segmented control whose selection slides between options.
struct SlidingSegments<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var compact = false
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                let selected = value == selection
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { selection = value }
                } label: {
                    Text(title)
                        .font(.system(size: compact ? 11 : 12, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected ? .primary : .tertiary)
                        .padding(.horizontal, compact ? 9 : 12)
                        .padding(.vertical, compact ? 2 : 4)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: compact ? 6 : 7, style: .continuous)
                                    .fill(Theme.cardTop)
                                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: compact ? 6 : 7, style: .continuous)
                                            .strokeBorder(Theme.lineStrong)
                                    )
                                    .matchedGeometryEffect(id: "thumb", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous))
    }
}

/// A soft rounded button: quiet by default, `.primary` for the one main action, `.danger` for
/// removing things. `large` is for the main action at the bottom of a window, such as setup.
struct SoftButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, danger, ok }
    var kind = Kind.normal
    var small = false
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration, kind: kind, small: small, large: large)
    }

    private struct ButtonBody: View {
        let configuration: Configuration
        let kind: Kind
        let small: Bool
        let large: Bool
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: large ? 9 : 8, style: .continuous)
            configuration.label
                .labelStyle(SoftButtonLabelStyle())
                .font(.system(size: large ? 13 : small ? 12 : 12.5, weight: .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, large ? 16 : small ? 11 : 12)
                .frame(height: large ? 32 : small ? 26 : 28)
                .background(shape.fill(background))
                .overlay(
                    shape.strokeBorder(
                        kind == .ok ? Theme.accent.opacity(0.45) : kind == .primary ? .clear : Theme.lineStrong)
                )
                .overlay(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.08 : isHovered ? 0.04 : 0)))
                .shadow(
                    color: kind == .ok ? Theme.glow.opacity(0.4) : .black.opacity(0.12), radius: kind == .ok ? 8 : 1,
                    y: kind == .ok ? 0 : 1
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .contentShape(shape)
                .onHover { isHovered = $0 }
        }

        private var foreground: Color {
            switch kind {
            case .normal: .primary
            case .primary: scheme == .dark ? .black : .white
            case .danger: Theme.danger
            case .ok: Theme.accent
            }
        }

        private var background: AnyShapeStyle {
            switch kind {
            case .primary: AnyShapeStyle(scheme == .dark ? Color(white: 0.95) : Color(white: 0.11))
            default:
                scheme == .dark
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [.white.opacity(0.075), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(
                        LinearGradient(colors: [.white, Color(white: 0.965)], startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

private struct SoftButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 11.5, weight: .medium))
            configuration.title
        }
    }
}

// MARK: Status island

/// The black capsule in the toolbar. It shows what the battery is doing and opens for a moment
/// to confirm a change ("Limit set to 75%"). Hovering it shows a few details.
@Observable
final class Confirmations {
    static let shared = Confirmations()
    /// Set while a confirmation is showing.
    private(set) var message: String?
    /// The latest confirmation, kept after it hides so it can fade out in place.
    private(set) var text = ""
    @ObservationIgnored private var clear: Task<Void, Never>?

    func show(_ message: String) {
        // The words change first, without animation, so the fade never shows a half-swapped line.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { text = message }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { self.message = message }
        clear?.cancel()
        clear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { self?.message = nil }
        }
    }
}

/// The status and a confirmation share one row in a capsule that keeps its size. Both lines are
/// always laid out; switching between them is a cross-fade with a slight lift and blur, so nothing
/// is inserted, removed or resized mid-animation and nothing can draw outside the capsule. A soft
/// pulse of the capsule marks that something was saved.
struct StatusIsland: View {
    let model: AppModel
    var details: [(String, String)] = []
    @State private var isHovered = false
    @State private var pulse = false
    private let confirmations = Confirmations.shared

    var body: some View {
        let confirming = confirmations.message != nil
        let showsDetails = !confirming && isHovered && !details.isEmpty
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .leading) {
                statusRow
                    .opacity(confirming ? 0 : 1)
                    .blur(radius: confirming ? 4 : 0)
                    .offset(y: confirming ? -6 : 0)
                confirmationRow
                    .opacity(confirming ? 1 : 0)
                    .blur(radius: confirming ? 0 : 4)
                    .offset(y: confirming ? 0 : 6)
            }
            .frame(height: 20)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                ForEach(0..<(details.count + 1) / 2, id: \.self) { row in
                    GridRow {
                        detail(details[row * 2])
                        if row * 2 + 1 < details.count { detail(details[row * 2 + 1]) }
                    }
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Color(white: 0.65))
            .lineLimit(1)
            .opacity(showsDetails ? 1 : 0)
        }
        .foregroundStyle(Color(white: 0.96))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(width: showsDetails ? 330 : 232, height: showsDetails ? nil : 32, alignment: .topLeading)
        .background(Theme.island)
        .clipShape(RoundedRectangle(cornerRadius: showsDetails ? 22 : 16, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: showsDetails ? 14 : 6, y: 4)
        .scaleEffect(pulse ? 1.04 : 1)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showsDetails)
        .onChange(of: confirmations.message) { _, message in
            guard message != nil else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.6)) { pulse = true }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.16)) { pulse = false }
        }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var statusRow: some View {
        HStack(spacing: 9) {
            ChargeRing(fraction: Double(model.battery?.percent ?? 0) / 100, color: ringColor)
                .frame(width: 15, height: 15)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 10)
            Text(model.battery.map { "\($0.percent)%" } ?? "")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color(white: 0.63))
                .rollingNumber(model.battery?.percent)
        }
    }

    private var confirmationRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.2, green: 0.84, blue: 0.29))
            Text(confirmations.text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }

    private func detail(_ item: (String, String)) -> some View {
        HStack(spacing: 4) {
            Text(item.0)
            Text(item.1).foregroundStyle(Color(white: 0.96)).fontWeight(.semibold)
        }
    }

    private var title: String {
        switch model.service {
        case .running, .checking: model.activitySummary.capitalizedFirst
        case .notInstalled: "Helper not installed"
        case .needsApproval: "Helper needs approval"
        case .notResponding: "Helper not responding"
        }
    }

    private var ringColor: Color {
        model.service == .running && model.settings?.isEnabled != false
            ? Color(red: 0.2, green: 0.84, blue: 0.29) : Color(red: 1, green: 0.7, blue: 0.25)
    }
}

/// A charge ring drawn in SwiftUI, for the island, the sidebar and empty states.
struct ChargeRing: View {
    let fraction: Double
    var color: Color = Theme.accent
    var lineWidth: CGFloat = 2.2

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.5), radius: 2)
        }
        .padding(lineWidth / 2)
        .animation(.easeOut(duration: 0.6), value: fraction)
    }
}

// MARK: Surfaces

/// A field of small dots, faded out towards the edges.
struct DotField: View {
    var spacing: CGFloat = 14
    var color: Color = Theme.dot

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
                    x += spacing
                }
                y += spacing
            }
            context.fill(path, with: .color(color))
        }
        .mask(
            RadialGradient(colors: [.black, .clear], center: .init(x: 0.5, y: 0.35), startRadius: 10, endRadius: 320)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Fine film grain over the window, the noise background from the mockups.
struct Grain: View {
    @Environment(\.colorScheme) private var scheme
    private static let image: NSImage = {
        let size = 128
        var pixels = [UInt8](repeating: 0, count: size * size)
        var seed: UInt32 = 0x9E37_79B9
        for index in pixels.indices {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            pixels[index] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        let image = provider.flatMap {
            CGImage(
                width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: $0, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)
        }
        return image.map { NSImage(cgImage: $0, size: NSSize(width: size / 2, height: size / 2)) } ?? NSImage()
    }()

    var body: some View {
        Rectangle()
            .fill(ImagePaint(image: Image(nsImage: Self.image)))
            .opacity(scheme == .dark ? 0.045 : 0.03)
            .blendMode(.overlay)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Cards settle in with a short blur and rise when a page appears.
struct SettleIn: ViewModifier {
    let order: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.6).delay(Double(order) * 0.055)) {
                    shown = true
                }
            }
    }
}

extension View {
    func settleIn(_ order: Int) -> some View { modifier(SettleIn(order: order)) }
}

/// The calm card used when a page has nothing to show yet: three stacked tiles over a dot field,
/// a title, a sentence and one action.
struct StackedEmptyState<Action: View>: View {
    let symbols: [String]
    let title: String
    let message: String
    @ViewBuilder var action: Action

    var body: some View {
        Panel(padding: 0) {
            ZStack {
                DotField().padding(1)
                VStack(spacing: 0) {
                    ZStack {
                        tile(symbols[0], accent: false).rotationEffect(.degrees(-8)).offset(x: -18, y: 14).opacity(0.6)
                        tile(symbols[1], accent: false).rotationEffect(.degrees(8)).offset(x: 18, y: 14).opacity(0.6)
                        tile(symbols[2], accent: true).offset(y: -2)
                    }
                    .frame(width: 132, height: 96)
                    .padding(.bottom, 22)
                    Text(title).font(.system(size: 18, weight: .semibold)).padding(.bottom, 8)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 430)
                        .padding(.bottom, 20)
                    action
                }
                .padding(.vertical, 60)
                .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, minHeight: 440)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ symbol: String, accent: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [Theme.cardTop, Theme.cardBottom], startPoint: .top, endPoint: .bottom))
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.window))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.lineStrong))
            .shadow(color: .black.opacity(0.25), radius: 15, y: 10)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(accent ? Theme.accent : .secondary)
            }
            .frame(width: 96, height: 64)
    }
}

/// The helper is missing, waiting or stuck: one empty state per page with the action that
/// state needs.
struct HelperEmptyState: View {
    let model: AppModel
    let symbols: [String]
    let title: String
    let message: String

    var body: some View {
        StackedEmptyState(symbols: symbols, title: title, message: message) {
            switch model.service {
            case .needsApproval:
                Button("Open Login Items") { ServiceInstaller.openLoginItems() }
                    .buttonStyle(SoftButtonStyle(kind: .primary))
            case .notResponding:
                Button {
                    model.installService()
                } label: {
                    Label(model.isInstallingService ? "Installing…" : "Install Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SoftButtonStyle(kind: .primary))
                .disabled(model.isInstallingService)
            default:
                Button {
                    model.installService()
                } label: {
                    Label(
                        model.isInstallingService ? "Installing…" : "Install Helper", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(SoftButtonStyle(kind: .primary))
                .disabled(model.isInstallingService)
            }
        }
    }
}

/// Lays cards out side by side with widths in proportion to their spans (7 and 5 of 12, say),
/// all as tall as the tallest.
struct SpanRow: Layout {
    var spans: [Int]
    var spacing: CGFloat = 14

    private func widths(_ total: CGFloat, count: Int) -> [CGFloat] {
        let spans = (0..<count).map { $0 < self.spans.count ? self.spans[$0] : 1 }
        let sum = CGFloat(spans.reduce(0, +))
        let available = max(total - spacing * CGFloat(count - 1), 0)
        return spans.map { available * CGFloat($0) / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 800
        let columns = widths(width, count: subviews.count)
        let height =
            zip(subviews, columns).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(bounds.width, count: subviews.count)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}
