import Foundation

enum ProcessRunnerError: LocalizedError {
    case notExecutable(String)
    case launchFailed(String)
    case nonzeroExit(status: Int32, detail: String)

    var errorDescription: String? {
        switch self {
        case let .notExecutable(path):
            "Executable is missing: \(path)"
        case let .launchFailed(message):
            message
        case let .nonzeroExit(_, detail):
            detail.isEmpty ? "The process failed." : detail
        }
    }
}

enum ProcessRunner {
    @discardableResult
    static func run(
        executableURL: URL,
        arguments: [String]
    ) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ProcessRunnerError.notExecutable(executableURL.path)
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let errorOutput = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            throw ProcessRunnerError.nonzeroExit(
                status: process.terminationStatus,
                detail: errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output
    }
}
