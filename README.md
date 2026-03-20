# AmphetamineXL

**Because Amphetamine keeps failing.**

AmphetamineXL is a tiny macOS menu bar app that actually prevents your Mac from sleeping when you close the lid. One click. Works. No nonsense.

## Why does this exist?

Amphetamine only holds `PreventUserIdleSystemSleep` — which blocks idle sleep, but not clamshell (lid-close) sleep. AmphetamineXL holds **both** assertions, including `PreventSystemSleep`, which is what you actually need.

## ⚠️ Required: Disable macOS Standby

**You must run this once in Terminal, or the app won't work reliably:**

```bash
sudo pmset -a standby 0 && sudo pmset -a hibernatemode 0 && sudo pmset -a autopoweroff 0
```

**Why?** Apple Silicon Macs have a hardware-level "standby" state managed by the SMC chip that overrides ALL software sleep prevention — including IOKit assertions and even `caffeinate`. When you close the lid, the SMC can put the Mac into deep standby regardless of what any app tells it. This command disables that deep standby permanently. Normal sleep still works perfectly — your Mac will sleep/wake as usual when AmphetamineXL is off. You're only disabling the ultra-deep hibernate state.

This is a one-time command. It persists across reboots.

To revert (re-enable standby): `sudo pmset -a standby 1 && sudo pmset -a hibernatemode 3`

## Install

1. Download `AmphetamineXL.dmg` from [Releases](https://github.com/HannoJacobs/AmphetamineXL/releases/latest)
2. Open the DMG and drag to Applications
3. Open Terminal, run: `xattr -cr /Applications/AmphetamineXL.app`
4. Open AmphetamineXL — ⚡ appears in menu bar, caffeinated by default
5. **Run the standby command above** (one-time, requires password)
6. Close your lid — Mac stays awake ✅

## Usage

- **⚡ bolt** = caffeinated, Mac stays awake with lid closed
- **⚡/ bolt-slash** = sleeping, normal Mac sleep behaviour
- Click the icon → toggle caffeine on/off
- Optional: enable "Launch at Login"

## Build from source

```bash
git clone https://github.com/HannoJacobs/AmphetamineXL
cd AmphetamineXL
xcodebuild -scheme AmphetamineXL -configuration Release -destination 'platform=macOS' build
```
