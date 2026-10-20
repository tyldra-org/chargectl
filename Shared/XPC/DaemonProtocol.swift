import Foundation

nonisolated enum DaemonIdentity {
    static let machService = "com.tyldra.chargectl.daemon"
    static let plistName = "com.tyldra.chargectl.daemon.plist"
    static let version = "0.1.0"
    static let appIdentifier = "com.tyldra.chargectl"

    /// Clients must be the Chargectl app. When the service is signed with a team (Apple
    /// Development or Developer ID), the app must be signed by the same team; ad-hoc builds can
    /// only pin the identifier.
    static func clientRequirement(team: String?) -> String {
        guard let team else { return "identifier \"\(appIdentifier)\"" }
        return "anchor apple generic and identifier \"\(appIdentifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
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
