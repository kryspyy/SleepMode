import Foundation

final class ScreenLockService: ScreenLocking {
    private let executableURL = URL(
        fileURLWithPath:
            "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
    )

    func lock() throws {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SleepModeError.unavailable("The macOS session-lock service is unavailable.")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-suspend"]
        do {
            try process.run()
        } catch {
            throw SleepModeError.operationFailed(
                "Could not lock the session: \(error.localizedDescription)"
            )
        }
    }
}
