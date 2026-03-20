# AmphetamineXL

**Your Mac stays awake when the lid closes. Actually.**

AmphetamineXL is a tiny macOS menu bar app that prevents your MacBook from sleeping when you close the lid — even on Apple Silicon, even without an external display, even on iPhone hotspot. One click. Works. No nonsense.

## Why does this exist?

On Apple Silicon Macs, closing the lid triggers a hardware-level "clamshell sleep" controlled by the SMC chip. This ignores:
- IOKit assertions (`caffeinate`, Amphetamine, etc.)
- `pmset` settings
- Every software-only approach

AmphetamineXL solves this by posting synthetic mouse events via `CGEventCreateMouseEvent` every second. The SMC sees real HID (Human Interface Device) activity and won't enter clamshell sleep. This is the same technique used by Amphetamine's "Drive Alive" feature, reverse-engineered from their binary.

## What it does (multi-layer defense)

| Layer | What | Why |
|-------|------|-----|
| 🖱️ CGEvent mouse jiggle | 1px move every 1s | Prevents clamshell sleep (the key fix) |
| 🔒 IOKit assertions | 3 types held simultaneously | Prevents idle + system + display sleep |
| ☕ caffeinate -s | Subprocess | Kernel-level sleep prevention |
| 🌐 Network keepalive | 5 DNS targets, UDP+TCP every 3s | Keeps hotspot/Wi-Fi alive |

## ⚠️ Required: Disable macOS Standby (one-time)

```bash
sudo pmset -a standby 0 && sudo pmset -a hibernatemode 0 && sudo pmset -a autopoweroff 0
```

This disables Apple Silicon's deep standby state that overrides all software sleep prevention. Normal sleep still works when AmphetamineXL is off. Persists across reboots.

To revert: `sudo pmset -a standby 1 && sudo pmset -a hibernatemode 3`

## Install

1. Download `AmphetamineXL.dmg` from [Releases](https://github.com/HannoJacobs/AmphetamineXL/releases/latest)
2. Open the DMG and drag to Applications
3. Open Terminal, run: `xattr -cr /Applications/AmphetamineXL.app`
4. Open AmphetamineXL — ⚡ appears in menu bar, caffeinated by default
5. **Run the standby command above** (one-time, requires password)
6. Close your lid — Mac stays awake ✅

## Usage

- **⚡ bolt** = caffeinated, Mac stays awake with lid closed
- **⚡/ bolt-slash** = sleeping, normal Mac sleep behaviour
- Click the icon → toggle caffeine on/off
- Optional: enable "Launch at Login"

## Known side-effects when caffeinated

- Mac won't auto-lock (mouse jiggle counts as user activity)
- Screen won't dim/sleep
- Both are intentional for the "backpack mode" use case (lid is closed anyway)

## Verify it's working

```bash
# Check the app is running
pgrep -x AmphetamineXL && echo "✅ App running" || echo "❌ Not running"

# Check sleep assertions are held
pmset -g assertions | grep -E "AmphetamineXL|caffeinate|UserIsActive"

# Check standby is disabled
pmset -g | grep -E "standby|hibernatemode|autopoweroff"

# Check caffeinate subprocess is alive
pgrep -x caffeinate
```

## Debugging

```bash
# View the app's detailed logs (init, assertions, sleep/wake events, jiggle counts)
log show --predicate 'subsystem == "com.hannojacobs.AmphetamineXL"' --last 10m

# Check sleep/wake history
pmset -g log | grep -E "Sleep|Wake|Clamshell" | tail -20

# Check all current assertions
pmset -g assertions

# Check lid state
ioreg -r -k AppleClamshellState | grep AppleClamshellState

# Revert standby settings (re-enable deep sleep)
sudo pmset -a standby 1 && sudo pmset -a hibernatemode 3 && sudo pmset -a autopoweroff 1
```

## Build from source

```bash
git clone https://github.com/HannoJacobs/AmphetamineXL
cd AmphetamineXL
xcodebuild -scheme AmphetamineXL -configuration Release -destination 'platform=macOS' build
```

One-liner to build and install:
```bash
git clone https://github.com/HannoJacobs/AmphetamineXL && cd AmphetamineXL && xcodebuild -scheme AmphetamineXL -configuration Release -destination 'platform=macOS' build && BINARY=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Release/AmphetamineXL" -type f 2>/dev/null | head -1) && mkdir -p /Applications/AmphetamineXL.app/Contents/MacOS && cp "$BINARY" /Applications/AmphetamineXL.app/Contents/MacOS/AmphetamineXL && xattr -cr /Applications/AmphetamineXL.app && open /Applications/AmphetamineXL.app
```

## How it was figured out

Reverse-engineering Amphetamine's binary revealed their "Drive Alive" feature uses `CGEventCreateMouseEvent` + `CGEventPost` to simulate mouse movement. This is the only technique that prevents Apple Silicon clamshell sleep without an external display. Everything else (IOKit assertions, caffeinate, pmset) is supplementary.

## License

MIT
