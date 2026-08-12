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
            MenuBarIcon(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
        }
        .defaultSize(width: 420, height: 224)
        .windowResizability(.contentSize)
    }
}

private struct MenuBarIcon: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Image(nsImage: MenuBarStatusImage.make(symbolName: appState.menuBarSymbol))
            .frame(width: MenuBarStatusImage.pointSize, height: MenuBarStatusImage.pointSize)
            .fixedSize()
            .accessibilityLabel(appState.mode.title)
    }
}

private enum MenuBarStatusImage {
    static let pointSize: CGFloat = 18

    static func make(symbolName: String) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let symbol = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        )
        let image = NSImage(size: size, flipped: false) { rect in
            guard let symbol else { return false }
            let glyphSize = symbol.size
            symbol.draw(
                in: NSRect(
                    x: rect.midX - glyphSize.width / 2,
                    y: rect.midY - glyphSize.height / 2,
                    width: glyphSize.width,
                    height: glyphSize.height
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        image.isTemplate = true
        return image
    }
}
