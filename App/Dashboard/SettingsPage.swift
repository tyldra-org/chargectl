import ServiceManagement
import SwiftUI

struct SettingsPage: View {
    let model: AppModel
    @AppStorage(PreferenceKey.showInMenuBar) private var showInMenuBar = true
    @AppStorage(PreferenceKey.showPercentage) private var showPercentage = true
    @AppStorage(PreferenceKey.temperatureUnit) private var unit = TemperatureUnit.systemDefault
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceMode.system
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmingUninstall = false

    var body: some View {
        Form {
            Section {
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                Toggle("Show percentage", isOn: $showPercentage)
                    .disabled(!showInMenuBar)
                Toggle("Open at login", isOn: $opensAtLogin)
            } header: {
                Text("General")
            } footer: {
                if !showInMenuBar { Text("Open Chargectl from Finder to get back to this window.") }
            }

            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Units") {
                Picker("Temperature", selection: $unit) {
                    ForEach(TemperatureUnit.allCases) { Text($0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(model.service == .running ? Theme.green : Theme.amber).frame(width: 7, height: 7)
                        Text(serviceStatus)
                    }
                }
                if let key = model.status?.adapterKey {
                    LabeledContent("Wall power key", value: key)
                }
                serviceButton
            } header: {
                Text("Helper")
            } footer: {
                Text(
                    ServiceInstaller.method == .launchdPlist
                        ? "A small helper runs as root, switches wall power and keeps your limit while Chargectl is closed. Installing it asks for your password once; updates keep it running. Removing it reconnects wall power."
                        : "A small helper runs as root, switches wall power and keeps your limit while Chargectl is closed. After installing, turn on Chargectl in System Settings › Login Items. Removing it reconnects wall power."
                )
            }

            Section {
                LabeledContent("Version", value: DaemonIdentity.version)
                Button("Uninstall Chargectl…", role: .destructive) { confirmingUninstall = true }
                    .tint(.red)
            } footer: {
                Text(
                    "Removes the app, its background service, Login Items entries, settings, history, logs, preferences and caches, and hands charging back to macOS."
                )
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Uninstall Chargectl?", isPresented: $confirmingUninstall) {
            Button("Uninstall", role: .destructive) {
                Task { await model.uninstallEverything() }
            }
        } message: {
            Text(
                "Charging goes back to normal. The background service, Login Items entries, settings, history, logs, preferences and caches are removed, and Chargectl is deleted."
            )
        }
        .onChange(of: opensAtLogin) { _, enabled in setOpensAtLogin(enabled) }
        .onChange(of: appearance) { _, mode in mode.apply() }
    }

    private var serviceStatus: String {
        switch model.service {
        case .running: "Running"
        case .checking: "Checking…"
        case .notInstalled: "Not installed"
        case .needsApproval: "Waiting to be turned on in Login Items"
        case .notResponding: "Not responding"
        }
    }

    @ViewBuilder private var serviceButton: some View {
        switch model.service {
        case .running:
            Button("Remove Helper…", role: .destructive) { model.uninstallService() }
        case .notResponding:
            HStack {
                Button("Install Again…") { model.installService() }
                Button("Remove Helper…", role: .destructive) { model.uninstallService() }
            }
        case .notInstalled:
            Button(model.isInstallingService ? "Installing…" : "Install Helper") { model.installService() }
                .disabled(model.isInstallingService)
        case .needsApproval:
            Button("Open Login Items") { ServiceInstaller.openLoginItems() }
        case .checking:
            EmptyView()
        }
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            model.message = "Open at login could not be changed: \(error.localizedDescription)"
            opensAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
