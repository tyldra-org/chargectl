import ServiceManagement
import SwiftUI

struct SettingsPage: View {
    let model: AppModel
    @AppStorage(PreferenceKey.showInMenuBar) private var showInMenuBar = true
    @AppStorage(PreferenceKey.showPercentage) private var showPercentage = true
    @AppStorage(PreferenceKey.temperatureUnit) private var unit = TemperatureUnit.systemDefault
    @AppStorage(PreferenceKey.appearance) private var appearance = AppearanceMode.system
    @AppStorage(PreferenceKey.autoUpdate) private var autoUpdate = true
    @AppStorage(PreferenceKey.notifyProblems) private var notifyProblems = true
    @AppStorage(PreferenceKey.notifyJobs) private var notifyJobs = true
    @AppStorage(PreferenceKey.notifyLimit) private var notifyLimit = false
    @State private var notificationsDenied = false
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmingUninstall = false
    @State private var confirmingRemove = false
    private let updater = Updater.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                menuBar.settleIn(0)
                ColumnRow(spans: [1, 1]) {
                    VStack(spacing: 14) {
                        appearanceCard.settleIn(1)
                        notifications.settleIn(2)
                    }
                    VStack(spacing: 14) {
                        helper.settleIn(2)
                        updates.settleIn(3)
                    }
                }
                uninstall.settleIn(4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .sheet(isPresented: $confirmingUninstall) { UninstallSheet(model: model) }
        .onChange(of: opensAtLogin) { _, enabled in setOpensAtLogin(enabled) }
        .onChange(of: appearance) { _, mode in mode.apply() }
    }

    // MARK: Menu bar

