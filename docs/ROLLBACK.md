# Rollback

AmphetamineXL v2.3.2 keeps two rollback paths ready at all times:

1. The frozen pre-fix artifact and machine-state evidence bundle in `~/Library/Application Support/AmphetamineXL/Rollback/`
2. A hidden built-in `legacy-max-awake` profile that keeps the stronger machine-wide sleep suppression while preserving the new cleanup and diagnostics

## Baseline Freeze

Before validating a new build, capture and keep:

```bash
cat ~/Library/Application\ Support/AmphetamineXL/Rollback/v2.2-baseline/git-head.txt
shasum -a 256 ~/Library/Application\ Support/AmphetamineXL/Rollback/v2.2-baseline/AmphetamineXL-v2.2-baseline.dmg
pmset -g
pmset -g custom
pmset -g assertions
pmset -g live
pgrep -fal 'AmphetamineXL|caffeinate|ScreenSaverEngine'
```

The fixed build also writes a baseline snapshot to:

```bash
~/Library/Application Support/AmphetamineXL/baseline-snapshot.json
```

## Tier 1: Artifact Rollback

Reinstall the frozen v2.2 app bundle or DMG if the fixed build proves insufficient.

```bash
pkill -x AmphetamineXL 2>/dev/null || true
open ~/Library/Application\ Support/AmphetamineXL/Rollback/v2.2-baseline/AmphetamineXL-v2.2-baseline.dmg
```

Verify after reinstall:

```bash
pgrep -fal 'AmphetamineXL|caffeinate|ScreenSaverEngine'
pmset -g assertions
```

## Tier 2: Hidden Legacy Max-Awake Profile

If v2.3.2’s default profile is too conservative, switch to the hidden compatibility profile without giving up the new cleanup and logging.

Enable:

```bash
defaults write com.hannojacobs.AmphetamineXL wakeProfile legacy-max-awake
pkill -x AmphetamineXL 2>/dev/null || true
open /Applications/AmphetamineXL.app
```

Return to the default fixed profile:

```bash
defaults delete com.hannojacobs.AmphetamineXL wakeProfile
pkill -x AmphetamineXL 2>/dev/null || true
open /Applications/AmphetamineXL.app
```

`legacy-max-awake` is allowed to apply:

- `standby 0`
- `hibernatemode 0`
- `autopoweroff 0` where supported
- `sleep 0`
- `displaysleep 0`
- `disablesleep 1`

The fixed build snapshots the values it replaces and restores them on disable, quit, termination, or recovery.

## Tier 3: Machine-State Rollback

If the app must be bypassed entirely, reapply the exact baseline state or a known effective emergency state manually.

Known emergency state:

```bash
sudo pmset -a standby 0 hibernatemode 0 sleep 0 displaysleep 0
sudo pmset disablesleep 1
```

Return to a normal portable baseline:

```bash
sudo pmset -a standby 1 hibernatemode 3 sleep 10 displaysleep 5
sudo pmset disablesleep 0
```

Adjust the timer values above if your saved baseline used different `sleep` or `displaysleep` values.

## Automatic Rollback Triggers

Rollback immediately if any of these happen:

- Closed-lid wakefulness regresses
- The lid-close lock plus display-off path regresses
- `caffeinate` survives app quit or crash
- The app introduces unowned `pmset` drift
- The new diagnostics logs are missing or incomplete during a failure

## Evidence Checklist

Every rollback decision should capture:

```bash
pgrep -fal 'AmphetamineXL|caffeinate|ScreenSaverEngine'
pmset -g
pmset -g custom
pmset -g assertions
pmset -g live
open ~/Library/Application\ Support/AmphetamineXL/Logs
```
