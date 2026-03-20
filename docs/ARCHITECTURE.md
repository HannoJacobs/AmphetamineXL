# Architecture

## ⚠️ The Standby Problem (read this first)

Apple Silicon Macs have a hardware-level sleep state called **standby** managed by the SMC (System Management Controller). This is separate from regular sleep and operates *below* the OS layer — it bypasses ALL IOKit power assertions, including `PreventSystemSleep`, and even ignores `caffeinate`. When the lid closes, the SMC can decide to enter standby regardless of what software says.

**The fix:** Disable standby via `pmset`:
```bash
sudo pmset -a standby 0 && sudo pmset -a hibernatemode 0 && sudo pmset -a autopoweroff 0
```

This is a one-time system-level change. Normal sleep is unaffected — the Mac still sleeps/wakes normally. Only the deep hibernate state is disabled.

To verify: `pmset -g | grep standby` should show `standby 0`.

Without this, AmphetamineXL (and any other caffeine app) will appear to work but will lose to the SMC on lid close.

## Why Amphetamine fails

Amphetamine holds `kIOPMAssertPreventUserIdleSystemSleep` — this only blocks **idle sleep** (Mac goes to sleep after inactivity). It does **not** block clamshell (lid-close) sleep.

When you close your MacBook lid, macOS triggers a separate code path: `Clamshell Sleep`. This ignores idle-sleep assertions entirely.

AmphetamineXL holds **both**:
- `kIOPMAssertPreventUserIdleSystemSleep` — blocks idle sleep
- `kIOPMAssertionTypePreventSystemSleep` — blocks clamshell/system sleep

The second assertion is what actually keeps the Mac awake with the lid closed.

## IOKit assertion lifecycle

```swift
// Enable
IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString,
    IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertionID)

// Disable (must always be paired with create to avoid leaking)
IOPMAssertionRelease(assertionID)
```

Assertion IDs are stored as `IOPMAssertionID` properties on `AppState`. If the app crashes without releasing, macOS cleans them up automatically when the process exits.

## AppState (@Observable)

`AppState` is the single source of truth. Uses `@Observable` macro (macOS 14+):
- `isActive: Bool` — is caffeine on?
- `activeSince: Date?` — when it was turned on
- `durationText: String` — human-readable "Active for Xh Ym" updated every 60s via `Timer`
- `menuBarIcon: String` — SF Symbol name driven by `isActive`

State is persisted to `UserDefaults` under key `amphetamine_active`. On init, if saved state is `true`, caffeine is re-enabled automatically.

## MenuBarExtra + SwiftUI gotcha

AmphetamineXL uses `MenuBarExtra` with `.window` style (a floating NSPanel, not a native menu). This has a quirk: SwiftUI `Button` inside `.window` style can **dismiss the panel before the action fires**.

**Solution**: use `HStack + .contentShape(Rectangle()) + .onTapGesture` for all interactive rows. This gives a full-width hit target that fires reliably. See `MenuBarView.swift`.

## Build system

No Xcode project file. Pure Swift Package Manager. xcodebuild resolves the SPM manifest automatically:

```bash
xcodebuild -scheme AmphetamineXL -configuration Release -destination 'platform=macOS' build
```

The binary ends up in `~/Library/Developer/Xcode/DerivedData/AmphetamineXL-*/Build/Products/Release/AmphetamineXL`.

## Release / packaging

`create-dmg.sh` finds the binary in DerivedData, wraps it in a `.app` bundle with a hand-crafted `Info.plist`, and packages it into a DMG with an Applications symlink. Version is hardcoded in the script — bump both `CFBundleVersion` and `CFBundleShortVersionString` on each release.

CI (`.github/workflows/release.yml`) runs on every push to `main`: builds release binary, runs `create-dmg.sh`, uploads to the latest GitHub release.
