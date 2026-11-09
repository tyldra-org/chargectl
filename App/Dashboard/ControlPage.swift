import SwiftUI

struct ControlPage: View {
    let model: AppModel
    @AppStorage(PreferenceKey.temperatureUnit) private var unit = TemperatureUnit.systemDefault
    @State private var draftLimit: Int?
    @State private var confirmingOff = false

    var body: some View {
        if let settings = model.settings, model.isControllable {
            ScrollView {
                VStack(spacing: 14) {
                    if !settings.isEnabled { offNotice.settleIn(0) }
                    charging(settings).settleIn(0).dimmed(!settings.isEnabled)
                    SpanRow(spans: [7, 5]) {
                        fullBy(settings).dimmed(!settings.isEnabled).settleIn(1)
                        master(settings).settleIn(2)
                    }
                    SpanRow(spans: [7, 5]) {
                        heat(settings).dimmed(!settings.isEnabled).settleIn(3)
                        magSafe(settings).dimmed(!settings.isEnabled).settleIn(4)
                    }
                    sleep(settings).dimmed(!settings.isEnabled).settleIn(5)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
        } else {
            HelperEmptyState(
                model: model, symbols: ["battery.75percent", "gauge.with.dots.needle.50percent", "checkmark.shield"],
                title: "Install the helper to set a charge limit",
                message:
                    "It runs in the background and keeps the limit while Chargectl is closed. macOS asks for your password once."
            )
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .settleIn(0)
        }
    }

    // MARK: Charging

    private func charging(_ settings: ChargeSettings) -> some View {
        let limit = draftLimit ?? settings.limit
        let lower = max(limit - settings.sailing, ChargeSettings.limitRange.lowerBound)
        return Panel(padding: 24, spotlight: true) {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "Charging", symbol: "gauge.with.dots.needle.50percent") {
                    Label("Applied", systemImage: "checkmark.circle").foregroundStyle(.tertiary)
                        .labelStyle(TightLabelStyle(tint: Theme.accent))
                }
                HStack(alignment: .center, spacing: 18) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(limit)")
                            .font(.system(size: 64, weight: .ultraLight))
                            .monospacedDigit()
                            .tracking(-2)
                            .contentTransition(.numericText(value: Double(limit)))
                            // Follows the slider exactly while it moves; rolls only for other changes.
                            .animation(
                                draftLimit == nil ? .spring(response: 0.35, dampingFraction: 0.85) : nil, value: limit)
                        Text("%").font(.system(size: 20, weight: .light)).foregroundStyle(.tertiary).baselineOffset(24)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Charge limit").font(.system(size: 15, weight: .semibold))
                        Text("Charging stops here.").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let percent = model.battery?.percent {
                        HStack(spacing: 6) {
                            Circle().strokeBorder(Color.primary, lineWidth: 1.5).frame(width: 9, height: 9)
                            Text("Charge now").foregroundStyle(.secondary)
                            Text("\(percent)%").fontWeight(.semibold).monospacedDigit()
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .overlay(Capsule().strokeBorder(Theme.lineStrong))
                    }
                }
                .padding(.top, 14)
                LimitSlider(
                    limit: limit, saved: settings.limit, lowerBound: settings.sailing > 0 ? lower : nil,
                    now: model.battery?.percent,
                    draft: $draftLimit
                ) { value in
                    model.update { $0.limit = value }
                    Confirmations.shared.show("Limit set to \(value)%")
                }
                .padding(.top, 16)
                VStack(spacing: 0) {
                    SettingRow(
                        title: "Sailing range",
                        detail: settings.sailing > 0
                            ? Text(
                                "Tops up again only below \(Text("\(lower)%").foregroundStyle(.primary)), so the battery isn’t charged in short bursts."
                            )
                            : Text("Tops up the moment the charge drops below the limit."), divider: false
                    ) {
                        CapsuleStepper(
                            value: "\(settings.sailing)%",
                            canDecrement: settings.sailing > ChargeSettings.sailingRange.lowerBound,
                            canIncrement: settings.sailing < ChargeSettings.sailingRange.upperBound,
                            accessibilityLabel: "Sailing range",
                            decrement: { changeSailing(-1) }, increment: { changeSailing(1) })
                    }
                    SettingRow(
                        title: "Discharge to the limit when plugged in",
                        detail: settings.autoDischarge
                            ? Text(
                                "On: above \(Text("\(limit)%").foregroundStyle(.primary)) on the charger, the battery runs down to the limit."
                            )
                            : Text(
                                "Off: above \(Text("\(limit)%").foregroundStyle(.primary)) on the charger, the battery stays where it is."
                            )
                    ) {
                        switchFor(\.autoDischarge, on: "Discharge to limit on", off: "Discharge to limit off")
                    }
                }
                .padding(.top, 6)
                RuleSentence(settings: settings, limit: limit, unit: unit)
                    .padding(.top, 10)
            }
        }
    }

