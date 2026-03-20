# AmphetamineXL

**Because Amphetamine keeps failing.**

AmphetamineXL is a tiny macOS menu bar app that actually prevents your Mac from sleeping when you close the lid. One click. Works. No nonsense.

## Why does this exist?

Amphetamine only holds `PreventUserIdleSystemSleep` — which blocks idle sleep, but not clamshell (lid-close) sleep. AmphetamineXL holds **both** assertions, including `PreventSystemSleep`, which is what you actually need.

## Install

1. Download `AmphetamineXL.dmg` from [Releases](https://github.com/HannoJacobs/AmphetamineXL/releases/latest)
2. Open the DMG and drag to Applications
3. Right-click > Open (first time, to bypass Gatekeeper)
4. Click the ⚡ icon in the menu bar

## Usage

- **⚡ bolt** = caffeinated, Mac will stay awake with lid closed
- **⚡/ bolt-slash** = sleeping, normal Mac sleep behaviour
- Click the icon → toggle caffeine on/off
- Optional: enable "Launch at Login"

## Build from source

```bash
git clone https://github.com/HannoJacobs/AmphetamineXL
cd AmphetamineXL
xcodebuild -scheme AmphetamineXL -configuration Release -destination 'platform=macOS' build
```
