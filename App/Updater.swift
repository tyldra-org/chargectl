import AppKit
import CryptoKit
import Observation

/// Keeps Chargectl up to date from its GitHub releases. Checks a minute after launch and then
/// every few hours; with automatic updates on, or after Later in the dashboard's update prompt,
/// installs a new version once no Chargectl window is open. The helper notices the replaced app,
/// restarts into its own new version and reopens the app.
@Observable
final class Updater {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case installing(String)
        case failed(String)
    }

    static let shared = Updater()
    private static let checkInterval: TimeInterval = 6 * 60 * 60
    /// How often a pending automatic install looks for a moment with no window open.
    private static let retryInterval = Duration.seconds(10 * 60)

    private(set) var phase = Phase.idle
    private(set) var lastChecked: Date?
    /// The version put off with Later in the update prompt. It installs once no Chargectl window is
    /// open. Kept in memory only, so the prompt shows again if Chargectl quits before that.
    private(set) var postponed: String?
    /// The version whose install failed, and why, for the update prompt to say so.
    private(set) var failure: (version: String, reason: String)?
    @ObservationIgnored private var release: AppRelease?
    @ObservationIgnored private var loop: Task<Void, Never>?

    static var isAutomatic: Bool {
        UserDefaults.standard.object(forKey: PreferenceKey.autoUpdate) as? Bool ?? true
    }

    /// The version the dashboard's update prompt offers: a new one, one installing, or one whose
    /// install just failed, unless it was put off with Later.
    var promptVersion: String? {
        let version: String? =
            switch phase {
            case .available(let version), .installing(let version): version
            case .failed: failure?.version
            default: nil
            }
        guard let version, version != postponed else { return nil }
        return version
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .installing: true
        default: false
        }
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            while !Task.isCancelled {
                await self?.runScheduled()
                try? await Task.sleep(for: Self.retryInterval)
            }
        }
    }

    private func runScheduled() async {
        if lastChecked.map({ Date.now.timeIntervalSince($0) >= Self.checkInterval }) ?? true { await check() }
        guard Self.isAutomatic || postponed != nil, case .available = phase, !Dashboard.isShowingWindow else { return }
        await installAvailable()
    }

    /// Later in the update prompt: hides it for this version, which then installs once the
    /// dashboard is closed.
    func postpone() {
        guard let version = promptVersion else { return }
        postponed = version
        Confirmations.shared.show("Updates when you close this window")
    }

    /// Installs a version put off with Later, now that no Chargectl window is open.
    func installPostponed() async {
        guard postponed != nil, case .available = phase, !Dashboard.isShowingWindow else { return }
        await installAvailable()
    }

    /// Says "Updated to …" in the status island the first time the dashboard opens on a newer
    /// version, after an update from here or from Homebrew.
    static func announceNewVersion() {
        guard !Setup.isDemo else { return }
        let defaults = UserDefaults.standard
        let current = DaemonIdentity.version
        let last = defaults.string(forKey: PreferenceKey.lastDashboardVersion)
        defaults.set(current, forKey: PreferenceKey.lastDashboardVersion)
        if let last, AppRelease.isNewer(current, than: last) { Confirmations.shared.show("Updated to \(current)") }
    }

    func check() async {
        guard !isBusy else { return }
        phase = .checking
        failure = nil
        do {
            var request = URLRequest(url: AppRelease.feed)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, let latest = AppRelease.parse(data) else {
                throw UpdateError.noRelease
            }
            lastChecked = .now
            if AppRelease.isNewer(latest.version, than: DaemonIdentity.version) {
                release = latest
                phase = .available(latest.version)
            } else {
                release = nil
                phase = .upToDate
            }
        } catch {
            phase = .failed("Could not check for updates: \(error.localizedDescription)")
        }
    }

    func installAvailable() async {
        guard let release, !isBusy else { return }
        failure = nil
        guard let app = Self.replaceableApp else {
            let reason = "Chargectl updates itself only when it is in the Applications folder."
            failure = (release.version, reason)
            phase = .failed(reason)
            return
        }
        phase = .installing(release.version)
        do {
            try await Self.replace(app, with: release)
        } catch {
            failure = (release.version, error.localizedDescription)
            phase = .failed("The update to \(release.version) failed: \(error.localizedDescription)")
            return
        }
        // The new copy starts right away; the helper then restarts into its own new version and
        // leaves an app started after the update alone.
        Self.relaunch(app)
    }

    /// The running app, when it can replace itself: in Applications and writable by this user.
    private static var replaceableApp: URL? {
        let app = Bundle.main.bundleURL
        let files = FileManager.default
        guard app.path.hasPrefix("/Applications/"), files.isWritableFile(atPath: app.path),
            files.isWritableFile(atPath: app.deletingLastPathComponent().path)
        else { return nil }
        return app
    }

    /// Downloads the release, checks it against its published SHA-256, its code signature, bundle
    /// identifier and version, then swaps it in for the installed app in one step.
    nonisolated private static func replace(_ app: URL, with release: AppRelease) async throws {
        let files = FileManager.default
        let staging = try files.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        defer { try? files.removeItem(at: staging) }

        let (download, response) = try await URLSession.shared.download(from: release.archive)
        let zip = staging.appendingPathComponent("Chargectl.zip")
        try files.moveItem(at: download, to: zip)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.download }
        let (checksum, checksumResponse) = try await URLSession.shared.data(from: release.checksum)
        guard (checksumResponse as? HTTPURLResponse)?.statusCode == 200,
            let expected = String(decoding: checksum, as: UTF8.self).split(separator: " ").first
        else { throw UpdateError.download }
        let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard actual == expected.lowercased() else { throw UpdateError.checksum }

        try run("/usr/bin/ditto", "-x", "-k", zip.path, staging.path)
        let new = staging.appendingPathComponent("Chargectl.app")
        try run("/usr/bin/codesign", "--verify", "--deep", "--strict", new.path)
        // Releases signed with Chargectl's own certificate must be signed with that one.
        if let requirement = DaemonIdentity.requirement(identifier: DaemonIdentity.appIdentifier) {
            try run("/usr/bin/codesign", "--verify", "--deep", "--strict", "-R=\(requirement)", new.path)
        }
        let info = NSDictionary(contentsOf: new.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == DaemonIdentity.appIdentifier,
            info?["CFBundleShortVersionString"] as? String == release.version
        else { throw UpdateError.wrongApp }
        try? run("/usr/bin/xattr", "-dr", "com.apple.quarantine", new.path)
        _ = try files.replaceItemAt(app, withItemAt: new)
    }

    nonisolated private static func run(_ tool: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.tool((tool as NSString).lastPathComponent) }
    }

    private static func relaunch(_ app: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; exec /usr/bin/open -g \"$0\"", app.path]
        try? process.run()
        exit(0)
    }
}

#if DEBUG
    extension Updater {
        /// The version after this one, for sample prompts.
        static var sampleVersion: String {
            var parts = DaemonIdentity.version.split(separator: ".").map { Int($0) ?? 0 }
            if parts.isEmpty { parts = [0] }
            parts[parts.count - 1] += 1
            return parts.map(String.init).joined(separator: ".")
        }

        /// Shows a phase without checking GitHub, for design renders and --update-available.
        func preview(_ phase: Phase, failure: (version: String, reason: String)? = nil) {
            self.phase = phase
            self.failure = failure
            postponed = nil
        }
    }
#endif

enum UpdateError: LocalizedError {
    case noRelease
    case download
    case checksum
    case wrongApp
    case tool(String)

    var errorDescription: String? {
        switch self {
        case .noRelease: "GitHub did not return a release."
        case .download: "The download failed."
        case .checksum: "The download did not match its checksum."
        case .wrongApp: "The download is not the expected Chargectl version."
        case .tool(let name): "\(name) failed."
        }
    }
}
