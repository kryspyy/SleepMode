import Foundation

final class PreferencesService: PreferencesServing {
    private enum Key {
        static let rememberSelectedMode = "rememberSelectedMode"
        static let selectedMode = "selectedMode"
        static let turnWiFiOffDuringSleep = "turnWiFiOffDuringSleep"
        static let wifiWasDisabledByApp = "wifiWasDisabledByApp"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var rememberSelectedMode: Bool {
        get { defaults.bool(forKey: Key.rememberSelectedMode) }
        set { defaults.set(newValue, forKey: Key.rememberSelectedMode) }
    }

    var selectedMode: AppMode {
        get {
            guard
                let rawValue = defaults.string(forKey: Key.selectedMode),
                let mode = AppMode(rawValue: rawValue)
            else {
                return .normal
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.selectedMode) }
    }

    var turnWiFiOffDuringSleep: Bool {
        get { defaults.bool(forKey: Key.turnWiFiOffDuringSleep) }
        set { defaults.set(newValue, forKey: Key.turnWiFiOffDuringSleep) }
    }

    var wifiWasDisabledByApp: Bool {
        get { defaults.bool(forKey: Key.wifiWasDisabledByApp) }
        set { defaults.set(newValue, forKey: Key.wifiWasDisabledByApp) }
    }
}
