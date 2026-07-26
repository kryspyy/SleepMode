import SwiftUI

struct MenuContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Picker(
                "Mode",
                selection: Binding(
                    get: { appState.mode },
                    set: appState.selectMode
                )
            ) {
                ForEach(AppMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName)
                        .tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Text(appState.contextualText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle(
                "Turn Wi-Fi off when sleeping",
                isOn: Binding(
                    get: { appState.turnWiFiOffDuringSleep },
                    set: appState.setWiFiSleepBehavior
                )
            )
            .toggleStyle(.switch)
            .font(.callout)

            Text("Runs only for confirmed system sleep—not display sleep or screen locking.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let statusMessage = appState.statusMessage {
                Label(statusMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                SettingsLink {
                    Label("Settings…", systemImage: "gearshape")
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Quit") {
                    appState.quit()
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 330)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: appState.mode.symbolName)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(appState.mode == .stayAwake ? .orange : .indigo)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 1) {
                Text("SleepMode")
                    .font(.headline)
                Text(appState.mode.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
