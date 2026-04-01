# AmphetamineXL

**Your Mac stays awake when the lid closes. Actually.**

AmphetamineXL is a tiny macOS menu bar app that prevents your MacBook from sleeping when you close the lid — even on Apple Silicon, even without an external display, even on iPhone hotspot. One click. Works. No nonsense.

## Why does this exist?

On Apple Silicon Macs, closing the lid triggers a hardware-level "clamshell sleep" controlled by the SMC chip. This ignores IOKit assertions, `caffeinate`, `pmset` — every software-only approach.

AmphetamineXL solves this by posting synthetic mouse events via `CGEventCreateMouseEvent` every second. The SMC sees real HID activity and won't enter clamshell sleep. This technique was reverse-engineered from Amphetamine's binary (their "Drive Alive" feature).

## What it does

| Layer | Purpose |
|-------|---------|
| 🖱️ Mouse jiggle (1s) | Prevents clamshell sleep — the key fix |
| 🔒 Auto-lock on lid close | Locks screen + kills display backlight |
| 🌐 Network keepalive (3s) | 5 DNS targets, keeps hotspot/Wi-Fi alive |
| ☕ caffeinate + IOKit | Kernel + OS level sleep prevention |
| 🧠 Smart lid detection | Only activates defense when lid is actually closed |

## Install (DMG)

Download from [Releases](https://github.com/HannoJacobs/AmphetamineXL/releases/latest), drag to Applications, then run:

```bash
xattr -cr /Applications/AmphetamineXL.app && open /Applications/AmphetamineXL.app
```

On first launch, AmphetamineXL will prompt once for your password to set up passwordless pmset access. This is a one-time setup.

That's it. ⚡ appears in menu bar, caffeinated by default. Close your lid — Mac stays awake.

## Install (build from source)

```bash
git clone https://github.com/HannoJacobs/AmphetamineXL && cd AmphetamineXL && xcodebuild -scheme AmphetamineXL -configuration Release -destination 'platform=macOS' build && BINARY=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Release/AmphetamineXL" -type f 2>/dev/null | head -1) && mkdir -p /Applications/AmphetamineXL.app/Contents/MacOS && cp "$BINARY" /Applications/AmphetamineXL.app/Contents/MacOS/AmphetamineXL && xattr -cr /Applications/AmphetamineXL.app && open /Applications/AmphetamineXL.app
```

## Verify

```bash
pgrep -x AmphetamineXL && pmset -g assertions | grep -E "AmphetamineXL|UserIsActive" && pmset -g | grep -E "standby|hibernatemode|autopoweroff"
```

## Debug

```bash
# App logs in macOS unified logging
log show --predicate 'subsystem == "com.hannojacobs.AmphetamineXL"' --last 10m

# Persistent rotating log files
open ~/Library/Application\\ Support/AmphetamineXL/Logs

# Sleep/wake history
pmset -g log | grep -E "Sleep|Wake|Clamshell" | tail -20

# Lid state
/usr/sbin/ioreg -r -k AppleClamshellState | grep AppleClamshellState
```

## Usage

- **⚡** = caffeinated (Mac stays awake with lid closed)
- **⚡/** = sleeping (normal behaviour)
- Click to toggle. Optional: enable "Launch at Login"

**Lid closed:** screen locks → display off → mouse jiggle active → Mac stays awake
**Lid open:** screen dims/locks normally, no jiggle interference

## Recovery + Rollback

- Baseline rollback artifacts live in `~/Library/Application Support/AmphetamineXL/Rollback/`
- Session diagnostics live in `~/Library/Application Support/AmphetamineXL/Logs/`
- Hidden rollback mode:

```bash
defaults write com.hannojacobs.AmphetamineXL wakeProfile legacy-max-awake
```

- Return to the default fixed profile:

```bash
defaults delete com.hannojacobs.AmphetamineXL wakeProfile
```

## License

MIT
