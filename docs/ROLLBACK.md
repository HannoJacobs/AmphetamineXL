# Rollback

AmphetamineXL keeps two rollback paths ready at all times:

1. The frozen pre-fix artifact and machine-state evidence bundle in `~/Library/Application Support/AmphetamineXL/Rollback/`
2. The active runtime contract: caffeine ON always uses `legacy-max-awake`, while caffeine OFF or app quit restores the captured normal sleep-capable machine state

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

## Current Validation Position

- Initial user inspection on 2026-04-02 indicates the current state appears to work well
- This should still be treated as provisional until several weeks of real closed-lid use have passed
- If that longer validation fails, rollback preference is the pre-change "nuclear option" baseline from before the recent cleanup, recovery, and runtime-profile changes

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

## Tier 2: Active Runtime Rollback Contract

Active mode now always uses `legacy-max-awake` while preserving the new cleanup and diagnostics.

The active runtime is allowed to apply:

- `standby 0`
- `hibernatemode 0`
- `autopoweroff 0` where supported
- `sleep 0`
- `displaysleep 0`
- `disablesleep 1`

On disable, quit, termination, or recovery, the app restores the exact captured values it replaced, including:

- `standby`
- `hibernatemode`
- `sleep`
- `displaysleep`
- `disablesleep`

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

## Runtime Expectations

- Caffeine ON: aggressive max-awake machine state
- Caffeine OFF: normal sleep-capable machine state restored
- App quit: normal sleep-capable machine state restored

## Automatic Rollback Triggers

Rollback immediately if any of these happen:

- Closed-lid wakefulness regresses
- The lid-close lock plus display-off path regresses
- `caffeinate` survives app quit or crash
- The app introduces unowned `pmset` drift
- The new diagnostics logs are missing or incomplete during a failure
- Multi-week real-world testing shows the current build is less reliable than the pre-change baseline

## Preferred Fallback Order

If the current build disappoints during the extended validation window, prefer rollback in this order:

1. Pre-change "nuclear option" baseline from `~/Library/Application Support/AmphetamineXL/Rollback/v2.2-baseline/`
2. Manual machine-state rollback to the known emergency state in Tier 3
3. Only after rollback, investigate a new forward fix from logs and captured evidence

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
