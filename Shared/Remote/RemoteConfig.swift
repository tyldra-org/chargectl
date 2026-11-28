import CryptoKit
import Foundation

/// What the maintainers can change in Chargectl without a release: prompts and banners built from
/// blocks the app already has, feature flags and tunable values. It is read from a signed file in
/// the repository (`feed/app.json`), and only text, links and fixed actions travel in it; nothing in
/// it runs. A file whose signature doesn't check out is ignored.
nonisolated struct RemoteConfig: Codable, Equatable, Sendable {
    var items: [Item]
    /// Features shipped switched off, or to switch off: name to state.
    var flags: [String: Flag]?
    /// Numbers the app reads instead of a built-in default: name to value.
    var values: [String: Value]?

    static let empty = RemoteConfig(items: [])

    /// A prompt or a banner.
    nonisolated struct Item: Codable, Equatable, Sendable, Identifiable {
        enum Placement: String, Codable, Sendable {
            /// In the middle of the dashboard, like the update prompt.
            case prompt
            /// At the top of every dashboard page.
            case banner
        }

        enum Tone: String, Codable, Sendable { case info, warning }

        enum Dismissal: String, Codable, Sendable {
            /// Later hides it until Chargectl starts again.
            case later
            /// Done hides it for good.
            case done
        }

        var id: String
        var placement: Placement
        var tone: Tone?
        /// An SF Symbol name.
        var symbol: String?
        var title: String
        var body: String
        /// Shown in a block with a Copy button.
        var commands: [String]?
        /// Opened by the primary button, when there are no commands to copy.
        var link: URL?
        var linkTitle: String?
        var dismissal: Dismissal?
        var when: Conditions?
        /// Not shown after this moment.
        var until: Date?
    }

    /// Who sees an item or gets a flag. Every condition given must hold.
    nonisolated struct Conditions: Codable, Equatable, Sendable {
        /// Only below this version.
        var below: String?
        /// Only from this version on.
        var atLeast: String?
        /// Only while this Homebrew tap is tapped, like "tyldra-org/tools".
        var tapped: String?
        /// Only when Homebrew installed this copy from this tap.
        var installedFrom: String?
        /// Only when Chargectl was installed with Homebrew (true) or downloaded (false).
        var homebrew: Bool?
    }

    nonisolated struct Flag: Codable, Equatable, Sendable {
        var on: Bool
        var when: Conditions?
    }

    nonisolated struct Value: Codable, Equatable, Sendable {
        var number: Double
        var when: Conditions?
    }

    /// What the conditions are checked against.
    nonisolated struct Context: Equatable, Sendable {
        var version: String
        var taps: Set<String>
        /// The tap Homebrew installed this copy from; nil when it didn't.
        var installedFrom: String?
        var homebrew: Bool
        var now: Date
    }

    func items(for context: Context, placement: Item.Placement) -> [Item] {
        items.filter { $0.placement == placement && $0.applies(to: context) }
    }

    func flag(_ name: String, default fallback: Bool, context: Context) -> Bool {
        guard let flag = flags?[name], flag.when?.hold(for: context) ?? true else { return fallback }
        return flag.on
    }

    func value(_ name: String, default fallback: Double, context: Context) -> Double {
        guard let value = values?[name], value.when?.hold(for: context) ?? true else { return fallback }
        return value.number
    }
}

extension RemoteConfig.Item {
    /// The link, when it is a web page; anything else is never opened.
    nonisolated var webLink: URL? { link?.scheme == "https" ? link : nil }

    nonisolated func applies(to context: RemoteConfig.Context) -> Bool {
        if let until, context.now >= until { return false }
        return when?.hold(for: context) ?? true
    }
}

extension RemoteConfig.Conditions {
    nonisolated func hold(for context: RemoteConfig.Context) -> Bool {
        if let below, !AppRelease.isNewer(below, than: context.version) { return false }
        if let atLeast, AppRelease.isNewer(atLeast, than: context.version) { return false }
        if let tapped, !context.taps.contains(tapped) { return false }
        if let installedFrom, installedFrom != context.installedFrom { return false }
        if let homebrew, homebrew != context.homebrew { return false }
        return true
    }
}

/// Where the file lives and how its signature is checked.
nonisolated enum RemoteConfigFeed {
    static let url = URL(string: "https://raw.githubusercontent.com/tyldra/chargectl/main/feed/app.json")!
    static let signatureURL = URL(string: "https://raw.githubusercontent.com/tyldra/chargectl/main/feed/app.json.sig")!
    /// The Ed25519 key the file is signed with, raw and base64. Its private half stays in the
    /// maintainer's login Keychain (scripts/remote-config.swift).
    static let publicKey = "jusA1wLM8uN1Z3bAOo5xEKMrNEuS3vtEXqr9LCXBih0="

    /// The file's contents when `signature` (base64 text) is `key`'s signature of exactly these
    /// bytes; nil otherwise.
    static func verify(_ data: Data, signature: Data, key: String = publicKey) -> RemoteConfig? {
        guard let keyData = Data(base64Encoded: key),
            let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
            let text = String(data: signature, encoding: .utf8),
            let signatureData = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            publicKey.isValidSignature(signatureData, for: data)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RemoteConfig.self, from: data)
    }

    /// The Homebrew taps on this Mac, like "tyldra/tools", read from Homebrew's folders.
    static func installedTaps() -> Set<String> {
        var taps: Set<String> = []
        let files = FileManager.default
        for root in ["/opt/homebrew/Library/Taps", "/usr/local/Homebrew/Library/Taps"] {
            for user in (try? files.contentsOfDirectory(atPath: root)) ?? [] {
                for repository in (try? files.contentsOfDirectory(atPath: root + "/" + user)) ?? []
                where repository.hasPrefix("homebrew-") {
                    taps.insert(user + "/" + repository.dropFirst("homebrew-".count))
                }
            }
        }
        return taps
    }

    /// Whether this copy came from Homebrew: it keeps a folder for the cask.
    static func installedWithHomebrew() -> Bool {
        caskrooms.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// The tap Homebrew installed the cask from, read from its install receipt.
    static func installedFrom() -> String? {
        for room in caskrooms {
            let receipt = URL(fileURLWithPath: room + "/.metadata/INSTALL_RECEIPT.json")
            if let data = try? Data(contentsOf: receipt) { return tap(inReceipt: data) }
        }
        return nil
    }

    /// `source.tap` of a Homebrew install receipt.
    static func tap(inReceipt data: Data) -> String? {
        struct Receipt: Decodable {
            struct Source: Decodable { var tap: String? }
            var source: Source?
        }
        return (try? JSONDecoder().decode(Receipt.self, from: data))?.source?.tap
    }

    private static let caskrooms = ["/opt/homebrew/Caskroom/chargectl", "/usr/local/Caskroom/chargectl"]
}