    private func changeSailing(_ delta: Int) {
        guard let settings = model.settings else { return }
        let sailing = min(
            max(settings.sailing + delta, ChargeSettings.sailingRange.lowerBound),
            ChargeSettings.sailingRange.upperBound)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { model.update { $0.sailing = sailing } }
        let lower = max(settings.limit - sailing, ChargeSettings.limitRange.lowerBound)
        Confirmations.shared.show(sailing == 0 ? "Sailing off" : "Sailing \(lower)–\(settings.limit)%")
    }

    // MARK: Heat, MagSafe, sleep

    private func heat(_ settings: ChargeSettings) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "Heat", symbol: "thermometer.medium")
                SettingRow(
                    title: "Pause charging when warm",
                    detail: Text("Charging resumes once the battery cools by \(unit == .celsius ? "2 °C" : "4 °F")."),
                    divider: false
                ) {
                    switchFor(\.heatProtection, on: "Heat guard on", off: "Heat guard off")
                }
                .padding(.top, 6)
                if settings.heatProtection {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Pause above").font(.system(size: 13, weight: .medium))
                            Spacer()
                            CapsuleStepper(
                                value: unit.format(settings.heatThreshold, decimals: 0),
                                canDecrement: settings.heatThreshold > ChargeSettings.heatThresholdRange.lowerBound,
                                canIncrement: settings.heatThreshold < ChargeSettings.heatThresholdRange.upperBound,
                                accessibilityLabel: "Pause charging above",
                                decrement: { changeHeat(-1) }, increment: { changeHeat(1) })
                        }
                        TemperatureStrip(
                            now: model.battery?.temperature, threshold: settings.heatThreshold, unit: unit)
                    }
                    .padding(.top, 12)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: settings.heatProtection)
        }
    }

    private func changeHeat(_ delta: Double) {
        guard let settings = model.settings else { return }
        let range = ChargeSettings.heatThresholdRange
        let value = min(max(settings.heatThreshold + delta, range.lowerBound), range.upperBound)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { model.update { $0.heatThreshold = value } }
        Confirmations.shared.show("Pause above \(unit.format(value, decimals: 0))")
    }

    private func magSafe(_ settings: ChargeSettings) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                PanelHeader(title: "MagSafe light", symbol: "bolt")
                HStack {
                    MagSafePlug(
                        isOff: settings.magSafeLED == .off,
                        color: (model.battery?.isCharging ?? false)
                            ? Color(red: 1, green: 0.62, blue: 0.04)
                            : Color(red: 0.2, green: 0.84, blue: 0.29)
                    )
                    .frame(width: 132, height: 40)
                    Spacer()
                    SlidingSegments(
                        options: [(MagSafeLEDMode.system, "Automatic"), (.off, "Off")],
                        selection: Binding(
                            get: { model.settings?.magSafeLED ?? .system },
                            set: { mode in
                                model.update { $0.magSafeLED = mode }
                                Confirmations.shared.show(
                                    mode == .off ? "MagSafe light off" : "MagSafe light automatic")
                            }))
                }
                Text(
                    settings.magSafeLED == .off
                        ? "Off keeps the light dark, including while charging."
                        : "Automatic lets the light show charging as usual: amber while charging, green when held."
                )
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sleep(_ settings: ChargeSettings) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "Sleep", symbol: "moon")
                SettingRow(
                    title: "Keep discharging while asleep",
                    detail: Text(
                        "Before the Mac sleeps, Chargectl reconnects wall power if it had cut it to discharge. Turn this on to keep discharging while asleep. macOS holds the limit itself during sleep; where it can’t hold yours, wall power stays cut while asleep so the battery only drifts down a little."
                    ), divider: false
                ) {
                    switchFor(\.holdAsleep, on: "Discharge while asleep on", off: "Discharge while asleep off")
                }
                .padding(.top, 6)
            }
        }
    }

    // MARK: Full by

    private func fullBy(_ settings: ChargeSettings) -> some View {
        let schedule = settings.fullBy
        return Panel {
            VStack(alignment: .leading, spacing: 0) {
                PanelHeader(title: "Full by", symbol: "clock") {
                    if case .fullBy(let deadline) = model.status?.mode {
                        Label(
                            "Charging for \(deadline.formatted(date: .omitted, time: .shortened))",
                            systemImage: "bolt.fill"
                        )
                        .labelStyle(TightLabelStyle(tint: Theme.accent))
                    }
                }
                SettingRow(
                    title: "Charge to 100% by a set time",
                    detail: Text(
                        "Starts just long enough before, so the battery isn’t kept full for hours, then goes back to \(Text("\(settings.limit)%").foregroundStyle(.primary))."
                    ), divider: false
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { schedule != nil },
                            set: { on in
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                    model.update {
                                        $0.fullBy =
                                            on
                                            ? FullBySchedule(hour: 8, minute: 0, weekdays: FullBySchedule.weekdaysOnly)
                                            : nil
                                    }
                                }
                                Confirmations.shared.show(on ? "Full by weekdays at 8:00" : "Full by off")
                            })
                    )
                    .toggleStyle(GlowSwitchStyle())
                    .labelsHidden()
                    .accessibilityLabel("Full by")
                }
                .padding(.top, 6)
                if let schedule {
                    FullByEditor(schedule: schedule, percent: model.battery?.percent ?? settings.limit) { changed in
                        model.update { $0.fullBy = changed }
                        Confirmations.shared.show("Full by \(changed.summary)")
                    }
                    .padding(.top, 12)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: schedule != nil)
        }
    }

    // MARK: Master switch

    private func master(_ settings: ChargeSettings) -> some View {
        Panel(tint: settings.isEnabled ? nil : Theme.warn) {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeader(title: "Charge control", symbol: "shield")
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.isEnabled ? "On" : "Off").font(.system(size: 15, weight: .semibold))
                        Text(
                            settings.isEnabled
                                ? "Chargectl manages charging with the rules on this page."
                                : "macOS manages charging and charges to 100%."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { model.settings?.isEnabled ?? true },
                            set: { enabled in
                                if enabled {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        model.update { $0.isEnabled = true }
                                    }
                                    Confirmations.shared.show("Charge control on")
                                } else {
                                    confirmingOff = true
                                }
                            })
                    )
                    .toggleStyle(GlowSwitchStyle())
                    .accessibilityLabel("Charge control")
                    .popover(isPresented: $confirmingOff, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hand charging back to macOS?").font(.system(size: 13, weight: .semibold))
                            Text("macOS will charge to 100%. Your settings stay saved for when you turn it back on.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Spacer()
                                Button("Cancel") { confirmingOff = false }
                                    .buttonStyle(SoftButtonStyle(small: true))
                                    .keyboardShortcut(.cancelAction)
                                Button("Turn Off") {
                                    confirmingOff = false
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        model.update { $0.isEnabled = false }
                                    }
                                    Confirmations.shared.show("Charge control off")
                                }
                                .buttonStyle(SoftButtonStyle(kind: .danger, small: true))
                            }
                            .padding(.top, 8)
                        }
                        .padding(14)
                        .frame(width: 290)
                    }
                }
            }
        }
    }

    private var offNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warn)
            Text(
                "\(Text("Charge control is off.").fontWeight(.semibold)) macOS charges to 100% and the settings below are paused."
            )
            .font(.system(size: 12.5))
            Spacer()
            Button("Turn On") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { model.update { $0.isEnabled = true } }
                Confirmations.shared.show("Charge control on")
            }
            .buttonStyle(SoftButtonStyle(small: true))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.warn.opacity(0.25)))
    }

    private func switchFor(_ keyPath: WritableKeyPath<ChargeSettings, Bool>, on: String, off: String) -> some View {
        Toggle(
            "",
            isOn: Binding(
                get: { (model.settings ?? ChargeSettings())[keyPath: keyPath] },
                set: { value in
                    // One transaction, so cards that grow (heat guard) move their neighbours smoothly.
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        model.update { $0[keyPath: keyPath] = value }
                    }
                    Confirmations.shared.show(value ? on : off)
                })
        )
        .toggleStyle(GlowSwitchStyle())
        .labelsHidden()
    }
}

