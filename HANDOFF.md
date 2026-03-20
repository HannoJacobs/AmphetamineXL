# AmphetamineXL — Handoff Document

**Date:** 2026-03-20
**Status:** ✅ WORKING — v2.0 confirmed. Mac stays awake with lid closed, no external display, on iPhone hotspot.

---

## What It Is

AmphetamineXL — a macOS menu bar app that prevents Mac sleep when lid is closed.
- Repo: `/Users/hannojacobs/Documents/Code/AmphetamineXL`
- GitHub: https://github.com/HannoJacobs/AmphetamineXL
- Installed: `/Applications/AmphetamineXL.app`
- Current version: v2.0

## The Problem (solved)

MacBook (Apple Silicon) goes to Clamshell Sleep when lid closes, dropping iPhone hotspot. Need "backpack mode" — close lid, put in bag, everything stays connected.

## The Solution

**CGEvent mouse jiggle** — the only technique that prevents Apple Silicon clamshell sleep without an external display.

Every 1 second, the app posts `CGEventCreateMouseEvent(.mouseMoved)` to move the cursor 1px right then back. WindowServer registers this as `UserIsActive` HID activity. The SMC respects HID activity and won't enter clamshell sleep.

**Discovery:** Reverse-engineered from Amphetamine's binary using `nm`, `strings`, and `otool`. Key symbols found:
- `CGEventCreateMouseEvent` / `CGEventPost` (imports)
- `pSess_MoveMouse` / `MoveMouseInterval` (properties)
- "Drive Alive" (their feature name)

## Full Defense Stack (all active simultaneously)

1. **CGEvent mouse jiggle** — 1px move every 1s (THE fix)
2. **IOKit assertions** — PreventUserIdleSystemSleep + PreventSystemSleep + PreventUserIdleDisplaySleep
3. **caffeinate -s subprocess** — kernel-level sleep prevention
4. **Network keepalive** — rotates 5 DNS servers (Cloudflare, Google, Quad9, OpenDNS, Cloudflare secondary), UDP DNS lookup + TCP SYN probe every 3s
5. **pmset overrides** — standby 0, hibernatemode 0, autopoweroff 0

## Logging

Full `os.log` logging added. Subsystem: `com.hannojacobs.AmphetamineXL`, category: `SleepPrevention`.

```bash
# View all app logs
log show --predicate 'subsystem == "com.hannojacobs.AmphetamineXL"' --last 10m

# Check assertions
pmset -g assertions | grep -E "AmphetamineXL|caffeinate|UserIsActive"

# Check sleep/wake history
pmset -g log | grep -E "Sleep|Wake|Clamshell" | tail -20
```

Logs include:
- App init and assertion creation (with success/failure)
- Sleep/wake/display notifications
- Jiggle count every 60 ticks (~1 min)
- Keepalive count every 100 ticks (~5 min)
- caffeinate subprocess status

## What We Tried That Didn't Work (for posterity)

1. **IOKit assertions only** → SMC ignores them for clamshell sleep
2. **caffeinate -s** → SMC overrides it
3. **pmset standby 0** → Still enters Clamshell Sleep for ~15s then self-wakes
4. **Network pings only** → Doesn't prevent sleep, just helps hotspot stay connected after wake
5. **All of the above combined** → Still slept. Only the CGEvent mouse jiggle fixed it.

## Root Cause (documented)

On Apple Silicon with no external display, lid-close is a hardware event handled by the SMC. The SMC ignores all software sleep assertions. The ONLY thing it respects is HID (Human Interface Device) activity — which is what CGEventCreateMouseEvent provides.

This is fundamentally different from Intel Macs where `caffeinate -s` was sufficient.

## Known Side-Effects

- Mac won't auto-lock while caffeinated (mouse jiggle = user activity)
- Screen won't dim while caffeinated
- Both intentional for backpack mode (lid is closed)

## Future Improvements (not yet implemented)

- Only jiggle when display is off / lid is closed (detect via `screensDidSleep` notification) — would allow auto-lock when lid is open
- Privileged helper to set/unset `disablesleep` via pmset (like Amphetamine's `installPowerProtectSudoOverride`)
- Battery safeguard — auto-disable caffeine below X% battery
