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
        MenuBarExtra("SleepMode", systemImage: appState.menuBarSymbol) {
            MenuContentView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
        }
        .defaultSize(width: 420, height: 224)
        .windowResizability(.contentSize)
    }
}
