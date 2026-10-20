import Foundation

/// One reading of the battery and power path.
nonisolated struct BatterySnapshot: Codable, Equatable, Sendable {
    var date: Date
    /// State of charge, 0–100.
    var percent: Int
    var isPluggedIn: Bool
    var isCharging: Bool
    var cycleCount: Int
    var designCycleCount: Int?
    /// mAh
    var designCapacity: Int
    /// mAh
    var fullChargeCapacity: Int
    /// V
    var voltage: Double
    /// A; positive while charging, negative while the battery supplies power.
    var current: Double
    /// °C
    var temperature: Double?
    var adapterWatts: Int?
    var adapterName: String?
    /// W from the charger.
    var wallPower: Double?
    /// W the whole Mac draws.
    var systemPower: Double?
    /// V and A at the charger input, live.
    var chargerVoltage: Double?
    var chargerCurrent: Double?
    /// V the adapter negotiated.
    var adapterVoltage: Double?
    /// Minutes, when the battery is charging or discharging.
    var minutesToFull: Int?
    var minutesToEmpty: Int?

    /// Readings taken from the SMC at the same moment; they update every second, unlike the registry.
    nonisolated struct LiveReadings: Sendable {
        /// A, positive while charging.
        var batteryCurrent: Double?
        /// V
        var batteryVoltage: Double?
        var chargerVoltage: Double?
        var chargerCurrent: Double?
        var minutesToFull: Int?
        var minutesToEmpty: Int?
    }

    private static func minutes(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 65535 else { return nil }
        return value
    }

    /// Full-charge capacity as a fraction of design capacity.
    var health: Double? {
        guard designCapacity > 0, fullChargeCapacity > 0 else { return nil }
        return Double(fullChargeCapacity) / Double(designCapacity)
    }

    /// W; positive while charging, negative while supplying.
    var batteryPower: Double { voltage * current }

    /// Builds a snapshot from the AppleSmartBattery registry entry and optional SMC readings.
    /// chargerAttached comes from SMC AC-W; the registry reports the charger as gone while
    /// wall power is cut, so it is only the fallback.
    static func parse(
        registry: [String: Any], chargerAttached: Bool? = nil, temperature smcTemperature: Double?,
        wallPower: Double?, systemPower: Double?, date: Date, live: LiveReadings = LiveReadings()
    ) -> BatterySnapshot? {
        let batteryData = registry["BatteryData"] as? [String: Any] ?? [:]
        func int(_ key: String) -> Int? {
            (registry[key] as? NSNumber)?.intValue ?? (batteryData[key] as? NSNumber)?.intValue
        }
        guard let percent = int("CurrentCapacity") else { return nil }
        let adapter = registry["AdapterDetails"] as? [String: Any]
        let adapterWatts = (adapter?["Watts"] as? NSNumber)?.intValue
        let registryTemperature = int("Temperature").map { Double($0) / 100 }
        let name = (adapter?["Name"] as? String)?.trimmingCharacters(in: .whitespaces)
        return BatterySnapshot(
            date: date,
            percent: min(max(percent, 0), 100),
            isPluggedIn: chargerAttached ?? registry["ExternalConnected"] as? Bool ?? false,
            isCharging: registry["IsCharging"] as? Bool ?? false,
            cycleCount: int("CycleCount") ?? 0,
            designCycleCount: int("DesignCycleCount9C"),
            designCapacity: int("DesignCapacity") ?? 0,
            fullChargeCapacity: int("FullChargeCapacity") ?? int("NominalChargeCapacity") ?? 0,
            voltage: live.batteryVoltage ?? Double(int("Voltage") ?? 0) / 1000,
            current: live.batteryCurrent ?? Double(
                Int64(
                    truncatingIfNeeded: (registry["InstantAmperage"] as? NSNumber)?.int64Value
                        ?? Int64(int("Amperage") ?? 0))) / 1000,
            temperature: smcTemperature ?? registryTemperature,
            adapterWatts: adapterWatts.flatMap { $0 > 0 ? $0 : nil },
            adapterName: name?.isEmpty == false ? name : nil,
            wallPower: wallPower,
            systemPower: systemPower,
            chargerVoltage: live.chargerVoltage,
            chargerCurrent: live.chargerCurrent,
            adapterVoltage: ((adapter?["AdapterVoltage"] as? NSNumber)?.doubleValue).flatMap {
                $0 > 0 ? $0 / 1000 : nil
            },
            minutesToFull: minutes(live.minutesToFull ?? int("AvgTimeToFull")),
            minutesToEmpty: minutes(live.minutesToEmpty ?? int("AvgTimeToEmpty")))
    }
}
