import AppKit

final class DisplayControlService: DisplayControlling {
    private let pmsetExecutableURL = URL(fileURLWithPath: "/usr/bin/pmset")

    func turnDisplayOff() throws {
        do {
            try ProcessRunner.run(
                executableURL: pmsetExecutableURL,
                arguments: ["displaysleepnow"]
            )
        } catch {
            throw SleepModeError.operationFailed(
                "Could not turn the display off: \(error.localizedDescription)"
            )
        }
    }
}
