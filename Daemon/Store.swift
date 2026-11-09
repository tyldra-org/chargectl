import Foundation
import os

/// JSON files under /Library/Application Support/Chargectl, owned by root.
///
/// Settings and state are small and saved whole. History and logs grow by one entry at a time, so
/// they are kept one JSON object per line: recording an entry appends a line instead of rewriting
/// the file.
struct Store {
    enum File: String {
        case settings
        case state
        case history
        case logs
        case macOSLimit
        case daily
    }

    static let system = Store(
        directory: URL(fileURLWithPath: "/Library/Application Support/Chargectl", isDirectory: true))

    let directory: URL
    private let logger = Logger(subsystem: "com.tyldra.chargectl", category: "store")

    init(directory: URL) {
        self.directory = directory
    }

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

    // MARK: Lines

    /// Every entry of a line file, oldest first. Versions before 0.1.11 kept the list as one JSON
    /// array; those entries come first. A line cut short by a crash is skipped.
    func loadLines<Value: Decodable>(_ type: Value.Type, from file: File) -> [Value] {
        var values = load([Value].self, from: file) ?? []
        guard let data = try? Data(contentsOf: linesURL(for: file)) else { return values }
        for line in data.split(separator: UInt8(ascii: "\n")) {
            if let value = try? Coding.decode(type, from: Data(line)) { values.append(value) }
        }
        return values
    }

    /// Adds one entry to the end of a line file.
    func append<Value: Encodable>(_ value: Value, to file: File) {
        let url = linesURL(for: file)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Coding.encode(value) + Data("\n".utf8))
        } catch {
            logger.error("could not append to \(file.rawValue, privacy: .public): \(error, privacy: .public)")
        }
    }

    /// Writes a line file from scratch, dropping entries that were trimmed and any line cut short,
    /// and moves an old JSON array file over to lines.
    func replaceLines<Value: Encodable>(_ values: [Value], in file: File) {
        var data = Data()
        for value in values { data += Coding.encode(value) + Data("\n".utf8) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: linesURL(for: file), options: .atomic)
            remove(file)
        } catch {
            logger.error("could not rewrite \(file.rawValue, privacy: .public): \(error, privacy: .public)")
        }
    }

    private func url(for file: File) -> URL {
        directory.appendingPathComponent("\(file.rawValue).json")
    }

    private func linesURL(for file: File) -> URL {
        directory.appendingPathComponent("\(file.rawValue).jsonl")
    }
}
