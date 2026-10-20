import Foundation
import IOKit
import IOKit.pwr_mgt

/// Calls back before system sleep (sleep waits for willSleep to return) and after wake.
final class SleepWatcher {
    private static let canSystemSleep: UInt32 = 0xE000_0270
    private static let systemWillSleep: UInt32 = 0xE000_0280
    private static let systemHasPoweredOn: UInt32 = 0xE000_0300

    private let willSleep: () -> Void
    private let didWake: () -> Void
    private var rootPort: io_connect_t = 0
    private var notifier: io_object_t = 0
    private var port: IONotificationPortRef?

    init(willSleep: @escaping () -> Void, didWake: @escaping () -> Void) {
        self.willSleep = willSleep
        self.didWake = didWake
        let context = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(context, &port, sleepWatcherCallback, &notifier)
        if let port {
            let source = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    fileprivate func handle(_ message: UInt32, argument: Int) {
        switch message {
        case Self.canSystemSleep:
            IOAllowPowerChange(rootPort, argument)
        case Self.systemWillSleep:
            willSleep()
            IOAllowPowerChange(rootPort, argument)
        case Self.systemHasPoweredOn:
            didWake()
        default:
            break
        }
    }
}

/// The run loop source is on the main run loop, so callbacks arrive on the main thread.
private nonisolated func sleepWatcherCallback(
    _ context: UnsafeMutableRawPointer?, _ service: io_service_t, _ message: UInt32,
    _ argument: UnsafeMutableRawPointer?
) {
    // Pass addresses as integers: the pointers are only identifiers for this hop.
    let watcherAddress = Int(bitPattern: context)
    let notificationID = Int(bitPattern: argument)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: watcherAddress) else { return }
        let watcher = Unmanaged<SleepWatcher>.fromOpaque(pointer).takeUnretainedValue()
        watcher.handle(message, argument: notificationID)
    }
}