// MARK: - Parts

private struct TightLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

extension View {
    /// Settings that are paused while charge control is off.
    func dimmed(_ isDimmed: Bool) -> some View {
        opacity(isDimmed ? 0.42 : 1)
            .saturation(isDimmed ? 0.3 : 1)
            .allowsHitTesting(!isDimmed)
            .animation(.easeOut(duration: 0.3), value: isDimmed)
    }
}

/// A setting as a row: what it does in bold, what that means underneath, the control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: Text?
    var indented = false
    /// Off for the first row under a card's caption.
    var divider = true
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                if let detail {
                    detail
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.vertical, 13)
        .padding(.leading, indented ? 16 : 0)
        .overlay(alignment: .top) { if divider { Rectangle().fill(Theme.line).frame(height: 1) } }
        .overlay(alignment: .topLeading) {
            if indented {
                Elbow().stroke(Theme.lineStrong, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 10, height: 21)
                    .offset(x: 2, y: 1)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The time and days of a Full by schedule, and when charging will start.
private struct FullByEditor: View {
    let schedule: FullBySchedule
    let percent: Int
    let change: (FullBySchedule) -> Void

    private enum Repeat: Hashable {
        case once
        case weekdays
        case everyDay
        case custom
    }

    private var repeating: Repeat {
        if schedule.once != nil { return .once }
        if schedule.weekdays == FullBySchedule.weekdaysOnly { return .weekdays }
        if schedule.weekdays == FullBySchedule.everyDay { return .everyDay }
        return .custom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Full by").font(.system(size: 13, weight: .medium))
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.stepperField)
                    .fixedSize()
                Spacer(minLength: 8)
                SlidingSegments(
                    options: [
                        (Repeat.once, "Once"), (.weekdays, "Weekdays"), (.everyDay, "Every day"), (.custom, "Days"),
                    ],
                    selection: Binding(get: { repeating }, set: setRepeat), compact: true)
            }
            if repeating == .custom {
                HStack(spacing: 6) {
                    ForEach(Array(zip(1...7, Calendar.current.veryShortWeekdaySymbols)), id: \.0) { day, symbol in
                        let on = schedule.weekdays.contains(day)
                        Button(symbol) {
                            var changed = schedule
                            if on, changed.weekdays.count > 1 {
                                changed.weekdays.remove(day)
                            } else {
                                changed.weekdays.insert(day)
                            }
                            change(changed)
                        }
                        .buttonStyle(DayChipStyle(isOn: on))
                        .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            if let next = schedule.nextDeadline(after: .now) {
                let start = next.addingTimeInterval(-FullBySchedule.leadTime(from: percent))
                Text(
                    "Next \(Text(next.formatted(.dateTime.weekday(.wide).hour().minute())).foregroundStyle(.secondary)). Charging starts around \(Text(start.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary)) from today’s \(percent)%."
                )
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: .now)
                    ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                var changed = schedule
                changed.hour = parts.hour ?? schedule.hour
                changed.minute = parts.minute ?? schedule.minute
                if changed.once != nil {
                    changed = FullBySchedule.once(hour: changed.hour, minute: changed.minute, after: .now) ?? changed
                }
                change(changed)
            })
    }

    private func setRepeat(_ value: Repeat) {
        var changed = schedule
        switch value {
        case .once:
            changed = FullBySchedule.once(hour: schedule.hour, minute: schedule.minute, after: .now) ?? schedule
        case .weekdays:
            changed.once = nil
            changed.weekdays = FullBySchedule.weekdaysOnly
        case .everyDay:
            changed.once = nil
            changed.weekdays = FullBySchedule.everyDay
        case .custom:
            changed.once = nil
            if changed.weekdays.isEmpty || changed.weekdays == FullBySchedule.everyDay
                || changed.weekdays == FullBySchedule.weekdaysOnly
            {
                changed.weekdays = changed.weekdays.isEmpty ? FullBySchedule.weekdaysOnly : changed.weekdays
            }
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { change(changed) }
    }
}

/// A round day letter that fills green when chosen.
private struct DayChipStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
            .foregroundStyle(isOn ? Theme.accent : .secondary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(isOn ? Theme.accentSoft : Color.primary.opacity(0.05)))
            .overlay(Circle().strokeBorder(isOn ? Theme.accent.opacity(0.45) : Theme.lineStrong))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// A short line down and to the right: this setting belongs to the one above it.
nonisolated struct Elbow: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 6))
            path.addQuadCurve(to: CGPoint(x: rect.minX + 6, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    }
}

