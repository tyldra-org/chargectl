import Foundation

/// Sample entries for the widget gallery's previews and the design renders.
nonisolated extension BatteryEntry {
    enum Sample: String, CaseIterable, Sendable {
        case charging
        case holding
        case battery
        case fullBy
        case noHelper
    }

    static let placeholder = sample(.charging)

    static func sample(_ kind: Sample, now: Date = .now) -> BatteryEntry {
        let percent: Int =
            switch kind {
            case .charging, .noHelper: 61
            case .holding: 80
            case .battery: 58
            case .fullBy: 86
            }
        let plugged = kind != .battery
        let charging = kind == .charging || kind == .fullBy || kind == .noHelper
        let current = charging ? 2.13 : kind == .battery ? -1.03 : 0
        let battery = BatterySnapshot(
            date: now, percent: percent, isPluggedIn: plugged, isCharging: charging, cycleCount: 214,
            designCycleCount: 1000, designCapacity: 5760, fullChargeCapacity: 5234, voltage: 12.05, current: current,
            temperature: 28.5, adapterWatts: plugged ? 35 : nil,
            adapterName: plugged ? "35 W USB-C Power Adapter" : nil,
            wallPower: plugged ? (charging ? 35.1 : 9.6) : 0, systemPower: plugged ? (charging ? 8.1 : 9.4) : 12.4,
            chargerVoltage: plugged ? 19.8 : nil, chargerCurrent: plugged ? 1.77 : nil, adapterVoltage: 20,
            minutesToFull: nil, minutesToEmpty: kind == .battery ? 250 : nil)
        var settings = ChargeSettings()
        settings.fullBy = FullBySchedule(hour: 8, minute: 0, weekdays: FullBySchedule.weekdaysOnly)
        let deadline =
            Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: now.addingTimeInterval(3600))
            ?? now.addingTimeInterval(3600)
        let mode: ChargeMode = kind == .fullBy ? .fullBy(deadline) : .automatic
        let activity: ChargeActivity =
            switch kind {
            case .charging, .noHelper: .charging(to: 80)
            case .holding: .holding(80)
            case .battery: .onBattery
            case .fullBy: .chargingFull(by: deadline)
            }
        let status =
            kind == .noHelper
            ? nil
            : DaemonStatus(
                version: DaemonIdentity.version, settings: settings, mode: mode, activity: activity,
                adapterEnabled: true, adapterKey: "CHIE", lastError: nil, optimizedChargingEnabled: false)
        return BatteryEntry(
            date: now, battery: battery, status: status, history: history(now: now, ending: percent),
            daily: daily(now: now),
            events: [
                LogEntry(
                    date: now.addingTimeInterval(-60), level: .info, message: "charging to 80%", percent: 61,
                    source: .chargectl),
                LogEntry(
                    date: now.addingTimeInterval(-2400), level: .info, message: "charger plugged in", percent: 57,
                    source: .observed),
                LogEntry(
                    date: now.addingTimeInterval(-18000), level: .info, message: "on battery", percent: 80,
                    source: .observed),
            ])
    }

    /// A day of charge: held at 80%, on battery in the afternoon, charging again now.
    private static func history(now: Date, ending percent: Int) -> [HistorySample] {
        (0...1440).reversed().map { back in
            let minute = Double(back)
            let value: Double =
                switch minute {
                case 0..<40: Double(percent) - minute * 0.1
                case 40..<300: 57 + (minute - 40) * 0.02
                case 300..<720: 80 - (minute - 300) * 0.055
                default: 80
                }
            return HistorySample(
                date: now.addingTimeInterval(-minute * 60), percent: Int(value.rounded()),
                temperature: 28 + sin(minute / 90),
                systemPower: 8, wallPower: minute < 40 || minute > 720 ? 30 : 0, batteryPower: minute < 40 ? 25 : 0)
        }
    }

    /// Four months of the daily record, health easing from 92.4% to 90.9%.
    private static func daily(now: Date) -> [DailySample] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (1...120).reversed().compactMap { back -> DailySample? in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let age = Double(120 - back) / 120
            return DailySample(
                day: day, fullChargeCapacity: Int(5322 - 88 * age), designCapacity: 5760,
                cycleCount: 186 + Int(28 * age), minutesRecorded: 1440, minutesPlugged: 900,
                minutesHighCharge: back % 23 == 0 ? 180 : 0, averageTemperature: 29, maxTemperature: 33)
        }
    }
}
