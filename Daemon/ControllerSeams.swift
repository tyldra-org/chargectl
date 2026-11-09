import Foundation

// The hardware and system services the controller drives, as protocols so tests can stand in
// for them.

/// Connects and disconnects the charger's power to the Mac.
protocol WallPowerSwitch {
    /// The SMC key that does it, for the log and the app.
    var key: String { get }
    func isConnected() throws -> Bool
    func set(connected: Bool) throws
}

extension AdapterSwitch: WallPowerSwitch {}

/// macOS's own charge limit in System Settings › Battery.
nonisolated protocol MacOSLimitControl: AnyObject, Sendable {
    func current() throws -> MacOSChargeLimit.Setting
    /// Optimized Battery Charging; nil when unknown.
    func isOptimizedChargingEnabled() -> Bool?
    func apply(_ setting: MacOSChargeLimit.Setting) throws
    func set(limit: Int) throws
}

extension MacOSChargeLimit: MacOSLimitControl {}

/// The battery's readings.
protocol BatterySource {
    func read(now: Date) throws -> BatterySnapshot
}

extension BatteryReader: BatterySource {}
