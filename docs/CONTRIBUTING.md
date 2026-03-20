# Contributing

This repo is agent-operated. Hanno doesn't open Xcode. All changes are made via Claude Code, Codex, or equivalent agents through the CLI.

## How to make changes

1. Read `AGENTS.md` first — it has the full context
2. Edit Swift source files in `Sources/AmphetamineXL/`
3. Build to verify:
   ```bash
   cd /Users/hannojacobs/Documents/Code/AmphetamineXL && \
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -scheme AmphetamineXL -configuration Release \
     -destination "platform=macOS" build
   ```
4. Deploy and test locally before pushing
5. Full send deploy with the checklist in `AGENTS.md`

## Critical rules

- **Never remove the mouse jiggle** — it's the only thing that prevents Apple Silicon clamshell sleep
- **Never create `.xcodeproj`** — everything goes through SPM (`Package.swift`)
- **Use `onTapGesture` not `Button`** in MenuBarExtra `.window` views (Button dismisses the popup)
- **`@Observable` not `ObservableObject`** (macOS 14+)
- **Version lives in `create-dmg.sh`** — the inline Info.plist, not Package.swift
- **Create GitHub release BEFORE pushing** — CI uploads DMG to latest release

## Architecture quick ref

The app has two modes based on lid state (`AppleClamshellState` via IOKit):

**Lid open:** IOKit assertions + caffeinate + network keepalive. No jiggle. Screen behaves normally.

**Lid closed:** Everything above + mouse jiggle (CGEvent, 1s) + auto-lock (ScreenSaverEngine) + display off (pmset displaysleepnow) + display assertion.

See `docs/ARCHITECTURE.md` for the full deep-dive.

## Debugging

```bash
# App logs
log show --predicate 'subsystem == "com.hannojacobs.AmphetamineXL"' --last 10m

# Assertions
pmset -g assertions | grep -E "AmphetamineXL|caffeinate|UserIsActive"

# Lid state
/usr/sbin/ioreg -r -k AppleClamshellState | grep AppleClamshellState

# Sleep/wake history
pmset -g log | grep -E "Sleep|Wake|Clamshell" | tail -20
```

## Dependencies

Keep it lean. Currently only `LaunchAtLogin-Modern` (sindresorhus). Prefer well-maintained Swift ecosystem packages.
