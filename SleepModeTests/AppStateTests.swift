import XCTest
@testable import SleepMode

@MainActor
final class AppStateTests: XCTestCase {
    func testAppIncludesBluetoothUsageDescription() {
        let description = Bundle.main.object(
            forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription"
        ) as? String

        XCTAssertFalse(description?.isEmpty ?? true)
    }

    func testStartRequestsBluetoothAccessImmediately() {
        let system = makeTestSystem()

        system.state.start()

        XCTAssertEqual(system.bluetooth.powerStateCallCount, 1)
    }

    func testPMSetSleepDisabledOutputParsing() {
        let enabledOutput = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         sleep                1
        """
        let disabledOutput = """
        System-wide power settings:
         SleepDisabled\t\t0
        """

        XCTAssertEqual(sleepDisabledValue(from: enabledOutput), true)
        XCTAssertEqual(sleepDisabledValue(from: disabledOutput), false)
        XCTAssertNil(sleepDisabledValue(from: "Currently in use:\n sleep 1"))
    }

    func testWiFiPowerOutputParsing() {
        XCTAssertEqual(wifiPoweredOn(from: "Wi-Fi Power (en0): On"), true)
        XCTAssertEqual(wifiPoweredOn(from: "Wi-Fi Power (en0): Off"), false)
        XCTAssertNil(wifiPoweredOn(from: "unexpected"))
    }

    func testSleepControlUsesPrivilegedPersistentSleepSetting() {
        let privileged = MockPrivilegedOperations()
        let sleepControl = SleepControlService(privilegedOperations: privileged)
        var results: [Result<Bool, Error>] = []

        sleepControl.setPreventingSleep(true) { results.append($0) }
        XCTAssertTrue(sleepControl.isPreventingSleep)
        XCTAssertEqual(privileged.requestedSleepDisabledStates, [true])

        sleepControl.setPreventingSleep(false) { results.append($0) }
        XCTAssertFalse(sleepControl.isPreventingSleep)
        XCTAssertEqual(privileged.requestedSleepDisabledStates, [true, false])
        XCTAssertEqual(results.compactMap { try? $0.get() }, [true, false])
    }

    func testSleepControlPropagatesPrivilegedFailureWithoutClaimingSuccess() {
        let privileged = MockPrivilegedOperations()
        privileged.setSleepDisabledError = SleepModeError.operationFailed("pmset failed")
        let sleepControl = SleepControlService(privilegedOperations: privileged)

        var receivedError: Error?
        sleepControl.setPreventingSleep(true) {
            if case let .failure(error) = $0 {
                receivedError = error
            }
        }
        XCTAssertNotNil(receivedError)
        XCTAssertFalse(sleepControl.isPreventingSleep)
    }

    func testStayAwakeTransitionConfirmsAssertionAndStartsLidMonitoring() {
        let system = makeTestSystem()
        system.state.start()

        system.state.selectMode(.stayAwake)

        XCTAssertEqual(system.state.mode, .stayAwake)
        XCTAssertTrue(system.sleep.isPreventingSleep)
        XCTAssertTrue(system.lid.isMonitoring)
        XCTAssertEqual(system.sleep.preventCallCount, 1)
    }

    func testPendingModeChangeDoesNotBlockOrClaimUnconfirmedState() {
        let system = makeTestSystem()
        system.state.start()
        system.sleep.automaticallyCompletes = false

        system.state.selectMode(.stayAwake)

        XCTAssertTrue(system.state.isChangingMode)
        XCTAssertEqual(system.state.pendingMode, .stayAwake)
        XCTAssertEqual(system.state.mode, .normal)
        XCTAssertFalse(system.lid.isMonitoring)

        system.sleep.completeNextChange()

        XCTAssertFalse(system.state.isChangingMode)
        XCTAssertNil(system.state.pendingMode)
        XCTAssertEqual(system.state.mode, .stayAwake)
        XCTAssertTrue(system.lid.isMonitoring)
    }

    func testShutdownIgnoresAStaleModeCompletion() {
        let system = makeTestSystem()
        system.state.start()
        system.sleep.automaticallyCompletes = false
        system.state.selectMode(.stayAwake)

        system.state.shutdown()
        system.sleep.completeNextChange()

        XCTAssertEqual(system.state.mode, .normal)
        XCTAssertFalse(system.state.isChangingMode)
        XCTAssertFalse(system.lid.isMonitoring)
        XCTAssertEqual(system.sleep.restoreCallCount, 1)
    }

    func testNormalTransitionStopsLidMonitoringAndReleasesAssertion() {
        let system = makeTestSystem()
        system.state.start()
        system.state.selectMode(.stayAwake)

        system.state.selectMode(.normal)

        XCTAssertEqual(system.state.mode, .normal)
        XCTAssertFalse(system.sleep.isPreventingSleep)
        XCTAssertFalse(system.lid.isMonitoring)
    }

    func testFailedStayAwakeFallsBackToConfirmedNormalState() {
        let system = makeTestSystem()
        system.state.start()
        system.sleep.preventError = SleepModeError.operationFailed("No assertion")

        system.state.selectMode(.stayAwake)

        XCTAssertEqual(system.state.mode, .normal)
        XCTAssertFalse(system.lid.isMonitoring)
        XCTAssertEqual(system.state.statusMessage, "No assertion")
    }

    func testLidMonitoringFailureRollsBackStayAwake() {
        let system = makeTestSystem()
        system.state.start()
        system.lid.startError = SleepModeError.operationFailed("Lid monitor failed")

        system.state.selectMode(.stayAwake)

        XCTAssertEqual(system.state.mode, .normal)
        XCTAssertFalse(system.sleep.isPreventingSleep)
        XCTAssertFalse(system.lid.isMonitoring)
        XCTAssertEqual(system.sleep.preventCallCount, 1)
        XCTAssertEqual(system.sleep.allowCallCount, 2)
        XCTAssertEqual(system.state.statusMessage, "Lid monitor failed")
    }

    func testLidCloseTurnsDisplayOffOnlyWhileStayAwakeIsActive() {
        let system = makeTestSystem()
        system.state.start()
        system.state.selectMode(.stayAwake)

        system.lid.emit(closed: true)
        XCTAssertEqual(system.display.turnDisplayOffCallCount, 1)

        system.lid.emit(closed: false)
        XCTAssertEqual(system.display.turnDisplayOffCallCount, 1)

        system.state.selectMode(.normal)
        system.lid.emit(closed: true)
        XCTAssertEqual(system.display.turnDisplayOffCallCount, 1)
    }

    func testStayAwakeDoesNotTurnDisplayOffWhenLidIsAlreadyClosed() {
        let system = makeTestSystem()
        system.lid.initialClosed = true
        system.state.start()
        system.state.selectMode(.stayAwake)

        XCTAssertEqual(system.display.turnDisplayOffCallCount, 0)

        system.lid.emit(closed: false)
        XCTAssertEqual(system.display.turnDisplayOffCallCount, 0)

        system.lid.emit(closed: true)
        XCTAssertEqual(system.display.turnDisplayOffCallCount, 1)
    }

    func testQueuedModeChangeAppliesAfterInFlightRequest() {
        let system = makeTestSystem()
        system.state.start()
        system.sleep.automaticallyCompletes = false

        system.state.selectMode(.stayAwake)
        system.state.selectMode(.normal)

        XCTAssertTrue(system.state.isChangingMode)
        XCTAssertEqual(system.state.pendingMode, .normal)
        XCTAssertFalse(system.lid.isMonitoring)

        system.sleep.completeNextChange()
        XCTAssertEqual(system.state.mode, .stayAwake)
        XCTAssertEqual(system.state.pendingMode, .normal)
        XCTAssertFalse(system.lid.isMonitoring)

        system.sleep.completeNextChange()
        XCTAssertEqual(system.state.mode, .normal)
        XCTAssertFalse(system.state.isChangingMode)
        XCTAssertFalse(system.lid.isMonitoring)
        XCTAssertFalse(system.sleep.isPreventingSleep)
    }

    func testDelayedWiFiDisableAfterWakeRestoresRadio() {
        let system = makeTestSystem { preferences in
            preferences.turnWiFiOffDuringSleep = true
        }
        system.state.start()
        system.wifi.automaticallyCompletesSetPower = false

        system.power.emitSleep()
        XCTAssertTrue(system.preferences.wifiWasDisabledByApp)
        XCTAssertTrue(system.wifi.requestedPowerStates.isEmpty)

        system.power.emitWake()
        system.wifi.automaticallyCompletesSetPower = true
        system.wifi.completeNextSetPower()

        XCTAssertTrue(system.wifi.isPoweredOn)
        XCTAssertEqual(system.wifi.requestedPowerStates, [false, true])
        XCTAssertFalse(system.preferences.wifiWasDisabledByApp)
    }

    func testDismissStatusMessageClearsError() {
        let system = makeTestSystem()
        system.state.start()
        system.sleep.preventError = SleepModeError.operationFailed("No assertion")
        system.state.selectMode(.stayAwake)

        XCTAssertEqual(system.state.statusMessage, "No assertion")
        system.state.dismissStatusMessage()
        XCTAssertNil(system.state.statusMessage)
    }

    func testSystemSleepTurnsWiFiOffAndWakeRestoresOnlyAppChange() {
        let system = makeTestSystem { preferences in
            preferences.turnWiFiOffDuringSleep = true
        }
        system.state.start()

        system.power.emitSleep()
        XCTAssertEqual(system.wifi.requestedPowerStates, [false])
        XCTAssertTrue(system.preferences.wifiWasDisabledByApp)

        system.power.emitWake()
        XCTAssertEqual(system.wifi.requestedPowerStates, [false, true])
        XCTAssertFalse(system.preferences.wifiWasDisabledByApp)
    }

    func testSystemSleepDoesNotClaimWiFiThatWasAlreadyOff() {
        let system = makeTestSystem(wifiPoweredOn: false) { preferences in
            preferences.turnWiFiOffDuringSleep = true
        }
        system.state.start()

        system.power.emitSleep()
        system.power.emitWake()

        XCTAssertTrue(system.wifi.requestedPowerStates.isEmpty)
        XCTAssertFalse(system.preferences.wifiWasDisabledByApp)
        XCTAssertFalse(system.wifi.isPoweredOn)
    }

    func testSystemSleepTurnsBluetoothOffAndWakeRestoresOnlyAppChange() {
        let system = makeTestSystem { preferences in
            preferences.turnBluetoothOffDuringSleep = true
        }
        system.state.start()

        system.power.emitSleep()
        XCTAssertEqual(system.bluetooth.requestedPowerStates, [false])
        XCTAssertTrue(system.preferences.bluetoothWasDisabledByApp)

        system.power.emitWake()
        XCTAssertEqual(system.bluetooth.requestedPowerStates, [false, true])
        XCTAssertFalse(system.preferences.bluetoothWasDisabledByApp)
    }

    func testSystemSleepDoesNotClaimBluetoothThatWasAlreadyOff() {
        let system = makeTestSystem(bluetoothPoweredOn: false) { preferences in
            preferences.turnBluetoothOffDuringSleep = true
        }
        system.state.start()

        system.power.emitSleep()
        system.power.emitWake()

        XCTAssertTrue(system.bluetooth.requestedPowerStates.isEmpty)
        XCTAssertFalse(system.preferences.bluetoothWasDisabledByApp)
        XCTAssertFalse(system.bluetooth.isPoweredOn)
    }

    func testDisablingBluetoothSleepBehaviorRestoresAppChange() {
        let system = makeTestSystem { preferences in
            preferences.turnBluetoothOffDuringSleep = true
        }
        system.state.start()
        system.power.emitSleep()

        system.state.setBluetoothSleepBehavior(false)

        XCTAssertTrue(system.bluetooth.isPoweredOn)
        XCTAssertFalse(system.preferences.bluetoothWasDisabledByApp)
        XCTAssertFalse(system.preferences.turnBluetoothOffDuringSleep)
    }

    func testFailedWiFiDisableDoesNotClaimWiFiThatRemainedOn() {
        let system = makeTestSystem { preferences in
            preferences.turnWiFiOffDuringSleep = true
        }
        system.state.start()
        system.wifi.failWhenSetting = false

        system.power.emitSleep()

        XCTAssertTrue(system.wifi.isPoweredOn)
        XCTAssertFalse(system.preferences.wifiWasDisabledByApp)
        XCTAssertEqual(system.state.statusMessage, "Wi-Fi test failure")
    }

    func testDelayedSleepCallbackCannotTurnWiFiOffAfterWake() {
        let system = makeTestSystem { preferences in
            preferences.turnWiFiOffDuringSleep = true
        }
        system.state.start()
        system.wifi.automaticallyCompletesPowerState = false

        system.power.emitSleep()
        system.power.emitWake()
        system.wifi.completeNextPowerState()

        XCTAssertTrue(system.wifi.isPoweredOn)
        XCTAssertTrue(system.wifi.requestedPowerStates.isEmpty)
        XCTAssertFalse(system.preferences.wifiWasDisabledByApp)
    }

    func testWiFiRecoveryFailureKeepsMarkerAndRetries() {
        let system = makeTestSystem { preferences in
            preferences.turnWiFiOffDuringSleep = true
        }
        system.state.start()
        system.power.emitSleep()
        system.wifi.failWhenSetting = true

        system.power.emitWake()
        XCTAssertTrue(system.preferences.wifiWasDisabledByApp)
        XCTAssertFalse(system.wifi.isPoweredOn)

        system.wifi.failWhenSetting = nil
        system.power.emitWake()
        XCTAssertTrue(system.wifi.isPoweredOn)
        XCTAssertFalse(system.preferences.wifiWasDisabledByApp)
    }

    func testLaunchRecoversWiFiBeforeApplyingRememberedMode() {
        let system = makeTestSystem(wifiPoweredOn: false) { preferences in
            preferences.wifiWasDisabledByApp = true
            preferences.rememberSelectedMode = true
            preferences.selectedMode = .stayAwake
        }

        system.state.start()

        XCTAssertTrue(system.wifi.isPoweredOn)
        XCTAssertFalse(system.preferences.wifiWasDisabledByApp)
        XCTAssertEqual(system.state.mode, .stayAwake)
    }

    func testShutdownRestoresNormalAndRadios() {
        let system = makeTestSystem { preferences in
            preferences.turnWiFiOffDuringSleep = true
            preferences.turnBluetoothOffDuringSleep = true
        }
        system.state.start()
        system.state.selectMode(.stayAwake)
        system.power.emitSleep()

        system.state.shutdown()

        XCTAssertEqual(system.state.mode, .normal)
        XCTAssertFalse(system.sleep.isPreventingSleep)
        XCTAssertFalse(system.lid.isMonitoring)
        XCTAssertTrue(system.wifi.isPoweredOn)
        XCTAssertFalse(system.preferences.wifiWasDisabledByApp)
        XCTAssertTrue(system.bluetooth.isPoweredOn)
        XCTAssertFalse(system.preferences.bluetoothWasDisabledByApp)
        XCTAssertEqual(system.sleep.restoreCallCount, 1)
    }

    func testRememberModePersistsOnlyAfterConfirmedTransition() {
        let system = makeTestSystem()
        system.state.start()
        system.state.setRememberSelectedMode(true)
        system.state.selectMode(.stayAwake)

        XCTAssertEqual(system.preferences.selectedMode, .stayAwake)

        system.sleep.allowError = SleepModeError.operationFailed("Release failed")
        system.state.selectMode(.normal)

        XCTAssertEqual(system.state.mode, .stayAwake)
        XCTAssertEqual(system.preferences.selectedMode, .stayAwake)
    }

    func testLaunchAtLoginReflectsConfirmedServiceState() {
        let system = makeTestSystem()
        system.state.setLaunchAtLogin(true)
        XCTAssertTrue(system.state.launchAtLogin)

        system.loginItem.error = SleepModeError.operationFailed("Denied")
        system.state.setLaunchAtLogin(false)

        XCTAssertTrue(system.state.launchAtLogin)
        XCTAssertEqual(system.state.statusMessage, "Denied")
    }
}
