import Foundation

/// Accepts XPC connections from the app. Reads come from the status board on the XPC queue;
/// changes go to the controller on the main actor.
final class DaemonService: NSObject, NSXPCListenerDelegate, ChargeDaemonProtocol {
    private let controller: ChargeController
    private nonisolated let board: StatusBoard

    init(controller: ChargeController) {
        self.controller = controller
        board = controller.board
    }

    nonisolated func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
        -> Bool
    {
        connection.exportedInterface = NSXPCInterface(with: (any ChargeDaemonProtocol).self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    nonisolated func status(reply: @escaping @Sendable (Data) -> Void) {
        if let status = board.status {
            reply(Coding.encode(status))
        } else {
            Task { @MainActor in reply(Coding.encode(self.controller.status())) }
        }
    }

    nonisolated func updateSettings(_ settings: Data, reply: @escaping @Sendable (String?) -> Void) {
        Task { @MainActor in
            do {
                self.controller.update(try Coding.decode(ChargeSettings.self, from: settings))
                reply(nil)
            } catch {
                reply("The settings could not be read: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func perform(_ command: String, reply: @escaping @Sendable (String?) -> Void) {
        Task { @MainActor in
            guard let command = DaemonCommand(rawValue: command) else {
                reply("Unknown command \(command).")
                return
            }
            reply(self.controller.perform(command))
        }
    }

    nonisolated func history(reply: @escaping @Sendable (Data) -> Void) {
        reply(Coding.encode(board.history))
    }

    nonisolated func logs(reply: @escaping @Sendable (Data) -> Void) {
        reply(Coding.encode(board.logs))
    }

    nonisolated func dailyHistory(reply: @escaping @Sendable (Data) -> Void) {
        reply(Coding.encode(board.daily))
    }
}
