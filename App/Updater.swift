import AppKit
import CryptoKit
import Observation

/// Keeps Chargectl up to date from its GitHub releases. Checks a minute after launch and then
/// every few hours; with automatic updates on, installs a new version once no Chargectl window
/// is open. The helper notices the replaced app, restarts into its own new version and reopens
/// the app.
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
    /// Set by AppModel: whether the helper is running, so it can reopen the app after an update.
    @ObservationIgnored var helperIsRunning: () -> Bool = { false }
    @ObservationIgnored private var release: AppRelease?
    @ObservationIgnored private var loop: Task<Void, Never>?

    static var isAutomatic: Bool {
        UserDefaults.standard.object(forKey: PreferenceKey.autoUpdate) as? Bool ?? true
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
        guard Self.isAutomatic, case .available = phase, !Dashboard.isShowingWindow else { return }
        await installAvailable()
    }

    func check() async {
        guard !isBusy else { return }
        phase = .checking
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
        guard let app = Self.replaceableApp else {
            phase = .failed("Chargectl updates itself only when it is in the Applications folder.")
            return
        }
        phase = .installing(release.version)
        do {
            try await Self.replace(app, with: release)
        } catch {
            phase = .failed("The update to \(release.version) failed: \(error.localizedDescription)")
            return
        }
        // The helper stops this copy and opens the new one within seconds; without a helper, or
        // if it does not, the app reopens itself.
        let delay: Duration = helperIsRunning() ? .seconds(30) : .zero
        try? await Task.sleep(for: delay)
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
