# AmphetamineXL — Agent Briefing

This repo is maintained entirely by agents. Hanno never opens Xcode. Read this before touching anything.

---

## What It Is

AmphetamineXL is a macOS menu bar app that prevents sleep — including lid-close (clamshell) sleep. It's a spiritual successor to Amphetamine, but better: it holds the `PreventSystemSleep` IOKit assertion that Amphetamine misses, which is what actually blocks clamshell sleep.

- **Platform**: macOS 14+ (Sonoma+)
- **Build system**: Swift Package Manager (no .xcodeproj)
- **Bundle ID**: `com.hannojacobs.AmphetamineXL`
- **GitHub**: `HannoJacobs/AmphetamineXL`
- **GitHub Pages**: `docs/` folder on `main` → https://hannojacobs.github.io/AmphetamineXL/

---

## Project Structure

```
AmphetamineXL/
├── Package.swift                          # SPM manifest — macOS 14+, LaunchAtLogin-Modern dep
├── Package.resolved                       # Lockfile — commit this
├── create-dmg.sh                          # Packages the built binary into a DMG for distribution
├── Sources/AmphetamineXL/
│   ├── AmphetamineXLApp.swift             # @main entry, MenuBarExtra scene
│   ├── AppState.swift                     # All logic: IOKit assertions, duration timer, UserDefaults
│   └── MenuBarView.swift                  # SwiftUI popup view — uses onTapGesture not Button
├── docs/
│   ├── index.html                         # Landing page (GitHub Pages)
│   ├── ARCHITECTURE.md                    # Technical deep-dive
│   └── CONTRIBUTING.md                    # Agent contribution guide
├── .github/workflows/release.yml          # CI: builds on push to main, uploads DMG to latest release
├── AGENTS.md                              # This file
├── CLAUDE.md                              # Claude Code variant of this briefing
└── CHANGELOG.md                           # Version history
```

---

## How to Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme AmphetamineXL -configuration Release \
  -destination "platform=macOS" build
```

The binary lands in `~/Library/Developer/Xcode/DerivedData/AmphetamineXL-*/Build/Products/Release/AmphetamineXL`.

---

## How to Install Locally After Build

```bash
# Find the binary
BINARY=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Release/AmphetamineXL" -type f 2>/dev/null | head -1)
echo "Binary: $BINARY"

# Kill running instance
pkill -x AmphetamineXL 2>/dev/null || true
sleep 1

# Copy binary into the app bundle
cp "$BINARY" /Applications/AmphetamineXL.app/Contents/MacOS/AmphetamineXL

# Open
open /Applications/AmphetamineXL.app

# Verify it launched
pgrep -x AmphetamineXL
```

If `/Applications/AmphetamineXL.app` doesn't exist yet, create the bundle structure first:

```bash
mkdir -p /Applications/AmphetamineXL.app/Contents/MacOS
mkdir -p /Applications/AmphetamineXL.app/Contents/Resources
cp "$BINARY" /Applications/AmphetamineXL.app/Contents/MacOS/AmphetamineXL
```

Then write an `Info.plist` at `/Applications/AmphetamineXL.app/Contents/Info.plist` matching the one in `create-dmg.sh`.

---

## Full Send Deploy Sequence

"Full send" = bump version + commit + create GitHub release + push (CI uploads DMG) + install locally + verify.

### Step 1 — Bump version in create-dmg.sh

In `create-dmg.sh`, update both version strings in the inline `Info.plist`:

```xml
<key>CFBundleVersion</key>
<string>X.Y</string>
<key>CFBundleShortVersionString</key>
<string>X.Y</string>
```

### Step 2 — Update CHANGELOG.md

Add the new version entry at the top.

### Step 3 — Commit

```bash
git add -A
git commit -m "vX.Y: <short description>"
```

### Step 4 — Create GitHub release BEFORE pushing

CI uploads the DMG to the *latest* release. Create the release first so CI has somewhere to attach the artifact:

```bash
gh release create vX.Y \
  --title "vX.Y — <title>" \
  --notes "- Change one\n- Change two"
