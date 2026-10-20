import Foundation

nonisolated enum DaemonIdentity {
    static let machService = "com.tyldra.chargectl.daemon"
    static let plistName = "com.tyldra.chargectl.daemon.plist"
    static let version = "0.1.0"
    /// Clients must be the Chargectl app. Ad-hoc builds can only pin the identifier;
    /// add the team anchor once the app is signed with a Developer ID.
    static let clientRequirement = #"identifier "com.tyldra.chargectl""#
}

nonisolated enum DaemonCommand: String, Codable, CaseIterable, Sendable {
    case topUp
    case discharge
    case calibrate
    case stop
    case reset
    /// Restore charging and delete the daemon's data, before the app unregisters it.
    case uninstall
    /// Restore charging and stop the service, keeping its data.
    case removeService
}

/// XPC surface of the root daemon. Payloads are JSON so both sides share Codable types.
@objc protocol ChargeDaemonProtocol {
    func status(reply: @escaping @Sendable (Data) -> Void)
    func updateSettings(_ settings: Data, reply: @escaping @Sendable (String?) -> Void)
    func perform(_ command: String, reply: @escaping @Sendable (String?) -> Void)
    func history(reply: @escaping @Sendable (Data) -> Void)
    func logs(reply: @escaping @Sendable (Data) -> Void)
}
