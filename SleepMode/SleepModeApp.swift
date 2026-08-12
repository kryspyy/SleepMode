import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.shutdown()
    }
}

@main
struct SleepModeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        let state = AppState.live()
        _appState = StateObject(wrappedValue: state)
        appDelegate.appState = state
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(appState: appState)
        } label: {
            ZStack {
                ForEach(AppMode.allCases) { mode in
                    Image(systemName: mode.symbolName)
                        .resizable()
                        .scaledToFit()
                        .opacity(appState.mode == mode ? 1 : 0)
                }
            }
            .frame(width: 16, height: 16)
            .fixedSize()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
        }
        .defaultSize(width: 420, height: 224)
        .windowResizability(.contentSize)
    }
}