```

### Step 5 — Push to main (triggers CI)

```bash
git push origin main
```

CI runs `.github/workflows/release.yml`: builds the binary, runs `create-dmg.sh`, uploads `AmphetamineXL.dmg` to the latest release.

### Step 6 — Install locally

```bash
BINARY=$(find ~/Library/Developer/Xcode/DerivedData -path "*/Release/AmphetamineXL" -type f 2>/dev/null | head -1)
pkill -x AmphetamineXL 2>/dev/null || true
sleep 1
cp "$BINARY" /Applications/AmphetamineXL.app/Contents/MacOS/AmphetamineXL

# Update Info.plist versions to match
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion X.Y" /Applications/AmphetamineXL.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString X.Y" /Applications/AmphetamineXL.app/Contents/Info.plist

open /Applications/AmphetamineXL.app
```

### Step 7 — Verify

```bash
pgrep -x AmphetamineXL        # should print a PID
gh release view vX.Y           # confirm release exists and has AmphetamineXL.dmg asset
```

---

## Key Files Deep Dive

### Package.swift
- Target: `.executableTarget` (not `.app` target — SPM executable convention)
- Dependency: `LaunchAtLogin-Modern` by sindresorhus
- Min platform: `.macOS(.v14)`

### AppState.swift
- `@Observable @MainActor` — SwiftUI Observation framework (macOS 14+)
- Holds **two** IOKit assertions simultaneously:
  - `kIOPMAssertPreventUserIdleSystemSleep` — prevents idle sleep (what most tools use)
  - `kIOPMAssertionTypePreventSystemSleep` — prevents ALL system sleep, including clamshell lid close
- State persisted via `UserDefaults` key `"amphetamine_active"` — restored on next launch
- Duration timer fires every 60s on `RunLoop.main` with `.common` mode so it works during scroll

### MenuBarView.swift
- **Use `onTapGesture`, NOT `Button`** in `MenuBarExtra .window` style views
- `Button` in a `.window`-style `MenuBarExtra` dismisses the popup on click — this is a SwiftUI bug/quirk
- `contentShape(Rectangle())` is required to make the full row area tappable, not just the text

### AmphetamineXLApp.swift
- `MenuBarExtra` with `.menuBarExtraStyle(.window)` — renders the view as a floating panel
- Icon switches dynamically: `bolt.fill` (active) / `bolt.slash` (inactive)

### create-dmg.sh
- Builds the `.app` bundle manually from the compiled binary
- Writes `Info.plist` inline — **this is where you bump the version**
- Creates a DMG with an Applications symlink for drag-to-install UX

### .github/workflows/release.yml
- Triggered on every push to `main`
- Uploads `AmphetamineXL.dmg` to the *most recent* GitHub release (by `gh release list`)
- **Always create the GitHub release before pushing** or CI has no release to attach to

---

## IOKit — Why Two Assertions

| Assertion | What it blocks |
|---|---|
| `kIOPMAssertPreventUserIdleSystemSleep` | Idle timeout sleep only |
| `kIOPMAssertionTypePreventSystemSleep` | All system sleep — including lid close |

Amphetamine and most tools only hold the first. Closing the lid triggers the second type of sleep event. AmphetamineXL holds both, which is the core differentiator.

---

## SwiftUI MenuBarExtra Quirks

- `.menuBarExtraStyle(.window)` renders the scene as a floating popup window attached to the menu bar icon
- In this style, `Button` views dismiss the popup when tapped (unexpected behavior)
- Use `onTapGesture` on an `HStack` with `.contentShape(Rectangle())` instead
- The `Toggle` in `LaunchAtLoginRow` is fine because toggles don't dismiss the window

---

## Dependencies

| Package | Purpose |
|---|---|
| `LaunchAtLogin-Modern` (sindresorhus) | Register/unregister launch-at-login via SMAppService |

---

## What Agents Should Never Do

- Open or modify `.xcodeproj` / `.xcworkspace` files (there are none — SPM only)
- Use `xed` or assume Xcode GUI is available
- Commit without bumping version first on a deploy
- Push before creating the GitHub release (CI will fail to upload the DMG)
- Mark a deploy as done without running `pgrep -x AmphetamineXL` and `gh release view vX.Y`
