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
    func setPreventingSleep(
        _ enabled: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    )
    func restoreSafeDefaults()
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
    func turnDisplayOff() throws
}

protocol WiFiControlling: AnyObject {
    func powerState(completion: @escaping (Result<Bool, Error>) -> Void)
    func setPower(
        _ poweredOn: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    )
}

protocol PreferencesServing: AnyObject {
    var rememberSelectedMode: Bool { get set }
    var selectedMode: AppMode { get set }
    var turnWiFiOffDuringSleep: Bool { get set }
    var wifiWasDisabledByApp: Bool { get set }
}

protocol LoginItemControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(
        _ enabled: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    )
}

enum ClosedLidCapability: Equatable {
    case systemManaged
    case unavailable(reason: String)
}

protocol PrivilegedOperationsServing: AnyObject {
    var closedLidCapability: ClosedLidCapability { get }
    func setSleepDisabled(
        _ disabled: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    )
    func restoreSafeDefaults()
}
