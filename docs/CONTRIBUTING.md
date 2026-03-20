# Contributing

This repo is agent-operated. Hanno doesn't open Xcode. All changes are made via Claude Code, Codex, or equivalent agents through the CLI.

## How to make changes

1. Read `AGENTS.md` first — it has the full context
2. Edit Swift source files in `Sources/AmphetamineXL/`
3. Build to verify: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme AmphetamineXL -configuration Release -destination 'platform=macOS' build`
4. Fix any compiler errors before deploying
5. Deploy with the full send checklist (see `AGENTS.md` or `.cursor/rules/full-send.mdc`)

## No Xcode project files

Do not create `.xcodeproj` or `.xcworkspace` files. Everything goes through SPM (`Package.swift`).

## Adding dependencies

Add to `Package.swift` dependencies array and target dependencies. Prefer packages from `sindresorhus` (LaunchAtLogin pattern) or well-maintained Swift ecosystem packages. Keep it lean — this app intentionally has minimal dependencies.

## Version bumping

Version lives **only** in `create-dmg.sh`. Bump `CFBundleVersion` and `CFBundleShortVersionString` there. The GitHub Pages site dynamically fetches the latest release tag — no manual website update needed.

## Changelog

Update `CHANGELOG.md` on every release. Format:

```markdown
## vX.Y — YYYY-MM-DD
- What changed
```

## SwiftUI rules

- `onTapGesture` not `Button` for menu rows (see `ARCHITECTURE.md`)
- `@Observable` not `ObservableObject` (macOS 14+)
- `@Environment(AppState.self)` not `@EnvironmentObject`
