---
name: amphetamine-xl
description: >
  Build, deploy, and manage the AmphetamineXL macOS menu bar app.
  Use when: making changes to the app, doing a full send deployment,
  checking build status, updating the changelog, or managing the GitHub release.
---

# AmphetamineXL Skill

Repo: `/Users/hannojacobs/Documents/Code/AmphetamineXL`
GitHub: `HannoJacobs/AmphetamineXL`
Landing page: `https://hannojacobs.github.io/AmphetamineXL/`

## Key Facts
- Swift Package Manager, macOS 14+, NO Xcode project file
- Menu bar caffeine toggle — holds both IOKit sleep assertions (including clamshell)
- Bundle ID: `com.hannojacobs.AmphetamineXL`
- Version lives in `create-dmg.sh` (CFBundleVersion + CFBundleShortVersionString)

## Build
```bash
cd /Users/hannojacobs/Documents/Code/AmphetamineXL
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme AmphetamineXL -configuration Release -destination 'platform=macOS' build
```

## Full Send (deploy everything)
Read `AGENTS.md` in the repo root for the full sequence. Short version:
1. Bump version in `create-dmg.sh`
2. Update `CHANGELOG.md`
3. Commit all changes
4. `gh release create vX.Y --title "vX.Y — <title>" --notes "..."`
5. `git push` (CI builds DMG + uploads to release)
6. Install locally: find binary in DerivedData → kill old → cp to `/Applications/AmphetamineXL.app/Contents/MacOS/` → update plist → `open /Applications/AmphetamineXL.app`

## Check app is running
```bash
pgrep -x AmphetamineXL && echo "Running" || echo "Not running"
```

## Source files
- `Sources/AmphetamineXL/AppState.swift` — IOKit assertions, toggle logic, duration timer
- `Sources/AmphetamineXL/MenuBarView.swift` — SwiftUI menu bar popup
- `Sources/AmphetamineXL/AmphetamineXLApp.swift` — app entry point
- `create-dmg.sh` — packaging + version source of truth
- `docs/index.html` — landing page (GitHub Pages, auto-fetches release version)

## SwiftUI gotcha
Use `onTapGesture` not `Button` for menu rows in `MenuBarExtra(.window)` views —
Button can dismiss the popup before the action fires.