    private var menuBar: some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "Menu bar and startup", symbol: "menubar.rectangle")
                MenuBarPreview(
                    model: model, showsItem: showInMenuBar, showsPercentage: showPercentage
                )
                .padding(.top, 12)
                .padding(.bottom, 4)
                SettingRow(
                    title: "Show in menu bar", detail: Text("Chargectl’s charge ring next to the clock."),
                    divider: false
                ) {
                    toggle($showInMenuBar, on: "Shown in the menu bar", off: "Hidden from the menu bar")
                }
                SettingRow(
                    title: "Show percentage",
                    detail: Text(
                        "The charge beside the ring, as in \(Text("\(model.battery?.percent ?? 61)%").foregroundStyle(.secondary))."
                    ),
                    indented: true
                ) {
                    toggle($showPercentage, on: "Percentage shown", off: "Percentage hidden")
                }
                .dimmed(!showInMenuBar)
                SettingRow(
                    title: "Open at login",
                    detail: Text("Starts Chargectl when you log in. The helper keeps your limit either way.")
                ) {
                    toggle($opensAtLogin, on: "Opens at login", off: "Won’t open at login")
                }
                if !showInMenuBar {
                    Label(
                        "Open Chargectl from Finder to get back to this window.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.warn.opacity(0.22))
                    )
                    .padding(.top, 6)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: showInMenuBar)
        }
    }

    // MARK: Appearance

    private var appearanceCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "Appearance", symbol: "sun.max")
                HStack(spacing: 12) {
                    ForEach(AppearanceMode.allCases) { mode in
                        AppearanceTile(mode: mode, isSelected: appearance == mode) {
                            appearance = mode
                            Confirmations.shared.show("Appearance: \(mode.title)")
                        }
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 10)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Appearance")
                SettingRow(
                    title: "Temperature",
                    detail: Text(
                        "The battery is at \(Text(unit.format(model.battery?.temperature)).foregroundStyle(.secondary)) now."
                    )
                ) {
                    SlidingSegments(
                        options: TemperatureUnit.allCases.map { ($0, $0.symbol) },
                        selection: Binding(
                            get: { unit },
                            set: { value in
                                unit = value
                                Confirmations.shared.show("Temperature in \(value.symbol)")
                            }))
                }
            }
        }
    }

    // MARK: Notifications

    private var notifications: some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "Notifications", symbol: "bell")
                SettingRow(
                    title: "Problems",
                    detail: Text(
                        "The helper stops, cutting wall power has no effect, the battery is too warm, or the charger can’t keep up."
                    ), divider: false
                ) {
                    toggle($notifyProblems, on: "Problem notifications on", off: "Problem notifications off")
                }
                .padding(.top, 6)
                SettingRow(title: "Jobs finished", detail: Text("Top Up, Discharge, Calibrate and Full by are done.")) {
                    toggle($notifyJobs, on: "Job notifications on", off: "Job notifications off")
                }
                SettingRow(title: "Limit reached", detail: Text("Charging stopped at your limit.")) {
                    toggle($notifyLimit, on: "Limit notifications on", off: "Limit notifications off")
                }
                if notificationsDenied {
                    HStack(spacing: 10) {
                        Label("Notifications are off for Chargectl in System Settings.", systemImage: "bell.slash")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.warn)
                        Spacer(minLength: 8)
                        Button("Open") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                        .buttonStyle(SoftButtonStyle(small: true))
                    }
                    .padding(.top, 10)
                }
            }
        }
        .task { notificationsDenied = await Notifier.isDenied() }
        .onChange(of: [notifyProblems, notifyJobs, notifyLimit]) { _, values in
            guard values.contains(true) else { return }
            Task {
                await Notifier.requestPermission()
                notificationsDenied = await Notifier.isDenied()
            }
        }
    }

    // MARK: Helper

    private var helper: some View {
        let (title, pill, detail, tone): (String, String, String, HelperTone) =
            switch model.service {
            case .running:
                ("Running", "Active", "Switches wall power and keeps your limit while Chargectl is closed.", .ok)
            case .checking: ("Checking…", "Asking", "Asking the helper how it is.", .quiet)
            case .notInstalled: ("Not installed", "Off", "Charge control is off until the helper is installed.", .quiet)
            case .needsApproval:
                (
                    "Waiting for approval", "Login Items",
                    "Turn on Chargectl in System Settings › Login Items to start it.", .warn
                )
            case .notResponding:
                (
                    "Not responding", "Stalled",
                    "The helper is installed but doesn’t answer. Installing it again usually fixes this.", .warn
                )
            }
        return Panel {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "Helper", symbol: "shield")
                HStack(spacing: 12) {
                    Image(
                        systemName: tone == .ok
                            ? "checkmark.shield" : tone == .warn ? "exclamationmark.triangle" : "shield"
                    )
                    .font(.system(size: 17))
                    .foregroundStyle(tone.color)
                    .frame(width: 38, height: 38)
                    .background(tone.soft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(tone.color.opacity(0.3)))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(title).font(.system(size: 15, weight: .semibold))
                            HStack(spacing: 6) {
                                Circle().fill(tone.color).frame(width: 6, height: 6).shadow(
                                    color: tone.color, radius: tone == .quiet ? 0 : 3)
                                Text(pill)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(tone.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(tone.soft, in: Capsule())
                        }
                        Text(detail).font(.system(size: 12)).foregroundStyle(.tertiary).fixedSize(
                            horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 4)
                if let key = model.status?.adapterKey {
                    SettingRow(
                        title: "Wall power key",
                        detail: Text("The SMC key this Mac uses to cut and restore wall power."), divider: false
                    ) {
                        Text(key)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.lineStrong))
                    }
                }
                HStack(spacing: 8) { helperActions }
                    .padding(.top, 12)
                Text(
                    ServiceInstaller.method == .launchdPlist
                        ? "The helper runs as root. Installing it asks for your password once; updates keep it running. Removing it reconnects wall power."
                        : "The helper runs as root. After installing, turn on Chargectl in System Settings › Login Items. Removing it reconnects wall power."
                )
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            }
        }
    }

    @ViewBuilder private var helperActions: some View {
        switch model.service {
        case .running:
            removeButton
        case .notResponding:
            Button {
                model.installService()
            } label: {
                Label(model.isInstallingService ? "Installing…" : "Install Again…", systemImage: "arrow.clockwise")
            }
            .buttonStyle(SoftButtonStyle(small: true))
            .disabled(model.isInstallingService)
            removeButton
        case .notInstalled:
            Button {
                model.installService()
            } label: {
                Label(model.isInstallingService ? "Installing…" : "Install Helper", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(SoftButtonStyle(kind: .primary, small: true))
            .disabled(model.isInstallingService)
        case .needsApproval:
            Button("Open Login Items") { ServiceInstaller.openLoginItems() }
                .buttonStyle(SoftButtonStyle(kind: .primary, small: true))
        case .checking:
            EmptyView()
        }
    }

    private var removeButton: some View {
        Button("Remove Helper…") { confirmingRemove = true }
            .buttonStyle(SoftButtonStyle(kind: .danger, small: true))
            .popover(isPresented: $confirmingRemove, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remove the helper?").font(.system(size: 13, weight: .semibold))
                    Text(
                        "Wall power is reconnected and macOS takes over charging. Your settings, history and logs are kept."
                    )
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Cancel") { confirmingRemove = false }
                            .buttonStyle(SoftButtonStyle(small: true))
                            .keyboardShortcut(.cancelAction)
                        Button("Remove") {
                            confirmingRemove = false
                            model.uninstallService()
                            Confirmations.shared.show("Helper removed")
                        }
                        .buttonStyle(SoftButtonStyle(kind: .danger, small: true))
                    }
                    .padding(.top, 8)
                }
                .padding(14)
                .frame(width: 290)
            }
    }

    // MARK: Updates

    private var updates: some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "Updates", symbol: "arrow.triangle.2.circlepath")
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Chargectl").font(.system(size: 13, weight: .medium))
                            Text(DaemonIdentity.version)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.lineStrong))
                        }
                        updateStatus
                    }
                    Spacer()
                    Button(updater.phase == .checking ? "Checking…" : "Check for Updates") {
                        Task { await updater.check() }
                    }
                    .buttonStyle(SoftButtonStyle(small: true))
                    .disabled(updater.isBusy)
                }
                .padding(.top, 14)
                availablePanel
                    .animation(.spring(response: 0.4, dampingFraction: 0.86), value: updater.phase)
                SettingRow(
                    title: "Update automatically",
                    detail: Text(
                        autoUpdate
                            ? "Installs new versions while Chargectl’s windows are closed."
                            : "Chargectl tells you about new versions; you install them here.")
                ) {
                    toggle($autoUpdate, on: "Automatic updates on", off: "Automatic updates off")
                }
                .padding(.top, 8)
                Text(
                    "Chargectl checks GitHub for a new release every few hours. Each download is checked against its published checksum and code signature."
                )
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            }
        }
    }

    @ViewBuilder private var updateStatus: some View {
        Group {
            switch updater.phase {
            case .idle: Label("Not checked yet", systemImage: "clock")
            case .checking:
                Label {
                    Text("Checking…")
                } icon: {
                    ProgressView().controlSize(.mini)
                }
            case .upToDate:
                Label(
                    updater.lastChecked.map { "Up to date, checked \($0.formatted(.relative(presentation: .named)))" }
                        ?? "Up to date", systemImage: "checkmark.circle"
                )
                .labelStyle(TintedIconLabelStyle(tint: Theme.accent))
            case .available:
                Label("New version found", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(TintedIconLabelStyle(tint: Theme.accent))
            case .installing(let version):
                Label {
                    Text("Installing \(version)…")
                } icon: {
                    ProgressView().controlSize(.mini)
                }
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .labelStyle(TintedIconLabelStyle(tint: Theme.warn))
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder private var availablePanel: some View {
        let version: String? =
            switch updater.phase {
            case .available(let version), .installing(let version): version
            default: nil
            }
        if let version {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Version \(version) is available").font(.system(size: 13, weight: .semibold))
                    Text("New")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color(red: 0.02, green: 0.13, blue: 0.04))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule())
                }
                Text(
                    "Downloaded from GitHub and checked against its published checksum and code signature before it installs."
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if case .installing = updater.phase {
                    ProgressView().progressViewStyle(.linear).tint(Theme.accent).padding(.top, 8)
                } else {
                    Button {
                        Task { await updater.installAvailable() }
                    } label: {
                        Label("Install \(version)", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(SoftButtonStyle(kind: .primary, small: true))
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Theme.accentSoft, .clear], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.3)))
            .padding(.top, 12)
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
    }

    // MARK: Uninstall

    private var uninstall: some View {
        Panel(padding: 16, tint: Theme.danger) {
            HStack(spacing: 16) {
                Image(systemName: "trash")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.danger)
                    .frame(width: 34, height: 34)
                    .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uninstall Chargectl").font(.system(size: 13, weight: .medium))
                    Text(
                        "Removes the app, its background service, Login Items entries, settings, history, logs, preferences, caches and widget data, and hands charging back to macOS."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Uninstall Chargectl…") { confirmingUninstall = true }
                    .buttonStyle(SoftButtonStyle(kind: .danger, small: true))
            }
        }
    }

    private func toggle(_ binding: Binding<Bool>, on: String, off: String) -> some View {
        Toggle(
            "",
            isOn: Binding(
                get: { binding.wrappedValue },
                set: { value in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { binding.wrappedValue = value }
                    Confirmations.shared.show(value ? on : off)
                })
        )
        .toggleStyle(GlowSwitchStyle())
        .labelsHidden()
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

// MARK: - Parts

private enum HelperTone {
    case ok, warn, quiet

    var color: Color {
        switch self {
        case .ok: Theme.accent
        case .warn: Theme.warn
        case .quiet: .secondary
        }
    }

    var soft: Color {
        switch self {
        case .ok: Theme.accentSoft
        case .warn: Theme.warnSoft
        case .quiet: Color.primary.opacity(0.07)
        }
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

/// A slim menu bar over a soft wallpaper, with Chargectl's item next to the clock. It follows the
/// two menu bar switches.
private struct MenuBarPreview: View {
    let model: AppModel
    let showsItem: Bool
    let showsPercentage: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink: Color = scheme == .dark ? .white : Color(white: 0.11)
        HStack(spacing: 14) {
            // The menus give way first, as on a real menu bar, so the status items always fit.
            ViewThatFits(in: .horizontal) {
                menus(["File", "Edit", "View"])
                menus(["File", "Edit"])
                menus(["File"])
                menus([])
            }
            .opacity(0.9)
            Spacer(minLength: 8)
            if showsItem {
                HStack(spacing: 5) {
                    Image(nsImage: RingIcon.image(for: model))
                        .renderingMode(.template)
                    if showsPercentage, let percent = model.battery?.percent {
                        Text("\(percent)%").monospacedDigit().transition(
                            .opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .fixedSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(ink.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            Image(systemName: "wifi")
            Text(Date.now, format: .dateTime.weekday(.abbreviated).hour().minute()).lineLimit(1).fixedSize()
        }
        .lineLimit(1)
        .font(.system(size: 12.5, weight: .medium))
        .foregroundStyle(ink)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background {
            LinearGradient(
                colors: scheme == .dark
                    ? [
                        Color(red: 0.23, green: 0.17, blue: 0.36), Color(red: 0.35, green: 0.23, blue: 0.43),
                        Color(red: 0.75, green: 0.42, blue: 0.35), Color(red: 0.9, green: 0.6, blue: 0.36),
                    ]
                    : [
                        Color(red: 0.74, green: 0.83, blue: 0.95), Color(red: 0.85, green: 0.78, blue: 0.94),
                        Color(red: 0.96, green: 0.82, blue: 0.74),
                    ],
                startPoint: .leading, endPoint: .trailing
            )
            .overlay(scheme == .dark ? Color(white: 0.08).opacity(0.4) : Color.white.opacity(0.45))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showsItem)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showsPercentage)
        .accessibilityHidden(true)
    }

    private func menus(_ titles: [String]) -> some View {
        HStack(spacing: 14) {
            Text("Chargectl").fontWeight(.bold)
            ForEach(titles, id: \.self) { Text($0) }
        }
        .fixedSize()
    }
}

/// System, Light or Dark as a small window, as in System Settings.
private struct AppearanceTile: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 8) {
                ZStack {
                    window(dark: false)
                    if mode != .light {
                        window(dark: true)
                            .mask {
                                if mode == .system {
                                    GeometryReader { geometry in
                                        Path { path in
                                            let w = geometry.size.width
                                            let h = geometry.size.height
                                            path.move(to: CGPoint(x: w * 0.62, y: 0))
                                            path.addLine(to: CGPoint(x: w, y: 0))
                                            path.addLine(to: CGPoint(x: w, y: h))
                                            path.addLine(to: CGPoint(x: w * 0.38, y: h))
                                            path.closeSubpath()
                                        }
                                    }
                                } else {
                                    Rectangle()
                                }
                            }
                    }
                }
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isSelected ? Theme.accent : Theme.lineStrong, lineWidth: isSelected ? 2 : 1)
                )
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(isSelected ? 0.2 : 0), lineWidth: 3)
                        .padding(-4)
                )
                .shadow(color: .black.opacity(0.18), radius: 7, y: 4)
                HStack(spacing: 5) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    }
                    Text(mode.title)
                }
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .animation(.easeOut(duration: 0.2), value: isSelected)
    }

    private func window(dark: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(dark ? Color(red: 0.125, green: 0.125, blue: 0.14) : Color(red: 0.91, green: 0.91, blue: 0.93))
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(dark ? Color(white: 0.18) : Color(white: 0.86)).frame(width: 1)
                }
                .layoutPriority(0)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Color(red: 0.2, green: 0.84, blue: 0.29)).frame(width: 30, height: 5)
                Capsule().fill(dark ? Color(white: 0.2) : Color(white: 0.86)).frame(width: 52, height: 5)
                Capsule().fill(dark ? Color(white: 0.2) : Color(white: 0.86)).frame(width: 42, height: 5)
                Spacer()
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(dark ? Color(red: 0.094, green: 0.094, blue: 0.106) : Color(red: 0.957, green: 0.957, blue: 0.965))
    }
}

