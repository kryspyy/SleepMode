# SleepMode

SleepMode is a small, local-only macOS menu bar app for keeping your Mac awake when you need it and returning to normal sleep behavior when you do not.

## Features

- **Stay Awake** — prevent system sleep from the menu bar.
- **Normal** — restore standard macOS sleep and lid behavior.
- **Lid-close display control** — while Stay Awake is active, closing the lid turns the display off without putting the Mac to sleep. macOS still controls when your password is required.
- **Wi-Fi during sleep** — optionally turn Wi-Fi off when macOS actually starts sleeping and restore it after wake.
- **Bluetooth during sleep** — optionally turn Bluetooth off during sleep and restore it after wake.
- **Launch at Login** — start SleepMode automatically when you sign in.
- **Remember selected mode** — optionally restore the last confirmed mode when the app opens.
- **Safe recovery** — verify changes against the live macOS state and restore settings SleepMode changed when it quits or starts again.
- **Private by design** — no accounts, analytics, cloud services, or network connection.

## Getting started

SleepMode lives in the menu bar. If you have a built `SleepMode.app`:

1. Move `SleepMode.app` to `/Applications`.
2. Open SleepMode.
3. Click the SleepMode icon in the menu bar.
4. Choose **Stay Awake** or **Normal**.
5. Use the **Wi-Fi** and **Bluetooth** switches if you want those radios turned off while the Mac sleeps.

The first time you choose **Stay Awake**, macOS asks for administrator authorization to install SleepMode's helper. This is a one-time setup; changing modes later does not require another password prompt.

## Modes

### Stay Awake

SleepMode prevents system sleep and watches for lid changes. When the lid closes, it turns the display off while keeping the Mac awake. Set **System Settings → Lock Screen → Require password after screen saver begins or display is turned off** to **Immediately** if you want the Mac to require authentication as soon as the display turns off.

### Normal

SleepMode returns the Mac to standard macOS sleep behavior and stops lid monitoring. Quit also restores Normal mode.

## Sleep-time radio controls

The **Off while asleep** switches are available in the menu bar popover. SleepMode only changes a radio after macOS reports that the Mac is going to sleep. It records whether it made the change and restores that radio after wake, when the app opens, when the option is disabled, or when the app quits.

If Wi-Fi or Bluetooth was already off, SleepMode leaves it off. It only restores a radio that it turned off itself.

## Settings

Open **Settings…** from the menu bar popover to configure:

- **Launch at Login** — open SleepMode automatically when you sign in.
- **Remember selected mode** — restore the last confirmed mode when SleepMode launches. When this is disabled, the app starts in Normal mode.

## Safety and privacy

SleepMode reads the live macOS state before and after important changes, so the menu does not claim a mode or radio state that was not confirmed. If an operation fails, the app shows the error in the menu instead of silently pretending it succeeded.

SleepMode is entirely local. It does not create an account, collect analytics, or contact a server. The app's only persistent system change is the sleep setting used by Stay Awake, and it explicitly restores that setting to Normal when you switch modes or quit.

## Requirements

- macOS 26.0 or later
- A built and signed `SleepMode.app`

## Build from source

SleepMode is a native SwiftUI project with no third-party dependencies.

1. Open `SleepMode.xcodeproj` in Xcode.
2. Select the **SleepMode** target and choose your Development Team under **Signing & Capabilities** if you are making a distributable build.
3. Build the **SleepMode** scheme.
4. Move the resulting app to `/Applications` before testing the one-time helper installation.

From Terminal, the equivalent build and test commands are:

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

The test suite covers confirmed mode transitions, authorization failures, lid-close handling, sleep/wake radio ownership and recovery, remembered mode, launch-at-login, and shutdown cleanup.

## Technical overview

- The menu bar UI is built with SwiftUI `MenuBarExtra`.
- Stay Awake uses a small privileged helper to apply the fixed `pmset` sleep-setting changes required by macOS. The helper is installed once in macOS's protected system locations through the standard administrator authorization flow.
- Lid changes are observed through public IOKit notifications with a live-state polling fallback. The display is turned off with macOS's `/usr/bin/pmset displaysleepnow` command.
- Sleep and wake events come from `NSWorkspace`. Wi-Fi uses CoreWLAN and `networksetup`; Bluetooth uses `IOBluetooth`.
- System operations run away from the main UI thread, and state changes are confirmed from the live system before the UI is updated.
- The app uses Hardened Runtime and is intentionally not sandboxed because it integrates with IOKit, CoreWLAN, IOBluetooth, Service Management, and macOS power/network tools. It does not use Accessibility, Automation, or AppleScript permissions.

## License

SleepMode is available under the [MIT License](LICENSE).
