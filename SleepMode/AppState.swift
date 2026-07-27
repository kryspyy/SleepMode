import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var mode: AppMode = .normal
    @Published private(set) var pendingMode: AppMode?
    @Published private(set) var isChangingMode = false
    @Published private(set) var launchAtLogin = false
    @Published private(set) var isUpdatingLoginItem = false
    @Published var rememberSelectedMode: Bool
    @Published var turnWiFiOffDuringSleep: Bool
    @Published private(set) var statusMessage: String?

    private let sleepControl: SleepControlling
    private let lidMonitor: LidMonitoring
    private let powerMonitor: SystemPowerMonitoring
    private let screenLocker: ScreenLocking
    private let wifiControl: WiFiControlling
    private let preferences: PreferencesServing
    private let loginItem: LoginItemControlling
    private let privilegedOperations: PrivilegedOperationsServing

    private var started = false
    private var shuttingDown = false
    private var systemIsSleeping = false
    private var lidWasClosedInStayAwake = false
    private var modeRequestID = 0

    init(
        sleepControl: SleepControlling,
        lidMonitor: LidMonitoring,
        powerMonitor: SystemPowerMonitoring,
        screenLocker: ScreenLocking,
        wifiControl: WiFiControlling,
        preferences: PreferencesServing,
        loginItem: LoginItemControlling,
        privilegedOperations: PrivilegedOperationsServing
    ) {
        self.sleepControl = sleepControl
        self.lidMonitor = lidMonitor
        self.powerMonitor = powerMonitor
        self.screenLocker = screenLocker
        self.wifiControl = wifiControl
        self.preferences = preferences
        self.loginItem = loginItem
        self.privilegedOperations = privilegedOperations
        rememberSelectedMode = preferences.rememberSelectedMode
        turnWiFiOffDuringSleep = preferences.turnWiFiOffDuringSleep
        launchAtLogin = loginItem.isEnabled
    }

    static func live() -> AppState {
        let privilegedOperations = PrivilegedOperationsService()
        return AppState(
            sleepControl: SleepControlService(
                privilegedOperations: privilegedOperations
            ),
            lidMonitor: LidMonitoringService(),
            powerMonitor: SystemPowerMonitor(),
            screenLocker: ScreenLockService(),
            wifiControl: WiFiService(),
            preferences: PreferencesService(),
            loginItem: LoginItemService(),
            privilegedOperations: privilegedOperations
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
            switch privilegedOperations.closedLidCapability {
            case .systemManaged:
                "Sleep is prevented; closing the lid locks your session."
            case .unavailable:
                "Idle sleep is prevented; macOS still controls lid sleep."
            }
        case .normal:
            "Standard macOS sleep and lid behavior is active."
        }
    }

    func start() {
        guard !started else { return }
        started = true
        shuttingDown = false

        powerMonitor.start(
            onSleep: { [weak self] in self?.systemWillSleep() },
            onWake: { [weak self] in self?.systemDidWake() }
        )

        let initialMode: AppMode =
            rememberSelectedMode ? preferences.selectedMode : .normal
        recoverWiFiIfNeeded { [weak self] in
            self?.selectMode(initialMode)
        }
    }

    func selectMode(_ requestedMode: AppMode) {
        guard !shuttingDown, !isChangingMode else { return }

        statusMessage = nil
        isChangingMode = true
        pendingMode = requestedMode
        modeRequestID += 1
        let requestID = modeRequestID

        if requestedMode == .normal {
            lidWasClosedInStayAwake = false
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
            recoverWiFiIfNeeded()
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
                case let .failure(error):
                    self.launchAtLogin = self.loginItem.isEnabled
                    self.report(error)
                }
            }
        }
    }

    func shutdown() {
        guard started else { return }
        shuttingDown = true
        systemIsSleeping = false
        modeRequestID += 1
        pendingMode = nil
        isChangingMode = false

        lidMonitor.stop()
        lidWasClosedInStayAwake = false
        powerMonitor.stop()
        sleepControl.restoreSafeDefaults()
        mode = .normal
        recoverWiFiIfNeeded()
        started = false
    }

    func quit() {
        shutdown()
        NSApp.terminate(nil)
    }

    private func completeModeChange(
        _ requestedMode: AppMode,
        requestID: Int,
        result: Result<Bool, Error>
    ) {
        guard !shuttingDown, requestID == modeRequestID else { return }

        switch result {
        case let .success(confirmedState):
            let confirmedMode: AppMode = confirmedState ? .stayAwake : .normal
            guard confirmedMode == requestedMode else {
                finishModeChange(
                    confirmedMode: confirmedMode,
                    requestedMode: requestedMode,
                    error: SleepModeError.operationFailed(
                        "macOS confirmed a different sleep mode."
                    )
                )
                return
            }

            if confirmedMode == .stayAwake {
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
                error: nil
            )

        case let .failure(error):
            let confirmedMode: AppMode =
                sleepControl.isPreventingSleep ? .stayAwake : .normal
            if confirmedMode == .stayAwake {
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
        }
    }

    private func rollbackStayAwake(after originalError: Error, requestID: Int) {
        lidMonitor.stop()
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
                self.finishModeChange(
                    confirmedMode: confirmedMode,
                    requestedMode: .stayAwake,
                    error: originalError
                )
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
        }
        pendingMode = nil
        isChangingMode = false

        if rememberSelectedMode, confirmedMode == requestedMode {
            preferences.selectedMode = confirmedMode
        }
        if let error {
            report(error)
        }
    }

    private func handleLidChange(closed: Bool) {
        guard mode == .stayAwake else { return }

        if closed {
            lidWasClosedInStayAwake = true
        } else {
            guard lidWasClosedInStayAwake else { return }
            lidWasClosedInStayAwake = false
        }

        // Request the lock on close and once more on reopen. Newer macOS
        // versions can ignore ScreenSaverEngine while the internal display is
        // transitioning off; the reopen retry completes before normal use.
        do {
            try screenLocker.lock()
        } catch {
            report(error)
        }

        // `disablesleep 1` prevents system sleep but can also leave the display
        // pipeline awake. Turn it off only on the closed transition; the lid
        // reopening remains free to wake the display normally.
        if closed {
            do {
                try screenLocker.turnDisplayOff()
            } catch {
                report(error)
            }
        }
    }

    private func systemWillSleep() {
        guard turnWiFiOffDuringSleep else { return }
        systemIsSleeping = true

        wifiControl.powerState { [weak self] result in
            self?.onMain {
                guard
                    let self,
                    self.systemIsSleeping,
                    self.turnWiFiOffDuringSleep
                else {
                    return
                }
                switch result {
                case .success(true):
                    self.preferences.wifiWasDisabledByApp = true
                    self.wifiControl.setPower(false) { [weak self] changeResult in
                        self?.onMain {
                            self?.completeWiFiDisable(changeResult)
                        }
                    }
                case .success(false):
                    break
                case .failure(let error):
                    self.report(error)
                }
            }
        }
    }

    private func completeWiFiDisable(_ result: Result<Bool, Error>) {
        switch result {
        case let .success(poweredOn):
            if poweredOn {
                preferences.wifiWasDisabledByApp = false
                report(SleepModeError.operationFailed(
                    "macOS did not turn Wi-Fi off before sleep."
                ))
            }
        case let .failure(error):
            // A command can fail after changing power. Inspect the real state
            // before deciding whether SleepMode owns recovery.
            wifiControl.powerState { [weak self] stateResult in
                self?.onMain {
                    guard let self else { return }
                    if case let .success(poweredOn) = stateResult, poweredOn {
                        self.preferences.wifiWasDisabledByApp = false
                    }
                    self.report(error)
                }
            }
        }
    }

    private func systemDidWake() {
        systemIsSleeping = false
        recoverWiFiIfNeeded()
    }

    private func recoverWiFiIfNeeded(completion: (() -> Void)? = nil) {
        guard preferences.wifiWasDisabledByApp else {
            completion?()
            return
        }

        wifiControl.powerState { [weak self] stateResult in
            self?.onMain {
                guard let self else { return }
                switch stateResult {
                case .success(true):
                    self.preferences.wifiWasDisabledByApp = false
                    completion?()
                case .success(false):
                    self.wifiControl.setPower(true) { [weak self] result in
                        self?.onMain {
                            guard let self else { return }
                            switch result {
                            case .success(true):
                                self.preferences.wifiWasDisabledByApp = false
                            case .success(false):
                                self.report(SleepModeError.operationFailed(
                                    "macOS did not confirm Wi-Fi recovery."
                                ))
                            case .failure(let error):
                                self.report(error)
                            }
                            completion?()
                        }
                    }
                case .failure(let error):
                    self.report(error)
                    completion?()
                }
            }
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
