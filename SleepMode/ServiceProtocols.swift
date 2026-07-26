import Foundation

enum SleepModeError: LocalizedError, Equatable {
    case operationFailed(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .operationFailed(message), let .unavailable(message):
            message
        }
    }
}

protocol SleepControlling: AnyObject {
    var isPreventingSleep: Bool { get }
    func preventSleep() throws
    func allowSleep() throws
}

protocol LidMonitoring: AnyObject {
    var isMonitoring: Bool { get }
    func start(onChange: @escaping (Bool) -> Void) throws
    func stop()
}

protocol SystemPowerMonitoring: AnyObject {
    func start(onSleep: @escaping () -> Void, onWake: @escaping () -> Void)
    func stop()
}

protocol ScreenLocking: AnyObject {
    func lock() throws
}

protocol WiFiControlling: AnyObject {
    var isPoweredOn: Bool { get }
    func setPower(_ poweredOn: Bool) throws
}

protocol PreferencesServing: AnyObject {
    var rememberSelectedMode: Bool { get set }
    var selectedMode: AppMode { get set }
    var turnWiFiOffDuringSleep: Bool { get set }
    var wifiWasDisabledByApp: Bool { get set }
}

protocol LoginItemControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

enum ClosedLidCapability: Equatable {
    case systemManaged
    case unavailable(reason: String)
}

protocol PrivilegedOperationsServing: AnyObject {
    var closedLidCapability: ClosedLidCapability { get }
    func restoreSafeDefaults()
}
