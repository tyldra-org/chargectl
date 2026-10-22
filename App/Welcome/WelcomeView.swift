import AppKit
import ServiceManagement
import SwiftUI

/// First-run setup: what Chargectl does, installing the helper, the first limit, and where to
/// find the app afterwards. Opens on every launch until it is finished.
struct WelcomeView: View {
    enum Step: Int, CaseIterable {
        case welcome
        case helper
        case limit
        case done
    }

    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @State private var step: Step =
        UserDefaults.standard.bool(forKey: PreferenceKey.setupComplete) ? .helper : .welcome
    @State private var draftLimit: Double?
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome: welcome
                case .helper: helper
                case .limit: limit
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .padding(.vertical, 28)
            .transition(.opacity)
            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 580, height: 600)
        .animation(.easeOut(duration: 0.2), value: step)
        .tint(Theme.green)
        .onAppear { Dashboard.show(Dashboard.window(WindowID.welcome)) }
        .onDisappear { Dashboard.didClose() }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Welcome to Chargectl").font(.largeTitle.weight(.semibold))
                Text("Keep your MacBook's battery at a charge limit, right from the menu bar.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                Feature(
                    symbol: "battery.75percent", title: "Charge to a limit",
                    text:
                        "Stop anywhere from 20% to 100% and run on the charger, so the battery isn't kept full all day."
                )
                Feature(
                    symbol: "bolt", title: "Live power",
                    text: "See what the charger, the Mac and the battery are doing, second by second.")
                Feature(
                    symbol: "chart.xyaxis.line", title: "History",
                    text: "Charge, temperature and power over the last day.")
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
    }

    private var helper: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            StepHeader(
                symbol: "lock.shield", title: "Install the helper",
                text:
                    "Charging is controlled by a small helper that runs as an administrator, also while Chargectl is closed."
            )
            VStack(spacing: 0) {
                ChecklistRow(
                    number: 1, title: "Install the helper",
                    detail: needsApproval ? "Adds it to Login Items." : "macOS asks for your password once.",
                    state: helperInstalled ? .done : model.isInstallingService ? .working : .current)
                Divider().padding(.leading, 44)
                if needsApproval {
                    ChecklistRow(
                        number: 2, title: "Turn on Chargectl",
                        detail: "System Settings › General › Login Items & Extensions › Allow in the Background.",
                        state: !helperInstalled ? .waiting : model.service == .needsApproval ? .current : .done)
                    Divider().padding(.leading, 44)
                }
                ChecklistRow(
                    number: needsApproval ? 3 : 2, title: "Helper running", detail: "Charge control is active.",
                    state: model.service == .running ? .done : helperApproved ? .working : .waiting)
            }
            .padding(.vertical, 4)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke) }
            helperAction.frame(height: 36)
            if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Theme.amber)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// Only an SMAppService helper waits to be turned on in Login Items.
    private var needsApproval: Bool { ServiceInstaller.method == .appService }

    private var helperInstalled: Bool { model.service == .running || ServiceInstaller().isInstalled }
    private var helperApproved: Bool { ServiceInstaller().registration == .enabled }

    @ViewBuilder private var helperAction: some View {
        switch model.service {
        case .running:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.green)
        case .needsApproval:
            Button {
                ServiceInstaller.openLoginItems()
            } label: {
                Text("Open Login Items").frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .checking where helperInstalled:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Starting the helper…").foregroundStyle(.secondary)
            }
        default:
            Button {
                model.installService()
            } label: {
                Text(helperInstalled ? "Install Again" : "Install Helper").frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isInstallingService)
        }
    }

    private var limit: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            StepHeader(
                symbol: "battery.75percent", title: "Choose a limit",
                text: "Charging stops here and the Mac keeps running on the charger.")
            if let settings = model.settings, model.isControllable {
                let value = Int(draftLimit ?? Double(settings.limit))
                VStack(spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(value)")
                            .font(.system(size: 56, weight: .thin))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("%").font(.title2.weight(.light)).foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(get: { draftLimit ?? Double(settings.limit) }, set: { draftLimit = $0 }),
                        in: Double(
                            ChargeSettings.limitRange.lowerBound)...Double(
                                ChargeSettings.limitRange.upperBound),
                        step: 1
                    ) {
                        Text("Charge limit")
                    } minimumValueLabel: {
                        Text("20%").font(.caption).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("100%").font(.caption).foregroundStyle(.secondary)
                    } onEditingChanged: { editing in
                        guard !editing, let draftLimit else { return }
                        model.update { $0.limit = Int(draftLimit) }
                    }
                    .labelsHidden()
                    HStack(spacing: 8) {
                        ForEach([60, 70, 80, 90, 100], id: \.self) { preset in
                            Button("\(preset)%") {
                                draftLimit = Double(preset)
                                model.update { $0.limit = preset }
                            }
                            .buttonStyle(TileButtonStyle(isOn: value == preset))
                        }
                    }
                }
                .padding(18)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("When plugged in above the limit").font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        Button("Hold the charge") { model.update { $0.autoDischarge = false } }
                            .buttonStyle(TileButtonStyle(isOn: !settings.autoDischarge))
                        Button("Discharge to the limit") { model.update { $0.autoDischarge = true } }
                            .buttonStyle(TileButtonStyle(isOn: settings.autoDischarge))
                    }
                }
                Text(limitNote(value))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Install the helper first; until then Chargectl only shows readings.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
    }

    private func limitNote(_ value: Int) -> String {
        if value >= 100 { return "The battery charges fully, as it would without Chargectl." }
        let start = model.macOSLimit.map { "Your macOS charge limit was \($0)%. " } ?? ""
        return start + "You can change this any time from the menu bar."
    }

    private var done: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            StepHeader(
                symbol: "checkmark.seal.fill", title: "You're all set",
                text: "Chargectl lives in your menu bar. Click the ring to see your battery and change the limit.")
            HStack(spacing: 6) {
                Image(nsImage: RingIcon.image(fraction: Double(model.battery?.percent ?? 80) / 100, size: 18))
                Text("\(model.battery?.percent ?? 80)%").monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.chipFill, in: Capsule())
            .accessibilityHidden(true)
            VStack(spacing: 0) {
                SummaryRow(title: "Charge limit", value: model.settings.map { "\($0.limit)%" } ?? "–")
                Divider()
                SummaryRow(
                    title: "Above the limit",
                    value: model.settings.map { $0.autoDischarge ? "Discharge to it" : "Hold the charge" } ?? "–")
                Divider()
                SummaryRow(title: "Helper", value: model.service == .running ? "Running" : "Not running")
                Divider()
                HStack {
                    Text("Open Chargectl at login")
                    Spacer()
                    Toggle("Open Chargectl at login", isOn: $opensAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke) }
            .onChange(of: opensAtLogin) { _, enabled in setOpensAtLogin(enabled) }
            Spacer(minLength: 0)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? Theme.green : Theme.chipFill)
                        .frame(width: item == step ? 18 : 7, height: 7)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
            Spacer()
            if step != .welcome && step != .done {
                Button("Back") { move(-1) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
            }
            if step == .helper && model.service != .running {
                Button("Skip for Now") { move(1) }
            }
            primaryButton
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case .welcome:
            Button("Get Started") { move(1) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .helper:
            Button("Continue") { move(1) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.service != .running)
        case .limit:
            Button("Continue") { move(1) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .done:
            Button("Done") { finish() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func move(_ offset: Int) {
        step = Step(rawValue: step.rawValue + offset) ?? step
    }

    /// Ends setup and opens the dashboard on Overview.
    private func finish() {
        Setup.finish()
        Dashboard.show()
        openWindow(id: WindowID.dashboard)
        dismissWindow(id: WindowID.welcome)
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
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.green)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Icon, title and one line of explanation, shared by the setup steps.
private struct StepHeader: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.green)
                .frame(height: 46)
            Text(title).font(.title.weight(.semibold))
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ChecklistRow: View {
    enum State {
        case waiting
        case current
        case working
        case done
    }

    let number: Int
    let title: String
    let detail: String
    let state: State

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                case .working:
                    ProgressView().controlSize(.small)
                case .current:
                    Text("\(number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Theme.green, in: Circle())
                case .waiting:
                    Text("\(number)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .overlay { Circle().strokeBorder(Theme.cardStroke) }
                }
            }
            .font(.title3)
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(state == .waiting ? .secondary : .primary)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct SummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
