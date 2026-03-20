# Changelog

## v1.4 — 2026-03-20 (current)
> **Note:** Requires one-time system change — see README. Without it, Apple Silicon standby overrides all sleep prevention.
- Fix: launch `caffeinate -s` subprocess to block standby/clamshell sleep at kernel level (IOKit assertions alone don't survive Apple Silicon standby)
- Fix: network keepalive ping every 5s to prevent iPhone Personal Hotspot from dropping

## v1.3 — 2026-03-20
- Default ON: caffeine enabled automatically on first launch and after login
- User must manually disable — off is never the default

## v1.2 — 2026-03-20
- Fix: hold PreventUserIdleDisplaySleep assertion so Chrome/Meet doesn't drop when lid closes
- Now holds all 3 assertions: PreventUserIdleSystemSleep, PreventSystemSleep, PreventUserIdleDisplaySleep

## v1.1 — 2026-03-20
- Added ⚡ lightning bolt app icon
- Agent scaffolding: AGENTS.md, CLAUDE.md, ARCHITECTURE.md, cursor rules

## v1.0 — 2026-03-20
- Initial release
- Menu bar caffeine toggle with proper clamshell sleep prevention
- Holds PreventSystemSleep assertion (blocks lid-close sleep that Amphetamine misses)
- Launch at login support
- Remembers active state across restarts
- Duration display (shows how long caffeine has been active)
