import AppKit
import SwiftUI

/// The panel under the menu bar ring: charge at a glance, the limit, a few switches and jobs.
struct MenuContent: View {
    let model: AppModel
    private let updater = Updater.shared
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PreferenceKey.temperatureUnit) private var unit = TemperatureUnit.systemDefault
    private let confirmations = Confirmations.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let battery = model.battery {
                header(battery)
                MenuLimitBar(
                    percent: battery.percent, limit: model.isControllable ? model.settings?.limit : nil,
                    lowerBound: model.isControllable ? model.settings?.lowerBound : nil,
                    macOSLimit: model.macOSLimit, isDraining: model.isDraining
                ) { limit in
                    model.update { $0.limit = limit }
                    confirmations.show("Limit set to \(limit)%")
                }
                .padding(.top, 18)
                metrics(battery)
            } else {
                Text(model.batteryError ?? "Reading the battery…").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            if let settings = model.settings, model.isControllable {
                switches(settings).padding(.top, 14)
                jobs(settings).padding(.top, 8)
                    .animation(.easeInOut(duration: 0.25), value: model.status?.mode)
            } else if model.service != .checking {
                serviceNotice.padding(.top, 14)
            }
            footer.padding(.top, 14)
        }
        .padding(16)
        .frame(width: 340)
        .overlay(alignment: .top) {
            if let message = confirmations.message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .labelStyle(ToastLabelStyle())
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .tint(Theme.accent)
    }

    // MARK: Header

    private func header(_ battery: BatterySnapshot) -> some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(battery.percent)")
                    .font(.system(size: 46, weight: .light))
                    .tracking(-1.4)
                    .monospacedDigit()
                    .rollingNumber(battery.percent)
                Text("%").font(.system(size: 19, weight: .light)).foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tone)
                        .frame(width: 7, height: 7)
                        .shadow(color: tone, radius: tone == .secondary ? 0 : 4)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tone == .secondary ? .primary : tone)
                        .lineLimit(1)
                }
                Text(subtitle(battery))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch model.service {
        case .notInstalled, .needsApproval, .notResponding:
            model.battery.map { $0.isCharging ? "Charging" : $0.isPluggedIn ? "Plugged in" : "On battery" }
                ?? "Chargectl"
        default: model.activitySummary.capitalizedFirst
        }
    }

    private var tone: Color {
        if model.isDraining { return Theme.warn }
        if let status = model.status {
            return RingIcon.glyph(for: status.activity) == .charging ? Theme.accent : .secondary
        }
        return model.battery?.isCharging == true ? Theme.accent : .secondary
    }

    private func subtitle(_ battery: BatterySnapshot) -> String {
        var parts: [String] = []
        if let limit = model.settings?.limit, model.isControllable { parts.append("Limit \(limit)%") }
        parts.append(unit.format(battery.temperature))
        if let macOSLimit = model.macOSLimit { parts.append("macOS \(macOSLimit)%") }
        return parts.joined(separator: " · ")
    }

    // MARK: Metrics

    private func metrics(_ battery: BatterySnapshot) -> some View {
        let watts = battery.batteryPower
        return HStack(spacing: 0) {
            Metric(title: "Health", value: Format.percent(battery.health), first: true)
            Metric(title: "Cycles", value: "\(battery.cycleCount)")
            Metric(title: "Charger", value: (battery.wallPower ?? 0) < 0.05 ? "0 W" : Format.watts(battery.wallPower))
            Metric(title: "Mac", value: Format.watts(battery.systemPower))
            Metric(
                title: "Battery", value: abs(watts) < 0.05 ? "0 W" : Format.signedWatts(watts),
                tint: watts > 0.05 ? Theme.accent : watts < -0.05 ? Theme.warn : nil)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .padding(.top, 10)
    }

    // MARK: Switches and jobs

    private func switches(_ settings: ChargeSettings) -> some View {
        HStack(spacing: 8) {
            tile("Auto discharge", "arrow.down.to.line", settings.autoDischarge) { $0.autoDischarge.toggle() }
                .help("Plugged in above the limit: discharge down to it instead of holding the charge")
            tile("Heat guard", "thermometer.medium", settings.heatProtection) { $0.heatProtection.toggle() }
                .help("Pause charging while the battery is warm")
            tile("Sleep discharge", "moon", settings.holdAsleep) { $0.holdAsleep.toggle() }
                .help("Keep discharging while the Mac sleeps")
        }
    }

    private func tile(
        _ title: String, _ symbol: String, _ isOn: Bool, change: @escaping (inout ChargeSettings) -> Void
    ) -> some View {
        Button {
            model.update(change)
            confirmations.show("\(title) \(isOn ? "off" : "on")")
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isOn ? .white : .secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.1)), in: Circle()
                        )
                        .shadow(color: isOn ? Theme.glow : .clear, radius: 6)
                    Spacer()
                    Text(isOn ? "On" : "Off")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isOn ? Theme.accentSoft : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isOn ? Theme.accent.opacity(0.4) : Theme.line)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .animation(.easeOut(duration: 0.2), value: isOn)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "on" : "off")
    }

    @ViewBuilder private func jobs(_ settings: ChargeSettings) -> some View {
        let mode = model.status?.mode ?? .automatic
        if mode == .automatic {
            let canDischarge = (model.battery?.percent ?? 0) > settings.limit
            HStack(spacing: 8) {
                Button {
                    model.perform(.discharge)
                    confirmations.show("Discharging to \(settings.limit)%")
                } label: {
                    Label("Discharge", systemImage: "battery.25percent")
                }
                .disabled(!canDischarge)
                .help(
                    canDischarge
                        ? "Run on battery down to \(settings.limit)%"
                        : "The battery is already at or below \(settings.limit)%")
                Button {
                    model.perform(.topUp)
                    confirmations.show("Topping up to 100%")
                } label: {
                    Label("Top Up", systemImage: "battery.100percent.bolt")
                }
                .help("Charge to 100% once, then return to the limit")
                Button {
                    openDashboard(.overview)
                } label: {
                    Label("Calibrate…", systemImage: "gauge.with.dots.needle.50percent")
                }
                .help("Opens Chargectl to confirm a calibration")
            }
            .buttonStyle(JobButtonStyle())
        } else {
            let percent = model.battery?.percent ?? 0
            let (title, detail, progress, color): (String, String, Double, Color) =
                switch mode {
                case .topUp:
                    (
                        "Topping up to 100%", "Then back to \(settings.limit)%",
                        Double(percent - settings.limit) / Double(max(100 - settings.limit, 1)), Theme.accent
                    )
                case .discharge(let target):
                    (
                        "Discharging to \(target)%", "On battery until it gets there",
                        Double(100 - percent) / Double(max(100 - target, 1)), Theme.warn
                    )
                case .calibrate:
                    ("Calibrating", model.activitySummary.capitalizedFirst, 0, Theme.accent)
                case .fullBy(let deadline):
                    (
                        "Full by \(deadline.formatted(date: .omitted, time: .shortened))",
                        "Charging to 100%, then back to \(settings.limit)%",
                        Double(percent - settings.limit) / Double(max(100 - settings.limit, 1)), Theme.accent
                    )
                case .automatic:
                    ("", "", 0, Theme.accent)
                }
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12.5, weight: .medium))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.tertiary)
                    if progress > 0 {
                        MiniBar(fraction: min(max(progress, 0.08), 1), color: color).padding(.top, 4)
                    }
                }
                Spacer()
                Button("Stop") {
                    model.perform(.stop)
                    confirmations.show("\(mode.title.capitalizedFirst) stopped")
                }
                .buttonStyle(SoftButtonStyle(small: true))
            }
            .padding(10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.line))
        }
    }

    private var serviceNotice: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warn)
            Text(
                model.service == .needsApproval
                    ? "Turn on Chargectl in Login Items." : "Charge control needs its helper."
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if model.service == .needsApproval {
                Button("Open") { ServiceInstaller.openLoginItems() }
                    .buttonStyle(SoftButtonStyle(kind: .primary, small: true))
            } else {
                Button(model.isInstallingService ? "Installing…" : "Install Helper") { model.installService() }
                    .buttonStyle(SoftButtonStyle(kind: .primary, small: true))
                    .disabled(model.isInstallingService)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.warn.opacity(0.28)))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1).padding(.bottom, 6)
            FooterRow(title: "Open Chargectl", symbol: "macwindow", shortcut: "O") { openDashboard(.overview) }
            FooterRow(title: "Settings…", symbol: "gearshape", shortcut: ",") { openDashboard(.settings) }
            updateRow
            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 5)
            FooterRow(title: "Quit Chargectl", symbol: "power") { Dashboard.quit() }
        }
    }

    /// A new version waiting to be installed, as other Mac apps show it in their menus.
    @ViewBuilder private var updateRow: some View {
        switch updater.phase {
        case .available(let version):
            FooterRow(title: "Restart to Update", symbol: "arrow.down.circle.fill", detail: version, tint: Theme.accent)
            {
                Task { await updater.installAvailable() }
            }
        case .installing(let version):
            FooterRow(title: "Installing \(version)…", symbol: "arrow.down.circle", detail: nil, tint: nil) {}
                .disabled(true)
        default:
            EmptyView()
        }
    }

    private func openDashboard(_ page: DashboardPage) {
        Dashboard.show()
        openWindow(id: WindowID.dashboard)
        NSWorkspace.shared.open(URL(string: "chargectl://dashboard/\(page.rawValue)")!)
    }
}

