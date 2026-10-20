import Charts
import SwiftUI

struct OverviewPage: View {
    let model: AppModel
    @AppStorage(PreferenceKey.temperatureUnit) private var unit = TemperatureUnit.systemDefault
    @State private var confirmingCalibration = false

    var body: some View {
        if let battery = model.battery {
            ScrollView {
                VStack(spacing: 16) {
                    hero(battery)
                    HStack(alignment: .top, spacing: 16) {
                        powerFlow(battery)
                        charger(battery)
                        estimate(battery)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 16) {
                        health(battery)
                        control
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 16) {
                        recentCharge
                        recentActivity
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
            .task {
                while !Task.isCancelled {
                    await model.loadHistory()
                    await model.loadLogs()
                    try? await Task.sleep(for: .seconds(15))
                }
            }
        } else {
            ContentUnavailableView(
                "Battery Unavailable", systemImage: "battery.0percent",
                description: Text(model.batteryError ?? "Reading the battery…"))
        }
    }

    // MARK: Hero

    private func hero(_ battery: BatterySnapshot) -> some View {
        Card {
            HStack(alignment: .center, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(battery.percent)")
                        .font(.system(size: 64, weight: .thin))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.title2.weight(.light))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.activitySummary.capitalizedFirst)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(model.isDraining ? Theme.amber : .primary)
                    Text(subtitle(battery))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 16)
                actions
            }
            ChargeBar(
                percent: battery.percent, limit: model.settings?.limit,
                lowerBound: model.settings?.lowerBound, isDraining: model.isDraining,
                onSetLimit: model.isControllable ? { limit in model.update { $0.limit = limit } } : nil
            )
            .padding(.top, 4)
            if !featureItems.isEmpty {
                HStack(spacing: 6) {
                    ForEach(featureItems, id: \.self) { item in
                        Text(item)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.chipFill, in: Capsule())
                    }
                }
            }
        }
    }

    private func subtitle(_ battery: BatterySnapshot) -> String {
        var parts = [unit.format(battery.temperature)]
        if battery.isPluggedIn { parts.append(battery.adapterName ?? "Charger connected") }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder private var actions: some View {
        let mode = model.status?.mode ?? .automatic
        let limit = model.settings?.limit ?? 80
        Group {
            if mode == .automatic {
                HStack(spacing: 8) {
                    Button("Discharge") { model.perform(.discharge) }
                        .disabled((model.battery?.percent ?? 0) <= limit)
                        .help("Run on battery down to \(limit)%")
                    Button("Top Up") { model.perform(.topUp) }
                        .help("Charge to 100% once, then return to the limit")
                    Button("Calibrate…") { confirmingCalibration = true }
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(mode.title.capitalizedFirst).foregroundStyle(.secondary)
                    Button("Stop") { model.perform(.stop) }
                }
            }
        }
        .controlSize(.regular)
        .disabled(!model.isControllable)
        .confirmationDialog("Calibrate the battery?", isPresented: $confirmingCalibration) {
            Button("Calibrate") { model.perform(.calibrate) }
        } message: {
            Text(
                "Chargectl runs the battery down to \(ChargePolicy.calibrationFloor)%, charges it to 100%, rests for an hour, then returns to your limit. Keep the charger connected. This takes several hours."
            )
        }
    }

    private var featureItems: [String] {
        var items: [String] = []
        if let settings = model.settings, settings.isEnabled {
            if settings.sailing > 0 { items.append("Sailing \(settings.lowerBound)–\(settings.limit)%") }
            items.append(settings.autoDischarge ? "Auto discharge" : "Holds above limit")
            if settings.heatProtection {
                items.append("Heat guard \(unit.format(settings.heatThreshold, decimals: 0))")
            }
            if settings.holdAsleep { items.append("Discharges asleep") }
        }
        return items
    }

    // MARK: Live power

    private func powerFlow(_ battery: BatterySnapshot) -> some View {
        let batteryPower = battery.batteryPower
        let scale = max(Double(battery.adapterWatts ?? 30), battery.systemPower ?? 0, abs(batteryPower), 1)
        let batteryTint: Color = batteryPower > 0.05 ? Theme.green : batteryPower < -0.05 ? Theme.amber : .secondary
        return Card(title: "Power", symbol: "bolt") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                meterRow("Charger", Format.watts(battery.wallPower), (battery.wallPower ?? 0) / scale, tint: .secondary)
                meterRow("Mac", Format.watts(battery.systemPower), (battery.systemPower ?? 0) / scale, tint: .secondary)
                meterRow("Battery", batteryText(batteryPower), abs(batteryPower) / scale, tint: batteryTint)
            }
            Text(flowSentence(battery))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func batteryText(_ watts: Double) -> String {
        abs(watts) < 0.05 ? "0 W" : Format.signedWatts(watts)
    }

    private func flowSentence(_ battery: BatterySnapshot) -> String {
        let watts = battery.batteryPower
        if !battery.isPluggedIn { return "The battery runs the Mac." }
        if watts > 0.05 { return "The charger runs the Mac and charges the battery." }
        if watts < -0.05 { return "The battery helps run the Mac; the charger is plugged in." }
        return "The charger runs the Mac; the battery is idle."
    }

    private func meterRow(_ title: String, _ value: String, _ fraction: Double, tint: Color) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .contentTransition(.numericText())
                .gridColumnAlignment(.trailing)
            PowerMeter(fraction: fraction, tint: tint).frame(minWidth: 50)
        }
    }

    private func charger(_ battery: BatterySnapshot) -> some View {
        Card(title: "Charger", symbol: "powerplug") {
            if battery.isPluggedIn {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    InfoRow(title: "Adapter", value: battery.adapterWatts.map { "\($0) W" } ?? "–")
                    InfoRow(
                        title: "Input",
                        value: battery.chargerVoltage.map { String(format: "%.1f V", $0) } ?? "–")
                    InfoRow(
                        title: "Current",
                        value: battery.chargerCurrent.map { String(format: "%.2f A", $0) } ?? "–")
                    InfoRow(title: "Wall power", value: wallPowerText, tint: wallPowerTint)
                }
            } else {
                Text("Not connected").foregroundStyle(.secondary)
            }
        }
    }

    private var wallPowerText: String {
        guard let status = model.status else { return "–" }
        return status.adapterEnabled ? "Connected" : "Cut by Chargectl"
    }

    private var wallPowerTint: Color? {
        model.status.map { $0.adapterEnabled ? nil : Theme.amber } ?? nil
    }

    private func estimate(_ battery: BatterySnapshot) -> some View {
        Card(title: "Estimate", symbol: "clock") {
            VStack(alignment: .leading, spacing: 6) {
                Text(estimateValue(battery))
                    .font(.system(size: 26, weight: .light))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(estimateLabel(battery))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func estimateValue(_ battery: BatterySnapshot) -> String {
        if battery.current > 0.05, let minutes = battery.minutesToFull { return TimeText.minutes(minutes) }
        if battery.current < -0.05, let minutes = battery.minutesToEmpty { return TimeText.minutes(minutes) }
        return "–"
    }

    private func estimateLabel(_ battery: BatterySnapshot) -> String {
        if battery.current > 0.05 { return battery.minutesToFull == nil ? "Charging" : "until full" }
        if battery.current < -0.05 { return battery.minutesToEmpty == nil ? "Discharging" : "until empty at this rate" }
        return battery.isPluggedIn ? "Holding steady; no time to estimate." : "Idle"
    }

    // MARK: Battery and control

    private func health(_ battery: BatterySnapshot) -> some View {
        Card(title: "Battery", symbol: "battery.75percent") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                InfoRow(title: "Health", value: Format.percent(battery.health))
                InfoRow(
                    title: "Cycles",
                    value: battery.designCycleCount.map { "\(battery.cycleCount) of \($0)" } ?? "\(battery.cycleCount)")
                InfoRow(title: "Capacity", value: "\(battery.fullChargeCapacity) of \(battery.designCapacity) mAh")
                InfoRow(title: "Voltage", value: String(format: "%.2f V", battery.voltage))
                InfoRow(
                    title: "Current",
                    value: abs(battery.current) < 0.005 ? "0 A" : String(format: "%+.2f A", battery.current))
                InfoRow(title: "Temperature", value: unit.format(battery.temperature))
            }
        }
    }

    private var control: some View {
        Card(title: "Charge Control", symbol: "slider.horizontal.3") {
            if let settings = model.settings, let status = model.status {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    InfoRow(title: "Status", value: settings.isEnabled ? status.mode.title.capitalizedFirst : "Off")
                    InfoRow(title: "Limit", value: "\(settings.limit)%")
                    InfoRow(
                        title: "Sailing",
                        value: settings.sailing == 0 ? "Off" : "\(settings.lowerBound)–\(settings.limit)%")
                    InfoRow(title: "Above limit", value: settings.autoDischarge ? "Discharge" : "Hold")
                    InfoRow(title: "macOS limit", value: model.macOSLimit.map { "\($0)%" } ?? "Off")
                    InfoRow(
                        title: "Heat guard",
                        value: settings.heatProtection ? unit.format(settings.heatThreshold, decimals: 0) : "Off")
                }
            } else {
                Text("The helper is not running.").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Recent

    private var recentCharge: some View {
        let start = Date.now.addingTimeInterval(-6 * 60 * 60)
        let samples = model.history.filter { $0.date >= start }
        return Card(title: "Last 6 Hours", symbol: "chart.xyaxis.line") {
            if samples.count < 2 {
                Text("Collecting; a point is recorded every minute.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
            } else {
                Chart(samples, id: \.date) { sample in
                    AreaMark(
                        x: .value("Time", sample.date), yStart: .value("Base", 0),
                        yEnd: .value("Charge", sample.percent)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.green.opacity(0.28), Theme.green.opacity(0.02)], startPoint: .top,
                            endPoint: .bottom))
                    LineMark(x: .value("Time", sample.date), y: .value("Charge", sample.percent))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.green)
                    if let limit = model.settings?.limit {
                        RuleMark(y: .value("Limit", limit))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXScale(domain: start...Date.now)
                .chartYScale(domain: 0...100)
                .chartPlotStyle { $0.clipped() }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine().foregroundStyle(Theme.chipFill)
                        AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                    }
                }
                .frame(height: 120)
            }
        }
    }

    private var recentActivity: some View {
        let entries = Array(model.logs.suffix(6).reversed())
        return Card(title: "Recent Activity", symbol: "list.bullet") {
            if entries.isEmpty {
                Text("Nothing logged yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(entry.date, format: .dateTime.hour().minute())
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .leading)
                            Text(entry.message.capitalizedFirst)
                                .font(.callout)
                                .foregroundStyle(entry.level == .warning ? Theme.amber : .primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
