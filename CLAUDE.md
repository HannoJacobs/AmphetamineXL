# AmphetamineXL — Claude Code Briefing

macOS menu bar app that prevents Apple Silicon clamshell sleep. Swift SPM, macOS 14+, no Xcode project files. Hanno never opens Xcode — all work is done by agents via CLI.

Full briefing: see `AGENTS.md`. This file is the concise session-start reference.

---

## How It Works (v2.3)

**The core fix is CGEvent mouse jiggle.** Every 1 second (only when lid is closed), posts `CGEventCreateMouseEvent(.mouseMoved)` to move cursor 1px right then back. WindowServer registers this as `UserIsActive` HID activity. The SMC respects HID activity and won't enter clamshell sleep.

This was reverse-engineered from Amphetamine's binary (their "Drive Alive" feature).

**Do NOT remove the mouse jiggle — it's the only thing that prevents clamshell sleep on Apple Silicon.**

### Lid-Aware Behavior

**Lid open:** 2 IOKit assertions + caffeinate + network keepalive. Screen dims/locks normally. No jiggle.

**Lid closed:** All of the above PLUS auto-lock (ScreenSaverEngine) → display off (`pmset displaysleepnow`) → mouse jiggle (1s) → display assertion held.

**Lid detection:** `AppleClamshellState` via IOKit `IOPMrootDomain`, polled every 2s.

### Defense Stack

1. CGEvent mouse jiggle (1s, lid closed only) — prevents clamshell sleep
2. IOKit assertions (x2 open, x3 closed)
3. caffeinate -s subprocess — kernel-level
4. Network keepalive (3s) — 5 DNS hosts, UDP + TCP probes
5. Auto-lock + display off on lid close
6. os.log logging — subsystem `com.hannojacobs.AmphetamineXL`
7. Sleep/wake notification handlers — restart timers on wake

## Key Files

| File | Role |
|---|---|
| `Sources/AmphetamineXL/AppState.swift` | ALL logic — jiggle, IOKit, caffeinate, keepalive, lid detect, lock, logging |
| `Sources/AmphetamineXL/MenuBarView.swift` | SwiftUI popup |
| `Sources/AmphetamineXL/AmphetamineXLApp.swift` | @main entry |
| `create-dmg.sh` | DMG packaging, contains Info.plist with **VERSION** (bump here) |

## Build + Deploy

```bash
# Build
cd /Users/hannojacobs/Documents/Code/AmphetamineXL && \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme AmphetamineXL -configuration Release \
  -destination "platform=macOS" build

# Deploy
pkill -x AmphetamineXL 2>/dev/null; sleep 1
BINARY=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Release/AmphetamineXL" -type f 2>/dev/null | head -1)
cp "$BINARY" /Applications/AmphetamineXL.app/Contents/MacOS/AmphetamineXL
open /Applications/AmphetamineXL.app
```

## Debugging

```bash
log show --predicate 'subsystem == "com.hannojacobs.AmphetamineXL"' --last 10m
pmset -g assertions | grep -E "AmphetamineXL|caffeinate|UserIsActive"
/usr/sbin/ioreg -r -k AppleClamshellState | grep AppleClamshellState
pmset -g log | grep -E "Sleep|Wake|Clamshell" | tail -20
```

## Full Send Deploy

1. Bump version in `create-dmg.sh` (CFBundleVersion + CFBundleShortVersionString)
2. Update `CHANGELOG.md`
3. Update ALL docs that reference version/features (`README.md`, `HANDOFF.md`, `CLAUDE.md`, `AGENTS.md`, `docs/index.html`, `docs/ARCHITECTURE.md`)
4. Commit: `git add -A && git commit -m "vX.Y: <description>"`
5. Create release BEFORE push: `gh release create vX.Y --title "vX.Y — <title>" --notes "..."`
6. Push: `git push origin main`
7. Deploy locally (see above) + bump Info.plist via PlistBuddy
8. Verify: `pgrep -x AmphetamineXL` + `gh release view vX.Y`

## Critical Rules

- **Never remove mouse jiggle** — only thing that prevents clamshell sleep
- **Use `onTapGesture` not `Button`** in MenuBarExtra .window views
- **Create GitHub release BEFORE pushing** (CI uploads DMG to latest)
- **Version lives in `create-dmg.sh`** only
