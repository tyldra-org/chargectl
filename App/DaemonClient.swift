import Foundation
import Synchronization

enum DaemonClientError: LocalizedError {
    case unavailable(String)
    case timedOut
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "The helper is not reachable: \(reason)"
        case .timedOut: "The helper did not answer."
        case .rejected(let message): message
        }
    }
}

/// Talks to chargectld over XPC. One connection is reused until it is invalidated.
final class DaemonClient {
    private static let timeout = Duration.seconds(4)
    private var connection: NSXPCConnection?

    func status() async throws -> DaemonStatus {
        let data: Data = try await call { $0.status(reply: $1) }
        return try Coding.decode(DaemonStatus.self, from: data)
    }

    func history() async throws -> [HistorySample] {
        let data: Data = try await call { $0.history(reply: $1) }
        return try Coding.decode([HistorySample].self, from: data)
    }

    func logs() async throws -> [LogEntry] {
        let data: Data = try await call { $0.logs(reply: $1) }
        return try Coding.decode([LogEntry].self, from: data)
    }

    func update(_ settings: ChargeSettings) async throws {
        let payload = Coding.encode(settings)
        let message: String? = try await call { $0.updateSettings(payload, reply: $1) }
        if let message { throw DaemonClientError.rejected(message) }
    }

    func perform(_ command: DaemonCommand) async throws {
        let message: String? = try await call { $0.perform(command.rawValue, reply: $1) }
        if let message { throw DaemonClientError.rejected(message) }
    }

    private func call<Value: Sendable>(
        _ send: (any ChargeDaemonProtocol, @escaping @Sendable (Value) -> Void) -> Void
    ) async throws -> Value {
        let connection = currentConnection()
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.resume(throwing: DaemonClientError.unavailable(error.localizedDescription))
            }
            guard let daemon = proxy as? any ChargeDaemonProtocol else {
                once.resume(throwing: DaemonClientError.unavailable("unexpected proxy"))
                return
            }
            Task {
                try? await Task.sleep(for: Self.timeout)
                once.resume(throwing: DaemonClientError.timedOut)
            }
            send(daemon) { once.resume(returning: $0) }
        }
    }

    private func currentConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: DaemonIdentity.machService, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: (any ChargeDaemonProtocol).self)
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}

/// Resumes a continuation exactly once: the reply, the XPC error and the timeout race.
nonisolated final class ResumeOnce<Value: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<Value, any Error>?>

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        self.continuation = Mutex(continuation)
    }

    func resume(returning value: Value) {
        continuation.withLock { $0.take() }?.resume(returning: value)
    }

    func resume(throwing error: any Error) {
        continuation.withLock { $0.take() }?.resume(throwing: error)
    }
}
