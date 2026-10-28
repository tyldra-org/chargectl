import Foundation

/// The latest published Chargectl release, read from GitHub's releases API.
nonisolated struct AppRelease: Equatable, Sendable {
    var version: String
    /// Chargectl-<version>.zip
    var archive: URL
    /// Chargectl-<version>.zip.sha256
    var checksum: URL

    static let feed = URL(string: "https://api.github.com/repos/tyldra-org/chargectl/releases/latest")!

    /// nil for a draft or prerelease, a tag that is not vMAJOR.MINOR.PATCH, or a release without
    /// its zip and checksum.
    static func parse(_ data: Data) -> AppRelease? {
        nonisolated struct Payload: Decodable {
            nonisolated struct Asset: Decodable {
                var name: String
                var browserDownloadUrl: URL
            }
            var tagName: String
            var draft: Bool
            var prerelease: Bool
            var assets: [Asset]
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let payload = try? decoder.decode(Payload.self, from: data), !payload.draft, !payload.prerelease,
            payload.tagName.hasPrefix("v")
        else { return nil }
        let version = String(payload.tagName.dropFirst())
        guard components(version) != nil else { return nil }
        let zip = "Chargectl-\(version).zip"
        guard let archive = payload.assets.first(where: { $0.name == zip })?.browserDownloadUrl,
            let checksum = payload.assets.first(where: { $0.name == zip + ".sha256" })?.browserDownloadUrl
        else { return nil }
        return AppRelease(version: version, archive: archive, checksum: checksum)
    }

    /// Compares MAJOR.MINOR.PATCH numerically; false when either is not in that form.
    static func isNewer(_ version: String, than installed: String) -> Bool {
        guard let new = components(version), let old = components(installed) else { return false }
        return new.lexicographicallyPrecedes(old) == false && new != old
    }

    static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        return parts.compactMap { $0 }
    }
}
