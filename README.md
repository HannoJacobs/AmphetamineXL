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
| 🤖 Tool-aware auto-awake | Keeps the Mac awake while Codex / Claude work is still active |

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
pgrep -x AmphetamineXL && pmset -g assertions | grep -E "AmphetamineXL|caffeinate|UserIsActive" && pmset -g live | grep -E "SleepDisabled|standby|hibernatemode|sleep|displaysleep"
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

- **Caffeine ON** = aggressive max-awake machine state while the app is active
- **Caffeine OFF** = app stays resident, but your normal sleep-capable machine settings are restored
- Click to toggle. Optional: enable "Launch at Login"
- Even with manual caffeine off, AmphetamineXL can now keep the Mac awake automatically while monitored Codex / Claude work is still active
- After monitored work finishes, the app keeps the wake stack alive for 60 more seconds before releasing it

**Lid closed:** screen locks → display off → mouse jiggle active → Mac stays awake
**Lid open:** no jiggle interference, but the active max-awake `pmset` profile is still held until you disable caffeine or quit the app

### Monitored tools

Automatic wake monitoring currently checks local runtime state for:

- `Codex.app`
- `codex` CLI processes
- Codex queued follow-ups from `~/.codex/.codex-global-state.json`
- `claude` / Claude Code sessions from `~/.claude/sessions`
- Claude todo payloads from `~/.claude/todos`

This means the app can hold the wake stack for active Codex / Claude work even when manual caffeine is off, then release it after the 60-second cooldown.

## Recovery + Rollback

- Baseline rollback artifacts live in `~/Library/Application Support/AmphetamineXL/Rollback/`
- Session diagnostics live in `~/Library/Application Support/AmphetamineXL/Logs/`
- Runtime contract:

- Caffeine ON: `legacy-max-awake`
- Caffeine OFF or app quit: restore the captured normal machine state
- Full rollback details: [docs/ROLLBACK.md](docs/ROLLBACK.md)

## License

MIT
