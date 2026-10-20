import Foundation

// chargectld: the root launch daemon that enforces charge settings, also while the
// app is closed. The app installs it with SMAppService and talks to it over XPC.

let controller = ChargeController(store: .system)
let service = DaemonService(controller: controller)
let listener = NSXPCListener(machServiceName: DaemonIdentity.machService)
listener.setConnectionCodeSigningRequirement(DaemonIdentity.clientRequirement)
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