/// The limit slider: a ruler from 20 to 100%, the sailing range hatched under the limit, today's
/// charge as a small marker, and a thumb with a value bubble while dragging. Arrow keys move 1%,
/// Shift 5%. Also used by setup.
struct LimitSlider: View {
    let limit: Int
    let saved: Int
    let lowerBound: Int?
    let now: Int?
    @Binding var draft: Int?
    let commit: (Int) -> Void
    @FocusState private var focused: Bool
    @State private var pendingCommit: Task<Void, Never>?
    @State private var dragging = false

    private let range = ChargeSettings.limitRange
    /// Follows the pointer exactly while dragging; glides for keyboard and outside changes.
    private var motion: Animation? { dragging ? nil : .spring(response: 0.3, dampingFraction: 0.85) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = { (value: Int) in width * CGFloat(value - range.lowerBound) / CGFloat(range.count - 1) }
            ZStack(alignment: .topLeading) {
                GlowDots(fraction: Double(x(limit) / max(width, 1)), color: Theme.accent)
                    .frame(height: 28)
                Capsule().fill(Theme.track).frame(height: 12).offset(y: 38)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.75), Theme.accent], startPoint: .leading,
                            endPoint: .trailing)
                    )
                    .frame(width: x(limit), height: 12)
                    .shadow(color: Theme.glow.opacity(0.5), radius: 6)
                    .offset(y: 38)
                    .animation(motion, value: limit)
                if let lowerBound, lowerBound < limit {
                    Hatch(color: Color.white)
                        .opacity(0.6)
                        .frame(width: x(limit) - x(lowerBound), height: 12)
                        .offset(x: x(lowerBound), y: 38)
                        .animation(motion, value: limit)
                        .animation(motion, value: lowerBound)
                }
                if let now, range.contains(now) {
                    Circle()
                        .fill(Theme.window)
                        .overlay(Circle().strokeBorder(Color.primary, lineWidth: 2))
                        .frame(width: 10, height: 10)
                        .offset(x: x(now) - 5, y: 39)
                        .help("Charge now \(now)%")
                }
                Circle()
                    .fill(.white)
                    .frame(width: 26, height: 26)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .background(
                        Circle().fill(Theme.accent.opacity(draft != nil ? 0.35 : focused ? 0.26 : 0.18))
                            .frame(width: draft != nil ? 44 : 36, height: draft != nil ? 44 : 36)
                    )
                    .overlay(alignment: .top) {
                        // Always present and faded, never inserted or removed: a removal transition
                        // left an empty grey capsule behind for a few frames.
                        Text("\(limit)%")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.window)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.primary, in: Capsule())
                            .fixedSize()
                            .offset(y: draft != nil ? -30 : -24)
                            .opacity(draft != nil ? 1 : 0)
                            .animation(.easeOut(duration: 0.18), value: draft != nil)
                            .allowsHitTesting(false)
                    }
                    .offset(x: x(limit) - 13, y: 31)
                    .animation(motion, value: limit)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: draft != nil)
                Ruler(from: range.lowerBound, labels: [20, 40, 60, 80, 100])
                    .frame(height: 22)
                    .offset(y: 62)
            }
            // Offset children draw outside the stack's own size; hit-test the whole area.
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let fraction = min(max(drag.location.x / max(width, 1), 0), 1)
                        dragging = true
                        draft = range.lowerBound + Int((fraction * CGFloat(range.count - 1)).rounded())
                        focused = true
                    }
                    .onEnded { _ in
                        if let draft, draft != saved { commit(draft) }
                        self.draft = nil
                        dragging = false
                    })
        }
        .frame(height: 88)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let step = press.modifiers.contains(.shift) ? 5 : 1
            let up = press.key == .rightArrow || press.key == .upArrow
            let value = min(max((draft ?? limit) + (up ? step : -step), range.lowerBound), range.upperBound)
            draft = value
            pendingCommit?.cancel()
            pendingCommit = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                commit(value)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { draft = nil }
            }
            return .handled
        }
        .accessibilityElement()
        .accessibilityLabel("Charge limit")
        .accessibilityValue("\(limit) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: commit(min(limit + 1, range.upperBound))
            case .decrement: commit(max(limit - 1, range.lowerBound))
            @unknown default: break
            }
        }
    }
}

