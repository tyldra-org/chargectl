import Foundation
import ObjectiveC

/// macOS's own charge limit (System Settings › Battery › Charging), set through the private
/// PowerUISmartChargeClient. PowerUIAgent holds the entitlement that stops charging while the
/// Mac keeps running on the charger. Its API accepts 80% to 100%; lower limits go through its
/// preferences.
/// Created on a background queue at startup, then used only on the main actor.
nonisolated final class MacOSChargeLimit: @unchecked Sendable {
    nonisolated struct Setting: Codable, Equatable, Sendable {
        var isEnabled: Bool
        var limit: Int
    }

    enum LimitError: Error, CustomStringConvertible {
        case rejected(String, NSError?)
        case notApplied(requested: Int, actual: Int)
        case preferencesNotWritten

        var description: String {
            switch self {
            case .rejected(let call, let error):
                "\(call) failed\(error.map { " (\($0.domain) \($0.code))" } ?? "")"
            case .notApplied(let requested, let actual):
                "macOS kept its limit at \(actual)% instead of \(requested)%"
            case .preferencesNotWritten:
                "PowerUIAgent's preferences could not be written"
            }
        }
    }

    /// PowerUIAgent's preferences (root's domain). Apple's API refuses limits below 80%, but
    /// PowerUIAgent applies whatever this key holds when it reloads them.
    nonisolated(unsafe) private static let preferencesDomain = "com.apple.smartcharging.topoffprotection" as CFString
    nonisolated(unsafe) private static let limitKey = "mclLimitValue" as CFString
    private static let reloadNotification = "com.apple.smartcharging.defaultschanged"

    private typealias InitFunction = @convention(c) (AnyObject, Selector, NSString) -> AnyObject?
    private typealias BoolFunction = @convention(c) (AnyObject, Selector) -> Bool
    private typealias ByteFunction = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> UInt8
    private typealias WordFunction = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> UInt64
    private typealias ActionFunction = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> Bool
    private typealias SetFunction =
        @convention(c) (AnyObject, Selector, UInt8, UnsafeMutablePointer<NSError?>?) -> Bool

    private static let frameworkPath = "/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI"
    private static let requiredSelectors = [
        "isMCLSupported", "getMCLLimitWithError:", "isMCLCurrentlyEnabled:", "setMCLLimit:error:",
        "enableMCL:", "disableMCL:",
    ]

    private let client: AnyObject

    /// nil when PowerUI is missing, its interface changed, or this Mac has no charge limit.
    init?() {
        guard dlopen(Self.frameworkPath, RTLD_NOW) != nil,
            let type = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type
        else { return nil }
        guard let instance = type.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
            Self.requiredSelectors.allSatisfy({ instance.responds(to: Selector($0)) }),
            instance.responds(to: Selector(("initWithClientName:"))),
            let client = Self.function(instance, "initWithClientName:", InitFunction.self)(
                instance, Selector(("initWithClientName:")), "chargectl")
        else { return nil }
        self.client = client
        guard Self.function(client, "isMCLSupported", BoolFunction.self)(client, Selector(("isMCLSupported"))) else {
            return nil
        }
    }

    func current() throws -> Setting {
        var error: NSError?
        let limit = Self.function(client, "getMCLLimitWithError:", ByteFunction.self)(
            client, Selector(("getMCLLimitWithError:")), &error)
        if let error { throw LimitError.rejected("getMCLLimit", error) }
        let enabled = Self.function(client, "isMCLCurrentlyEnabled:", WordFunction.self)(
            client, Selector(("isMCLCurrentlyEnabled:")), &error)
        if let error { throw LimitError.rejected("isMCLCurrentlyEnabled", error) }
        return Setting(isEnabled: enabled != 0, limit: Int(limit))
    }

    /// Optimized Battery Charging, which can hold or delay charging by itself. nil when unknown.
    func isOptimizedChargingEnabled() -> Bool? {
        let selector = "isSmartChargingCurrentlyEnabled:"
        guard (client as? NSObject)?.responds(to: Selector(selector)) == true else { return nil }
        var error: NSError?
        let enabled = Self.function(client, selector, WordFunction.self)(client, Selector(selector), &error)
        return error == nil ? enabled != 0 : nil
    }

    func apply(_ setting: Setting) throws {
        if setting.isEnabled {
            try set(limit: setting.limit)
        } else {
            try call("disableMCL:")
        }
    }

    func set(limit: Int) throws {
        guard limit < ChargePolicy.macOSLimitAPIFloor else { return try setThroughAPI(limit) }
        // Make an allowed 80% request so PowerUIAgent owns an enabled limit, then
        // write the lower value into its preferences and have it reload them.
        try setThroughAPI(ChargePolicy.macOSLimitAPIFloor)
        let host = Self.preferencesHost
        CFPreferencesSetValue(Self.limitKey, limit as CFNumber, Self.preferencesDomain, kCFPreferencesCurrentUser, host)
        guard CFPreferencesSynchronize(Self.preferencesDomain, kCFPreferencesCurrentUser, host) else {
            throw LimitError.preferencesNotWritten
        }
        notify_post(Self.reloadNotification)
        for _ in 0..<20 {
            if try current().limit == limit { return }
            usleep(100_000)
        }
        throw LimitError.notApplied(requested: limit, actual: try current().limit)
    }

    /// PowerUIAgent's preferences as they are, for the log.
    static func preferencesSummary(keys wanted: Set<String>) -> String {
        var parts: [String] = []
        for (name, host) in [("any host", kCFPreferencesAnyHost), ("this host", kCFPreferencesCurrentHost)] {
            guard let keys = CFPreferencesCopyKeyList(preferencesDomain, kCFPreferencesCurrentUser, host) as? [String]
            else { continue }
            let values = keys.filter(wanted.contains).sorted().map { key -> String in
                let value = CFPreferencesCopyValue(key as CFString, preferencesDomain, kCFPreferencesCurrentUser, host)
                let text = value.map { "\($0)" } ?? "nil"
                let type = value.map { String(describing: Swift.type(of: $0)) } ?? "-"
                return "\(key)=\(text.count > 60 ? String(text.prefix(60)) + "…" : text) (\(type))"
            }
            parts.append("\(name): " + values.joined(separator: ", "))
        }
        return parts.isEmpty ? "none readable" : parts.joined(separator: " | ")
    }

    /// Writes where PowerUIAgent already keeps the key; any host otherwise, like `defaults write`.
    private static var preferencesHost: CFString {
        let existing = CFPreferencesCopyValue(
            limitKey, preferencesDomain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return existing == nil ? kCFPreferencesAnyHost : kCFPreferencesCurrentHost
    }

    private func setThroughAPI(_ limit: Int) throws {
        let value = UInt8(
            min(max(limit, ChargePolicy.macOSLimitRange.lowerBound), ChargePolicy.macOSLimitRange.upperBound))
        var error: NSError?
        let ok = Self.function(client, "setMCLLimit:error:", SetFunction.self)(
            client, Selector(("setMCLLimit:error:")), value, &error)
        guard ok else { throw LimitError.rejected("setMCLLimit(\(value))", error) }
        if try !current().isEnabled { try call("enableMCL:") }
    }

    private func call(_ selector: String) throws {
        var error: NSError?
        guard Self.function(client, selector, ActionFunction.self)(client, Selector(selector), &error) else {
            throw LimitError.rejected(selector, error)
        }
    }

    private static func function<T>(_ object: AnyObject, _ selector: String, _ type: T.Type) -> T {
        unsafeBitCast(class_getMethodImplementation(object_getClass(object), Selector(selector)), to: type)
    }
}
