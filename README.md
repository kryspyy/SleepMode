# SleepMode

SleepMode is a local-only macOS menu-bar utility built with SwiftUI and Liquid
Glass. It provides two confirmed modes:

- **Stay Awake** creates a process-scoped IOKit assertion that prevents idle
  system sleep. Lid monitoring is active only in this mode, and a close event
  locks the current session.
- **Normal** releases SleepMode's assertion and restores standard macOS power
  behavior.

The independent **Turn Wi-Fi off when sleeping** option listens only for real
`NSWorkspace.willSleepNotification` and `didWakeNotification` events. It records
ownership before turning Wi-Fi off, restores only a change it made, and keeps a
recovery marker until macOS confirms that Wi-Fi is back on.

## Important platform boundary

Apple's public `PreventUserIdleSystemSleep` assertion explicitly does **not**
override forced lid-close sleep. SleepMode therefore does not modify undocumented
power settings, invoke `sudo`, or install a root helper that pretends to provide
that guarantee. Closing the lid locks the session, but whether background work
continues with the lid closed remains macOS-managed (for example, supported
closed-display configurations).

This is a deliberate safety boundary. Process-scoped assertions are
automatically released by macOS after a crash, so SleepMode cannot leave sleep
disabled. The privileged-operations boundary is isolated in the architecture,
but no helper is installed because none of the implemented public operations
requires root access.

References:

- [Apple: PreventUserIdleSystemSleep](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)
- [Apple: workspace sleep notification](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification)
- [Apple: Service Management](https://developer.apple.com/documentation/servicemanagement/smappservice)

## Requirements and setup

- Xcode 26.6 or later
- macOS 26 or later
- A Mac developer signing identity for distribution

1. Open `SleepMode.xcodeproj`.
2. Select the **SleepMode** target, choose your Development Team, and replace
   `local.sleepmode.app` with your reverse-DNS bundle identifier.
3. Build and run the shared **SleepMode** scheme.

The app is `LSUIElement`-only, so it appears in the menu bar and not the Dock.
No account, Accessibility permission, AppleScript, analytics, or external
network service is used. The App Sandbox is intentionally not enabled because
the app integrates with IOKit, CoreWLAN, and the macOS session service; Hardened
Runtime is enabled for signed builds.

**Launch at Login** uses `SMAppService.mainApp`. macOS may show the standard
Login Items approval UI. Wi-Fi is controlled with the public CoreWLAN API.

## Architecture

`AppState` coordinates narrow, injectable services for sleep assertions, lid
events, system sleep/wake, session locking, Wi-Fi, preferences, login items, and
the privileged-operations boundary. UI state changes only after the underlying
service reports success. Quit and termination paths stop observers, release the
assertion, retry Wi-Fi recovery, and restore safe defaults.

## Build and test

```sh
xcodebuild \
  -project SleepMode.xcodeproj \
  -scheme SleepMode \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/SleepModeDerivedData \
  build

xcodebuild \
  -project SleepMode.xcodeproj \
  -scheme SleepMode \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/SleepModeDerivedData \
  test
```

The unit suite covers confirmed mode transitions, transition failures,
lid-close locking, real sleep/wake Wi-Fi ownership, already-off Wi-Fi, recovery
retries, crash-marker recovery, remembered mode, login-item failures, and app
shutdown.
