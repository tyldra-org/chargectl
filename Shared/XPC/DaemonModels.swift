import Foundation

nonisolated struct DaemonStatus: Codable, Equatable, Sendable {
    var version: String
    var settings: ChargeSettings
    var mode: ChargeMode
    var activity: ChargeActivity
    var adapterEnabled: Bool
    /// The SMC key used to switch wall power, or nil when this Mac has none.
    var adapterKey: String?
    var lastError: String?
    /// Optimized Battery Charging can hold or delay charging on its own.
    var optimizedChargingEnabled: Bool? = nil
    /// Set when charge control is not having its effect (ControlCheck).
    var controlProblem: String? = nil
    /// The Full by time that was skipped or stopped, while it is still ahead. Helpers before 0.2.4
    /// do not send it.
    var skippedFullBy: Date? = nil
    /// The smart limit's level and what it learned. Helpers before 0.3.0 do not send it.
    var smartLimit: SmartLimit.Status? = nil
}

nonisolated struct HistorySample: Codable, Equatable, Sendable {
    var date: Date
    var percent: Int
    /// °C
    var temperature: Double?
    /// W
    var systemPower: Double?
    /// W
    var wallPower: Double?
    /// W, positive while charging.
    var batteryPower: Double?
    /// The charger is connected, also while wall power is cut. Helpers before 0.3.0 leave it out.
    var pluggedIn: Bool? = nil

    /// Samples further apart than this have nothing recorded between them: Chargectl was quit, which
    /// stops the helper, or the Mac slept without waking. The helper records once a minute while the
    /// Mac is awake, and a sleeping Mac wakes to record about every 15 minutes.
    static let maximumSpacing: TimeInterval = 20 * 60
}

extension [HistorySample] {
    /// For each sample, in date order, the number of the unbroken run it belongs to. Charts draw each
    /// run as its own line, so a gap in the recording shows as a gap, not a straight line across it.
    nonisolated var runs: [Int] {
        var run = 0
        return indices.map { index in
            if index > 0, self[index].date.timeIntervalSince(self[index - 1].date) > HistorySample.maximumSpacing {
                run += 1
            }
            return run
        }
    }

    /// A value at `date`, read along the line between the samples around it, so a marker can follow the
    /// pointer smoothly. Nil when nothing was recorded then. Samples must be in date order.
    nonisolated func value(at date: Date, _ read: (HistorySample) -> Double?) -> Double? {
        guard let nearest = sample(near: date) else { return nil }
        let after = firstIndex { $0.date >= date }
        guard let after, after > 0 else { return read(nearest) }
        let (a, b) = (self[after - 1], self[after])
        let span = b.date.timeIntervalSince(a.date)
        guard span > 0, span <= HistorySample.maximumSpacing, let va = read(a), let vb = read(b) else {
            return read(nearest)
        }
        return va + (vb - va) * date.timeIntervalSince(a.date) / span
    }

    /// The sample recorded closest to `date`, or nil when nothing was recorded near it. Samples must be
    /// in date order.
    nonisolated func sample(near date: Date) -> HistorySample? {
        var low = 0
        var high = count
        while low < high {
            let middle = (low + high) / 2
            if self[middle].date < date { low = middle + 1 } else { high = middle }
        }
        let nearest = [low - 1, low].filter { indices.contains($0) }.min {
            abs(self[$0].date.timeIntervalSince(date)) < abs(self[$1].date.timeIntervalSince(date))
        }
        guard let nearest, abs(self[nearest].date.timeIntervalSince(date)) <= HistorySample.maximumSpacing / 2 else {
            return nil
        }
        return self[nearest]
    }
}

nonisolated struct LogEntry: Codable, Equatable, Identifiable, Sendable {
    nonisolated enum Level: String, Codable, Sendable {
        case info
        case warning
    }

    nonisolated enum Source: String, Codable, Sendable {
        /// Measured from the hardware: what actually happened.
        case observed
        /// Chargectl's own decision or action.
        case chargectl
    }

    var id = UUID()
    var date: Date
    var level: Level
    var message: String
    var percent: Int?
    var source: Source?
}

nonisolated enum Coding {
    static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Encoding these value types cannot fail.
        return (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
