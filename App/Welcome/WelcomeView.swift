import AppKit
import ServiceManagement
import SwiftUI

/// First-run setup: what Chargectl does, installing the helper, the first limit, and where to
/// find the app afterwards. Opens on every launch until it is finished.
///
/// One centred column per step: a picture, a title, one sentence and the step's controls, with
/// Back, the step dots and the main action along the bottom.
struct WelcomeView: View {
    enum Step: Int, CaseIterable {
        case welcome
        case helper
        case limit
        case done
    }

    static let size = CGSize(width: 640, height: 572)

    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step
    /// Which way the last move went, so the next page slides in from that side.
    @State private var forward = true
    @State private var draftLimit: Int?
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    init(model: AppModel, initialStep: Step? = nil) {
        self.model = model
        _step = State(
            initialValue: initialStep
                ?? (UserDefaults.standard.bool(forKey: PreferenceKey.setupComplete) ? .helper : .welcome))
    }

    var body: some View {
        VStack(spacing: 0) {
            // A ZStack, so the page going out and the page coming in overlap instead of stacking.
            ZStack(alignment: .top) {
                page
                    .id(step)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            ZStack {
                Theme.window
                RadialGradient(
                    colors: [Color.white.opacity(0.035), .clear], center: UnitPoint(x: 0.5, y: 0.05), startRadius: 0,
                    endRadius: 480)
                Grain()
            }
            .ignoresSafeArea()
        }
        .tint(Theme.accent)
        .ignoresSafeArea(edges: .top)
        .onAppear { Dashboard.show(Dashboard.window(WindowID.welcome)) }
        .onDisappear { Dashboard.didClose() }
    }

    // MARK: Page

    private var page: some View {
        VStack(spacing: 0) {
            picture
                .frame(height: 156)
                .settleIn(0)
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.4)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 480)
            .padding(.top, 14)
            .settleIn(1)
            controls
                .frame(width: 472)
                .padding(.top, 26)
                .settleIn(2)
        }
        .padding(.top, 46)
    }

    private var title: String {
        switch step {
        case .welcome: "Welcome to Chargectl"
        case .helper: "Install the helper"
        case .limit: "Choose a limit"
        case .done: "You’re all set"
        }
    }

    private var message: String {
        switch step {
        case .welcome: "Keep your MacBook’s battery at a charge limit, right from the menu bar."
        case .helper:
            "Charging is controlled by a small helper that runs as an administrator, also while Chargectl is closed."
        case .limit: "Charging stops here and your Mac keeps running on the charger."
        case .done:
            "Chargectl lives in your menu bar. Click the ring any time to see your battery and change the limit."
        }
    }

    @ViewBuilder private var picture: some View {
        switch step {
        case .welcome:
            WelcomeRing()
        case .helper:
            HelperDiagram(phase: helperPhase)
        case .limit:
            if model.settings != nil, model.isControllable {
                let limit = currentLimit
                LimitRing(
                    fill: model.battery?.percent ?? limit, limit: limit, number: limit, caption: "Limit",
                    smooth: draftLimit == nil)
            } else {
                let percent = model.battery?.percent ?? 0
                LimitRing(fill: percent, limit: 100, number: percent, caption: "Charge now").opacity(0.55)
            }
        case .done:
            MenuBarPreview(model: model)
        }
    }

    @ViewBuilder private var controls: some View {
        switch step {
        case .welcome: features
        case .helper: helperSteps
        case .limit: limitControls
        case .done: summary
        }
    }

    // MARK: Welcome

    private var features: some View {
        HStack(alignment: .top, spacing: 0) {
            Feature(symbol: "battery.75percent", title: "A charge limit", text: "Stop anywhere from 20% to 100%.")
            Rectangle().fill(Theme.line).frame(width: 1, height: 52)
            Feature(symbol: "bolt", title: "Live power", text: "Watts in and out, second by second.")
            Rectangle().fill(Theme.line).frame(width: 1, height: 52)
            Feature(symbol: "chart.xyaxis.line", title: "History", text: "Charge and heat over the last day.")
        }
    }

    // MARK: Helper

    private var helperSteps: some View {
        VStack(spacing: 12) {
            Panel(padding: 0) {
                VStack(spacing: 0) {
                    TaskRow(
                        number: 1, title: "Install the helper",
                        detail: needsApproval ? "Adds it to Login Items." : "macOS asks for your password once.",
                        phase: isInstalled ? .done : model.isInstallingService ? .working : .current, divider: false)
                    if needsApproval {
                        TaskRow(
                            number: 2, title: "Allow it in Login Items",
                            detail: "System Settings › General › Login Items & Extensions.",
                            phase: !isInstalled ? .waiting : model.service == .needsApproval ? .current : .done)
                    }
                    TaskRow(
                        number: needsApproval ? 3 : 2, title: "Helper running", detail: runningDetail,
                        phase: runningPhase)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if let message = model.message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Only an SMAppService helper waits to be turned on in Login Items.
    private var needsApproval: Bool { ServiceInstaller.method == .appService }

    private var isInstalled: Bool {
        switch model.service {
        case .running, .needsApproval: true
        default: ServiceInstaller().isInstalled
        }
    }

    private var runningPhase: TaskRow.Phase {
        switch model.service {
        case .running: .done
        case .notResponding: .failed
        case .checking where isInstalled: .working
        default: .waiting
        }
    }

    private var runningDetail: String {
        switch model.service {
        case .running: "Charge control is on."
        case .notResponding: "It stopped answering. Install it again."
        default: "Starts by itself once it’s installed."
        }
    }

    private var helperPhase: HelperDiagram.Phase {
        if model.isInstallingService { return .installing }
        switch model.service {
        case .running: return .live
        case .needsApproval: return .waiting
        case .notResponding: return .failed
        case .checking: return isInstalled ? .starting : .off
        case .notInstalled: return .off
        }
    }

    // MARK: Limit

    private var currentLimit: Int { draftLimit ?? model.settings?.limit ?? 80 }

    @ViewBuilder private var limitControls: some View {
        if let settings = model.settings, model.isControllable {
            let limit = currentLimit
            VStack(spacing: 16) {
                LimitSlider(
                    limit: limit, saved: settings.limit, lowerBound: nil, now: model.battery?.percent,
                    draft: $draftLimit
                ) { value in
                    model.update { $0.limit = value }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Plugged in above the limit").font(.system(size: 13, weight: .medium))
                        Spacer()
                        SlidingSegments(
                            options: [(false, "Hold"), (true, "Discharge")],
                            selection: Binding(
                                get: { settings.autoDischarge },
                                set: { value in model.update { $0.autoDischarge = value } }))
                    }
                    Text(
                        settings.autoDischarge
                            ? "Above \(Text("\(limit)%").foregroundStyle(.secondary)) on the charger, the battery runs down to the limit, then holds."
                            : "Above \(Text("\(limit)%").foregroundStyle(.secondary)) on the charger, the battery stays where it is."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        } else {
            Panel(padding: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "lock")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Needs the helper").font(.system(size: 13, weight: .medium))
                        Text("Until it’s installed, Chargectl only shows readings.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 8)
                    Button("Install Helper") { go(to: .helper) }
                        .buttonStyle(SoftButtonStyle(small: true))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Done

    private var summary: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                SettingRow(title: "Charge limit", divider: false) {
                    value(model.settings.map { "\($0.limit)%" } ?? "–")
                }
                SettingRow(title: "Above the limit") {
                    value(model.settings.map { $0.autoDischarge ? "Discharge" : "Hold" } ?? "–")
                }
                SettingRow(title: "Helper") {
                    HStack(spacing: 8) {
                        if model.service == .running {
                            PulseDot()
                        } else {
                            Circle().fill(Theme.warn).frame(width: 7, height: 7)
                        }
                        value(model.service == .running ? "Running" : "Not installed")
                    }
                }
                SettingRow(title: "Open Chargectl at login") {
                    Toggle("", isOn: $opensAtLogin)
                        .toggleStyle(GlowSwitchStyle())
                        .labelsHidden()
                        .accessibilityLabel("Open Chargectl at login")
                }
            }
            .padding(.horizontal, 16)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: opensAtLogin) { _, enabled in setOpensAtLogin(enabled) }
    }

    private func value(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit()
    }

    // MARK: Footer

    private var footer: some View {
        ZStack {
            StepDots(step: step)
            HStack(spacing: 6) {
                if step == .welcome {
                    Text("Takes about a minute").font(.system(size: 12)).foregroundStyle(.tertiary)
                } else {
                    Button {
                        go(to: Step(rawValue: step.rawValue - 1) ?? .welcome)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 10.5, weight: .semibold))
                            Text("Back")
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut("[", modifiers: .command)
                }
                Spacer()
                if step == .helper && model.service != .running {
                    Button("Skip for Now") { go(to: .limit) }
                        .buttonStyle(QuietButtonStyle())
                }
                primaryButton
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 68)
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case .welcome: primary("Get Started") { go(to: .helper) }
        case .helper: helperButton
        case .limit: primary("Continue") { go(to: .done) }
        case .done: primary("Open Chargectl") { finish() }
        }
    }

    @ViewBuilder private var helperButton: some View {
        switch model.service {
        case .running:
            primary("Continue") { go(to: .limit) }
        case .needsApproval:
            primary("Open Login Items") { ServiceInstaller.openLoginItems() }
        case .checking where isInstalled:
            primary("Starting…", enabled: false) {}
        case .notResponding:
            primary(model.isInstallingService ? "Installing…" : "Install Again", enabled: !model.isInstallingService) {
                model.installService()
            }
        default:
            primary(model.isInstallingService ? "Installing…" : "Install Helper", enabled: !model.isInstallingService) {
                model.installService()
            }
        }
    }

    private func primary(_ title: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(SoftButtonStyle(kind: .primary, large: true))
            .keyboardShortcut(.defaultAction)
            .disabled(!enabled)
    }

    // MARK: Actions

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: forward ? 14 : -14)),
            removal: .opacity.animation(.easeOut(duration: 0.14)))
    }

    private func go(to target: Step) {
        guard target != step else { return }
        forward = target.rawValue > step.rawValue
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.45)) {
            step = target
        }
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

