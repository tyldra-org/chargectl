import Foundation

/// Reads the charge limit macOS itself enforces (System Settings › Battery › Charging).
/// powerd keeps the active policies for the current boot in a world-readable file.
nonisolated enum NativeChargeLimit {
    static let preferencesURL = URL(fileURLWithPath: "/Library/Preferences/com.apple.powerd.charging.plist")

    /// The lowest active macOS limit this boot, or nil when macOS is not limiting.
    static func current() -> Int? {
        guard let data = try? Data(contentsOf: preferencesURL) else { return nil }
        return limit(inPreferences: data, bootSession: bootSessionUUID())
    }

    static func limit(inPreferences data: Data, bootSession: String?) -> Int? {
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let policies = plist["policies"] as? Data
        else { return nil }
        if let stored = plist["bootSessionUUID"] as? String, let bootSession, stored != bootSession {
            return nil
        }
        return activeLimit(inArchive: policies)
    }

    static func activeLimit(inArchive data: Data) -> Int? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.setClass(PowerdChargePolicy.self, forClassName: "ChargeCtrlPolicy")
        let root = unarchiver.decodeObject(
            of: [NSArray.self, PowerdChargePolicy.self], forKey: NSKeyedArchiveRootObjectKey)
        unarchiver.finishDecoding()
        let policies = (root as? [Any] ?? []).compactMap { $0 as? PowerdChargePolicy }
        return activePolicy(policies)?.socLimit
    }

    /// Whether macOS discharges the battery when it is above the active limit.
    static func drainsAboveLimit(inArchive data: Data) -> Bool {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return false }
        unarchiver.setClass(PowerdChargePolicy.self, forClassName: "ChargeCtrlPolicy")
        let root = unarchiver.decodeObject(
            of: [NSArray.self, PowerdChargePolicy.self], forKey: NSKeyedArchiveRootObjectKey)
        unarchiver.finishDecoding()
        return activePolicy((root as? [Any] ?? []).compactMap { $0 as? PowerdChargePolicy })?.drain ?? false
    }

    static func currentDrains() -> Bool {
        guard let data = try? Data(contentsOf: preferencesURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let policies = plist["policies"] as? Data
        else { return false }
        return drainsAboveLimit(inArchive: policies)
    }

    private static func activePolicy(_ policies: [PowerdChargePolicy]) -> PowerdChargePolicy? {
        policies.filter { !$0.terminated && (1..<100).contains($0.socLimit) }.min { $0.socLimit < $1.socLimit }
    }

    static func bootSessionUUID() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// The two fields this app reads from powerd's private ChargeCtrlPolicy archive.
@objc(ChargectlPowerdChargePolicy)
nonisolated final class PowerdChargePolicy: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let socLimit: Int
    let terminated: Bool
    /// Above the limit, macOS runs the Mac on battery down to it instead of only not charging.
    let drain: Bool

    init(socLimit: Int, terminated: Bool, drain: Bool) {
        self.socLimit = socLimit
        self.terminated = terminated
        self.drain = drain
    }

    init?(coder: NSCoder) {
        socLimit = coder.decodeInteger(forKey: "soclimit")
        terminated = coder.decodeBool(forKey: "terminated")
        drain = coder.decodeBool(forKey: "drain")
    }

    func encode(with coder: NSCoder) {
        coder.encode(socLimit, forKey: "soclimit")
        coder.encode(terminated, forKey: "terminated")
        coder.encode(drain, forKey: "drain")
    }
}
