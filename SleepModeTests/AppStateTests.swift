import XCTest
@testable import SleepMode

@MainActor
final class AppStateTests: XCTestCase {
    func testStayAwakeTransitionConfirmsAssertionAndStartsLidMonitoring() {
        let system = makeTestSystem()
        system.state.start()

        system.state.selectMode(.stayAwake)

        XCTAssertEqual(system.state.mode, .stayAwake)
        XCTAssertTrue(system.sleep.isPreventingSleep)
        XCTAssertTrue(system.lid.isMonitoring)
        XCTAssertEqual(system.sleep.preventCallCount, 1)
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

    func testLidCloseLocksOnlyWhileStayAwakeIsActive() {
        let system = makeTestSystem()
        system.state.start()
        system.state.selectMode(.stayAwake)

        system.lid.emit(closed: true)
        XCTAssertEqual(system.locker.lockCallCount, 1)

        system.state.selectMode(.normal)
        system.lid.emit(closed: true)
        XCTAssertEqual(system.locker.lockCallCount, 1)
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

    func testShutdownRestoresNormalAndWiFi() {
        let system = makeTestSystem { preferences in
            preferences.turnWiFiOffDuringSleep = true
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
        XCTAssertEqual(system.privileged.restoreCallCount, 1)
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
