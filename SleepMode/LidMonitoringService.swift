import Foundation
import IOKit
import IOKit.pwr_mgt

// Swift cannot import the function-like C macro. This is the public
// iokit_family_msg(sub_iokit_powermanagement, 0x100) value from IOPM.h.
private let lidStateChangeMessage = natural_t(0xE003_4100)

private func lidInterestCallback(
    refcon: UnsafeMutableRawPointer?,
    service: io_service_t,
    messageType: natural_t,
    messageArgument: UnsafeMutableRawPointer?
) {
    guard
        messageType == lidStateChangeMessage,
        let refcon
    else {
        return
    }

    let monitor = Unmanaged<LidMonitoringService>.fromOpaque(refcon).takeUnretainedValue()
    let bits = UInt(bitPattern: messageArgument)
    monitor.receive(closed: (bits & UInt(kClamshellStateBit)) != 0)
}

final class LidMonitoringService: LidMonitoring {
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0
    private var rootDomain: io_service_t = 0
    private var pollTimer: DispatchSourceTimer?
    private var onChange: ((Bool) -> Void)?
    private var lastClosedState: Bool?

    private(set) var isMonitoring = false

    func start(onChange: @escaping (Bool) -> Void) throws {
        guard !isMonitoring else {
            self.onChange = onChange
            return
        }

        let root = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPMrootDomain")
        )
        guard root != 0 else {
            throw SleepModeError.unavailable("Lid state is unavailable on this Mac.")
        }

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            IOObjectRelease(root)
            throw SleepModeError.operationFailed("Could not create the lid notification port.")
        }

        self.onChange = onChange
        rootDomain = root
        notificationPort = port

        let result = IOServiceAddInterestNotification(
            port,
            root,
            kIOGeneralInterest,
            lidInterestCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            &notifier
        )

        guard result == kIOReturnSuccess else {
            stop()
            throw SleepModeError.operationFailed(
                "Could not observe lid changes (\(result))."
            )
        }

        IONotificationPortSetDispatchQueue(port, .main)
        isMonitoring = true

        if let currentState = currentLidState() {
            receive(closed: currentState)
        }

        // Clamshell notifications can be coalesced while macOS transitions the
        // internal display. Polling the same public IOKit property is a small,
        // reliable fallback and runs only while Stay Awake is active.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(250),
            repeating: .milliseconds(250),
            leeway: .milliseconds(50)
        )
        timer.setEventHandler { [weak self] in
            guard
                let self,
                let currentState = self.currentLidState()
            else {
                return
            }
            self.receive(closed: currentState)
        }
        pollTimer = timer
        timer.resume()
    }

    func stop() {
        isMonitoring = false
        onChange = nil
        lastClosedState = nil

        pollTimer?.cancel()
        pollTimer = nil
        if notifier != 0 {
            IOObjectRelease(notifier)
            notifier = 0
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
        if rootDomain != 0 {
            IOObjectRelease(rootDomain)
            rootDomain = 0
        }
    }

    fileprivate func receive(closed: Bool) {
        guard isMonitoring, lastClosedState != closed else { return }
        lastClosedState = closed
        onChange?(closed)
    }

    private func currentLidState() -> Bool? {
        guard rootDomain != 0 else { return nil }
        guard let value = IORegistryEntryCreateCFProperty(
            rootDomain,
            kAppleClamshellStateKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }
        return (value as? NSNumber)?.boolValue
    }

    deinit {
        stop()
    }
}
