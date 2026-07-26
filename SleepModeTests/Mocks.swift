import Foundation
@testable import SleepMode

final class MockSleepControl: SleepControlling {
    var isPreventingSleep = false
    var preventError: Error?
    var allowError: Error?
    private(set) var preventCallCount = 0
    private(set) var allowCallCount = 0

    func preventSleep() throws {
        preventCallCount += 1
        if let preventError { throw preventError }
        isPreventingSleep = true
    }

    func allowSleep() throws {
        allowCallCount += 1
        if let allowError { throw allowError }
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
    private(set) var lockCallCount = 0

    func lock() throws {
        lockCallCount += 1
        if let error { throw error }
    }
}

final class MockWiFiControl: WiFiControlling {
    var isPoweredOn: Bool
    var failWhenSetting: Bool?
    private(set) var requestedPowerStates: [Bool] = []

    init(isPoweredOn: Bool = true) {
        self.isPoweredOn = isPoweredOn
    }

    func setPower(_ poweredOn: Bool) throws {
        requestedPowerStates.append(poweredOn)
        if failWhenSetting == poweredOn {
            throw SleepModeError.operationFailed("Wi-Fi test failure")
        }
        isPoweredOn = poweredOn
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

    func setEnabled(_ enabled: Bool) throws {
        if let error { throw error }
        isEnabled = enabled
    }
}

final class MockPrivilegedOperations: PrivilegedOperationsServing {
    var closedLidCapability: ClosedLidCapability = .unavailable(reason: "Test")
    private(set) var restoreCallCount = 0

    func restoreSafeDefaults() {
        restoreCallCount += 1
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