/// Uninstall confirmation: what is removed, then Chargectl hands charging back and quits.
private struct UninstallSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var removing = false

    private let items = [
        ("app.dashed", "The app"), ("gearshape.2", "Background service"),
        ("person.crop.circle.badge.checkmark", "Login Items entries"),
        ("slider.horizontal.3", "Settings"), ("chart.xyaxis.line", "History"), ("list.bullet.rectangle", "Logs"),
        ("switch.2", "Preferences"), ("internaldrive", "Caches"),
        ("square.grid.2x2", "Widget data"), ("exclamationmark.triangle", "Crash reports"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "trash")
                .font(.system(size: 18))
                .foregroundStyle(Theme.danger)
                .frame(width: 40, height: 40)
                .background(Theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.bottom, 12)
            Text("Uninstall Chargectl?")
                .font(.system(size: 16, weight: .semibold))
                .padding(.bottom, 4)
            Text("Charging goes back to normal. These are removed, and Chargectl is deleted:")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
            LazyVGrid(
                columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                spacing: 8
            ) {
                ForEach(items, id: \.1) { symbol, item in
                    Label(item, systemImage: symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 18)
            HStack(spacing: 8) {
                if removing {
                    ProgressView().controlSize(.small)
                    Text("Handing charging back to macOS, then removing everything…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SoftButtonStyle(small: true))
                    .keyboardShortcut(.cancelAction)
                    .disabled(removing)
                Button(removing ? "Uninstalling…" : "Uninstall") {
                    removing = true
                    Task {
                        // Returns only when a step failed; the reason shows as a notice.
                        await model.uninstallEverything()
                        removing = false
                        dismiss()
                    }
                }
                .buttonStyle(SoftButtonStyle(kind: .danger, small: true))
                .disabled(removing)
            }
        }
        .padding(22)
        .frame(width: 440)
    }
}
