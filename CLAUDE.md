# AmphetamineXL — Claude Code Briefing

macOS menu bar app that prevents sleep including clamshell lid close on Apple Silicon. Swift SPM, macOS 14+, no Xcode project files. Hanno never opens Xcode — all work is done by agents via CLI.

Full briefing: see `AGENTS.md`. This file is the concise session-start reference.

---

## How It Works (v2.0)

**The core fix is CGEvent mouse jiggle.** Every 1 second, posts `CGEventCreateMouseEvent(.mouseMoved)` to move cursor 1px right then back. WindowServer registers this as `UserIsActive` HID activity. The SMC respects HID activity and won't enter clamshell sleep.

This was reverse-engineered from Amphetamine's binary (their "Drive Alive" feature).

IOKit assertions, caffeinate, and pmset are supplementary — they do NOT prevent clamshell sleep on Apple Silicon alone.

### Defense Stack

1. CGEvent mouse jiggle (1s) — prevents clamshell sleep
2. IOKit assertions (x3) — PreventUserIdleSystemSleep + PreventSystemSleep + PreventUserIdleDisplaySleep
3. caffeinate -s subprocess — kernel-level
4. Network keepalive (3s) — 5 DNS hosts, UDP + TCP probes
5. os.log logging — subsystem `com.hannojacobs.AmphetamineXL`
6. Sleep/wake notification handlers — restart timers on wake

## Stack

- Swift Package Manager — `Package.swift` is the source of truth, no `.xcodeproj`
- macOS 14+ (Observation framework, MenuBarExtra .window style)
- Bundle ID: `com.hannojacobs.AmphetamineXL`
- GitHub: `HannoJacobs/AmphetamineXL`
- GitHub Pages: `docs/` on `main` → https://hannojacobs.github.io/AmphetamineXL/

## Key Files

| File | Role |
|---|---|
| `Package.swift` | SPM manifest |
| `Sources/AmphetamineXL/AppState.swift` | All logic — CGEvent jiggle, IOKit, caffeinate, keepalive, os.log |
| `Sources/AmphetamineXL/MenuBarView.swift` | SwiftUI popup |
| `Sources/AmphetamineXL/AmphetamineXLApp.swift` | @main entry |
| `create-dmg.sh` | Packages binary → DMG, contains Info.plist with version strings |
| `.github/workflows/release.yml` | CI — builds + uploads DMG to latest GitHub release |

## Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme AmphetamineXL -configuration Release \
  -destination "platform=macOS" build
```

## Debugging

```bash
# View app logs
log show --predicate 'subsystem == "com.hannojacobs.AmphetamineXL"' --last 10m

# Check assertions
pmset -g assertions | grep -E "AmphetamineXL|caffeinate|UserIsActive"

# Check sleep/wake
pmset -g log | grep -E "Sleep|Wake|Clamshell" | tail -20
```

## Full Send Deploy (always do ALL steps in order)

1. **Bump version** in `create-dmg.sh` — `CFBundleVersion` + `CFBundleShortVersionString`
2. **Update** `CHANGELOG.md`
3. **Commit**: `git commit -m "vX.Y: <description>"`
4. **Create GitHub release BEFORE pushing** (CI uploads DMG to latest release):
   `gh release create vX.Y --title "vX.Y — <title>" --notes "..."`
5. **Push**: `git push origin main` (CI builds + uploads DMG)
6. **Install locally**:
   ```bash
   BINARY=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Release/AmphetamineXL" -type f 2>/dev/null | head -1)
   pkill -x AmphetamineXL 2>/dev/null || true && sleep 1
   cp "$BINARY" /Applications/AmphetamineXL.app/Contents/MacOS/AmphetamineXL
   open /Applications/AmphetamineXL.app
   ```
7. **Verify**: `pgrep -x AmphetamineXL` (PID) + `gh release view vX.Y` (has DMG asset)

## Critical Gotchas

**SwiftUI**: Use `onTapGesture` not `Button` in `MenuBarExtra .window` views — `Button` dismisses the popup on click.

**CGEvent**: The mouse jiggle is the ONLY thing that prevents clamshell sleep on Apple Silicon. Without it, everything else fails. Do not remove it.

**CI**: Always create the GitHub release BEFORE pushing. CI finds the latest release by `gh release list` and uploads to it.

**Version**: The version string lives in `create-dmg.sh` (the inline Info.plist), not in `Package.swift`.

## Definition of Done (deploy)

- [ ] `pgrep -x AmphetamineXL` returns a PID on local machine
- [ ] `gh release view vX.Y` shows `AmphetamineXL.dmg` as an asset
