import Foundation

final class PrivilegedOperationsService: PrivilegedOperationsServing {
    let closedLidCapability: ClosedLidCapability = .unavailable(
        reason: "macOS public power assertions do not override forced lid-close sleep."
    )

    func restoreSafeDefaults() {
        // Supported sleep prevention is process-scoped. macOS releases the assertion
        // automatically if this process exits, so no persistent privileged mutation
        // needs to be reversed.
    }
}
