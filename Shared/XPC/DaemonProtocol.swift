import Foundation

nonisolated enum DaemonIdentity {
    static let machService = "com.tyldra.chargectl.daemon"
    static let plistName = "com.tyldra.chargectl.daemon.plist"
    /// MARKETING_VERSION, from the app's Info.plist or the one embedded in the service's binary.
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    static let appIdentifier = "com.tyldra.chargectl"
    /// The first helper with the daily record (dailyHistory).
    static let dailyHistorySince = "0.2.0"

    /// Whether a helper of this version has the daily record. An older helper does not answer the
    /// call, so it is not made.
    static func hasDailyHistory(_ version: String) -> Bool {
        AppRelease.components(version) != nil && !AppRelease.isNewer(dailyHistorySince, than: version)
    }
    /// The helper's code-signing identifier.
    static let serviceIdentifier = "com.tyldra.chargectl.daemon"
    /// The widget extension's, which asks the helper for its status and runs widget buttons.
    static let widgetsIdentifier = "com.tyldra.chargectl.widgets"
    private static let clients = "(identifier \"\(appIdentifier)\" or identifier \"\(widgetsIdentifier)\")"

    /// SHA-1 of the certificate releases are signed with when there is no Apple team, set at build
    /// time from CHARGECTL_RELEASE_CERT (scripts/make-release-certificate.sh); nil for builds
    /// signed ad hoc or with a team.
    static let releaseCertificate = (Bundle.main.object(forInfoDictionaryKey: "ChargectlReleaseCertificate") as? String)
        .flatMap(validCertificate)

    /// Clients must be the Chargectl app or its widgets. When the service is signed with a team
    /// (Apple Development or Developer ID), they must be signed by the same team; with Chargectl's
    /// release certificate, by that certificate. Ad-hoc builds can only pin the identifiers.
    static func clientRequirement(team: String?, certificate: String? = releaseCertificate) -> String {
        if let team {
            return "anchor apple generic and \(clients) and certificate leaf[subject.OU] = \"\(team)\""
        }
        if let certificate = certificate.flatMap(validCertificate) {
            return "\(clients) and certificate leaf = H\"\(certificate)\""
        }
        return clients
    }

    /// Code with this identifier, signed with the release certificate; nil without one.
    static func requirement(identifier: String, certificate: String? = releaseCertificate) -> String? {
        certificate.flatMap(validCertificate).map { "identifier \"\(identifier)\" and certificate leaf = H\"\($0)\"" }
    }

    /// A SHA-1 as 40 hex digits, upper-cased; anything else is ignored rather than spliced into a
    /// code requirement.
    static func validCertificate(_ text: String) -> String? {
        let hex = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard hex.count == 40, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex
    }
}

nonisolated enum DaemonCommand: String, Codable, CaseIterable, Sendable {
    case topUp
    case discharge
    case calibrate
    case stop
    case reset
    /// Skip the next Full by time, or stop the one charging now.
    case skipFullBy
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
    /// One sample a day, oldest first (DailySample). Helpers before 0.1.11 do not have it.
    func dailyHistory(reply: @escaping @Sendable (Data) -> Void)
}
