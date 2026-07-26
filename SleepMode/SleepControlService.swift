import Foundation
import IOKit.pwr_mgt

final class SleepControlService: SleepControlling {
    private var assertionID = IOPMAssertionID(kIOPMNullAssertionID)

    var isPreventingSleep: Bool {
        guard assertionID != kIOPMNullAssertionID else { return false }
        guard let properties = IOPMAssertionCopyProperties(assertionID) else { return false }
        _ = properties.takeRetainedValue()
        return true
    }

    func preventSleep() throws {
        guard !isPreventingSleep else { return }

        var newAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "SleepMode Stay Awake" as CFString,
            &newAssertionID
        )

        guard result == kIOReturnSuccess else {
            throw SleepModeError.operationFailed(
                "macOS could not create the sleep-prevention assertion (\(result))."
            )
        }

        assertionID = newAssertionID
        guard isPreventingSleep else {
            assertionID = IOPMAssertionID(kIOPMNullAssertionID)
            throw SleepModeError.operationFailed("macOS did not confirm sleep prevention.")
        }
    }

    func allowSleep() throws {
        guard assertionID != kIOPMNullAssertionID else { return }
        let currentID = assertionID
        let result = IOPMAssertionRelease(currentID)

        guard result == kIOReturnSuccess else {
            throw SleepModeError.operationFailed(
                "macOS could not release the sleep-prevention assertion (\(result))."
            )
        }
        assertionID = IOPMAssertionID(kIOPMNullAssertionID)
    }

    deinit {
        if assertionID != kIOPMNullAssertionID {
            IOPMAssertionRelease(assertionID)
        }
    }
}
