# AmphetamineXL — Lid-Close Sleep Handoff

**Date:** 2026-03-20  
**Status:** Mac still sleeping on lid close despite all mitigations. Need root fix.

---

## What We Built

AmphetamineXL — a menu bar app that prevents Mac sleep when lid is closed. Lives at:
- Repo: `/Users/hannojacobs/Documents/Code/AmphetamineXL`
- GitHub: https://github.com/HannoJacobs/AmphetamineXL
- Installed: `/Applications/AmphetamineXL.app`
- Current version: v1.4

## The Core Problem

MacBook (Apple Silicon, ~2 years old) goes to **Clamshell Sleep** every time the lid closes, even with all sleep prevention active. This drops the iPhone Personal Hotspot connection.

**Current config:**
- `standby = 0` (disabled via sudo pmset)
- `hibernatemode = 0`
- `autopoweroff = 0`
- AmphetamineXL holding 3 IOKit assertions
- `caffeinate -s` subprocess running
- Ping to `172.20.10.1` (iPhone hotspot gateway) every 2s
- Ping to `1.1.1.1` every 3s

**Still sleeping.** Every lid close triggers ~15 second Clamshell Sleep, then it wakes itself up.

---

## Everything We Tried (in order)

### 1. IOKit assertions only
Held `kIOPMAssertPreventUserIdleSystemSleep` + `kIOPMAssertionTypePreventSystemSleep` + `kIOPMAssertPreventUserIdleDisplaySleep`.  
**Result:** Still slept. `PreventSystemSleep` shows `0` system-wide even when held.

### 2. caffeinate -s subprocess
Spawned `/usr/bin/caffeinate -s` as a child process of AmphetamineXL.  
**Result:** Still slept. SMC overrides it.

### 3. Disable standby via pmset
```bash
sudo pmset -a standby 0 && sudo pmset -a hibernatemode 0 && sudo pmset -a autopoweroff 0
```
**Result:** Standby shows 0, but Mac STILL enters Clamshell Sleep for ~15 seconds then self-wakes.

### 4. Network keepalive pings
Background pings to iPhone gateway + Cloudflare DNS.  
**Result:** Reduces hotspot drop probability but doesn't prevent the sleep.

---

## What the Logs Show

Check logs with:
```bash
pmset -g log | grep -E "Sleep|Wake|Clamshell" | tail -20
```

Pattern every time:
```
Entering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:XX%)
Wake from Deep Idle [CDNVA] : due to smc.sysState.Wake(0x70070000) lid SMC.OutboxNotEmpty/HID Activity
```

The `smc.sysState.Wake` means the **SMC itself is forcing the sleep AND the wake**. This is hardware-level, not software. The Mac sleeps for ~15s then wakes because the IOKit assertions eventually kick back in — but there's always that initial sleep window.

Check current assertions:
```bash
pmset -g assertions | grep -E "AmphetamineXL|caffeinate|PreventSystem"
```

Check if caffeinate is alive:
```bash
pgrep -x caffeinate
```

---

## Root Cause (current theory)

On Apple Silicon with **no external display connected**, macOS treats lid-close as a mandatory hardware event. The SMC forces a brief clamshell sleep regardless of software assertions. This is different from Intel Macs where `caffeinate -s` was sufficient.

Potential real fixes to investigate:
1. **Connect an external display** — Macs in "clamshell mode" with external display don't sleep. Could use a dummy HDMI dongle (~$5) to fool the Mac into thinking a display is connected.
2. **SleepWatcher** — a third-party daemon that can run scripts on sleep/wake events, potentially preventing sleep via a different kernel hook.
3. **pmset -b sleep 0** — disable sleep entirely on battery (nuclear, but might work). Command: `sudo pmset -b sleep 0`

---

## AmphetamineXL App State

The app itself is working correctly:
- Caffeinated by default on launch
- Holds all 3 IOKit assertions
- Spawns caffeinate subprocess
- Network keepalive every 5s
- Persists state across restarts
- `pgrep -x AmphetamineXL` to verify running

## What Hanno Wants

**Goal:** Close MacBook lid → put it in backpack → iPhone hotspot stays connected → agents keep running → open lid later and everything still works.

Use case: gym sessions, car travel. Mac is the brain, iPhone is the hotspot. No external display.

---

## Restart Prompt for Next Session

Copy-paste this to start fresh:

> Read `/Users/hannojacobs/Documents/Code/AmphetamineXL/HANDOFF.md` — we built AmphetamineXL (menu bar caffeine app) but the Mac still sleeps briefly on lid close due to Apple Silicon SMC clamshell behaviour. Everything we tried is documented there including log commands. Continue the investigation and fix the lid-close sleep. The app is installed and running at `/Applications/AmphetamineXL.app`. The repo is at `/Users/hannojacobs/Documents/Code/AmphetamineXL`.
