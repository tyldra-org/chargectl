import Foundation
import os

/// JSON files under /Library/Application Support/Chargectl, owned by root.
struct Store {
    enum File: String {
        case settings
        case state
        case history
        case logs
        case macOSLimit
    }

    static let system = Store(
        directory: URL(fileURLWithPath: "/Library/Application Support/Chargectl", isDirectory: true))

    let directory: URL
    private let logger = Logger(subsystem: "com.tyldra.chargectl", category: "store")

    func load<Value: Decodable>(_ type: Value.Type, from file: File) -> Value? {
        let url = url(for: file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try Coding.decode(type, from: data)
        } catch {
            logger.error("ignoring unreadable \(url.path, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    func save<Value: Encodable>(_ value: Value, to file: File) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Coding.encode(value).write(to: url(for: file), options: .atomic)
        } catch {
            logger.error("could not save \(file.rawValue, privacy: .public): \(error, privacy: .public)")
        }
    }

    func remove(_ file: File) {
        try? FileManager.default.removeItem(at: url(for: file))
    }

    func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private func url(for file: File) -> URL {
        directory.appendingPathComponent("\(file.rawValue).json")
    }
}
