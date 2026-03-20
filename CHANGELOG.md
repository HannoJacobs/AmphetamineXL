# Changelog

## v2.0 — 2026-03-20 (current) 🎉
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
