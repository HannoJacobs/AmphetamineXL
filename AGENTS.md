# AmphetamineXL — Agent Briefing

This repo is maintained entirely by agents. Hanno never opens Xcode. Read this before touching anything.

---

## What It Is

AmphetamineXL is a macOS menu bar app that prevents Apple Silicon clamshell sleep — the hardware-level sleep that occurs when you close the lid without an external display.

- **Platform**: macOS 14+ (Sonoma+)
- **Build system**: Swift Package Manager (no .xcodeproj)
- **Bundle ID**: `com.hannojacobs.AmphetamineXL`
- **GitHub**: `HannoJacobs/AmphetamineXL`
- **GitHub Pages**: `docs/` folder on `main` → https://hannojacobs.github.io/AmphetamineXL/
- **Current version**: v2.3

---

## How Sleep Prevention Works

### The Core Fix: CGEvent Mouse Jiggle

On Apple Silicon, **IOKit assertions do NOT prevent clamshell sleep**. The SMC ignores them. The only thing the SMC respects is HID (Human Interface Device) activity.

AmphetamineXL posts `CGEventCreateMouseEvent(.mouseMoved)` every 1 second, moving the cursor 1px right then back. WindowServer registers this as `UserIsActive`. The SMC sees HID activity and won't enter clamshell sleep.

**This was reverse-engineered from Amphetamine's binary** (their "Drive Alive" feature). Do NOT remove the mouse jiggle — it's the only thing that actually prevents clamshell sleep.

### Smart Lid Detection

The app detects lid state via `AppleClamshellState` (IOKit `IOPMrootDomain`, polled every 2s) and behaves differently:

**Lid open:**
- 2 IOKit assertions (PreventUserIdleSystemSleep + PreventSystemSleep)
- caffeinate -s subprocess
- Network keepalive (5 DNS hosts, 3s interval)
- NO mouse jiggle (screen dims/locks normally)
- NO display assertion

**Lid closed:**
- All of the above, PLUS:
- 🔒 Auto-lock via ScreenSaverEngine
- 🖥️ Display forced off via `pmset displaysleepnow`
- 🖱️ Mouse jiggle (1s interval)
- Display assertion (`PreventUserIdleDisplaySleep`)

### Multi-Layer Defense Stack

| Layer | Interval | What it prevents |
|-------|----------|-----------------|
| CGEvent mouse jiggle | 1s (lid closed only) | Clamshell sleep (THE key fix) |
| IOKit assertions (x2-3) | Always held | Idle + system sleep (+ display when lid closed) |
| caffeinate -s subprocess | Always running | Kernel-level sleep prevention |
| Network keepalive (5 DNS hosts) | 3s | Hotspot/Wi-Fi connection drops |
| Auto-lock + display off | On lid close | Security + battery saving |
| pmset overrides | System-level (one-time) | Deep standby/hibernate |

### Logging

Subsystem: `com.hannojacobs.AmphetamineXL`, category: `SleepPrevention`

```bash
log show --predicate 'subsystem == "com.hannojacobs.AmphetamineXL"' --last 10m
```

Logs: init, assertion results, lid state changes, lock events, sleep/wake notifications, jiggle count (every 60s), keepalive count (every 5min).

---

## Project Structure

```
AmphetamineXL/
├── Package.swift                          # SPM manifest — macOS 14+, LaunchAtLogin-Modern dep
├── Package.resolved                       # Lockfile — commit this
├── create-dmg.sh                          # Packages built binary → DMG, contains Info.plist with VERSION
├── Sources/AmphetamineXL/
│   ├── AmphetamineXLApp.swift             # @main entry, MenuBarExtra scene
│   ├── AppState.swift                     # ALL logic: jiggle, IOKit, caffeinate, keepalive, lid detect, lock, os.log
│   └── MenuBarView.swift                  # SwiftUI popup view — uses onTapGesture not Button
├── docs/
│   ├── index.html                         # Landing page (GitHub Pages) — has all install/debug commands
│   ├── ARCHITECTURE.md                    # Technical deep-dive
│   └── CONTRIBUTING.md                    # Agent contribution guide
├── .github/workflows/release.yml          # CI: builds on push to main, uploads DMG to latest release
├── AGENTS.md                              # This file
├── CLAUDE.md                              # Claude Code variant of this briefing
├── HANDOFF.md                             # Session handoff document
└── CHANGELOG.md                           # Version history
```

---

## How to Build

```bash
cd /Users/hannojacobs/Documents/Code/AmphetamineXL && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme AmphetamineXL -configuration Release \
  -destination "platform=macOS" build
```

