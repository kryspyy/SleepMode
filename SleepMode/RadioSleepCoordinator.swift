import Foundation

@MainActor
final class RadioSleepCoordinator {
    private enum Kind {
        case wifi
        case bluetooth

        var displayName: String {
            switch self {
            case .wifi: "Wi-Fi"
            case .bluetooth: "Bluetooth"
            }
        }
    }

    var onError: (Error) -> Void = { _ in }

    private let wifi: RadioControlling
    private let bluetooth: RadioControlling
    private let preferences: PreferencesServing

    private var systemIsSleeping = false
    private var wifiDisableInFlight = false
    private var bluetoothDisableInFlight = false

    init(
        wifi: RadioControlling,
        bluetooth: RadioControlling,
        preferences: PreferencesServing
    ) {
        self.wifi = wifi
        self.bluetooth = bluetooth
        self.preferences = preferences
    }

    func probeBluetoothAccess() {
        bluetooth.powerState { [weak self] result in
            guard case let .failure(error) = result else { return }
            self?.onMain {
                self?.onError(error)
            }
        }
    }

    func handleSystemWillSleep() {
        guard
            preferences.turnWiFiOffDuringSleep
                || preferences.turnBluetoothOffDuringSleep
        else {
            return
        }
        systemIsSleeping = true
        if preferences.turnWiFiOffDuringSleep {
            disable(.wifi)
        }
        if preferences.turnBluetoothOffDuringSleep {
            disable(.bluetooth)
        }
    }

    func handleSystemDidWake() {
        systemIsSleeping = false
        recoverIfNeeded()
    }

    func recoverIfNeeded(completion: (() -> Void)? = nil) {
        recover(.wifi) { [weak self] in
            self?.recover(.bluetooth, completion: completion)
        }
    }

    func recoverWiFiIfNeeded() {
        recover(.wifi)
    }

    func recoverBluetoothIfNeeded() {
        recover(.bluetooth)
    }

    func stopSleepHandling() {
        systemIsSleeping = false
    }

    private func control(_ kind: Kind) -> RadioControlling {
        switch kind {
        case .wifi: wifi
        case .bluetooth: bluetooth
        }
    }

    private func isEnabled(_ kind: Kind) -> Bool {
        switch kind {
        case .wifi: preferences.turnWiFiOffDuringSleep
        case .bluetooth: preferences.turnBluetoothOffDuringSleep
        }
    }

    private func wasDisabledByApp(_ kind: Kind) -> Bool {
        switch kind {
        case .wifi: preferences.wifiWasDisabledByApp
        case .bluetooth: preferences.bluetoothWasDisabledByApp
        }
    }

    private func setWasDisabledByApp(_ kind: Kind, _ value: Bool) {
        switch kind {
        case .wifi: preferences.wifiWasDisabledByApp = value
        case .bluetooth: preferences.bluetoothWasDisabledByApp = value
        }
    }

    private func isInFlight(_ kind: Kind) -> Bool {
        switch kind {
        case .wifi: wifiDisableInFlight
        case .bluetooth: bluetoothDisableInFlight
        }
    }

    private func setInFlight(_ kind: Kind, _ value: Bool) {
        switch kind {
        case .wifi: wifiDisableInFlight = value
        case .bluetooth: bluetoothDisableInFlight = value
        }
    }

    private func disable(_ kind: Kind) {
        setInFlight(kind, true)
        control(kind).powerState { [weak self] result in
            self?.onMain {
                guard let self else { return }
                guard self.systemIsSleeping, self.isEnabled(kind) else {
                    self.setInFlight(kind, false)
                    return
                }

                switch result {
                case .success(true):
                    self.setWasDisabledByApp(kind, true)
                    self.control(kind).setPower(false) { [weak self] changeResult in
                        self?.onMain {
                            self?.completeDisable(kind, changeResult)
                        }
                    }
                case .success(false):
                    self.setInFlight(kind, false)
                case let .failure(error):
                    self.setInFlight(kind, false)
                    self.onError(error)
                }
            }
        }
    }

    private func completeDisable(_ kind: Kind, _ result: Result<Bool, Error>) {
        setInFlight(kind, false)

        switch result {
        case let .success(poweredOn):
            setWasDisabledByApp(kind, !poweredOn)
            if poweredOn {
                onError(SleepModeError.operationFailed(
                    "macOS did not turn \(kind.displayName) off before sleep."
                ))
            }
            if !systemIsSleeping, !poweredOn {
                recover(kind)
            }
        case let .failure(error):
            control(kind).powerState { [weak self] stateResult in
                self?.onMain {
                    guard let self else { return }
                    if case let .success(poweredOn) = stateResult {
                        self.setWasDisabledByApp(kind, !poweredOn)
                        if !self.systemIsSleeping, !poweredOn {
                            self.recover(kind)
                        }
                    }
                    self.onError(error)
                }
            }
        }
    }

    private func recover(_ kind: Kind, completion: (() -> Void)? = nil) {
        guard wasDisabledByApp(kind) else {
            completion?()
            return
        }
        guard !isInFlight(kind) else {
            completion?()
            return
        }

        control(kind).powerState { [weak self] stateResult in
            self?.onMain {
                guard let self else {
                    completion?()
                    return
                }
                switch stateResult {
                case .success(true):
                    self.setWasDisabledByApp(kind, false)
                    completion?()
                case .success(false):
                    self.control(kind).setPower(true) { [weak self] result in
                        self?.onMain {
                            guard let self else {
                                completion?()
                                return
                            }
                            switch result {
                            case .success(true):
                                self.setWasDisabledByApp(kind, false)
                            case .success(false):
                                self.onError(SleepModeError.operationFailed(
                                    "macOS did not confirm \(kind.displayName) recovery."
                                ))
                            case let .failure(error):
                                self.onError(error)
                            }
                            completion?()
                        }
                    }
                case let .failure(error):
                    self.onError(error)
                    completion?()
                }
            }
        }
    }

    private func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
}
