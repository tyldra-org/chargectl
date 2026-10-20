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
