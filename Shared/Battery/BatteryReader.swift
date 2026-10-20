import Foundation
import IOKit

nonisolated enum BatteryReadError: Error, CustomStringConvertible {
    case noBattery
    case unreadable

    var description: String {
        switch self {
        case .noBattery: "this Mac has no battery"
        case .unreadable: "the battery registry entry could not be read"
        }
    }
}

/// Reads the battery from the IORegistry and power figures from the SMC. Needs no privileges.
final class BatteryReader {
    private let smc: SMC?

    init(smc: SMC?) {
        self.smc = smc
    }

    func read(now: Date = .now) throws -> BatterySnapshot {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { throw BatteryReadError.noBattery }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let registry = properties?.takeRetainedValue() as? [String: Any],
            let snapshot = BatterySnapshot.parse(
                registry: registry,
                chargerAttached: chargerAttached(),
                temperature: float(SMCKey.batteryTemperature),
                wallPower: float(SMCKey.wallPower),
                systemPower: float(SMCKey.systemPower),
                date: now,
                live: liveReadings())
        else { throw BatteryReadError.unreadable }
        return snapshot
    }

    private func liveReadings() -> BatterySnapshot.LiveReadings {
        BatterySnapshot.LiveReadings(
            batteryCurrent: integer(SMCKey.batteryCurrent).map { Double($0) / 1000 },
            batteryVoltage: integer(SMCKey.batteryVoltage).flatMap { $0 > 0 ? Double($0) / 1000 : nil },
            chargerVoltage: float(SMCKey.chargerVoltage),
            chargerCurrent: float(SMCKey.chargerCurrent),
            minutesToFull: integer(SMCKey.timeToFull),
            minutesToEmpty: integer(SMCKey.timeToEmpty))
    }

    private func integer(_ key: String) -> Int? {
        guard let smc else { return nil }
        return try? smc.read(key).integer
    }

    /// nil when the key is missing, so the registry is used instead.
    private func chargerAttached() -> Bool? {
        guard let smc, let value = try? smc.read(SMCKey.chargerAttached).integer else { return nil }
        return value > 0
    }

    private func float(_ key: String) -> Double? {
        guard let value = try? smc?.read(key).float, value.isFinite else { return nil }
        return Double(value)
    }
}
