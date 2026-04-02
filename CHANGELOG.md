# Changelog

## Unreleased
> Active mode is now always max-awake, with normal sleep restored on disable or quit.

### What changed
- **Active runtime contract simplified:** Caffeine ON now always applies the aggressive `legacy-max-awake` machine profile. The retired `fixed-default` path remains only for backwards-compatible decoding of older session state and logs.
- **Normal sleep restored when inactive:** Disabling caffeine or quitting the app restores the exact pre-activation `pmset` snapshot, including `sleep`, `displaysleep`, `standby`, `hibernatemode`, and `disablesleep`.
- **Better power diagnostics:** Logs now explicitly record the active runtime contract and `SleepDisabled` before apply, after apply, and after restore.
- **Safer helper teardown:** The `caffeinate` termination callback no longer mutates tracked session state directly, avoiding the exclusivity crash seen when disabling caffeine from the menu bar.

## v2.3.2 — 2026-04-02 (current)
> Fix the default-on launch source and keep the inactive menu bar item visible.

### What changed
- **First launch defaults to ON again:** Launch state now comes from the saved user preference only, with a hard default of `true` when no preference exists. Stale session-state files no longer influence the first-launch default.
- **Stable menu bar label updates:** The menu bar extra now uses an explicit label view instead of the `systemImage:` initializer, which makes active/inactive icon changes more reliable.
- **Visible inactive icon:** The inactive menu bar state now uses `bolt.circle`, which is much harder to mistake for the app disappearing.

## v2.3.1 — 2026-04-02
> Fix the inactive menu bar icon so the app stays visibly present when caffeine is off.

### What changed
- **Visible inactive menu bar state:** The menu bar extra now uses a plain `bolt` icon when caffeine is disabled instead of `bolt.slash`, which made the app look like it had quit even though the process was still running.
- **Behavior unchanged:** Disabling caffeine still tears down the wake stack and restores app-owned `pmset` values, but the app remains resident in the menu bar in a clearly visible inactive state.

## v2.3 — 2026-04-01
> Leak-proof wake stack, hidden legacy rollback profile, and persistent diagnostics.

### What changed
- **Crash-safe caffeinate:** Replaced the raw helper with `caffeinate -s -w <app pid>` so it follows the app lifecycle and no longer survives normal app exits or crashes.
- **Single shutdown path:** Disable, menu quit, app termination, and launch recovery now all use the same teardown logic. Assertions, timers, `caffeinate`, and app-owned `pmset` state are cleaned up in one place.
- **Session recovery:** On launch, the app loads the previous session state, kills any recorded stale `caffeinate`, restores app-owned `pmset` keys after unclean exits, and logs the entire recovery pass before re-enabling caffeine.
- **Power profiles:** Added hidden `wakeProfile` support with `fixed-default` as the original default and `legacy-max-awake` as the built-in rollback profile. Later work on `main` simplified normal active runtime to always use `legacy-max-awake`.
- **Owned pmset restore:** The app now snapshots the exact per-source values it changes and restores those exact values instead of assuming system defaults.
- **Persistent diagnostics:** Added rotating file logs in `~/Library/Application Support/AmphetamineXL/Logs/` alongside `os.log`, 30-second heartbeats, startup snapshots, anomaly dumps, command stdout/stderr capture, and a menu action to open the logs immediately.
- **Rollback artifacts:** The app writes a baseline snapshot in Application Support so future investigations can compare current state to the first fixed-build launch state.

## v2.2 — 2026-03-24
> Automatic deep sleep management — pmset handled by the app, not the user.

### What changed
- **One-time sudoers setup:** On first launch, prompts once for password to create `/etc/sudoers.d/amphetaminexl` (grants passwordless `sudo pmset` only). Never stores your password.
- **pmset on toggle:** When caffeine turns ON, disables deep sleep (standby 0, hibernatemode 0, autopoweroff 0 where supported). When caffeine turns OFF, restores the exact values the app replaced.
- **No manual setup:** Removed `sudo pmset` from install command - the app manages it automatically.

## v2.1 — 2026-03-20
> Smart lid handling — jiggle, lock, and display off only when lid is closed.

### What changed
- **Smart lid detection:** Polls `AppleClamshellState` via IOKit every 2s to reliably detect lid open/close
- **Auto-lock on lid close:** Launches ScreenSaverEngine which triggers the lock screen (requires "Require password after screen saver" in System Settings)
- **Display off on lid close:** After locking, runs `pmset displaysleepnow` to kill backlight — no pixels burning with lid closed
- **Mouse jiggle only when lid is closed:** Screen can dim and Mac can auto-lock normally when lid is open
- **Display assertion only when lid is closed:** `PreventUserIdleDisplaySleep` only held during clamshell mode