Binary lands in `~/Library/Developer/Xcode/DerivedData/AmphetamineXL-*/Build/Products/Release/AmphetamineXL`.

---

## How to Deploy Locally After Build

```bash
pkill -x AmphetamineXL 2>/dev/null || true
sleep 1
BINARY=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Release/AmphetamineXL" -type f 2>/dev/null | head -1)
cp "$BINARY" /Applications/AmphetamineXL.app/Contents/MacOS/AmphetamineXL
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion X.Y" /Applications/AmphetamineXL.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString X.Y" /Applications/AmphetamineXL.app/Contents/Info.plist
open /Applications/AmphetamineXL.app
sleep 2
pgrep -x AmphetamineXL  # must return a PID
```

---

## Full Send Deploy Sequence

"Full send" = bump version + update docs + commit + create GitHub release + push + install locally + verify.

### Step 1 — Bump version in `create-dmg.sh`

Update both `CFBundleVersion` and `CFBundleShortVersionString` in the inline Info.plist.

### Step 2 — Update CHANGELOG.md

### Step 3 — Update all docs that reference the version or features

Check and update as needed: `README.md`, `HANDOFF.md`, `CLAUDE.md`, `AGENTS.md`, `docs/index.html`, `docs/ARCHITECTURE.md`

### Step 4 — Commit

```bash
git add -A && git commit -m "vX.Y: <short description>"
```

### Step 5 — Create GitHub release BEFORE pushing

```bash
gh release create vX.Y --title "vX.Y — <title>" --notes "..."
```

### Step 6 — Push to main (triggers CI)

```bash
git push origin main
```

### Step 7 — Install locally (see deploy section above)

### Step 8 — Verify

```bash
pgrep -x AmphetamineXL        # must print a PID
gh release view vX.Y           # must show AmphetamineXL.dmg as an asset
pmset -g assertions | grep AmphetamineXL  # must show assertions
```

---

## Debugging Commands

```bash
# App running?
pgrep -x AmphetamineXL

# Assertions held?
pmset -g assertions | grep -E "AmphetamineXL|caffeinate|UserIsActive"

# Lid state?
/usr/sbin/ioreg -r -k AppleClamshellState | grep AppleClamshellState

# App logs?
log show --predicate 'subsystem == "com.hannojacobs.AmphetamineXL"' --last 10m

# Sleep/wake history?
pmset -g log | grep -E "Sleep|Wake|Clamshell" | tail -20

# Standby disabled?
pmset -g | grep -E "standby|hibernatemode|autopoweroff"
```

---

## Key Files Deep Dive

### AppState.swift
- `@Observable @MainActor` — SwiftUI Observation framework (macOS 14+)
- **CGEvent mouse jiggle** — `CGEventCreateMouseEvent(.mouseMoved)` every 1s (lid closed only)
- **Lid detection** — `AppleClamshellState` via IOKit `IOPMrootDomain`, polled every 2s
- **Auto-lock** — ScreenSaverEngine + `pmset displaysleepnow` on lid close
- **IOKit assertions** — 2 always (idle + system), 1 on lid close (display)
- **caffeinate -s** subprocess for kernel-level sleep prevention
- **Network keepalive** — rotates 5 DNS hosts with UDP + TCP probes every 3s
- **os.log** — subsystem `com.hannojacobs.AmphetamineXL`, category `SleepPrevention`
- **Sleep/wake notifications** — willSleep, didWake, screensDidSleep, screensDidWake
- State persisted via `UserDefaults` key `"amphetamine_active"`

### MenuBarView.swift
- **Use `onTapGesture`, NOT `Button`** in `MenuBarExtra .window` style views
- `Button` in `.window`-style `MenuBarExtra` dismisses the popup on click — SwiftUI bug
- `contentShape(Rectangle())` required for full-width hit target

### create-dmg.sh
- Builds `.app` bundle from compiled binary
- Writes `Info.plist` inline — **this is where you bump the version**
- Creates DMG with Applications symlink

---

## Critical Rules

- **Never remove the mouse jiggle** — it's the ONLY thing that prevents clamshell sleep on Apple Silicon
- **Never create `.xcodeproj`** — SPM only
- **Always create GitHub release BEFORE pushing** — CI uploads DMG to latest release
- **Always verify with `pgrep` after deploy** — don't mark done without it
- **Version lives in `create-dmg.sh`** only (not Package.swift)
- **Use `onTapGesture` not `Button`** in MenuBarExtra window views

---

## Dependencies

| Package | Purpose |
|---|---|
| `LaunchAtLogin-Modern` (sindresorhus) | Register/unregister launch-at-login via SMAppService |