/// The charging rules as one sentence, numbers highlighted.
private struct RuleSentence: View {
    let settings: ChargeSettings
    let limit: Int
    let unit: TemperatureUnit

    var body: some View {
        let lower = max(limit - settings.sailing, ChargeSettings.limitRange.lowerBound)
        Text(sentence(lower: lower))
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
            // The words change in place: a rolling-digits transition on a whole paragraph blurs
            // and scrambles every letter while the limit is dragged.
            .transaction { $0.animation = nil }
    }

    private func sentence(lower: Int) -> AttributedString {
        if limit >= 100 { return plain("The battery charges ") + mark("fully") + plain(".") }
        var text = plain("Charging stops at ") + mark("\(limit)%") + plain(" and the Mac keeps running on the charger.")
        if settings.sailing > 0 {
            text +=
                plain(" If the charge drifts down, it is not topped up until it reaches ") + mark("\(lower)%")
                + plain(".")
        }
        text +=
            settings.autoDischarge
            ? plain(" Plugged in above the limit, the battery discharges down to ") + mark("\(limit)%") + plain(".")
            : plain(" Plugged in above the limit, the Mac runs on the charger and the battery stays where it is.")
        if settings.heatProtection {
            text +=
                plain(" Charging pauses above ") + mark(unit.format(settings.heatThreshold, decimals: 0)) + plain(".")
        }
        return text
    }