// MARK: - Pictures

/// The menu bar ring, large: the track ends at the limit and the charge fills it, so a closed
/// ring means the battery is held there.
private struct LimitRing: View {
    let fill: Int
    let limit: Int
    let number: Int
    let caption: String
    /// Off while a slider drives the value, so the ring follows the pointer exactly.
    var smooth = true

    var body: some View {
        ZStack {
            Group {
                Circle()
                    .trim(from: 0, to: Double(limit) / 100)
                    .stroke(Theme.track, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                Circle()
                    .trim(from: 0, to: Double(min(fill, limit)) / 100)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .shadow(color: Theme.glow.opacity(0.55), radius: 6)
            }
            .rotationEffect(.degrees(-90))
            .padding(3)
            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(number)")
                        .font(.system(size: 40, weight: .ultraLight))
                        .monospacedDigit()
                        .tracking(-1)
                        .contentTransition(.numericText(value: Double(number)))
                    Text("%").font(.system(size: 15, weight: .light)).foregroundStyle(.tertiary)
                }
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.opacity)
            }
        }
        .frame(width: 134, height: 134)
        .animation(smooth ? .smooth(duration: 0.35) : nil, value: limit)
        .animation(.smooth(duration: 0.35), value: caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption) \(number) percent")
    }
}

