import Foundation
import Security

final class PrivilegedOperationsService: PrivilegedOperationsServing {
    let closedLidCapability: ClosedLidCapability = .systemManaged

    private static let helperServiceName = "local.sleepmode.pmsethelper"
    private static let installedHelperPath =
        "/Library/PrivilegedHelperTools/local.sleepmode.pmsethelper"
    private static let installedPlistPath =
        "/Library/LaunchDaemons/local.sleepmode.pmsethelper.plist"

    private let queue = DispatchQueue(
        label: "local.sleepmode.pmset",
        qos: .userInitiated
    )
    private var helperConnection: NSXPCConnection?
    private var authorization: AuthorizationRef?

    func setSleepDisabled(
        _ disabled: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else {
                completion(.failure(SleepModeError.unavailable(
                    "The macOS authorization service is unavailable."
                )))
                return
            }

            do {
                if try self.readSleepDisabled() == disabled {
                    completion(.success(disabled))
                    return
                }

                try self.ensureHelperIsInstalled()
                self.runHelperPMSet(disabled: disabled) { result in
                    self.queue.async {
                        do {
                            try result.get()
                            let confirmed = try self.waitForConfirmedState(disabled)
                            completion(.success(confirmed))
                        } catch {
                            completion(.failure(error))
                        }
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    func restoreSafeDefaults() {
        setSleepDisabled(false) { _ in }
    }

    deinit {
        helperConnection?.invalidate()
        if let authorization {
            AuthorizationFree(authorization, [.destroyRights])
        }
    }

    private func ensureHelperIsInstalled() throws {
        if FileManager.default.isExecutableFile(
            atPath: Self.installedHelperPath
        ), FileManager.default.fileExists(atPath: Self.installedPlistPath) {
            return
        }

        guard let helperURL = Bundle.main.url(
            forAuxiliaryExecutable: "SleepModeHelper"
        ) ?? bundledHelperURL else {
            throw SleepModeError.unavailable(
                "The bundled SleepMode helper is missing."
            )
        }

        let authorization = try authorizationReference(
            executablePath: helperURL.path
        )
        let status = helperURL.path.withCString { helperPath in
            SMInstallPrivilegedHelper(
                authorization,
                helperPath,
                getuid()
            )
        }
        guard status == errAuthorizationSuccess else {
            throw authorizationError(status)
        }

        guard FileManager.default.isExecutableFile(
            atPath: Self.installedHelperPath
        ), FileManager.default.fileExists(atPath: Self.installedPlistPath) else {
            throw SleepModeError.operationFailed(
                "macOS did not complete the SleepMode helper installation."
            )
        }
    }

    private var bundledHelperURL: URL? {
        let url = Bundle.main.bundleURL
            .appendingPathComponent(
                "Contents/Library/HelperTools/SleepModeHelper"
            )
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private func authorizationReference(
        executablePath: String
    ) throws -> AuthorizationRef {
        if let authorization {
            return authorization
        }

        var createdAuthorization: AuthorizationRef?
        let status = kAuthorizationRightExecute.withCString { rightPointer in
            executablePath.withCString { pathPointer in
                var item = AuthorizationItem(
                    name: rightPointer,
                    valueLength: strlen(pathPointer) + 1,
                    value: UnsafeMutableRawPointer(mutating: pathPointer),
                    flags: 0
                )
                return withUnsafeMutablePointer(to: &item) { itemPointer in
                    var rights = AuthorizationRights(
                        count: 1,
                        items: itemPointer
                    )
                    return AuthorizationCreate(
                        &rights,
                        nil,
                        [.interactionAllowed, .extendRights, .preAuthorize],
                        &createdAuthorization
                    )
                }
            }
        }

        guard status == errAuthorizationSuccess, let createdAuthorization else {
            throw authorizationError(status)
        }
        authorization = createdAuthorization
        return createdAuthorization
    }

    private func runHelperPMSet(
        disabled: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let connection = helperConnection ?? makeHelperConnection()
        helperConnection = connection

        guard let helper = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            self?.queue.async {
                self?.helperConnection?.invalidate()
                self?.helperConnection = nil
                completion(.failure(SleepModeError.operationFailed(
                    "The SleepMode helper did not respond: \(error.localizedDescription)"
                )))
            }
        }) as? SleepModePrivilegedHelperProtocol else {
            completion(.failure(SleepModeError.unavailable(
                "The SleepMode helper is unavailable."
            )))
            return
        }

        helper.setSleepDisabled(disabled) { succeeded, message in
            if succeeded {
                completion(.success(()))
            } else {
                completion(.failure(SleepModeError.operationFailed(
                    message ?? "The SleepMode helper could not change the sleep setting."
                )))
            }
        }
    }

    private func makeHelperConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: Self.helperServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: SleepModePrivilegedHelperProtocol.self
        )
        connection.invalidationHandler = { [weak self, weak connection] in
            self?.queue.async {
                if self?.helperConnection === connection {
                    self?.helperConnection = nil
                }
            }
        }
        connection.resume()
        return connection
    }

    private func authorizationError(_ status: OSStatus) -> SleepModeError {
        switch status {
        case errAuthorizationCanceled:
            return .operationFailed("Administrator authorization was cancelled.")
        case errAuthorizationDenied:
            return .operationFailed("Administrator authorization was denied.")
        case errAuthorizationInternal:
            return .operationFailed(
                "The SleepMode helper could not be installed."
            )
        default:
            let detail = SecCopyErrorMessageString(status, nil) as String?
            return .operationFailed(
                detail.map { "Administrator authorization failed: \($0)" }
                    ?? "Administrator authorization failed (\(status))."
            )
        }
    }

    private func waitForConfirmedState(_ expected: Bool) throws -> Bool {
        for _ in 0..<30 {
            if try readSleepDisabled() == expected {
                return expected
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        throw SleepModeError.operationFailed(
            "macOS did not apply the requested sleep setting."
        )
    }

    private func readSleepDisabled() throws -> Bool {
        let output = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/pmset"),
            arguments: ["-g"]
        )
        guard let state = sleepDisabledValue(from: output) else {
            throw SleepModeError.operationFailed(
                "Could not read the current macOS sleep setting."
            )
        }
        return state
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String]
    ) throws -> String {
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
            throw SleepModeError.operationFailed(
                "Could not run pmset: \(error.localizedDescription)"
            )
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
            let detail = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SleepModeError.operationFailed(
                detail.isEmpty ? "pmset failed." : "pmset failed: \(detail)"
            )
        }
        return output
    }

}

func sleepDisabledValue(from pmsetOutput: String) -> Bool? {
    let pattern = #"(?mi)^\s*(?:SleepDisabled|disablesleep)\s+([01])\s*$"#
    guard
        let expression = try? NSRegularExpression(pattern: pattern),
        let match = expression.firstMatch(
            in: pmsetOutput,
            range: NSRange(pmsetOutput.startIndex..., in: pmsetOutput)
        ),
        let valueRange = Range(match.range(at: 1), in: pmsetOutput)
    else {
        return nil
    }
    return pmsetOutput[valueRange] == "1"
}
