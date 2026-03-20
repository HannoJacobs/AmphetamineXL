# Changelog

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
