import AppKit
import SwiftUI

/// The panel under the menu bar ring: charge at a glance, the limit, a few switches and jobs.
struct MenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PreferenceKey.temperatureUnit) private var unit = TemperatureUnit.systemDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let battery = model.battery {
                header(battery)
                ChargeBar(
                    percent: battery.percent, limit: model.settings?.limit,
                    lowerBound: model.settings?.lowerBound, isDraining: model.isDraining,
                    onSetLimit: model.isControllable ? { limit in model.update { $0.limit = limit } } : nil)
                metrics(battery)
            } else {
                Text(model.batteryError ?? "Reading the battery…").foregroundStyle(.secondary)
            }
            if let settings = model.settings, model.isControllable {
                switches(settings)
                jobs(settings)
            } else if model.service != .checking {
                serviceNotice
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    private func header(_ battery: BatterySnapshot) -> some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(battery.percent)")
                    .font(.system(size: 40, weight: .light))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("%").font(.title3.weight(.light)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.activitySummary.capitalizedFirst)
                    .font(.headline)
                    .foregroundStyle(model.isDraining ? Theme.amber : .primary)
                    .lineLimit(1)
                Text(subtitle(battery))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ battery: BatterySnapshot) -> String {
        var parts: [String] = []
        if let limit = model.settings?.limit { parts.append("Limit \(limit)%") }
        parts.append(unit.format(battery.temperature))
        if let macOSLimit = model.macOSLimit { parts.append("macOS \(macOSLimit)%") }
        return parts.joined(separator: " · ")
    }

    private func metrics(_ battery: BatterySnapshot) -> some View {
        HStack(spacing: 0) {
            Metric(title: "Health", value: Format.percent(battery.health))
            Metric(title: "Cycles", value: "\(battery.cycleCount)")
            Metric(title: "Charger", value: Format.watts(battery.wallPower))
            Metric(title: "Mac", value: Format.watts(battery.systemPower))
            Metric(
                title: "Battery",
                value: abs(battery.batteryPower) < 0.05 ? "0 W" : Format.signedWatts(battery.batteryPower))
        }
    }

    private func switches(_ settings: ChargeSettings) -> some View {
        HStack(spacing: 8) {
            toggle("Auto discharge", "arrow.down.circle", settings.autoDischarge) { $0.autoDischarge.toggle() }
                .help("Plugged in above the limit: discharge down to it instead of holding the charge")
            toggle("Heat guard", "thermometer.medium", settings.heatProtection) { $0.heatProtection.toggle() }
                .help("Pause charging while the battery is warm")
            toggle("Sleep discharge", "moon", settings.holdAsleep) { $0.holdAsleep.toggle() }
                .help("Keep discharging while the Mac sleeps")
        }
    }

    private func toggle(
        _ title: String, _ symbol: String, _ isOn: Bool, change: @escaping (inout ChargeSettings) -> Void
    ) -> some View {
        Button {
            model.update(change)
        } label: {
            StackedTileLabel(title: title, symbol: symbol)
        }
        .buttonStyle(TileButtonStyle(isOn: isOn, minHeight: 54))
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "on" : "off")
    }

    @ViewBuilder private func jobs(_ settings: ChargeSettings) -> some View {
        let mode = model.status?.mode ?? .automatic
        if mode == .automatic {
            HStack(spacing: 8) {
                Button {
                    model.perform(.discharge)
                } label: {
                    Label("Discharge", systemImage: "battery.25percent")
                }
                .disabled((model.battery?.percent ?? 0) <= settings.limit)
                .help("Run on battery down to \(settings.limit)%")
                Button {
                    model.perform(.topUp)
                } label: {
                    Label("Top Up", systemImage: "battery.100percent.bolt")
                }
                .help("Charge to 100% once, then return to the limit")
                Button {
                    openDashboard(.overview)
                } label: {
                    Label("Calibrate", systemImage: "gauge.with.dots.needle.50percent")
                }
                .help("Opens Chargectl to confirm a calibration")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(TileButtonStyle())
        } else {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Running \(mode.title)").foregroundStyle(.secondary)
                Spacer()
                Button("Stop") { model.perform(.stop) }
                    .buttonStyle(TileButtonStyle())
                    .frame(width: 80)
            }
        }
    }

    private var serviceNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "bolt.slash").foregroundStyle(Theme.amber)
            Text(
                model.service == .needsApproval
                    ? "Turn on Chargectl in Login Items." : "Charge control needs its helper."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer()
            if model.service == .needsApproval {
                Button("Open") { ServiceInstaller.openLoginItems() }.controlSize(.small)
            } else {
                Button(model.isInstallingService ? "Installing…" : "Install Helper") { model.installService() }
                    .controlSize(.small)
                    .disabled(model.isInstallingService)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            FooterRow(title: "Open Chargectl", symbol: "macwindow", shortcut: "O") { openDashboard(.overview) }
            FooterRow(title: "Settings…", symbol: "gearshape", shortcut: ",") { openDashboard(.settings) }
            Divider().padding(.vertical, 4)
            FooterRow(title: "Quit Chargectl", symbol: "power") { Dashboard.quit() }
        }
    }

    private func openDashboard(_ page: DashboardPage) {
        Dashboard.show()
        openWindow(id: WindowID.dashboard)
        NSWorkspace.shared.open(URL(string: "chargectl://dashboard/\(page.rawValue)")!)
    }
}

/// A full-width menu row with an icon and a key hint, like a native menu item.
private struct FooterRow: View {
    let title: String
    let symbol: String
    var shortcut: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                if let shortcut {
                    Text("⌘\(shortcut)").foregroundStyle(.secondary).font(.callout)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isHovered ? Theme.chipFill : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(OptionalShortcut(key: shortcut))
        .onHover { isHovered = $0 }
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

private struct Metric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
