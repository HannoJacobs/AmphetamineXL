# Architecture

## The Core Problem: Apple Silicon Clamshell Sleep

On Apple Silicon Macs, closing the lid triggers a **hardware-level clamshell sleep** controlled by the SMC (System Management Controller). This operates *below* the OS layer and **ignores all software sleep prevention**:

- ❌ IOKit assertions (`PreventSystemSleep`, `PreventUserIdleSystemSleep`) — ignored
- ❌ `caffeinate -s` — ignored
- ❌ `pmset standby 0` — reduces but doesn't prevent
- ❌ All of the above combined — still sleeps

This is fundamentally different from Intel Macs where `caffeinate -s` was sufficient.

## The Solution: CGEvent Mouse Jiggle (v2.0)

The **only** thing the SMC respects during clamshell events is HID (Human Interface Device) activity. If the system sees active user input, it won't enter clamshell sleep.

AmphetamineXL posts synthetic mouse events via CoreGraphics:

```swift
// Every 1 second:
let currentPos = CGEvent(source: nil)?.location ?? CGPoint(x: 100, y: 100)
let moved = CGPoint(x: currentPos.x + 1, y: currentPos.y)

if let moveEvent = CGEvent(
    mouseEventSource: nil,
    mouseType: .mouseMoved,
    mouseCursorPosition: moved,
    mouseButton: .left
) {
    moveEvent.post(tap: .cghidEventTap)
}
// Then move back 0.05s later
```

This creates real HID events that WindowServer registers as `UserIsActive`:
```
WindowServer: UserIsActive named: "com.apple.iohideventsystem.queue.tickle.nxevent service:IOHIDSystem pid:XXXX process:AmphetamineXL"
```

### How This Was Discovered

Reverse-engineering Amphetamine's binary with `nm`, `strings`, and `otool` revealed:
- `CGEventCreateMouseEvent` / `CGEventPost` imports
- `pSess_MoveMouse` / `MoveMouseInterval` / `MoveMouseSmoothSldr` properties
- `isDisplayClosed` — lid state detection
- "Drive Alive" — their feature name for the keepalive mechanism

Amphetamine has been using this technique all along. It's not documented anywhere public.

## Multi-Layer Defense Stack

AmphetamineXL uses 5 simultaneous layers, but **only the first one actually prevents clamshell sleep**. The others are supplementary:

| Layer | Interval | Purpose |
|-------|----------|---------|
| **CGEvent mouse jiggle** | 1s | **THE FIX** — prevents clamshell sleep via HID activity |
| IOKit assertions (x3) | Always held | Prevents idle sleep, system sleep, display sleep |
| caffeinate -s -w <app pid> | Always running while active | Kernel-level sleep prevention with automatic child cleanup |
| Network keepalive | 3s | Keeps hotspot/Wi-Fi alive (5 DNS hosts, UDP + TCP) |
| pmset max-awake profile | Session-owned | Applies `legacy-max-awake` while active and restores exact previous values when inactive |

### IOKit Assertions Held

| Assertion | What it blocks |
|---|---|
| `kIOPMAssertPreventUserIdleSystemSleep` | Idle timeout sleep |
| `kIOPMAssertionTypePreventSystemSleep` | System sleep (lid close on Intel; ignored by SMC on Apple Silicon) |
| `kIOPMAssertPreventUserIdleDisplaySleep` | Display dimming/sleep |

### Network Keepalive

Rotates through 5 DNS servers to keep network connections alive:
- 1.1.1.1 (Cloudflare), 8.8.8.8 (Google), 9.9.9.9 (Quad9), 208.67.222.222 (OpenDNS), 1.0.0.1 (Cloudflare secondary)

Each tick does:
1. UDP DNS lookup via `getaddrinfo`
2. Non-blocking TCP SYN to port 53 via `connect()`

Varied targets prevent any single host from rate-limiting and make traffic patterns look natural.

### pmset Ownership and Runtime Contract

AmphetamineXL now snapshots the exact `pmset` values it owns before changing them. On disable, quit, termination, or crash recovery, it restores those exact values instead of assuming defaults.

- Normal active runtime always uses `legacy-max-awake`
- `legacy-max-awake` owns `standby`, `hibernatemode`, `sleep`, `displaysleep`, and `disablesleep`
- `fixed-default` remains only for backwards-compatible decoding of older session files and logs
- Recovery runs before auto-enable so stale `pmset` state is cleaned up before a new session starts

## Logging

Dual logging:
- **Subsystem:** `com.hannojacobs.AmphetamineXL`
- **Category:** `SleepPrevention`
- **Persistent file logs:** `~/Library/Application Support/AmphetamineXL/Logs/`

```bash
log show --predicate 'subsystem == "com.hannojacobs.AmphetamineXL"' --last 10m
```

Events logged:
- 🚀 App init
- Session ID, wake profile, saved desired state, app/build version
- Full startup snapshots: `pmset -g`, `pmset -g custom`, `pmset -g assertions`, `pmset -g live`, related processes
- ⚡ Caffeine enable/disable with assertion results
- Exact `pmset` reads, applies, restores, exit codes, stdout, stderr
- `SleepDisabled` before apply, after apply, and after restore
- 🛑 `willSleep` — CRITICAL, means the jiggle failed
- 🟢 `didWake` — restarts all timers
- 🖥️ `screensDidSleep` / `screensDidWake` — display/lid events
- 🖱️ Jiggle count every 60 ticks (~1 min)
- 🌐 Keepalive count every 100 ticks (~5 min)
- ☕ caffeinate start/stop/death detection and stale-PID recovery
- 30-second heartbeats with current power-profile state
- Anomaly dumps with the recent trace buffer attached

## Sleep/Wake Notification Handling

Registers for 4 notifications via `NSWorkspace.shared.notificationCenter`:

| Notification | Handler |
|---|---|
| `willSleepNotification` | Posts last-ditch mouse event, logs CRITICAL |
| `didWakeNotification` | Restarts all timers, checks if caffeinate died |
| `screensDidSleepNotification` | Logs display off (lid close or manual) |
| `screensDidWakeNotification` | Logs display on (lid open) |

## AppState (@Observable)

`AppState` is the single source of truth. Uses `@Observable` macro (macOS 14+):
- `isActive: Bool` — is caffeine on?
- `activeSince: Date?` — when it was turned on
- `durationText: String` — "Active for Xh Ym" updated every 60s
- `menuBarIcon: String` — SF Symbol name driven by `isActive`
- `mouseJiggleCount: Int` — tracking for logs
- `keepaliveCount: Int` — tracking for logs

State persisted to `UserDefaults` under key `amphetamine_active`. On init, if saved state is `true` (or key not yet set), caffeine is re-enabled automatically. Default is ON.

## MenuBarExtra + SwiftUI Gotcha

Uses `MenuBarExtra` with `.window` style. SwiftUI `Button` inside `.window` style **dismisses the panel before the action fires**.

**Solution**: `HStack + .contentShape(Rectangle()) + .onTapGesture` for all interactive rows.

## Build System

Pure Swift Package Manager. No Xcode project file.

```bash
xcodebuild -scheme AmphetamineXL -configuration Release -destination 'platform=macOS' build
```

Binary: `~/Library/Developer/Xcode/DerivedData/AmphetamineXL-*/Build/Products/Release/AmphetamineXL`

## Known Side-Effects When Caffeinated

- Mac won't auto-lock (mouse jiggle = user activity)
- Screen won't dim
- Both intentional for "backpack mode" (lid is closed anyway)

When caffeine is disabled or the app quits, the exact pre-activation machine state is restored so normal sleep can work again.
