import Darwin
import Foundation

/// The per-user cache and temporary folders under /private/var/folders. Frameworks such as
/// Metal and URLCache put a com.tyldra.chargectl folder there for each process's user.
nonisolated enum DarwinDirectories {
    static var cache: URL? { url(_CS_DARWIN_USER_CACHE_DIR) }
    static var temporary: URL? { url(_CS_DARWIN_USER_TEMP_DIR) }

    /// Deletes every entry starting with prefix in the calling user's cache and temporary folders.
    static func removeEntries(withPrefix prefix: String) {
        let files = FileManager.default
        for directory in [cache, temporary].compactMap({ $0 }) {
            for name in (try? files.contentsOfDirectory(atPath: directory.path)) ?? [] where name.hasPrefix(prefix) {
                try? files.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    private static func url(_ name: Int32) -> URL? {
        let size = confstr(name, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard confstr(name, &buffer, size) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
