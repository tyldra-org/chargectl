import Charts
import SwiftUI

struct OverviewPage: View {
    let model: AppModel
    @AppStorage(PreferenceKey.temperatureUnit) private var unit = TemperatureUnit.systemDefault
    @State private var confirmingCalibration = false
    @State private var energy = EnergyMonitor()
    @State private var chartHours = 6

    var body: some View {
        if let battery = model.battery {
            ScrollView {
                VStack(spacing: 14) {
                    hero(battery).settleIn(0)
                    SpanRow(spans: [7, 5]) {
                        powerFlow(battery).settleIn(1)
                        health(battery).settleIn(2)
                    }
                    SpanRow(spans: [7, 5]) {
                        recentCharge.settleIn(3)
                        recentActivity.settleIn(4)
                    }
                    SpanRow(spans: [7, 5]) {
                        energyUse.settleIn(5)
                        charger(battery).settleIn(6)
                    }
                    controlStrip.settleIn(7)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
            .task {
                while !Task.isCancelled {
                    await model.loadHistory()
                    await model.loadLogs()
                    try? await Task.sleep(for: .seconds(15))
                }
            }
            .task { await energy.run() }
        } else {
            StackedEmptyState(
                symbols: ["bolt", "thermometer.medium", "battery.0percent"], title: "Reading the battery",
                message: model.batteryError ?? "Chargectl reads the battery once a second. This takes a moment."
            ) { EmptyView() }
            .padding(24)
        }
    }

    // MARK: Hero

    private func hero(_ battery: BatterySnapshot) -> some View {
        Panel(padding: 24, spotlight: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 22) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(battery.percent)")
                            .font(.system(size: 76, weight: .ultraLight, design: .default))
                            .monospacedDigit()
                            .rollingNumber(battery.percent)
                            .tracking(-2)
                        Text("%")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.tertiary)
                            .baselineOffset(30)
                    }
                    .accessibilityElement(children: .combine)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            PulseDot(color: model.isDraining ? Theme.warn : Theme.accent)
                            Text(model.activitySummary.capitalizedFirst)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(model.isDraining ? Theme.warn : .primary)
                        }
                        Text(subtitle(battery))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 16)
                    actions
                }
                HeroMeter(
                    percent: battery.percent, limit: model.settings?.limit, lowerBound: model.settings?.lowerBound,
                    isDraining: model.isDraining,
                    onSetLimit: model.isControllable
                        ? { limit in
                            model.update { $0.limit = limit }
                            Confirmations.shared.show("Limit set to \(limit)%")
                        } : nil
                )
                .padding(.top, 26)
            }
        }
    }

    private func subtitle(_ battery: BatterySnapshot) -> String {
        var parts: [String] = []
        if let estimate = model.estimate, let minutes = estimate.minutes {
            parts.append("\(TimeText.minutes(minutes)) \(estimate.caption)")
        }
        if battery.isPluggedIn { parts.append(battery.adapterName ?? "Charger connected") }
        parts.append(unit.format(battery.temperature))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var actions: some View {
        let mode = model.status?.mode ?? .automatic
        let limit = model.settings?.limit ?? 80
        Group {
            if mode == .automatic {
                HStack(spacing: 8) {
                    Button {
                        model.perform(.discharge)
                        Confirmations.shared.show("Discharging to \(limit)%")
                    } label: {
                        Label("Discharge", systemImage: "arrow.down.to.line")
                    }
                    .disabled((model.battery?.percent ?? 0) <= limit)
                    .help(
                        (model.battery?.percent ?? 0) <= limit
                            ? "The battery is already at or below \(limit)%" : "Run on battery down to \(limit)%")
                    Button {
                        model.perform(.topUp)
                        Confirmations.shared.show("Topping up to 100%")
                    } label: {
                        Label("Top Up", systemImage: "arrow.up.to.line")
                    }
                    .help("Charge to 100% once, then return to the limit")
                    Button {
                        confirmingCalibration = true
                    } label: {
                        Label("Calibrate", systemImage: "arrow.clockwise")
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(mode.title.capitalizedFirst).font(.system(size: 12.5)).foregroundStyle(.secondary)
                    Button("Stop") { model.perform(.stop) }
                }
            }
        }
        .buttonStyle(SoftButtonStyle())
        .disabled(!model.isControllable)
        .animation(.easeInOut(duration: 0.25), value: model.status?.mode)
        .confirmationDialog("Calibrate the battery?", isPresented: $confirmingCalibration) {
            Button("Calibrate") { model.perform(.calibrate) }
        } message: {
            Text(
                "Chargectl runs the battery down to \(ChargePolicy.calibrationFloor)%, charges it to 100%, rests for an hour, then returns to your limit. Keep the charger connected. This takes several hours."
            )
        }
    }

    // MARK: Power

    private func powerFlow(_ battery: BatterySnapshot) -> some View {
        let batteryPower = battery.batteryPower
        let mac = battery.systemPower ?? 0
        let wall = battery.wallPower ?? 0
        let charging = batteryPower > 0.05
        let draining = batteryPower < -0.05
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                PanelHeader(title: "Power", symbol: "bolt") { Text(flowSentence(battery)) }
                PowerFlow(
                    charger: wall, mac: mac, battery: batteryPower, pluggedIn: battery.isPluggedIn,
                    wallCut: model.status?.adapterEnabled == false
                )
                .frame(height: 132)
                let total = max(mac + max(batteryPower, 0), 0.1)
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        Capsule().fill(Theme.mac).frame(width: geometry.size.width * mac / total)
                        if charging || draining {
                            Capsule().fill(charging ? Theme.accent : Theme.warn)
                        }
                    }
                }
                .frame(height: 6)
                .background(Theme.track, in: Capsule())
                .animation(.easeOut(duration: 0.6), value: mac)
                HStack(spacing: 16) {
                    legend(Theme.mac, "Mac \(Int((mac / total * 100).rounded()))%")
                    if charging {
                        legend(Theme.accent, "Battery \(Int((batteryPower / total * 100).rounded()))%")
                    } else if draining {
                        legend(Theme.warn, "From battery \(Format.watts(-batteryPower))")
                    }
                    if battery.isPluggedIn, wall > mac + max(batteryPower, 0) {
                        legend(Theme.track, "Conversion \(Format.watts(wall - mac - max(batteryPower, 0)))")
                    }
                }
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func flowSentence(_ battery: BatterySnapshot) -> String {
        let watts = battery.batteryPower
        if model.status?.adapterEnabled == false { return "Wall power cut; the battery runs the Mac" }
        if !battery.isPluggedIn { return "The battery runs the Mac" }
        if watts > 0.05 { return "The charger runs the Mac and charges the battery" }
        if watts < -0.05 { return "The battery helps run the Mac" }
        return "The charger runs the Mac; the battery is resting"
    }

    // MARK: Health

    private func health(_ battery: BatterySnapshot) -> some View {
        let healthValue = battery.health ?? 0
        let warm = (battery.temperature ?? 0) >= 35
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                PanelHeader(title: "Battery health", symbol: "heart.text.square") {
                    Text(healthValue >= 0.8 ? "Normal" : "Below 80%")
                }
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 18) {
                    GridRow {
                        HealthCell(title: "Health", value: String(format: "%.1f", healthValue * 100), unit: "%") {
                            MiniBar(fraction: healthValue, color: Theme.accent)
                        }
                        HealthCell(
                            title: "Cycles", value: "\(battery.cycleCount)",
                            unit: battery.designCycleCount.map { "of \($0.formatted())" } ?? ""
                        ) {
                            MiniBar(
                                fraction: Double(battery.cycleCount) / Double(battery.designCycleCount ?? 1000),
                                color: Color.secondary)
                        }
                    }
                    GridRow {
                        HealthCell(
                            title: "Temperature",
                            value: battery.temperature.map { String(format: "%.1f", unit.value($0)) } ?? "–",
                            unit: unit.symbol
                        ) {
                            HStack(spacing: 6) {
                                Circle().fill(warm ? Theme.warn : Theme.accent).frame(width: 6, height: 6)
                                Text(warm ? "Warm" : "Normal").font(.system(size: 11.5)).foregroundStyle(.secondary)
                            }
                        }
                        HealthCell(
                            title: "Capacity", value: battery.fullChargeCapacity.formatted(), unit: "mAh"
                        ) {
                            Text(
                                String(
                                    format: "%.2f V · %@", battery.voltage,
                                    abs(battery.current) < 0.005 ? "0 A" : String(format: "%+.2f A", battery.current))
                            )
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // MARK: Recent charge

    private var recentCharge: some View {
        let start = Date.now.addingTimeInterval(-Double(chartHours) * 60 * 60)
        let samples = model.history.filter { $0.date >= start }
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                PanelHeader(title: "Charge, last \(chartHours) hours", symbol: "clock") {
                    SlidingSegments(
                        options: [(1, "1H"), (6, "6H"), (24, "24H")], selection: $chartHours, compact: true)
                }
                if samples.count < 2 {
                    Text("Collecting. A point is recorded every minute.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    ChargeChart(
                        samples: samples, domain: start...Date.now, limit: model.settings?.limit,
                        lowerBound: model.settings?.lowerBound, height: 150)
                    HStack(spacing: 0) {
                        let onCharger = samples.filter { ($0.wallPower ?? 0) > 0.5 }.count
                        let lowest = samples.map(\.percent).min() ?? 0
                        let change = (samples.last?.percent ?? 0) - (samples.first?.percent ?? 0)
                        stat("On charger", TimeText.minutes(onCharger))
                        stat("Lowest", "\(lowest)%")
                        stat(change >= 0 ? "Charged" : "Used", "\(change >= 0 ? "+" : "−")\(abs(change))%")
                    }
                    .padding(.top, 12)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Activity

    private var recentActivity: some View {
        let entries = Array(model.logs.reversed().prefix(5))
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(title: "Activity", symbol: "waveform.path.ecg") {
                    Button {
                        NSWorkspace.shared.open(URL(string: "chargectl://dashboard/logs")!)
                    } label: {
                        HStack(spacing: 3) {
                            Text("View in Logs")
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                }
                if entries.isEmpty {
                    Text("Nothing logged yet.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            ActivityRow(entry: entry, isFirst: index == 0, isLast: index == entries.count - 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: Energy and charger

    private var energyUse: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(title: "Using significant energy", symbol: "flame") { Text("Last minute") }
                if energy.apps.isEmpty {
                    Text(energy.isMeasuring ? "Measuring…" : "No apps are using significant energy.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    let top = energy.apps.first?.watts ?? 1
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(energy.apps) { app in
                            HStack(spacing: 10) {
                                Image(nsImage: energy.icon(for: app)).resizable().frame(width: 18, height: 18)
                                Text(app.name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
                                Spacer(minLength: 8)
                                MiniBar(fraction: app.watts / top, color: Theme.warn).frame(width: 60)
                                Text(Format.watts(app.watts))
                                    .font(.system(size: 12.5))
                                    .monospacedDigit()
                                    .rollingNumber(app.watts)
                                    .frame(minWidth: 48, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    private func charger(_ battery: BatterySnapshot) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(title: "Charger", symbol: "powerplug") {
                    if let status = model.status, !status.adapterEnabled {
                        Text("Cut by Chargectl").foregroundStyle(Theme.warn)
                    }
                }
                if battery.isPluggedIn {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                        InfoRow(title: "Adapter", value: battery.adapterWatts.map { "\($0) W" } ?? "–")
                        InfoRow(
                            title: "Input", value: battery.chargerVoltage.map { String(format: "%.1f V", $0) } ?? "–")
                        InfoRow(
                            title: "Current", value: battery.chargerCurrent.map { String(format: "%.2f A", $0) } ?? "–")
                        InfoRow(
                            title: "Wall power",
                            value: model.status.map { $0.adapterEnabled ? "Connected" : "Cut" } ?? "–",
                            tint: model.status?.adapterEnabled == false ? Theme.warn : nil)
                    }
                    .font(.system(size: 12.5))
                } else {
                    Text("Not connected").font(.system(size: 12.5)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 90)
                }
            }
        }
    }

    // MARK: Control strip

    private var controlStrip: some View {
        Panel(padding: 14) {
            HStack(spacing: 0) {
                let settings = model.settings
                let mode = model.status?.mode ?? .automatic
                Label(
                    settings == nil ? "Read only" : settings?.isEnabled == false ? "Off" : mode.title.capitalizedFirst,
                    systemImage: settings?.isEnabled == false || settings == nil ? "pause.circle" : "checkmark.circle"
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(settings?.isEnabled == false || settings == nil ? Theme.warn : Theme.accent)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(settings == nil ? Theme.warnSoft : Theme.accentSoft, in: Capsule())
                .padding(.trailing, 16)
                if let settings {
                    kv("Limit", "\(settings.limit)%")
                    kv("Sailing", settings.sailing == 0 ? "Off" : "\(settings.lowerBound)–\(settings.limit)%")
                    kv("Above limit", settings.autoDischarge ? "Discharge" : "Hold")
                    kv("macOS limit", model.macOSLimit.map { "\($0)%" } ?? "Off")
                    kv("Heat guard", settings.heatProtection ? unit.format(settings.heatThreshold, decimals: 0) : "Off")
                } else {
                    kv("macOS limit", model.macOSLimit.map { "\($0)%" } ?? "Off")
                }
                Spacer(minLength: 12)
                Button {
                    NSWorkspace.shared.open(URL(string: "chargectl://dashboard/control")!)
                } label: {
                    HStack(spacing: 6) {
                        Text("Edit in Control")
                        Text("⌘2").foregroundStyle(.tertiary)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func kv(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.tertiary)
            Text(value).fontWeight(.medium).monospacedDigit()
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 12)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1, height: 14) }
    }
}

extension String {
    /// "charging to 80%" → "Charging to 80%"; names that start lowercase, like macOS, stay.
    var capitalizedFirst: String { hasPrefix("macOS") ? self : prefix(1).uppercased() + dropFirst() }
}

// MARK: - Parts

/// The big charge meter: the charge as a green fill, the sailing range hatched under the limit,
/// the limit as a marker with a pill, a ruler underneath, and a row of dots that glow up to the
/// charge. Drag the limit pill to change it.
struct HeroMeter: View {
    let percent: Int
    let limit: Int?
    let lowerBound: Int?
    let isDraining: Bool
    var onSetLimit: ((Int) -> Void)?
    @State private var dragged: Int?

    var body: some View {
        let shown = dragged ?? limit
        let fillColor = isDraining ? Theme.warn : Theme.accent
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = { (value: Int) in width * CGFloat(value) / 100 }
            ZStack(alignment: .topLeading) {
                GlowDots(fraction: Double(percent) / 100, color: fillColor)
                    .frame(height: 30)
                Capsule().fill(Theme.track).frame(height: 12).offset(y: 42)
                if let shown, let lowerBound, lowerBound < shown, dragged == nil {
                    Hatch(color: Theme.accent)
                        .frame(width: x(shown) - x(lowerBound), height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .offset(x: x(lowerBound), y: 42)
                }
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [fillColor.opacity(0.7), fillColor], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(x(percent), 12), height: 12)
                    .shadow(color: fillColor.opacity(0.6), radius: 8)
                    .offset(y: 42)
                    .animation(.timingCurve(0.2, 0.9, 0.2, 1, duration: 1), value: percent)
                if let shown {
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 2, height: 26)
                        .overlay(Capsule().stroke(Theme.window, lineWidth: 3).padding(-1.5))
                        .offset(x: x(shown) - 1, y: 35)
                    Text("\(shown)%")
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.window)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.primary, in: Capsule())
                        .fixedSize()
                        .position(x: x(shown), y: 22)
                        .help(
                            "Charge limit \(shown)%. Charging stops here and the Mac runs on the charger."
                                + (lowerBound.map { " If the charge drifts below \($0)% it tops up again." } ?? ""))
                }
                Ruler().frame(height: 22).offset(y: 62)
            }
            // Offset children draw outside the stack's own size; hit-test the whole area.
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard let limit, dragged != nil || abs(drag.startLocation.x - x(limit)) <= 16 else { return }
                        let value = Int((drag.location.x / max(width, 1) * 100).rounded())
                        dragged = min(
                            max(value, ChargeSettings.limitRange.lowerBound), ChargeSettings.limitRange.upperBound)
                    }
                    .onEnded { _ in
                        if let dragged, dragged != limit { onSetLimit?(dragged) }
                        dragged = nil
                    },
                including: onSetLimit == nil ? .none : .all)
        }
        .frame(height: 86)
        .accessibilityElement()
        .accessibilityLabel("Charge limit")
        .accessibilityValue(shown.map { "limit \($0) percent, battery at \(percent) percent" } ?? "\(percent) percent")
        .accessibilityAdjustableAction { direction in
            guard let limit, let onSetLimit else { return }
            switch direction {
            case .increment: onSetLimit(min(limit + 1, ChargeSettings.limitRange.upperBound))
            case .decrement: onSetLimit(max(limit - 1, ChargeSettings.limitRange.lowerBound))
            @unknown default: break
            }
        }
    }
}

/// Ticks every 5%, labels at 0, 50 and 100.
struct Ruler: View {
    var from = 0
    var labels = [0, 50, 100]

    var body: some View {
        GeometryReader { geometry in
            let span = Double(100 - from)
            ForEach(Array(stride(from: from, through: 100, by: 5)), id: \.self) { value in
                let x = geometry.size.width * Double(value - from) / span
                Rectangle()
                    .fill(labels.contains(value) || value % 20 == 0 ? Color.secondary : Theme.lineStrong)
                    .frame(width: 1, height: labels.contains(value) || value % 20 == 0 ? 6 : 4)
                    .position(x: x, y: 3)
                if labels.contains(value) {
                    Text("\(value)\(from > 0 ? "%" : "")")
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .position(x: min(max(x, 10), geometry.size.width - 14), y: 16)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Diagonal stripes, for the sailing range.
struct Hatch: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 5
            }
            context.stroke(path, with: .color(color.opacity(0.5)), lineWidth: 1.6)
        }
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(color.opacity(0.35)))
    }
}

/// A row of dots that glow up to a fraction of the width.
struct GlowDots: View {
    let fraction: Double
    var color: Color = Theme.accent

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 14
            var lit = Path()
            var dim = Path()
            var y: CGFloat = 5
            while y < size.height {
                var x: CGFloat = 4
                while x < size.width {
                    let dot = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                    if x / size.width <= fraction { lit.addEllipse(in: dot) } else { dim.addEllipse(in: dot) }
                    x += step
                }
                y += step
            }
            context.fill(dim, with: .color(Theme.dot))
            context.addFilter(.shadow(color: color.opacity(0.8), radius: 3))
            context.fill(lit, with: .color(color.opacity(0.5)))
        }
        .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A thin bar with a fill.
struct MiniBar: View {
    let fraction: Double
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(color)
                .frame(width: geometry.size.width * min(max(fraction, 0), 1))
        }
        .frame(height: 3)
        .background(Theme.track, in: Capsule())
        .animation(.easeOut(duration: 0.5), value: fraction)
        .accessibilityHidden(true)
    }
}

private struct HealthCell<Footer: View>: View {
    let title: String
    let value: String
    let unit: String
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11.5)).foregroundStyle(.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .medium))
                    .tracking(-0.5)
                    .monospacedDigit()
                    .rollingNumber(value)
                Text(unit).font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Charger on the left, Mac and battery on the right, with power travelling along the wires.
private struct PowerFlow: View {
    let charger: Double
    let mac: Double
    let battery: Double
    let pluggedIn: Bool
    let wallCut: Bool
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let start = CGPoint(x: 150, y: size.height / 2)
            let macPoint = CGPoint(x: size.width - 150, y: 30)
            let batteryPoint = CGPoint(x: size.width - 150, y: size.height - 30)
            let fromBattery = battery < -0.05
            ZStack {
                wire(from: start, to: macPoint, active: pluggedIn && !wallCut, color: .secondary)
                wire(
                    from: fromBattery ? batteryPoint : start, to: fromBattery ? macPoint : batteryPoint,
                    active: abs(battery) > 0.05, color: fromBattery ? Theme.warn : Theme.accent,
                    bend: fromBattery)
                node(
                    "powerplug", value: pluggedIn ? Format.watts(charger) : "–",
                    title: wallCut ? "Charger, cut" : "Charger",
                    glow: pluggedIn && !wallCut, leading: true
                )
                .position(x: 70, y: size.height / 2)
                node("laptopcomputer", value: Format.watts(mac), title: "Mac", glow: false, leading: false)
                    .position(x: size.width - 70, y: 30)
                node(
                    battery > 0.05 ? "battery.100percent.bolt" : "battery.75percent",
                    value: abs(battery) < 0.05 ? "0 W" : Format.signedWatts(battery), title: "Battery",
                    glow: abs(battery) > 0.05, leading: false, tint: fromBattery ? Theme.warn : Theme.accent
                )
                .position(x: size.width - 70, y: size.height - 30)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = -18 }
        }
    }

    private func wire(from: CGPoint, to: CGPoint, active: Bool, color: Color, bend: Bool = false) -> some View {
        let path = Path { path in
            path.move(to: from)
            if bend {
                path.addCurve(
                    to: to, control1: CGPoint(x: from.x - 60, y: from.y), control2: CGPoint(x: to.x - 60, y: to.y))
            } else {
                path.addCurve(
                    to: to, control1: CGPoint(x: (from.x + to.x) / 2, y: from.y),
                    control2: CGPoint(x: (from.x + to.x) / 2, y: to.y))
            }
        }
        return ZStack {
            path.stroke(Theme.lineStrong, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            if active {
                path.stroke(
                    color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 12], dashPhase: phase)
                )
                .shadow(color: color.opacity(0.6), radius: 4)
            }
        }
    }

    private func node(
        _ symbol: String, value: String, title: String, glow: Bool, leading: Bool, tint: Color = Theme.accent
    ) -> some View {
        let icon = Image(systemName: symbol)
            .font(.system(size: 14))
            .foregroundStyle(glow ? tint : .secondary)
            .frame(width: 34, height: 34)
            .background(
                LinearGradient(colors: [Theme.cardTop, Theme.cardBottom], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(glow ? tint.opacity(0.4) : Theme.lineStrong)
            )
            .shadow(color: glow ? tint.opacity(0.35) : .clear, radius: 8)
        let text = VStack(alignment: leading ? .leading : .trailing, spacing: 1) {
            Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit().rollingNumber(value)
            Text(title).font(.system(size: 11.5)).foregroundStyle(.tertiary)
        }
        return HStack(spacing: 10) {
            if leading {
                icon
                text
            } else {
                text
                icon
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// One line in the Overview's activity list, on a rail.
private struct ActivityRow: View {
    let entry: LogEntry
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        let accent = entry.source == .chargectl && entry.level != .warning
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(Theme.lineStrong)
                    .frame(width: 1.5)
                    .padding(.top, isFirst ? 8 : 0)
                    .padding(.bottom, isLast ? 0 : -4)
                    .opacity(isLast ? 0 : 1)
                Circle()
                    .fill(entry.level == .warning ? Theme.warn : accent ? Theme.accent : Theme.window)
                    .overlay(
                        Circle().strokeBorder(
                            accent || entry.level == .warning ? .clear : Color.secondary, lineWidth: 1.5)
                    )
                    .shadow(color: accent ? Theme.glow : .clear, radius: 4)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
            }
            .frame(width: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message.capitalizedFirst)
                    .font(.system(size: 12.5, weight: accent ? .medium : .regular))
                    .foregroundStyle(entry.level == .warning ? Theme.warn : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let percent = entry.percent {
                    Text("At \(percent)%").font(.system(size: 11.5)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Text(entry.date, format: .dateTime.hour().minute())
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.bottom, isLast ? 0 : 10)
        .accessibilityElement(children: .combine)
    }
}

/// The charge over a range: a glowing line, a soft fill, the limit and the sailing range, and a
/// strip under it that shows when the charger was connected. Hover for the value at a moment.
struct ChargeChart: View {
    let samples: [HistorySample]
    let domain: ClosedRange<Date>
    let limit: Int?
    let lowerBound: Int?
    var height: CGFloat = 150
    @Binding var hovered: Date?

    init(
        samples: [HistorySample], domain: ClosedRange<Date>, limit: Int?, lowerBound: Int?, height: CGFloat = 150,
        hovered: Binding<Date?>? = nil
    ) {
        self.samples = samples
        self.domain = domain
        self.limit = limit
        self.lowerBound = lowerBound
        self.height = height
        _hovered = hovered ?? .constant(nil)
        _localHover = State(initialValue: nil)
        usesLocalHover = hovered == nil
    }

    @State private var localHover: Date?
    private let usesLocalHover: Bool

    private var selection: Binding<Date?> { usesLocalHover ? $localHover : $hovered }

    var body: some View {
        let shown = selection.wrappedValue.flatMap { date in
            samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        VStack(spacing: 10) {
            Chart {
                if let limit, let lowerBound, lowerBound < limit {
                    RectangleMark(
                        xStart: .value("Start", domain.lowerBound), xEnd: .value("End", domain.upperBound),
                        yStart: .value("Low", lowerBound), yEnd: .value("High", limit)
                    )
                    .foregroundStyle(Theme.accentSoft)
                }
                ForEach(samples, id: \.date) { sample in
                    AreaMark(
                        x: .value("Time", sample.date), yStart: .value("Base", 0),
                        yEnd: .value("Charge", sample.percent)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0)], startPoint: .top,
                            endPoint: .bottom))
                    LineMark(x: .value("Time", sample.date), y: .value("Charge", sample.percent))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .shadow(color: Theme.glow.opacity(0.6), radius: 4)
                }
                if let limit {
                    RuleMark(y: .value("Limit", limit))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.8))
                }
                if let last = samples.last, last.date > domain.upperBound.addingTimeInterval(-180) {
                    PointMark(x: .value("Time", last.date), y: .value("Charge", last.percent))
                        .symbolSize(40)
                        .foregroundStyle(Theme.accent)
                }
                if let shown {
                    RuleMark(x: .value("Time", shown.date))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.secondary)
                    PointMark(x: .value("Time", shown.date), y: .value("Charge", shown.percent))
                        .symbolSize(50)
                        .foregroundStyle(Theme.accent)
                        .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(shown.percent)%").font(.system(size: 13, weight: .semibold))
                                Text(shown.date, format: .dateTime.hour().minute())
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.window, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.lineStrong)
                            )
                            .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                        }
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: 0...100)
            .chartPlotStyle { $0.clipped() }
            .chartXSelection(value: selection)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                    AxisGridLine().foregroundStyle(Theme.line)
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                }
            }
            .frame(height: height)
            ChargerStrip(samples: samples, domain: domain)
                .frame(height: 6)
                .padding(.trailing, 34)
        }
    }
}

/// Green while the charger was connected and charging, dim while resting on it, empty on battery.
struct ChargerStrip: View {
    let samples: [HistorySample]
    let domain: ClosedRange<Date>

    var body: some View {
        Canvas { context, size in
            let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
            guard span > 0 else { return }
            context.fill(
                Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3), with: .color(Theme.track))
            for (index, sample) in samples.enumerated() where (sample.wallPower ?? 0) > 0.5 {
                let end = index + 1 < samples.count ? samples[index + 1].date : sample.date.addingTimeInterval(60)
                let x0 = size.width * sample.date.timeIntervalSince(domain.lowerBound) / span
                let x1 = size.width * end.timeIntervalSince(domain.lowerBound) / span
                let charging = (sample.batteryPower ?? 0) > 0.5
                context.fill(
                    Path(CGRect(x: x0, y: 0, width: max(x1 - x0, 1), height: size.height)),
                    with: .color(charging ? Theme.accent : Theme.accent.opacity(0.36)))
            }
        }
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}