### Lid open behavior
- 2 IOKit assertions (system sleep prevention)
- caffeinate subprocess
- Network keepalive
- Screen dims/locks normally

### Lid closed behavior
- All of the above, plus:
- Mouse jiggle (1s) — prevents clamshell sleep
- Display assertion held
- Screen locked via ScreenSaverEngine
- Display forced off via pmset

## v2.0 — 2026-03-20 🎉
> **THE FIX.** Lid-close sleep on Apple Silicon is finally solved.
> Mac stays fully awake with lid closed, no external display, on iPhone hotspot. Backpack mode works.

### What changed
- **CGEvent mouse jiggle (the breakthrough):** Posts `CGEventCreateMouseEvent(.mouseMoved)` every 1 second, moving the cursor 1px right then back. This creates real HID events that WindowServer registers as `UserIsActive`. The SMC respects HID activity and will NOT enter clamshell sleep. This was reverse-engineered from Amphetamine's binary — it's the same technique they use.
- **Enhanced network keepalive:** Rotates through 5 DNS servers (Cloudflare, Google, Quad9, OpenDNS) every 3 seconds with both UDP DNS lookups and non-blocking TCP SYN probes. Keeps hotspot/Wi-Fi connections alive with varied traffic patterns.
- **Full os.log logging:** Subsystem `com.hannojacobs.AmphetamineXL`, category `SleepPrevention`. Logs assertion creation, sleep/wake events, jiggle counts, keepalive stats. Use `log show --predicate 'subsystem == "com.hannojacobs.AmphetamineXL"'` to inspect.
- **Sleep/wake notification handling:** Registers for `willSleep`, `didWake`, `screensDidSleep`, `screensDidWake`. Restarts all timers on wake. Posts a last-ditch mouse event on `willSleep`.

### Root cause (confirmed)
On Apple Silicon with no external display, lid-close triggers a mandatory SMC-level clamshell sleep. This is a hardware event that ignores:
- IOKit assertions (`PreventSystemSleep`, `PreventUserIdleSystemSleep`, etc.)
- `caffeinate -s`
- `pmset standby 0`

The ONLY thing the SMC respects is real HID (Human Interface Device) activity. By posting synthetic mouse events via `CGEventCreateMouseEvent`, we fool the SMC into thinking a user is present. No sleep occurs.

### How it was discovered
Reverse-engineering Amphetamine's binary with `nm`, `strings`, and `otool` revealed:
- `CGEventCreateMouseEvent` / `CGEventPost` imports
- `pSess_MoveMouse` / `MoveMouseInterval` properties
- "Drive Alive" feature (their name for the keepalive mechanism)

### Known side-effects
- Mac won't auto-lock while caffeinated (mouse jiggle counts as user activity)
- Screen won't dim/sleep while caffeinated
- Both are intentional for the "backpack mode" use case

### Multi-layer defense (all active simultaneously)
1. **CGEvent mouse jiggle** — 1px move every 1s (prevents clamshell sleep)
2. **IOKit assertions** — PreventUserIdleSystemSleep + PreventSystemSleep + PreventUserIdleDisplaySleep
3. **caffeinate -s subprocess** — kernel-level sleep prevention
4. **Network keepalive** — 5 DNS targets, UDP + TCP probes every 3s
5. **pmset overrides** — standby 0, hibernatemode 0, autopoweroff 0 (system-level)

## v1.4 — 2026-03-20
> **Note:** Requires one-time system change — see README. Without it, Apple Silicon standby overrides all sleep prevention.
- Fix: launch `caffeinate -s` subprocess to block standby/clamshell sleep at kernel level (IOKit assertions alone don't survive Apple Silicon standby)
- Fix: network keepalive ping every 5s to prevent iPhone Personal Hotspot from dropping

## v1.3 — 2026-03-20
- Default ON: caffeine enabled automatically on first launch and after login
- User must manually disable — off is never the default

## v1.2 — 2026-03-20
- Fix: hold PreventUserIdleDisplaySleep assertion so Chrome/Meet doesn't drop when lid closes
- Now holds all 3 assertions: PreventUserIdleSystemSleep, PreventSystemSleep, PreventUserIdleDisplaySleep

## v1.1 — 2026-03-20
- Added ⚡ lightning bolt app icon
- Agent scaffolding: AGENTS.md, CLAUDE.md, ARCHITECTURE.md, cursor rules

## v1.0 — 2026-03-20
- Initial release
- Menu bar caffeine toggle with proper clamshell sleep prevention
- Holds PreventSystemSleep assertion (blocks lid-close sleep that Amphetamine misses)
- Launch at login support
- Remembers active state across restarts
- Duration display (shows how long caffeine has been active)
