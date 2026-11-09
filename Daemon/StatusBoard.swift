import Foundation
import Synchronization

/// The answers to the app's status, history and log requests, kept current by the controller.
/// The XPC service reads them on its own queue, so the app keeps getting answers while the main
/// thread waits on PowerUIAgent, which can take a minute to answer after the Mac starts.
nonisolated final class StatusBoard: Sendable {
    private struct Contents: Sendable {
        var status: DaemonStatus?
        var history: [HistorySample] = []
        var logs: [LogEntry] = []
        var daily: [DailySample] = []
    }

    private let contents = Mutex(Contents())

    /// nil until the controller has published once.
    var status: DaemonStatus? { contents.withLock { $0.status } }
    var history: [HistorySample] { contents.withLock { $0.history } }
    var logs: [LogEntry] { contents.withLock { $0.logs } }
    var daily: [DailySample] { contents.withLock { $0.daily } }

    func publish(status: DaemonStatus, history: [HistorySample], logs: [LogEntry], daily: [DailySample]) {
        contents.withLock { $0 = Contents(status: status, history: history, logs: logs, daily: daily) }
    }

    func publish(logs: [LogEntry]) {
        contents.withLock { $0.logs = logs }
    }
}
