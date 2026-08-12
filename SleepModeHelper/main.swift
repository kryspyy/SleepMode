import Foundation
import Security

private let serviceName = "local.sleepmode.helper"
private let appBundleIdentifier = "local.sleepmode.app"
private let legacyHelperPath =
    "/Library/PrivilegedHelperTools/local.sleepmode.pmsethelper"
private let legacyPlistPath =
    "/Library/LaunchDaemons/local.sleepmode.pmsethelper.plist"
private let legacyAuthorizedUserPath =
    "/Library/Application Support/SleepMode/authorized-user"

private final class Helper: NSObject, SleepModePrivilegedHelperProtocol {
    func setSleepDisabled(
        _ disabled: Bool,
        withReply reply: @escaping (Bool, String?) -> Void
    ) {
        do {
            try ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/pmset"),
                arguments: ["-a", "disablesleep", disabled ? "1" : "0"]
            )
            reply(true, nil)
        } catch let ProcessRunnerError.launchFailed(message) {
            reply(false, "Could not run pmset: \(message)")
        } catch let ProcessRunnerError.nonzeroExit(_, detail) {
            reply(false, detail.isEmpty ? "pmset failed." : detail)
        } catch {
            reply(false, "Could not run pmset: \(error.localizedDescription)")
        }
    }
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let helper = Helper()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard isSleepMode(connection) else { return false }

        connection.exportedInterface = NSXPCInterface(
            with: SleepModePrivilegedHelperProtocol.self
        )
        connection.exportedObject = helper
        connection.resume()
        return true
    }

    private func isSleepMode(_ connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0 else {
            return false
        }

        let attributes = [
            kSecGuestAttributePid: connection.processIdentifier
        ] as CFDictionary
        var guestCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(
            nil,
            attributes,
            [],
            &guestCode
        ) == errSecSuccess, let guestCode else {
            return false
        }

        guard let requirement = clientRequirement() else {
            return false
        }
        return SecCodeCheckValidity(guestCode, [], requirement) == errSecSuccess
    }

    private func clientRequirement() -> SecRequirement? {
        let requirementString: String
        if let teamID = signingTeamID() {
            requirementString =
                "identifier \"\(appBundleIdentifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
        } else {
            requirementString = "identifier \"\(appBundleIdentifier)\""
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementString as CFString,
            [],
            &requirement
        ) == errSecSuccess else {
            return nil
        }
        return requirement
    }

    private func signingTeamID() -> String? {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess,
              let selfCode else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
        let values = information as? [CFString: Any] else {
            return nil
        }
        return values[kSecCodeInfoTeamIdentifier] as? String
    }
}

private func removeLegacyPrivilegedHelper() {
    let ourPath = URL(fileURLWithPath: CommandLine.arguments[0])
        .resolvingSymlinksInPath()
        .path
    guard ourPath != legacyHelperPath else { return }

    _ = runLaunchctl(["bootout", "system/local.sleepmode.pmsethelper"])
    let fileManager = FileManager.default
    try? fileManager.removeItem(atPath: legacyHelperPath)
    try? fileManager.removeItem(atPath: legacyPlistPath)
    try? fileManager.removeItem(atPath: legacyAuthorizedUserPath)
}

private func runLaunchctl(_ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

removeLegacyPrivilegedHelper()

private let delegate = ListenerDelegate()
private let listener = NSXPCListener(machServiceName: serviceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
