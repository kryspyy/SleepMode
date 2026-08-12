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
    func restoreSafeDefaults(completion: @escaping () -> Void)
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

protocol DisplayControlling: AnyObject {
    func turnDisplayOff() throws
}

protocol RadioControlling: AnyObject {
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
    var turnBluetoothOffDuringSleep: Bool { get set }
    var bluetoothWasDisabledByApp: Bool { get set }
}

protocol LoginItemControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(
        _ enabled: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    )
}

protocol PrivilegedOperationsServing: AnyObject {
    func setSleepDisabled(
        _ disabled: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    )
    func restoreSafeDefaults()
    func restoreSafeDefaults(completion: @escaping () -> Void)
}