    private func plain(_ text: String) -> AttributedString { AttributedString(text) }

    private func mark(_ text: String) -> AttributedString {
        var value = AttributedString(" \(text) ")
        value.foregroundColor = Theme.accent
        value.backgroundColor = Theme.accentSoft
        value.font = .system(size: 12.5, weight: .semibold)
        return value
    }
}

/// Cool blue to hot red with today's temperature and the cut-off marked.
private struct TemperatureStrip: View {
    let now: Double?
    let threshold: Double
    let unit: TemperatureUnit
    private let range = 20.0...50.0

    var body: some View {
        GeometryReader { geometry in
            let x = { (celsius: Double) in
                geometry.size.width * (min(max(celsius, range.lowerBound), range.upperBound) - range.lowerBound)
                    / (range.upperBound - range.lowerBound)
            }
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.25, green: 0.6, blue: 1), Color(red: 0.2, green: 0.84, blue: 0.29),
                                Color(red: 1, green: 0.8, blue: 0.2), Color(red: 1, green: 0.27, blue: 0.23),
                            ], startPoint: .leading, endPoint: .trailing)
                    )
                    .opacity(0.75)
                    .frame(height: 6)
                    .offset(y: 4)
                Capsule().fill(Color.primary).frame(width: 2, height: 14).offset(x: x(threshold) - 1)
                Text(unit.format(threshold, decimals: 0))
                    .font(.system(size: 10.5, weight: .medium))
                    .fixedSize()
                    .position(x: x(threshold), y: 26)
                if let now {
                    Circle()
                        .fill(Theme.window)
                        .overlay(Circle().strokeBorder(Color.primary, lineWidth: 2))
                        .frame(width: 10, height: 10)
                        .offset(x: x(now) - 5, y: 2)
                    Text("Now \(unit.format(now))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .position(x: x(now), y: 26)
                }
            }
        }
        .frame(height: 34)
        .accessibilityElement()
        .accessibilityLabel(
            "Battery temperature \(unit.format(now)), charging pauses above \(unit.format(threshold, decimals: 0))")
    }
}

