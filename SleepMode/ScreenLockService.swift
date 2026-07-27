import AppKit

final class ScreenLockService: ScreenLocking {
    private let sessionExecutableURL = URL(
        fileURLWithPath:
            "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
    )
    private let screenSaverApplicationURL = URL(
        fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"
    )
    private let pmsetExecutableURL = URL(fileURLWithPath: "/usr/bin/pmset")

    func lock() throws {
        if FileManager.default.isExecutableFile(atPath: sessionExecutableURL.path) {
            try launch(
                sessionExecutableURL,
                arguments: ["-suspend"],
                failureMessage: "Could not lock the session"
            )
            return
        }

        // CGSession is absent on newer macOS releases. Ask Launch Services to
        // start Apple's ScreenSaverEngine in the active GUI session.
        guard FileManager.default.fileExists(atPath: screenSaverApplicationURL.path) else {
            throw SleepModeError.unavailable(
                "The macOS Lock Screen service is unavailable."
            )
        }
        guard NSWorkspace.shared.open(screenSaverApplicationURL) else {
            throw SleepModeError.operationFailed(
                "macOS did not accept the session-lock request."
            )
        }
    }

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
