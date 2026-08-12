import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var mode: AppMode = .normal
    @Published private(set) var pendingMode: AppMode?
    @Published private(set) var isChangingMode = false
    @Published private(set) var launchAtLogin = false
    @Published private(set) var isUpdatingLoginItem = false
    @Published private(set) var rememberSelectedMode: Bool
    @Published private(set) var turnWiFiOffDuringSleep: Bool
    @Published private(set) var turnBluetoothOffDuringSleep: Bool
    @Published private(set) var statusMessage: String?

    private let sleepControl: SleepControlling
    private let lidMonitor: LidMonitoring
    private let powerMonitor: SystemPowerMonitoring
    private let displayControl: DisplayControlling
    private let preferences: PreferencesServing
    private let loginItem: LoginItemControlling
    private let radios: RadioSleepCoordinator

    private var started = false
    private var shuttingDown = false
    private var lidWasClosedInStayAwake = false
    private var lidStateInitialized = false
    private var modeRequestID = 0
    private var queuedMode: AppMode?

    init(
        sleepControl: SleepControlling,
        lidMonitor: LidMonitoring,
        powerMonitor: SystemPowerMonitoring,
        displayControl: DisplayControlling,
        wifiControl: RadioControlling,
        bluetoothControl: RadioControlling,
        preferences: PreferencesServing,
        loginItem: LoginItemControlling
    ) {
        self.sleepControl = sleepControl
        self.lidMonitor = lidMonitor
        self.powerMonitor = powerMonitor
        self.displayControl = displayControl
        self.preferences = preferences
        self.loginItem = loginItem
        rememberSelectedMode = preferences.rememberSelectedMode
        turnWiFiOffDuringSleep = preferences.turnWiFiOffDuringSleep
        turnBluetoothOffDuringSleep = preferences.turnBluetoothOffDuringSleep
        launchAtLogin = loginItem.isEnabled
        radios = RadioSleepCoordinator(
            wifi: wifiControl,
            bluetooth: bluetoothControl,
            preferences: preferences
        )
        radios.onError = { [weak self] error in
            self?.report(error)
        }
    }

    static func live() -> AppState {
        let privilegedOperations = PrivilegedOperationsService()
        return AppState(
            sleepControl: SleepControlService(
                privilegedOperations: privilegedOperations
            ),
            lidMonitor: LidMonitoringService(),
            powerMonitor: SystemPowerMonitor(),
            displayControl: DisplayControlService(),
            wifiControl: WiFiService(),
            bluetoothControl: BluetoothService(),
            preferences: PreferencesService(),
            loginItem: LoginItemService()
        )
    }

    var menuBarSymbol: String {
        mode.symbolName
    }

    var pickerMode: AppMode {
        pendingMode ?? mode
    }

    var contextualText: String {
        switch mode {
        case .stayAwake:
            "Sleep is prevented; macOS controls locking when the display turns off."
        case .normal:
            "Standard macOS sleep and lid behavior is active."
        }
    }

    func start() {
        guard !started else { return }
        started = true
        shuttingDown = false

        radios.probeBluetoothAccess()

        powerMonitor.start(
            onSleep: { [weak self] in self?.radios.handleSystemWillSleep() },
            onWake: { [weak self] in self?.radios.handleSystemDidWake() }
        )

        let initialMode: AppMode =
            rememberSelectedMode ? preferences.selectedMode : .normal
        radios.recoverIfNeeded { [weak self] in
            self?.selectMode(initialMode)
        }
    }

    func selectMode(_ requestedMode: AppMode) {
        guard !shuttingDown else { return }
        if isChangingMode {
            queuedMode = requestedMode
            pendingMode = requestedMode
            return
        }

        statusMessage = nil
        isChangingMode = true
        pendingMode = requestedMode
        modeRequestID += 1
        let requestID = modeRequestID

        if requestedMode == .normal {
            lidWasClosedInStayAwake = false
            lidStateInitialized = false
            lidMonitor.stop()
        }

        sleepControl.setPreventingSleep(requestedMode == .stayAwake) { [weak self] result in
            self?.onMain {
                self?.completeModeChange(
                    requestedMode,
                    requestID: requestID,
                    result: result
                )
            }
        }
    }

    func setRememberSelectedMode(_ enabled: Bool) {
        rememberSelectedMode = enabled
        preferences.rememberSelectedMode = enabled
        if enabled {
            preferences.selectedMode = mode
        }
    }

    func setWiFiSleepBehavior(_ enabled: Bool) {
        turnWiFiOffDuringSleep = enabled
        preferences.turnWiFiOffDuringSleep = enabled

        if !enabled {
            radios.recoverWiFiIfNeeded()
        }
    }

    func setBluetoothSleepBehavior(_ enabled: Bool) {
        turnBluetoothOffDuringSleep = enabled
        preferences.turnBluetoothOffDuringSleep = enabled

        if !enabled {
            radios.recoverBluetoothIfNeeded()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isUpdatingLoginItem else { return }
        statusMessage = nil
        isUpdatingLoginItem = true

        loginItem.setEnabled(enabled) { [weak self] result in
            self?.onMain {
                guard let self else { return }
                self.isUpdatingLoginItem = false
                switch result {
                case let .success(confirmed):
                    self.launchAtLogin = confirmed
                    self.statusMessage = nil
                case let .failure(error):
                    self.launchAtLogin = self.loginItem.isEnabled
                    self.report(error)
                }
            }
        }
    }

    func dismissStatusMessage() {
        statusMessage = nil
    }

    func shutdown() {
        guard started else { return }
        beginShutdown()
        sleepControl.restoreSafeDefaults()
        radios.recoverIfNeeded()
        finishShutdown()
    }

    func quit() {
        guard started else {
            NSApp.terminate(nil)
            return
        }
        beginShutdown()
        sleepControl.restoreSafeDefaults { [weak self] in
            self?.onMain {
                guard let self else {
                    NSApp.terminate(nil)
                    return
                }
                self.radios.recoverIfNeeded {
                    self.finishShutdown()
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func beginShutdown() {
        shuttingDown = true
        radios.stopSleepHandling()
        modeRequestID += 1
        queuedMode = nil
        pendingMode = nil
        isChangingMode = false

        lidMonitor.stop()
        lidWasClosedInStayAwake = false
        lidStateInitialized = false
        powerMonitor.stop()
        mode = .normal
    }

    private func finishShutdown() {
        started = false
    }

    private func completeModeChange(
        _ requestedMode: AppMode,
        requestID: Int,
        result: Result<Bool, Error>
    ) {
        guard !shuttingDown, requestID == modeRequestID else { return }

        let confirmedMode: AppMode
        let error: Error?
        switch result {
        case let .success(confirmedState):
            confirmedMode = confirmedState ? .stayAwake : .normal
            error = confirmedMode == requestedMode
                ? nil
                : SleepModeError.operationFailed(
                    "macOS confirmed a different sleep mode."
                )
        case let .failure(operationError):
            confirmedMode =
                sleepControl.isPreventingSleep ? .stayAwake : .normal
            error = operationError
        }

        let queued = queuedMode
        queuedMode = nil
        let deferToQueue = queued != nil && queued != requestedMode

        if !deferToQueue, confirmedMode == .stayAwake {
            lidStateInitialized = false
            do {
                try lidMonitor.start { [weak self] closed in
                    self?.handleLidChange(closed: closed)
                }
            } catch {
                rollbackStayAwake(after: error, requestID: requestID)
                return
            }
        }

        finishModeChange(
            confirmedMode: confirmedMode,
            requestedMode: requestedMode,
            error: error
        )

        if let queued, queued != confirmedMode, !shuttingDown {
            selectMode(queued)
        }
    }

    private func rollbackStayAwake(after originalError: Error, requestID: Int) {
        lidMonitor.stop()
        lidStateInitialized = false
        sleepControl.setPreventingSleep(false) { [weak self] result in
            self?.onMain {
                guard
                    let self,
                    !self.shuttingDown,
                    requestID == self.modeRequestID
                else {
                    return
                }

                let confirmedMode: AppMode
                switch result {
                case let .success(isDisabled):
                    confirmedMode = isDisabled ? .stayAwake : .normal
                case .failure:
                    confirmedMode =
                        self.sleepControl.isPreventingSleep ? .stayAwake : .normal
                }
                let queued = self.queuedMode
                self.queuedMode = nil
                self.finishModeChange(
                    confirmedMode: confirmedMode,
                    requestedMode: .stayAwake,
                    error: originalError
                )
                if let queued, queued != confirmedMode, !self.shuttingDown {
                    self.selectMode(queued)
                }
            }
        }
    }

    private func finishModeChange(
        confirmedMode: AppMode,
        requestedMode: AppMode,
        error: Error?
    ) {
        mode = confirmedMode
        if confirmedMode == .normal {
            lidWasClosedInStayAwake = false
            lidStateInitialized = false
        }
        pendingMode = nil
        isChangingMode = false

        if rememberSelectedMode, confirmedMode == requestedMode {
            preferences.selectedMode = confirmedMode
        }
        if let error {
            report(error)
        } else {
            statusMessage = nil
        }
    }

    private func handleLidChange(closed: Bool) {
        let stayAwakeActive = mode == .stayAwake
            || (isChangingMode && pendingMode == .stayAwake)
        guard stayAwakeActive else { return }

        if !lidStateInitialized {
            lidStateInitialized = true
            lidWasClosedInStayAwake = closed
            return
        }

        if closed {
            lidWasClosedInStayAwake = true
        } else {
            lidWasClosedInStayAwake = false
            return
        }

        do {
            try displayControl.turnDisplayOff()
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        guard !shuttingDown else { return }
        statusMessage = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }

    private func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
}
