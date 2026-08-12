import CoreWLAN
import Foundation

final class WiFiService: RadioControlling {
    private let executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    private let queue = DispatchQueue(
        label: "local.sleepmode.wifi",
        qos: .userInitiated
    )

    func powerState(completion: @escaping (Result<Bool, Error>) -> Void) {
        queue.async {
            completion(Result { try self.readPowerState() })
        }
    }

    func setPower(
        _ poweredOn: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        queue.async {
            do {
                let interfaceName = try self.wifiInterfaceName()
                _ = try self.runNetworkSetup([
                    "-setairportpower",
                    interfaceName,
                    poweredOn ? "on" : "off",
                ])

                let confirmedState = try self.readPowerState(interfaceName: interfaceName)
                guard confirmedState == poweredOn else {
                    throw SleepModeError.operationFailed(
                        "macOS did not confirm the Wi-Fi power change."
                    )
                }
                completion(.success(confirmedState))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func readPowerState() throws -> Bool {
        try readPowerState(interfaceName: wifiInterfaceName())
    }

    private func readPowerState(interfaceName: String) throws -> Bool {
        let output = try runNetworkSetup([
            "-getairportpower",
            interfaceName,
        ])
        guard let state = wifiPoweredOn(from: output) else {
            throw SleepModeError.operationFailed(
                "Could not determine the Wi-Fi power state."
            )
        }
        return state
    }

    private func wifiInterfaceName() throws -> String {
        if let name = CWWiFiClient.shared().interface()?.interfaceName, !name.isEmpty {
            return name
        }

        let output = try runNetworkSetup(["-listallhardwareports"])
        let lines = output.components(separatedBy: .newlines)
        for index in lines.indices {
            guard
                lines[index].localizedCaseInsensitiveContains("hardware port: wi-fi"),
                lines.indices.contains(index + 1)
            else {
                continue
            }

            let deviceLine = lines[index + 1]
            guard let separator = deviceLine.firstIndex(of: ":") else { continue }
            let device = deviceLine[deviceLine.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            if !device.isEmpty {
                return device
            }
        }

        throw SleepModeError.unavailable("No Wi-Fi interface is available.")
    }

    private func runNetworkSetup(_ arguments: [String]) throws -> String {
        do {
            return try ProcessRunner.run(
                executableURL: executableURL,
                arguments: arguments
            )
        } catch ProcessRunnerError.notExecutable {
            throw SleepModeError.unavailable(
                "The macOS network configuration service is unavailable."
            )
        } catch let ProcessRunnerError.launchFailed(message) {
            throw SleepModeError.operationFailed(
                "Could not change Wi-Fi power: \(message)"
            )
        } catch let ProcessRunnerError.nonzeroExit(_, detail) {
            throw SleepModeError.operationFailed(
                detail.isEmpty
                    ? "The macOS network configuration command failed."
                    : "Could not change Wi-Fi power: \(detail)"
            )
        } catch {
            throw SleepModeError.operationFailed(
                "Could not change Wi-Fi power: \(error.localizedDescription)"
            )
        }
    }
}

func wifiPoweredOn(from networksetupOutput: String) -> Bool? {
    let normalized = networksetupOutput.lowercased()
    if normalized.contains(": on") {
        return true
    }
    if normalized.contains(": off") {
        return false
    }
    return nil
}
