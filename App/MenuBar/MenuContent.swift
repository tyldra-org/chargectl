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
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            Chip(title: "Auto discharge", symbol: "arrow.down.circle", isOn: settings.autoDischarge) {
                model.update { $0.autoDischarge.toggle() }
            }
            Chip(title: "Heat guard", symbol: "thermometer.medium", isOn: settings.heatProtection) {
                model.update { $0.heatProtection.toggle() }
            }
            Chip(title: "Clamshell", symbol: "laptopcomputer", isOn: settings.clamshell) {
                model.update { $0.clamshell.toggle() }
            }
            Chip(title: "Hold asleep", symbol: "moon", isOn: settings.holdAsleep) {
                model.update { $0.holdAsleep.toggle() }
            }
        }
    }

    @ViewBuilder private func jobs(_ settings: ChargeSettings) -> some View {
        let mode = model.status?.mode ?? .automatic
        if mode == .automatic {
            HStack(spacing: 8) {
                Button("Discharge") { model.perform(.discharge) }
                    .disabled((model.battery?.percent ?? 0) <= settings.limit)
                    .help("Run on battery down to \(settings.limit)%")
                Button("Top Up") { model.perform(.topUp) }
                    .help("Charge to 100% once, then return to the limit")
                Button("Calibrate…") { openDashboard(.overview) }
                    .help("Opens Chargectl to confirm a calibration")
            }
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        } else {
            HStack {
                ProgressView().controlSize(.small)
                Text("Running \(mode.title)").foregroundStyle(.secondary)
                Spacer()
                Button("Stop") { model.perform(.stop) }.controlSize(.small)
            }
        }
    }

    private var serviceNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "bolt.slash").foregroundStyle(Theme.amber)
            Text("Charge control needs its helper.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button(model.isInstallingService ? "Installing…" : "Install Helper") { model.installService() }
                .controlSize(.small)
                .disabled(model.isInstallingService)
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

/// A soft pill that toggles one setting.
private struct Chip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(isOn ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .foregroundStyle(isOn ? Theme.green : .primary)
                .background(isOn ? Theme.green.opacity(0.16) : Theme.chipFill, in: Capsule())
                .overlay { Capsule().strokeBorder(isOn ? Theme.green.opacity(0.45) : Theme.cardStroke) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "on" : "off")
    }
}
