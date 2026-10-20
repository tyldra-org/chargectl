import Foundation

// Chargectl Service: the root launch daemon that enforces charge settings, also while the
// app is closed. The app talks to it over XPC.

let controller = ChargeController(store: .system)
if CommandLine.arguments.contains("--restore") {
    controller.restoreForUninstall()
    exit(0)
}
let service = DaemonService(controller: controller)
let listener = NSXPCListener(machServiceName: DaemonIdentity.machService)
listener.setConnectionCodeSigningRequirement(DaemonIdentity.clientRequirement(team: CodeSigning.ownTeam()))
listener.delegate = service
listener.resume()

// launchd sends SIGTERM on unregister, update and shutdown: hand wall power back first.
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    MainActor.assumeIsolated {
        controller.shutdown()
        exit(0)
    }
}
termination.resume()

controller.start()
RunLoop.main.run()