/// A MagSafe connector in the side of a Mac, its light showing the chosen mode.
private struct MagSafePlug: View {
    let isOff: Bool
    let color: Color

    var body: some View {
        Canvas { context, size in
            let sy = size.height / 40
            let sx = size.width / 132
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy)
            }
            let fg = Color.primary
            context.fill(Path(roundedRect: rect(0.5, 3, 13, 34), cornerRadius: 3), with: .color(fg.opacity(0.05)))
            context.stroke(Path(roundedRect: rect(0.5, 3, 13, 34), cornerRadius: 3), with: .color(Theme.lineStrong))
            context.fill(Path(roundedRect: rect(11, 14.5, 2.5, 11), cornerRadius: 1.25), with: .color(fg.opacity(0.16)))
            var cable = Path()
            cable.move(to: CGPoint(x: 60 * sx, y: 20 * sy))
            cable.addCurve(
                to: CGPoint(x: 130 * sx, y: 25 * sy), control1: CGPoint(x: 82 * sx, y: 20 * sy),
                control2: CGPoint(x: 94 * sx, y: 27 * sy))
            context.stroke(cable, with: .color(fg.opacity(0.24)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            context.stroke(cable, with: .color(fg.opacity(0.07)), style: StrokeStyle(lineWidth: 4.5, dash: [1, 2.5]))
            var relief = Path()
            relief.move(to: CGPoint(x: 52 * sx, y: 15.5 * sy))
            relief.addLine(to: CGPoint(x: 61 * sx, y: 17.6 * sy))
            relief.addLine(to: CGPoint(x: 61 * sx, y: 22.4 * sy))
            relief.addLine(to: CGPoint(x: 52 * sx, y: 24.5 * sy))
            relief.closeSubpath()
            context.fill(relief, with: .color(fg.opacity(0.12)))
            let head = Path(roundedRect: rect(13.5, 13, 40, 14), cornerRadius: 4.5)
            context.fill(head, with: .color(fg.opacity(0.13)))
            context.stroke(head, with: .color(fg.opacity(0.2)))
            var sheen = Path()
            sheen.move(to: CGPoint(x: 18 * sx, y: 14.2 * sy))
            sheen.addLine(to: CGPoint(x: 49 * sx, y: 14.2 * sy))
            context.stroke(sheen, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            if !isOff {
                var glow = context
                glow.addFilter(.blur(radius: 3.5))
                glow.fill(Path(ellipseIn: rect(16.5, 13.5, 13, 13)), with: .color(color.opacity(0.45)))
            }
            context.fill(Path(ellipseIn: rect(21, 18, 4, 4)), with: .color(isOff ? fg.opacity(0.2) : color))
        }
        .animation(.easeOut(duration: 0.4), value: isOff)
        .accessibilityHidden(true)
    }
}
