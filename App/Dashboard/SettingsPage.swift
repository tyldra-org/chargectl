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
    @AppStorage(PreferenceKey.autoUpdate) private var autoUpdate = true
    private let updater = Updater.shared

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
                Toggle("Update automatically", isOn: $autoUpdate)
                LabeledContent("Version", value: DaemonIdentity.version)
                LabeledContent("Status", value: updateStatus)
                HStack {
                    Button(updater.phase == .checking ? "Checking…" : "Check for Updates") {
                        Task { await updater.check() }
                    }
                    if case .available(let version) = updater.phase {
                        Button("Install \(version)") { Task { await updater.installAvailable() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .disabled(updater.isBusy)
            } header: {
                Text("Updates")
            } footer: {
                Text(
                    "Chargectl checks GitHub for a new release every few hours and, with automatic updates on, installs it while its windows are closed. Each download is checked against its published checksum and code signature."
                )
            }

            Section {
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

    private var updateStatus: String {
        switch updater.phase {
        case .idle: "Not checked yet"
        case .checking: "Checking…"
        case .upToDate:
            if let date = updater.lastChecked {
                "Up to date, checked \(date.formatted(.relative(presentation: .named)))"
            } else {
                "Up to date"
            }
        case .available(let version): "Version \(version) is available"
        case .installing(let version): "Installing \(version)…"
        case .failed(let reason): reason
        }
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
