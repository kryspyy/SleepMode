import AppKit
import SwiftUI

struct MenuContentView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 6) {
                Picker(
                    "Mode",
                    selection: Binding(
                        get: { appState.pickerMode },
                        set: appState.selectMode
                    )
                ) {
                    ForEach(AppMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(appState.isChangingMode)

                Text(appState.contextualText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)

            Divider()
                .padding(.vertical, 10)

            sleepRadioPreferences

            if let statusMessage = appState.statusMessage {
                StatusCallout(
                    message: statusMessage,
                    onDismiss: appState.dismissStatusMessage
                )
                .padding(.top, 10)
            }

            Divider()
                .padding(.vertical, 10)

            HStack {
                Button {
                    presentSettings()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }

                Spacer()

                Button("Quit") {
                    appState.quit()
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: appState.mode.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(modeColor)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 20, height: 20)

            Text("SleepMode")
                .font(.headline)

            Spacer()

            if appState.isChangingMode {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(height: 20)
    }

    private var modeColor: Color {
        appState.mode == .stayAwake ? .orange : .indigo
    }

    private var sleepRadioPreferences: some View {
        HStack(spacing: 8) {
            Text("Off while asleep")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 2)

            compactToggle(
                "Wi-Fi",
                isOn: Binding(
                    get: { appState.turnWiFiOffDuringSleep },
                    set: appState.setWiFiSleepBehavior
                )
            )

            compactToggle(
                "Bluetooth",
                isOn: Binding(
                    get: { appState.turnBluetoothOffDuringSleep },
                    set: appState.setBluetoothSleepBehavior
                )
            )
        }
    }

    private func compactToggle(
        _ title: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.caption)
            .help("Turn \(title) off while this Mac is sleeping")
    }

    private func presentSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()

        // A Settings scene can be created on the next run-loop turn. Focusing
        // both now and then also handles an existing window hidden behind
        // another app.
        focusSettingsWindow()
        DispatchQueue.main.async {
            focusSettingsWindow()
        }
    }

    private func focusSettingsWindow() {
        guard let settingsWindow = NSApp.windows.first(where: { window in
            window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true
        }) ?? NSApp.windows.first(where: { window in
            window.canBecomeKey
                && window.styleMask.contains(.titled)
                && !(window is NSPanel)
        }) else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.orderFrontRegardless()
        settingsWindow.makeKeyAndOrderFront(nil)
    }
}
