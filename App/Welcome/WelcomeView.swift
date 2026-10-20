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
            .padding(.horizontal, 48)
            .padding(.top, 40)
            .transition(.opacity)
            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 560, height: 540)
        .animation(.easeOut(duration: 0.2), value: step)
        .tint(Theme.green)
        .onAppear { Dashboard.show(Dashboard.window(WindowID.welcome)) }
        .onDisappear { Dashboard.didClose() }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 18) {
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
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.green)
            VStack(spacing: 6) {
                Text("Install the helper").font(.title.weight(.semibold))
                Text(
                    "Charging is controlled by a small helper that runs as an administrator, also while Chargectl is closed. macOS asks for your password once."
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            helperStatus.padding(.top, 8)
            if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(Theme.amber)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("Removing it later from Settings hands charging back to macOS.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var helperStatus: some View {
        if model.service == .running {
            Label("Helper installed and running", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Theme.green)
        } else if model.isInstallingService {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Waiting for your password…").foregroundStyle(.secondary)
            }
        } else if model.service == .checking, ServiceInstaller().isInstalled {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Starting the helper…").foregroundStyle(.secondary)
            }
        } else {
            Button {
                model.installService()
            } label: {
                Text(ServiceInstaller().isInstalled ? "Install Again…" : "Install Helper…").frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var limit: some View {
        VStack(spacing: 18) {
            Text("Choose a limit").font(.title.weight(.semibold))
            if let settings = model.settings, model.isControllable {
                let value = Int(draftLimit ?? Double(settings.limit))
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(value)")
                        .font(.system(size: 64, weight: .thin))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%").font(.title2.weight(.light)).foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(get: { draftLimit ?? Double(settings.limit) }, set: { draftLimit = $0 }),
                    in: Double(ChargeSettings.limitRange.lowerBound)...Double(ChargeSettings.limitRange.upperBound),
                    step: 1
                ) {
                    Text("Charge limit")
                } minimumValueLabel: {
                    Text("20%")
                } maximumValueLabel: {
                    Text("100%")
                } onEditingChanged: { editing in
                    guard !editing, let draftLimit else { return }
                    model.update { $0.limit = Int(draftLimit) }
                }
                .labelsHidden()
                Text(limitNote(value))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Install the helper first; until then Chargectl only shows readings.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            Text("You can change it any time from the menu bar.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
    }

    private func limitNote(_ value: Int) -> String {
        if value >= 100 { return "The battery charges fully, as it would without Chargectl." }
        let start =
            model.macOSLimit.map { "Your macOS charge limit was \($0)%. " } ?? ""
        return start + "Charging stops at \(value)% and the Mac keeps running on the charger."
    }

    private var done: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.green)
            VStack(spacing: 6) {
                Text("You're all set").font(.title.weight(.semibold))
                Text("Chargectl lives in your menu bar. Click the ring to see your battery and change the limit.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Image(nsImage: RingIcon.image(fraction: Double(model.battery?.percent ?? 80) / 100, size: 18))
                Text("\(model.battery?.percent ?? 80)%").monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.chipFill, in: Capsule())
            .accessibilityHidden(true)
            Toggle("Open Chargectl at login", isOn: $opensAtLogin)
                .toggleStyle(.switch)
                .padding(.top, 12)
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