/// Step one's picture: the ring charges up to an 80% limit and holds there.
private struct WelcomeRing: View {
    @State private var charge = 32
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let limit = 80

    var body: some View {
        LimitRing(
            fill: charge, limit: limit, number: charge, caption: charge < limit ? "Charging" : "Held at the limit"
        )
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion else {
                charge = limit
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            while charge < limit, !Task.isCancelled {
                withAnimation(.linear(duration: 0.03)) { charge += 1 }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }
}

/// Step two's picture: Chargectl, the helper and the battery, joined by lines that carry a soft
/// pulse once the helper works.
private struct HelperDiagram: View {
    enum Phase {
        case off
        case installing
        case waiting
        case starting
        case live
        case failed
    }

    let phase: Phase

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            node("Chargectl") {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 58, height: 58)
            }
            Beam(style: links.0).frame(height: 48)
            node("Helper") {
                tile {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 19))
                        .foregroundStyle(helperTint)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            Beam(style: links.1).frame(height: 48)
            node("Battery") {
                tile {
                    Image(systemName: "battery.75percent")
                        .font(.system(size: 18))
                        .foregroundStyle(phase == .live ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                }
            }
        }
        .frame(width: 400)
        .frame(maxHeight: .infinity)
        .animation(.smooth(duration: 0.4), value: phase)
        .accessibilityHidden(true)
    }

    private var links: (Beam.Style, Beam.Style) {
        switch phase {
        case .off: (.idle, .idle)
        case .installing: (.flowing, .idle)
        case .waiting, .failed: (.solid, .blocked)
        case .starting: (.solid, .flowing)
        case .live: (.flowing, .flowing)
        }
    }

    private var helperTint: Color {
        switch phase {
        case .live, .starting: Theme.accent
        case .waiting, .failed: Theme.warn
        case .off, .installing: .secondary
        }
    }

    private func node<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 9) {
            content().frame(width: 48, height: 48)
            Text(label).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(width: 76)
    }

    private func tile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Theme.cardTop, Theme.cardBottom], startPoint: .top, endPoint: .bottom))
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.window))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.lineStrong))
                .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
            content()
        }
        .frame(width: 46, height: 46)
    }
}

/// A line between two parts of the diagram.
private struct Beam: View {
    enum Style {
        /// Not connected yet: a dotted hairline.
        case idle
        /// Connected but not working: a dotted amber line.
        case blocked
        /// Connected.
        case solid
        /// Connected and working: a pulse travels along it.
        case flowing
    }

