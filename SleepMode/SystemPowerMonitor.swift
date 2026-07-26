import AppKit
import Foundation

final class SystemPowerMonitor: SystemPowerMonitoring {
    private var observerTokens: [NSObjectProtocol] = []

    func start(onSleep: @escaping () -> Void, onWake: @escaping () -> Void) {
        stop()
        let center = NSWorkspace.shared.notificationCenter

        observerTokens = [
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { _ in onSleep() },
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { _ in onWake() }
        ]
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observerTokens.forEach(center.removeObserver)
        observerTokens.removeAll()
    }

    deinit {
        stop()
    }
}
