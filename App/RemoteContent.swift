import AppKit
import Foundation
import Observation

/// The remote config in use: the last copy whose signature checked out, kept on disk so its
/// prompts show right after a restart or an update, and refreshed with every update check.
@Observable
final class RemoteContent {
    static let shared = RemoteContent()

    private(set) var config: RemoteConfig = .empty
    /// The Mac as the conditions see it: version, Homebrew taps, how Chargectl was installed.
    private(set) var context = RemoteContent.currentContext()
    /// Put away with Later; they show again when Chargectl next starts.
    private var hiddenThisLaunch: Set<String> = []
    /// Put away with Done, for good.
    private var done = Set(UserDefaults.standard.stringArray(forKey: PreferenceKey.remoteDone) ?? [])

    private init() {
        if let cached = Self.loadCache() { config = cached }
    }

    /// The prompt to show in the middle of the dashboard, if any.
    var prompt: RemoteConfig.Item? { visible(.prompt).first }
    /// Banners for the top of the dashboard.
    var banners: [RemoteConfig.Item] { visible(.banner) }

    func flag(_ name: String, default fallback: Bool) -> Bool {
        config.flag(name, default: fallback, context: context)
    }

    func value(_ name: String, default fallback: Double) -> Double {
        config.value(name, default: fallback, context: context)
    }

    private func visible(_ placement: RemoteConfig.Item.Placement) -> [RemoteConfig.Item] {
        config.items(for: context, placement: placement).filter {
            !done.contains($0.id) && !hiddenThisLaunch.contains($0.id)
        }
    }

    func later(_ item: RemoteConfig.Item) {
        hiddenThisLaunch.insert(item.id)
    }

    func finish(_ item: RemoteConfig.Item) {
        done.insert(item.id)
        UserDefaults.standard.set(Array(done).sorted(), forKey: PreferenceKey.remoteDone)
    }

    /// Reads the Mac again, so an item goes away once its conditions stop holding, like a prompt
    /// to move taps once the user has moved.
    func recheck() {
        context = Self.currentContext()
    }

    /// Downloads the file and its signature, and uses them only when the signature checks out.
    func refresh() async {
        defer { recheck() }
        do {
            let data = try await Self.download(RemoteConfigFeed.url)
            let signature = try await Self.download(RemoteConfigFeed.signatureURL)
            guard let verified = RemoteConfigFeed.verify(data, signature: signature) else { return }
            config = verified
            Self.saveCache(data, signature: signature)
        } catch {
            // Offline or GitHub unreachable: keep the copy in use.
        }
    }

    private static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    private static func currentContext() -> RemoteConfig.Context {
        RemoteConfig.Context(
            version: DaemonIdentity.version, taps: RemoteConfigFeed.installedTaps(),
            installedFrom: RemoteConfigFeed.installedFrom(), homebrew: RemoteConfigFeed.installedWithHomebrew(),
            now: .now)
    }

    private static var cacheFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Chargectl/Remote", isDirectory: true)
    }

    /// The saved copy, checked against its signature again, since the file could have changed on disk.
    private static func loadCache() -> RemoteConfig? {
        guard let folder = cacheFolder,
            let data = try? Data(contentsOf: folder.appendingPathComponent("app.json")),
            let signature = try? Data(contentsOf: folder.appendingPathComponent("app.json.sig"))
        else { return nil }
        return RemoteConfigFeed.verify(data, signature: signature)
    }

    private static func saveCache(_ data: Data, signature: Data) {
        guard let folder = cacheFolder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent("app.json"), options: .atomic)
        try? signature.write(to: folder.appendingPathComponent("app.json.sig"), options: .atomic)
    }
}

#if DEBUG
    extension RemoteContent {
        /// Fixed content for rendering the design.
        func preview(_ config: RemoteConfig, taps: Set<String> = []) {
            self.config = config
            context = RemoteConfig.Context(
                version: DaemonIdentity.version, taps: taps, installedFrom: taps.first, homebrew: true, now: .now)
            hiddenThisLaunch = []
            done = []
        }
    }
#endif
