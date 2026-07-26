import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { appState.launchAtLogin },
                        set: appState.setLaunchAtLogin
                    )
                )

                Toggle(
                    "Remember selected mode",
                    isOn: Binding(
                        get: { appState.rememberSelectedMode },
                        set: appState.setRememberSelectedMode
                    )
                )

                Toggle(
                    "Turn Wi-Fi off when sleeping",
                    isOn: Binding(
                        get: { appState.turnWiFiOffDuringSleep },
                        set: appState.setWiFiSleepBehavior
                    )
                )
            }

            Section("App Information") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Data", value: "Stored locally")
                LabeledContent("Privacy", value: "No accounts, analytics, or network services")
            }

            if let statusMessage = appState.statusMessage {
                Section {
                    Label(statusMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 470, height: 360)
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        return version ?? "0.1"
    }
}
