import Foundation
import ServiceManagement

final class PrivilegedOperationsService: PrivilegedOperationsServing {
    private static let helperServiceName = "local.sleepmode.helper"
    private static let helperPlistName = "local.sleepmode.pmsethelper.plist"

    private let queue = DispatchQueue(
        label: "local.sleepmode.pmset",
        qos: .userInitiated
    )
    private var helperConnection: NSXPCConnection?

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
            } catch {
                completion(.failure(error))
                return
            }

            self.ensureHelperIsRegistered { result in
                self.queue.async {
                    switch result {
                    case .success:
                        self.runHelperPMSet(disabled: disabled) { pmsetResult in
                            self.queue.async {
                                do {
                                    try pmsetResult.get()
                                    let confirmed = try self.waitForConfirmedState(disabled)
                                    completion(.success(confirmed))
                                } catch {
                                    completion(.failure(error))
                                }
                            }
                        }
                    case let .failure(error):
                        self.completeWithLiveState(
                            operationError: error,
                            completion: completion
                        )
                    }
                }
            }
        }
    }

    private func completeWithLiveState(
        operationError: Error,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        do {
            completion(.success(try readSleepDisabled()))
        } catch {
            completion(.failure(operationError))
        }
    }

    func restoreSafeDefaults() {
        let completion = DispatchSemaphore(value: 0)
        restoreSafeDefaults {
            completion.signal()
        }
        _ = completion.wait(timeout: .now() + 3)
    }

    func restoreSafeDefaults(completion: @escaping () -> Void) {
        setSleepDisabled(false) { _ in
            completion()
        }
    }

    deinit {
        helperConnection?.invalidate()
    }

    private func ensureHelperIsRegistered(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let service = SMAppService.daemon(plistName: Self.helperPlistName)
        switch service.status {
        case .enabled:
            completion(.success(()))
            return
        case .requiresApproval:
            completion(.failure(approvalRequiredError()))
            return
        default:
            break
        }

        DispatchQueue.main.async {
            do {
                try service.register()
                if service.status == .requiresApproval {
                    completion(.failure(self.approvalRequiredError()))
                    return
                }
                completion(.success(()))
            } catch {
                completion(.failure(SleepModeError.operationFailed(
                    "Could not register the SleepMode helper: \(error.localizedDescription)"
                )))
            }
        }
    }

    private func approvalRequiredError() -> SleepModeError {
        DispatchQueue.main.async {
            SMAppService.openSystemSettingsLoginItems()
        }
        return .operationFailed(
            "Approve SleepMode in System Settings → Login Items & Extensions → Allow in the Background."
        )
    }

    private func runHelperPMSet(
        disabled: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let once = OnceReply(completion)
        let connection = helperConnection ?? makeHelperConnection()
        helperConnection = connection

        guard let helper = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
            self?.queue.async {
                self?.helperConnection?.invalidate()
                self?.helperConnection = nil
                once.send(.failure(SleepModeError.operationFailed(
                    "The SleepMode helper did not respond: \(error.localizedDescription)"
                )))
            }
        }) as? SleepModePrivilegedHelperProtocol else {
            once.send(.failure(SleepModeError.unavailable(
                "The SleepMode helper is unavailable."
            )))
            return
        }

        helper.setSleepDisabled(disabled) { succeeded, message in
            if succeeded {
                once.send(.success(()))
            } else {
                once.send(.failure(SleepModeError.operationFailed(
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
        let output: String
        do {
            output = try ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/pmset"),
                arguments: ["-g"]
            )
        } catch let ProcessRunnerError.launchFailed(message) {
            throw SleepModeError.operationFailed("Could not run pmset: \(message)")
        } catch let ProcessRunnerError.nonzeroExit(_, detail) {
            throw SleepModeError.operationFailed(
                detail.isEmpty ? "pmset failed." : "pmset failed: \(detail)"
            )
        } catch {
            throw SleepModeError.operationFailed(
                "Could not run pmset: \(error.localizedDescription)"
            )
        }
        guard let state = sleepDisabledValue(from: output) else {
            throw SleepModeError.operationFailed(
                "Could not read the current macOS sleep setting."
            )
        }
        return state
    }
}

private final class OnceReply {
    private let lock = NSLock()
    private var completion: ((Result<Void, Error>) -> Void)?

    init(_ completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
    }

    func send(_ result: Result<Void, Error>) {
        lock.lock()
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        completion?(result)
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