// MARK: - Parts

/// The charge, the sailing range and a limit marker you can drag or move with the arrow keys.
private struct MenuLimitBar: View {
    let percent: Int
    let limit: Int?
    let lowerBound: Int?
    let macOSLimit: Int?
    let isDraining: Bool
    let setLimit: (Int) -> Void
    @State private var dragged: Int?
    @FocusState private var focused: Bool

    var body: some View {
        let shown = dragged ?? limit
        let color = isDraining ? Theme.warn : Theme.accent
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = { (value: Int) in width * CGFloat(value) / 100 }
            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.primary.opacity(0.1)).frame(height: 8).offset(y: 6)
                if let shown, let lowerBound, lowerBound < shown, dragged == nil {
                    Hatch(color: Theme.accent)
                        .frame(width: x(shown) - x(lowerBound), height: 8)
                        .offset(x: x(lowerBound), y: 6)
                }
                Capsule()
                    .fill(
                        LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(x(percent), 8), height: 8)
                    .shadow(color: color.opacity(0.5), radius: 5)
                    .offset(y: 6)
                if let shown {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary)
                        .frame(width: dragged != nil || focused ? 5 : 4, height: 20)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .offset(x: x(shown) - 2)
                }
                if let label = shown.map({ "Limit \($0)%" }) ?? macOSLimit.map({ "macOS limit \($0)%" }) {
                    Text(label)
                        .font(.system(size: 10.5, weight: dragged != nil ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(dragged != nil || focused ? .primary : .tertiary)
                        .fixedSize()
                        .position(x: min(max(x(shown ?? macOSLimit ?? 80), 34), width - 34), y: 30)
                }
            }
            // Offset children draw outside the stack's own size; hit-test the whole area.
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard let limit, dragged != nil || abs(drag.startLocation.x - x(limit)) <= 14 else { return }
                        let value = Int((drag.location.x / max(width, 1) * 100).rounded())
                        dragged = min(
                            max(value, ChargeSettings.limitRange.lowerBound), ChargeSettings.limitRange.upperBound)
                    }
                    .onEnded { _ in
                        if let dragged, dragged != limit { setLimit(dragged) }
                        dragged = nil
                    },
                including: limit == nil ? .none : .all)
        }
        .frame(height: 38)
        .focusable(limit != nil)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard let limit else { return .ignored }
            let step = press.modifiers.contains(.shift) ? 5 : 1
            let value = limit + (press.key == .rightArrow ? step : -step)
            setLimit(min(max(value, ChargeSettings.limitRange.lowerBound), ChargeSettings.limitRange.upperBound))
            return .handled
        }
        .onHover { hovering in
            guard limit != nil else { return }
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityElement()
        .accessibilityLabel("Charge limit")
        .accessibilityValue(shown.map { "limit \($0) percent, battery at \(percent) percent" } ?? "\(percent) percent")
        .accessibilityAdjustableAction { direction in
            guard let limit else { return }
            switch direction {
            case .increment: setLimit(min(limit + 1, ChargeSettings.limitRange.upperBound))
            case .decrement: setLimit(max(limit - 1, ChargeSettings.limitRange.lowerBound))
            @unknown default: break
            }
        }
    }
}

