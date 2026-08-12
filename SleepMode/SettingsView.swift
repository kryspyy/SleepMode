import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 6) {
            Form {
                Section {
                    preferenceRow(
                        "Launch at Login",
                        description: "Open SleepMode when you sign in.",
                        isOn: Binding(
                            get: { appState.launchAtLogin },
                            set: appState.setLaunchAtLogin
                        ),
                        isUpdating: appState.isUpdatingLoginItem
                    )

                    preferenceRow(
                        "Remember selected mode",
                        description: "Restore your last mode when SleepMode opens.",
                        isOn: Binding(
                            get: { appState.rememberSelectedMode },
                            set: appState.setRememberSelectedMode
                        )
                    )
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            if let statusMessage = appState.statusMessage {
                StatusCallout(
                    message: statusMessage,
                    onDismiss: appState.dismissStatusMessage
                )
                .padding(.horizontal, 20)
            }

            Text("Built by Kryspyy")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 10)
        }
        .frame(width: 420, height: settingsHeight)
    }

    private var settingsHeight: CGFloat {
        appState.statusMessage == nil ? 168 : 220
    }

    private func preferenceRow(
        _ title: String,
        description: String,
        isOn: Binding<Bool>,
        isUpdating: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)

            if isUpdating {
                ProgressView()
                    .controlSize(.small)
            }

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isUpdating)
        }
        .padding(.vertical, 3)
    }
}
