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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)

            Divider()
                .padding(.vertical, 10)

            wifiPreference

            if let statusMessage = appState.statusMessage {
                statusCallout(statusMessage)
                    .padding(.top, 12)
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
                .frame(width: 20)

            Text("SleepMode")
                .font(.headline)

            Spacer()

            if appState.isChangingMode {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var modeColor: Color {
        appState.mode == .stayAwake ? .orange : .indigo
    }

    private var wifiPreference: some View {
        Toggle(
            isOn: Binding(
                get: { appState.turnWiFiOffDuringSleep },
                set: appState.setWiFiSleepBehavior
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Turn Wi-Fi off when sleeping")
                    .font(.callout)

                Text("Restores automatically after wake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func statusCallout(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.orange.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
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