private struct Metric: View {
    let title: String
    let value: String
    var tint: Color?
    var first = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(tint ?? .primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .rollingNumber(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, first ? 0 : 9)
        .overlay(alignment: .leading) {
            if !first { Rectangle().fill(Theme.line).frame(width: 1) }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct JobButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        JobBody(configuration: configuration)
    }

    private struct JobBody: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .labelStyle(JobLabelStyle())
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    Color.primary.opacity(isHovered && isEnabled ? 0.09 : 0.05),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.38)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }

    private struct JobLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 6) {
                configuration.icon.font(.system(size: 11)).foregroundStyle(.secondary)
                configuration.title
            }
        }
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct ToastLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(Color(red: 0.2, green: 0.84, blue: 0.29))
            configuration.title
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(Color(white: 0.96))
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Color.black, in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
}

/// A full-width menu row with an icon and a key hint, highlighted like a native menu item.
private struct FooterRow: View {
    let title: String
    let symbol: String
    var shortcut: String?
    /// Shown at the trailing edge instead of a shortcut, such as a version number.
    var detail: String?
    /// The icon's colour when the row is not highlighted.
    var tint: Color?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(
                        isHovered ? AnyShapeStyle(.white) : tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary)
                    )
                    .frame(width: 16)
                Text(title).font(.system(size: 13))
                Spacer()
                if let detail {
                    Text(detail).font(.system(size: 12, design: .monospaced)).foregroundStyle(
                        isHovered ? Color.white.opacity(0.85) : Color.secondary)
                } else if let shortcut {
                    Text("⌘\(shortcut)").font(.system(size: 12)).foregroundStyle(
                        isHovered ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .foregroundStyle(isHovered ? .white : .primary)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                isHovered ? Color(nsColor: .selectedContentBackgroundColor) : .clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(OptionalShortcut(key: shortcut))
        .onHover { isHovered = $0 }
        .padding(.horizontal, -8)
    }
}

private struct OptionalShortcut: ViewModifier {
    let key: String?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(KeyEquivalent(Character(key.lowercased())), modifiers: .command)
        } else {
            content
        }
    }
}
