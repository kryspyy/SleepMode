import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var mode: AppMode = .normal
    @Published private(set) var launchAtLogin = false
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
        AppState(
            sleepControl: SleepControlService(),
            lidMonitor: LidMonitoringService(),
            powerMonitor: SystemPowerMonitor(),
            screenLocker: ScreenLockService(),
            wifiControl: WiFiService(),
            preferences: PreferencesService(),
            loginItem: LoginItemService(),
            privilegedOperations: PrivilegedOperationsService()
        )
    }

    var menuBarSymbol: String {
        mode.symbolName
    }

    var contextualText: String {
        switch mode {
        case .stayAwake:
            switch privilegedOperations.closedLidCapability {
            case .systemManaged:
                "Sleep is prevented and closing the lid locks your session."
            case .unavailable:
                "Idle sleep is prevented. Lid close locks your session; macOS still controls clamshell sleep."
            }
        case .normal:
            "Standard macOS sleep and lid-close behavior is active."
        }
    }

    func start() {
        guard !started else { return }
        started = true

        powerMonitor.start(
            onSleep: { [weak self] in self?.systemWillSleep() },
            onWake: { [weak self] in self?.systemDidWake() }
        )

        recoverWiFiIfNeeded()
        let initialMode: AppMode = rememberSelectedMode ? preferences.selectedMode : .normal
        selectMode(initialMode)
    }

    func selectMode(_ requestedMode: AppMode) {
        statusMessage = nil

        switch requestedMode {
        case .stayAwake:
            activateStayAwake()
        case .normal:
            activateNormal()
        }

        if rememberSelectedMode, mode == requestedMode {
            preferences.selectedMode = requestedMode
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
        statusMessage = nil
        do {
            try loginItem.setEnabled(enabled)
            launchAtLogin = loginItem.isEnabled
        } catch {
            launchAtLogin = loginItem.isEnabled
            report(error)
        }
    }

    func shutdown() {
        lidMonitor.stop()
        powerMonitor.stop()

        do {
            try sleepControl.allowSleep()
        } catch {
            report(error)
        }
        mode = sleepControl.isPreventingSleep ? .stayAwake : .normal

        recoverWiFiIfNeeded()
        privilegedOperations.restoreSafeDefaults()
        started = false
    }

    func quit() {
        shutdown()
        NSApp.terminate(nil)
    }

    private func activateStayAwake() {
        do {
            try sleepControl.preventSleep()
            guard sleepControl.isPreventingSleep else {
                throw SleepModeError.operationFailed("macOS did not confirm Stay Awake.")
            }

            try lidMonitor.start { [weak self] closed in
                guard closed else { return }
                self?.lockForLidClose()
            }
            mode = .stayAwake
        } catch {
            lidMonitor.stop()
            try? sleepControl.allowSleep()
            mode = sleepControl.isPreventingSleep ? .stayAwake : .normal
            report(error)
        }
    }

    private func activateNormal() {
        lidMonitor.stop()
        do {
            try sleepControl.allowSleep()
            guard !sleepControl.isPreventingSleep else {
                throw SleepModeError.operationFailed("macOS did not confirm Normal mode.")
            }
            mode = .normal
        } catch {
            mode = sleepControl.isPreventingSleep ? .stayAwake : .normal
            if mode == .stayAwake {
                try? lidMonitor.start { [weak self] closed in
                    guard closed else { return }
                    self?.lockForLidClose()
                }
            }
            report(error)
        }
    }

    private func lockForLidClose() {
        guard mode == .stayAwake else { return }
        do {
            try screenLocker.lock()
        } catch {
            report(error)
        }
    }

    private func systemWillSleep() {
        guard turnWiFiOffDuringSleep, wifiControl.isPoweredOn else { return }

        // Persist intent first. If the app is terminated between sleep and wake,
        // the next launch restores Wi-Fi before doing anything else.
        preferences.wifiWasDisabledByApp = true
        do {
            try wifiControl.setPower(false)
        } catch {
            report(error)
        }
    }

    private func systemDidWake() {
        recoverWiFiIfNeeded()
    }

    private func recoverWiFiIfNeeded() {
        guard preferences.wifiWasDisabledByApp else { return }
        do {
            if !wifiControl.isPoweredOn {
                try wifiControl.setPower(true)
            }
            guard wifiControl.isPoweredOn else {
                throw SleepModeError.operationFailed("macOS did not confirm Wi-Fi recovery.")
            }
            preferences.wifiWasDisabledByApp = false
        } catch {
            // Keep the marker so another wake or launch retries recovery.
            report(error)
        }
    }

    private func report(_ error: Error) {
        statusMessage = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }
}
