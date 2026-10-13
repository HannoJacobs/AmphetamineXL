# Monitored Task Awake Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep the Mac awake automatically while Codex CLI, Codex app, or Claude Code still have active work, then release the wake stack 60 seconds after activity fully stops.

**Architecture:** Add a pure monitored-activity layer that converts runtime signals from local processes and tool state files into a single `shouldPreventSleep` decision with a cooldown window. Integrate that layer into `AppState` as an automatic wake reason that composes with the existing manual toggle instead of replacing it.

**Tech Stack:** Swift 5.9, SwiftPM executable target, XCTest-based unit tests, Foundation/AppKit/ProcessInfo.

### Task 1: Add test target and pure detector surface

**Files:**
- Modify: `Package.swift`
- Create: `Tests/AmphetamineXLTests/MonitoredActivityTests.swift`
- Test: `Tests/AmphetamineXLTests/MonitoredActivityTests.swift`

**Step 1: Write the failing test**

Create tests for:
- Codex app process detection
- Codex CLI process detection
- Claude session PID detection
- Codex queued follow-up detection
- 60-second cooldown after activity ends

**Step 2: Run test to verify it fails**

Run: `swift test --filter MonitoredActivityTests`
Expected: FAIL because the new test target and detector types do not exist yet.

**Step 3: Write minimal implementation**

Create a new pure detector type that accepts injected process/state snapshots and returns:
- matched activity sources
- whether work is still considered active
- cooldown expiration handling

**Step 4: Run test to verify it passes**

Run: `swift test --filter MonitoredActivityTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Package.swift Tests/AmphetamineXLTests/MonitoredActivityTests.swift Sources/AmphetamineXL/MonitoredActivityMonitor.swift
git commit -m "添加任务监测唤醒逻辑"
```

### Task 2: Integrate automatic wake reason into app state

**Files:**
- Modify: `Sources/AmphetamineXL/AppState.swift`
- Modify: `Sources/AmphetamineXL/MenuBarView.swift`
- Modify: `Sources/AmphetamineXL/DiagnosticsSupport.swift`
- Test: `Tests/AmphetamineXLTests/MonitoredActivityTests.swift`

**Step 1: Write the failing test**

Add tests for the composition rule:
- manual wake on => app stays awake regardless of monitor state
- manual wake off + monitored work active => app stays awake
- manual wake off + work finished but inside cooldown => app stays awake
- manual wake off + cooldown elapsed => app may sleep

**Step 2: Run test to verify it fails**

Run: `swift test --filter MonitoredActivityTests`
Expected: FAIL because app-state composition logic is missing.

**Step 3: Write minimal implementation**

Refactor `AppState` so the wake stack is driven by combined reasons rather than only a single boolean toggle. Add a timer-based monitor refresh and concise menu/status text showing when automatic monitoring is currently holding the wake stack.

**Step 4: Run test to verify it passes**

Run: `swift test --filter MonitoredActivityTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AmphetamineXL/AppState.swift Sources/AmphetamineXL/MenuBarView.swift Sources/AmphetamineXL/DiagnosticsSupport.swift Tests/AmphetamineXLTests/MonitoredActivityTests.swift
git commit -m "接入自动任务保持唤醒"
```

### Task 3: Verify end-to-end behavior and document assumptions

**Files:**
- Modify: `README.md`
- Test: `Tests/AmphetamineXLTests/MonitoredActivityTests.swift`

**Step 1: Write the failing test**

No new unit test if coverage is already sufficient; if a missing edge case appears during verification, add it first and watch it fail.

**Step 2: Run test to verify it fails**

Only if a new regression test is added.

**Step 3: Write minimal implementation**

Document the monitored tools, the queue heuristics used, and the 60-second cooldown in the README.

**Step 4: Run test to verify it passes**

Run:
- `swift test --filter MonitoredActivityTests`
- `swift test`

Expected: PASS

**Step 5: Commit**

```bash
git add README.md Tests/AmphetamineXLTests/MonitoredActivityTests.swift
git commit -m "补充任务监测使用说明"
```
