# SleepMode

SleepMode is a local-only macOS menu-bar utility built with SwiftUI.

- **Stay Awake** asks the bundled, system-managed helper to run
  `/usr/bin/pmset -a disablesleep 1`. It reads the live `pmset` state before
  updating the UI. Lid monitoring is active only in this mode.
- **Normal** runs `/usr/bin/pmset -a disablesleep 0`, confirms the live system
  state, and stops lid monitoring.
- **Turn Wi-Fi off when sleeping** listens only for real
  `NSWorkspace.willSleepNotification` and `didWakeNotification` events. It uses
  `/usr/sbin/networksetup -setairportpower`, records ownership before turning
  Wi-Fi off, and restores Wi-Fi only when SleepMode made the change.
- **Turn Bluetooth off when sleeping** follows the same ownership rule for the
  Mac's Bluetooth controller, restoring it after wake only when SleepMode
  turned it off.

The app has no accounts, analytics, or network services.

## First-run setup

1. Move `SleepMode.app` to `/Applications`.
2. Launch SleepMode.
3. Select **Stay Awake**.
4. On first use, approve the standard administrator prompt that installs the
   fixed SleepMode helper.

The helper is installed in `/Library/PrivilegedHelperTools` and registered by
its root-owned `/Library/LaunchDaemons` property list. Later mode changes do not
need another password. The helper accepts only the two fixed `pmset`
enable/disable operations and verifies the calling user and SleepMode bundle
identifier. It does not run `sudo` or accept arbitrary commands. Helper
communication and system commands run away from the main thread so the menu
remains responsive.

For lid-close locking on macOS versions where `CGSession` is unavailable,
SleepMode launches the native ScreenSaverEngine through Launch Services. It
observes the public IOKit lid notification with a live-state polling fallback
and retries the lock as the lid reopens. On lid closure it also runs
`/usr/bin/pmset displaysleepnow`, which turns the display off without allowing
the computer itself to sleep. Set **System Settings → Lock Screen → Require
password after screen saver begins or display is turned off** to **Immediately**
for immediate locking.

## Safety and recovery

`disablesleep` is persistent:

- Normal mode and Quit explicitly restore `disablesleep 0`.
- Unless **Remember selected mode** is enabled, launch selects Normal.
- The app reads the live `pmset` state instead of trusting a saved mode.

For Wi-Fi and Bluetooth, separate ownership markers are written before power is
turned off. Wake, launch, disabling either option, and app shutdown retry that
radio's restoration until macOS confirms it is on.

## Signing

Open `SleepMode.xcodeproj`, select the **SleepMode** target, and choose your
Development Team for distribution signing. Local ad-hoc builds are supported
for testing because the one-time installer places the helper and launchd
property list in macOS's protected system locations. Move the resulting app to
`/Applications` before testing helper installation.

The app uses Hardened Runtime. It is intentionally not sandboxed because it
integrates with IOKit, CoreWLAN, Service Management, and system power/network
tools. No Accessibility, Automation, or AppleScript permission is used.

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

The tests cover confirmed mode transitions, authorization failures,
pending operations, stale callbacks, lid-close locking and rollback, sleep/wake
Wi-Fi and Bluetooth ownership, already-off radios, delayed sleep callbacks,
recovery retries, remembered mode, login-item failures, and shutdown recovery.
