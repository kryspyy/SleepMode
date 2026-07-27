import CoreWLAN
import Foundation

final class WiFiService: WiFiControlling {
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
        let normalized = output.lowercased()

        if normalized.contains(": on") {
            return true
        }
        if normalized.contains(": off") {
            return false
        }
        throw SleepModeError.operationFailed(
            "Could not determine the Wi-Fi power state."
        )
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

    @discardableResult
    private func runNetworkSetup(_ arguments: [String]) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SleepModeError.unavailable(
                "The macOS network configuration service is unavailable."
            )
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
            throw SleepModeError.operationFailed(
                "Could not change Wi-Fi power: \(error.localizedDescription)"
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
                detail.isEmpty
                    ? "The macOS network configuration command failed."
                    : "Could not change Wi-Fi power: \(detail)"
            )
        }
        return output
    }
}
