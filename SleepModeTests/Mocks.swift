import Foundation
@testable import SleepMode

final class MockSleepControl: SleepControlling {
    var isPreventingSleep = false
    var preventError: Error?
    var allowError: Error?
    var automaticallyCompletes = true
    private(set) var preventCallCount = 0
    private(set) var allowCallCount = 0
    private(set) var restoreCallCount = 0
    private var pendingChanges: [
        (Bool, (Result<Bool, Error>) -> Void)
    ] = []

    func setPreventingSleep(
        _ enabled: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        guard automaticallyCompletes else {
            pendingChanges.append((enabled, completion))
            return
        }
        complete(enabled, completion: completion)
    }

    func completeNextChange() {
        guard !pendingChanges.isEmpty else { return }
        let (enabled, completion) = pendingChanges.removeFirst()
        complete(enabled, completion: completion)
    }

    private func complete(
        _ enabled: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        if enabled {
            preventCallCount += 1
            if let preventError {
                completion(.failure(preventError))
                return
            }
        } else {
            allowCallCount += 1
            if let allowError {
                completion(.failure(allowError))
                return
            }
        }
        isPreventingSleep = enabled
        completion(.success(enabled))
    }

    func restoreSafeDefaults() {
        restoreCallCount += 1
        isPreventingSleep = false
    }
}

final class MockLidMonitor: LidMonitoring {
    private(set) var isMonitoring = false
    private var onChange: ((Bool) -> Void)?
    var startError: Error?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start(onChange: @escaping (Bool) -> Void) throws {
        startCallCount += 1
        if let startError { throw startError }
        isMonitoring = true
        self.onChange = onChange
    }

    func stop() {
        stopCallCount += 1
        isMonitoring = false
        onChange = nil
    }

    func emit(closed: Bool) {
        onChange?(closed)
    }
}

final class MockPowerMonitor: SystemPowerMonitoring {
    private var onSleep: (() -> Void)?
    private var onWake: (() -> Void)?
    private(set) var isMonitoring = false

    func start(onSleep: @escaping () -> Void, onWake: @escaping () -> Void) {
        isMonitoring = true
        self.onSleep = onSleep
        self.onWake = onWake
    }

    func stop() {
        isMonitoring = false
        onSleep = nil
        onWake = nil
    }

    func emitSleep() { onSleep?() }
    func emitWake() { onWake?() }
}

final class MockScreenLocker: ScreenLocking {
    var error: Error?
    var displaySleepError: Error?
    private(set) var lockCallCount = 0
    private(set) var turnDisplayOffCallCount = 0

    func lock() throws {
        lockCallCount += 1
        if let error { throw error }
    }

    func turnDisplayOff() throws {
        turnDisplayOffCallCount += 1
        if let displaySleepError { throw displaySleepError }
    }
}

final class MockWiFiControl: WiFiControlling {
    var isPoweredOn: Bool
    var failWhenSetting: Bool?
    var automaticallyCompletesPowerState = true
    private(set) var requestedPowerStates: [Bool] = []
    private var pendingPowerStateCompletions: [
        (Result<Bool, Error>) -> Void
    ] = []

    init(isPoweredOn: Bool = true) {
        self.isPoweredOn = isPoweredOn
    }

    func powerState(completion: @escaping (Result<Bool, Error>) -> Void) {
        guard automaticallyCompletesPowerState else {
            pendingPowerStateCompletions.append(completion)
            return
        }
        completion(.success(isPoweredOn))
    }

    func completeNextPowerState() {
        guard !pendingPowerStateCompletions.isEmpty else { return }
        pendingPowerStateCompletions.removeFirst()(.success(isPoweredOn))
    }

    func setPower(
        _ poweredOn: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        requestedPowerStates.append(poweredOn)
        if failWhenSetting == poweredOn {
            completion(.failure(SleepModeError.operationFailed("Wi-Fi test failure")))
            return
        }
        isPoweredOn = poweredOn
        completion(.success(poweredOn))
    }
}

final class MockPreferences: PreferencesServing {
    var rememberSelectedMode = false
    var selectedMode: AppMode = .normal
    var turnWiFiOffDuringSleep = false
    var wifiWasDisabledByApp = false
}

final class MockLoginItem: LoginItemControlling {
    var isEnabled = false
    var error: Error?

    func setEnabled(
        _ enabled: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        if let error {
            completion(.failure(error))
            return
        }
        isEnabled = enabled
        completion(.success(enabled))
    }
}

final class MockPrivilegedOperations: PrivilegedOperationsServing {
    var closedLidCapability: ClosedLidCapability = .unavailable(reason: "Test")
    var isSleepDisabled = false
    var setSleepDisabledError: Error?
    private(set) var requestedSleepDisabledStates: [Bool] = []
    private(set) var restoreCallCount = 0

    func setSleepDisabled(
        _ disabled: Bool,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        requestedSleepDisabledStates.append(disabled)
        if let setSleepDisabledError {
            completion(.failure(setSleepDisabledError))
            return
        }
        isSleepDisabled = disabled
        completion(.success(disabled))
    }

    func restoreSafeDefaults() {
        restoreCallCount += 1
        isSleepDisabled = false
    }
}

struct TestSystem {
    let state: AppState
    let sleep: MockSleepControl
    let lid: MockLidMonitor
    let power: MockPowerMonitor
    let locker: MockScreenLocker
    let wifi: MockWiFiControl
    let preferences: MockPreferences
    let loginItem: MockLoginItem
    let privileged: MockPrivilegedOperations
}

@MainActor
func makeTestSystem(
    wifiPoweredOn: Bool = true,
    configure: (MockPreferences) -> Void = { _ in }
) -> TestSystem {
    let sleep = MockSleepControl()
    let lid = MockLidMonitor()
    let power = MockPowerMonitor()
    let locker = MockScreenLocker()
    let wifi = MockWiFiControl(isPoweredOn: wifiPoweredOn)
    let preferences = MockPreferences()
    let loginItem = MockLoginItem()
    let privileged = MockPrivilegedOperations()
    configure(preferences)

    return TestSystem(
        state: AppState(
            sleepControl: sleep,
            lidMonitor: lid,
            powerMonitor: power,
            screenLocker: locker,
            wifiControl: wifi,
            preferences: preferences,
            loginItem: loginItem,
            privilegedOperations: privileged
        ),
        sleep: sleep,
        lid: lid,
        power: power,
        locker: locker,
        wifi: wifi,
        preferences: preferences,
        loginItem: loginItem,
        privileged: privileged
    )
}