    let style: Style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: style != .flowing || reduceMotion)) { context in
            Canvas { canvas, size in
                let y = size.height / 2
                var line = Path()
                line.move(to: CGPoint(x: 4, y: y))
                line.addLine(to: CGPoint(x: size.width - 4, y: y))
                let dotted = StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [0.5, 4.5])
                switch style {
                case .idle: canvas.stroke(line, with: .color(Theme.lineStrong), style: dotted)
                case .blocked: canvas.stroke(line, with: .color(Theme.warn.opacity(0.75)), style: dotted)
                case .solid, .flowing: canvas.stroke(line, with: .color(Theme.accent.opacity(0.35)), lineWidth: 1.2)
                }
                guard style == .flowing, !reduceMotion else { return }
                let period = 2.0
                let time = context.date.timeIntervalSinceReferenceDate
                let progress = time.truncatingRemainder(dividingBy: period) / period
                let x = -40 + (size.width + 80) * progress
                let pulse = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [Theme.accent.opacity(0), Theme.accent, Theme.accent.opacity(0)]),
                    startPoint: CGPoint(x: x - 34, y: y), endPoint: CGPoint(x: x + 34, y: y))
                canvas.drawLayer { layer in
                    layer.addFilter(.blur(radius: 3))
                    layer.stroke(line, with: pulse, lineWidth: 3)
                }
                canvas.stroke(line, with: pulse, lineWidth: 1.4)
            }
        }
    }
}

/// Step four's picture: a menu bar with Chargectl's item pressed, as it looks on the Mac.
private struct MenuBarPreview: View {
    let model: AppModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "applelogo").font(.system(size: 13.5))
                Text("Finder").fontWeight(.semibold)
                Text("File")
                Text("Edit")
                Spacer(minLength: 0)
                item
                Image(systemName: "wifi")
                Image(systemName: "switch.2")
                Text(Date.now, format: .dateTime.weekday(.abbreviated).hour().minute()).fixedSize()
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.primary.opacity(0.82))
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(Color.primary.opacity(0.045))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            Spacer(minLength: 0)
        }
        .frame(width: 472, height: 116)
        .background(
            LinearGradient(colors: [Theme.cardTop, Theme.cardBottom], startPoint: .top, endPoint: .bottom), in: shape
        )
        .overlay(DotField(spacing: 12).padding(.top, 30).clipShape(shape))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.line))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 8)
        .accessibilityHidden(true)
    }

    private var item: some View {
        HStack(spacing: 4) {
            Image(nsImage: RingIcon.image(for: model)).renderingMode(.template)
            Text("\(model.battery?.percent ?? 0)%").monospacedDigit()
        }
        .foregroundStyle(.primary)
        .fixedSize()
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .top) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up").font(.system(size: 9.5, weight: .bold))
                Text("Click to open Chargectl")
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Theme.accentSoft, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.3)))
            .fixedSize()
            .offset(y: 38)
        }
    }
}

// MARK: - Parts

private struct Feature: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(height: 18)
            Text(title).font(.system(size: 12.5, weight: .medium))
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
    }
}

/// One line of the helper checklist: a numbered circle that becomes a spinner, then a check.
private struct TaskRow: View {
    enum Phase {
        case waiting
        case current
        case working
        case done
        case failed
    }

    let number: Int
    let title: String
    let detail: String
    let phase: Phase
    var divider = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            indicator
                .frame(width: 18, height: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: phase == .current || phase == .working ? .medium : .regular))
                    .foregroundStyle(phase == .waiting ? .secondary : .primary)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            if divider { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 46) }
        }
        .animation(.smooth(duration: 0.3), value: phase)
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder private var indicator: some View {
        switch phase {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                .frame(width: 18, height: 18)
                .background(Theme.accent, in: Circle())
                .shadow(color: Theme.glow.opacity(0.6), radius: 4)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        case .working:
            ProgressView().controlSize(.mini)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.warn)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Theme.warn.opacity(0.6), lineWidth: 1.5))
        case .current, .waiting:
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(phase == .current ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                .frame(width: 18, height: 18)
                .overlay(
                    Circle().strokeBorder(phase == .current ? Theme.accent : Theme.lineStrong, lineWidth: 1.5))
        }
    }

    private var accessibilityValue: String {
        switch phase {
        case .waiting: "Not yet"
        case .current: "Next"
        case .working: "In progress"
        case .done: "Done"
        case .failed: "Failed"
        }
    }
}

/// Where you are in setup: a dot per step, the current one stretched into a short bar.
private struct StepDots: View {
    let step: WelcomeView.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WelcomeView.Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.track))
                    .frame(width: item == step ? 20 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue + 1) of \(WelcomeView.Step.allCases.count)")
    }
}

/// Back and Skip: text only, with a soft fill on hover.
private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration)
    }

    private struct QuietButton: View {
        let configuration: Configuration
        @State private var isHovered = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(isHovered ? .primary : .secondary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.08 : isHovered ? 0.05 : 0)))
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .onHover { isHovered = $0 }
        }
    }
}
