import AppKit

final class DisplayControlService: DisplayControlling {
    private let pmsetExecutableURL = URL(fileURLWithPath: "/usr/bin/pmset")

    func turnDisplayOff() throws {
        try launch(
            pmsetExecutableURL,
            arguments: ["displaysleepnow"],
            failureMessage: "Could not turn the display off"
        )
    }

    private func launch(
        _ executableURL: URL,
        arguments: [String],
        failureMessage: String
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            throw SleepModeError.operationFailed(
                "\(failureMessage): \(error.localizedDescription)"
            )
        }
    }
}
