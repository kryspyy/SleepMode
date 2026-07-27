import Foundation
import Security

private let serviceName = "local.sleepmode.pmsethelper"
private let appBundleIdentifier = "local.sleepmode.app"
private let installedHelperPath =
    "/Library/PrivilegedHelperTools/local.sleepmode.pmsethelper"
private let installedPlistPath =
    "/Library/LaunchDaemons/local.sleepmode.pmsethelper.plist"
private let authorizedUserPath =
    "/Library/Application Support/SleepMode/authorized-user"

@objc(SleepModePrivilegedHelperProtocol)
private protocol SleepModePrivilegedHelperProtocol {
    func setSleepDisabled(
        _ disabled: Bool,
        withReply reply: @escaping (Bool, String?) -> Void
    )
}

private final class Helper: NSObject, SleepModePrivilegedHelperProtocol {
    func setSleepDisabled(
        _ disabled: Bool,
        withReply reply: @escaping (Bool, String?) -> Void
    ) {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            reply(false, "Could not run pmset: \(error.localizedDescription)")
            return
        }

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            reply(false, detail?.isEmpty == false ? detail : "pmset failed.")
            return
        }
        reply(true, nil)
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
        guard connection.effectiveUserIdentifier == authorizedUserID else {
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

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(
            guestCode,
            [],
            &staticCode
        ) == errSecSuccess,
        let staticCode,
        SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess
        else {
            return false
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
        let values = information as? [CFString: Any],
        values[kSecCodeInfoIdentifier] as? String == appBundleIdentifier
        else {
            return false
        }
        return true
    }

    private var authorizedUserID: uid_t? {
        guard
            let value = try? String(
                contentsOfFile: authorizedUserPath,
                encoding: .utf8
            ),
            let userID = uid_t(
                value.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        else {
            return nil
        }
        return userID
    }
}

private enum Installer {
    static func install(for userID: uid_t) throws {
        guard geteuid() == 0, userID >= 500 else {
            throw InstallError.invalidPrivileges
        }

        let fileManager = FileManager.default
        let sourceHelperURL = URL(
            fileURLWithPath: CommandLine.arguments[0]
        ).resolvingSymlinksInPath()
        let sourcePlistURL = sourceHelperURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "LaunchDaemons/local.sleepmode.pmsethelper.plist"
            )
        guard fileManager.fileExists(atPath: sourcePlistURL.path) else {
            throw InstallError.missingPlist
        }

        _ = runLaunchctl(["bootout", "system/\(serviceName)"])

        try replace(
            source: sourceHelperURL,
            destination: URL(fileURLWithPath: installedHelperPath),
            permissions: 0o755
        )
        try replace(
            source: sourcePlistURL,
            destination: URL(fileURLWithPath: installedPlistPath),
            permissions: 0o644
        )

        let supportURL = URL(fileURLWithPath: authorizedUserPath)
            .deletingLastPathComponent()
        try fileManager.createDirectory(
            at: supportURL,
            withIntermediateDirectories: true
        )
        try "\(userID)\n".write(
            toFile: authorizedUserPath,
            atomically: true,
            encoding: .utf8
        )
        try fileManager.setAttributes(
            [
                .ownerAccountID: 0,
                .groupOwnerAccountID: 0,
                .posixPermissions: 0o644
            ],
            ofItemAtPath: authorizedUserPath
        )

        guard runLaunchctl(
            ["bootstrap", "system", installedPlistPath]
        ) else {
            try? fileManager.removeItem(atPath: installedPlistPath)
            try? fileManager.removeItem(atPath: installedHelperPath)
            try? fileManager.removeItem(atPath: authorizedUserPath)
            throw InstallError.bootstrapFailed
        }
    }

    private static func replace(
        source: URL,
        destination: URL,
        permissions: Int
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporary = destination.appendingPathExtension("new")
        try? fileManager.removeItem(at: temporary)
        try fileManager.copyItem(at: source, to: temporary)
        try fileManager.setAttributes(
            [
                .ownerAccountID: 0,
                .groupOwnerAccountID: 0,
                .posixPermissions: permissions
            ],
            ofItemAtPath: temporary.path
        )
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: temporary, to: destination)
    }

    private static func runLaunchctl(_ arguments: [String]) -> Bool {
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

    private enum InstallError: Error {
        case invalidPrivileges
        case missingPlist
        case bootstrapFailed
    }
}

if CommandLine.arguments.count == 3,
   CommandLine.arguments[1] == "--install",
   let userID = uid_t(CommandLine.arguments[2]) {
    do {
        try Installer.install(for: userID)
        print("OK")
        exit(EXIT_SUCCESS)
    } catch {
        print("ERROR")
        exit(EXIT_FAILURE)
    }
}

private let delegate = ListenerDelegate()
private let listener = NSXPCListener(machServiceName: serviceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
