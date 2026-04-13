import XCTest
@testable import AmphetamineXL

final class MonitoredActivityTests: XCTestCase {
    func testActivityWindowDefaultsToThirtySeconds() {
        XCTAssertEqual(ActivityWindowSettings.defaultSeconds, 30)
    }

    func testActivityWindowNormalizesToFiveSecondStepsWithinBounds() {
        XCTAssertEqual(ActivityWindowSettings.normalize(7), 10)
        XCTAssertEqual(ActivityWindowSettings.normalize(33), 35)
        XCTAssertEqual(ActivityWindowSettings.normalize(123), 120)
    }

    func testMonitoringSelectionDisablesCodexForStatusAndWakeDetection() {
        let snapshot = MonitoredActivitySnapshot(
            runningProcesses: [
                RunningProcess(pid: 100, commandLine: "/opt/homebrew/bin/codex exec --full-auto")
            ],
            codexQueuedFollowUpCount: 1,
            claudeTodoTaskCount: 0,
            claudeSessionPIDs: []
        )
        let selection = MonitoringSelection(codexEnabled: false, claudeEnabled: true)

        let sources = MonitoredActivityMonitor.activeSources(in: snapshot, selection: selection)
        let status = MonitoredActivityMonitor.runtimeStatus(in: snapshot, selection: selection)

        XCTAssertEqual(sources, [])
        XCTAssertEqual(status.codex, .disabled)
    }

    func testMonitoringSelectionDisablesClaudeForStatusAndWakeDetection() {
        let snapshot = MonitoredActivitySnapshot(
            runningProcesses: [
                RunningProcess(pid: 200, commandLine: "claude")
            ],
            codexQueuedFollowUpCount: 0,
            claudeTodoTaskCount: 1,
            claudeSessionPIDs: [200],
            recentClaudeProjectActivityCount: 1
        )
        let selection = MonitoringSelection(codexEnabled: true, claudeEnabled: false)

        let sources = MonitoredActivityMonitor.activeSources(in: snapshot, selection: selection)
        let status = MonitoredActivityMonitor.runtimeStatus(in: snapshot, selection: selection)

        XCTAssertEqual(sources, [])
        XCTAssertEqual(status.claudeCode, .disabled)
    }

    func testWakeModeDisableUsesDisabledPresentation() {
        XCTAssertFalse(WakeMode.disabled.manualHoldRequested)
        XCTAssertFalse(WakeMode.disabled.autoWakeEnabled)
        XCTAssertFalse(WakeMode.disabled.showsAutoAwakeMonitor)
        XCTAssertEqual(WakeMode.disabled.menuBarIcon(isWakeStackRunning: false), "bolt.slash")
        XCTAssertEqual(WakeMode.disabled.statusTitle(isWakeStackRunning: false), "Sleep Allowed")
        XCTAssertEqual(WakeMode.disabled.descriptionText, "Sleep behaves normally. No manual hold and no automatic wake triggers.")
    }

    func testWakeModeAutoAwakeUsesIntermediatePresentation() {
        XCTAssertFalse(WakeMode.autoAwake.manualHoldRequested)
        XCTAssertTrue(WakeMode.autoAwake.autoWakeEnabled)
        XCTAssertTrue(WakeMode.autoAwake.showsAutoAwakeMonitor)
        XCTAssertEqual(WakeMode.autoAwake.menuBarIcon(isWakeStackRunning: false), "bolt.circle")
        XCTAssertEqual(WakeMode.autoAwake.menuBarIcon(isWakeStackRunning: true), "bolt.circle.fill")
        XCTAssertEqual(WakeMode.autoAwake.statusTitle(isWakeStackRunning: false), "Auto-awake")
        XCTAssertEqual(WakeMode.autoAwake.descriptionText, "Wake only when Codex or Claude work is active, then release automatically.")
    }

    func testWakeModeManualUsesManualPresentation() {
        XCTAssertTrue(WakeMode.manual.manualHoldRequested)
        XCTAssertFalse(WakeMode.manual.autoWakeEnabled)
        XCTAssertFalse(WakeMode.manual.showsAutoAwakeMonitor)
        XCTAssertEqual(WakeMode.manual.menuBarIcon(isWakeStackRunning: true), "bolt.fill")
        XCTAssertEqual(WakeMode.manual.statusTitle(isWakeStackRunning: true), "Manual Caffeine")
        XCTAssertEqual(WakeMode.manual.descriptionText, "Keep the Mac awake continuously until you switch back to another mode.")
    }

    func testMenuBarIconStaysFrozenWhileMenuIsPresented() {
        XCTAssertEqual(
            WakeMode.manual.resolvedMenuBarIcon(
                isWakeStackRunning: true,
                isMenuPresented: true,
                frozenIcon: "bolt.circle"
            ),
            "bolt.circle"
        )

        XCTAssertEqual(
            WakeMode.manual.resolvedMenuBarIcon(
                isWakeStackRunning: true,
                isMenuPresented: false,
                frozenIcon: "bolt.circle"
            ),
            "bolt.fill"
        )
    }

    func testClosedLidRequestsImmediateSleepAfterWakeStackStops() {
        XCTAssertTrue(ClosedLidSleepResolver.shouldRequestSleep(lidClosed: true))
        XCTAssertFalse(ClosedLidSleepResolver.shouldRequestSleep(lidClosed: false))
    }

    func testDetectsCodexCLIProcess() {
        let snapshot = MonitoredActivitySnapshot(
            runningProcesses: [
                RunningProcess(pid: 100, commandLine: "/opt/homebrew/bin/codex exec --full-auto")
            ],
            codexQueuedFollowUpCount: 0,
            claudeTodoTaskCount: 0,
            claudeSessionPIDs: []
        )

        let sources = MonitoredActivityMonitor.activeSources(in: snapshot)

        XCTAssertEqual(sources, [.codexCLI])
    }

    func testDoesNotTreatCodexAppServerAsActiveWork() {
        let snapshot = MonitoredActivitySnapshot(
            runningProcesses: [
                RunningProcess(pid: 100, commandLine: "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled")
            ],
            codexQueuedFollowUpCount: 0,
            claudeTodoTaskCount: 0,
            claudeSessionPIDs: []
        )

        let sources = MonitoredActivityMonitor.activeSources(in: snapshot)
        let status = MonitoredActivityMonitor.runtimeStatus(in: snapshot)

        XCTAssertEqual(sources, [])
        XCTAssertEqual(status.codex, .idle)
    }

    func testTreatsCodexAppServerWithRecentThreadActivityAsTasking() {
        let snapshot = MonitoredActivitySnapshot(
            runningProcesses: [
                RunningProcess(pid: 100, commandLine: "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled")
            ],
            codexQueuedFollowUpCount: 0,
            claudeTodoTaskCount: 0,
            claudeSessionPIDs: [],
            hasRecentCodexThreadActivity: true
        )

        let sources = MonitoredActivityMonitor.activeSources(in: snapshot)
        let status = MonitoredActivityMonitor.runtimeStatus(in: snapshot)

        XCTAssertEqual(sources, [.codexApp])
        XCTAssertEqual(status.codex, .tasking)
    }

    func testDetectsCodexAppQueueWithoutRelyingOnMainAppProcess() {
        let snapshot = MonitoredActivitySnapshot(
            runningProcesses: [],
            codexQueuedFollowUpCount: 2,
            claudeTodoTaskCount: 0,
            claudeSessionPIDs: []
        )

        let sources = MonitoredActivityMonitor.activeSources(in: snapshot)

        XCTAssertEqual(sources, [.codexQueue])
    }

    func testDetectsClaudeSessionWhenMatchingProcessIsStillRunningActiveTodos() {
        let snapshot = MonitoredActivitySnapshot(
            runningProcesses: [
                RunningProcess(pid: 34528, commandLine: "claude"),
                RunningProcess(pid: 90000, commandLine: "/Applications/Codex.app/Contents/MacOS/Codex")
            ],
            codexQueuedFollowUpCount: 0,
            claudeTodoTaskCount: 1,
            claudeSessionPIDs: [34528, 77777],
            recentClaudeProjectActivityCount: 1
        )

        let sources = MonitoredActivityMonitor.activeSources(in: snapshot)

        XCTAssertEqual(sources, [.claudeCode])
    }

    func testDoesNotTreatIdleClaudeSessionProcessAsRunningWork() {
        let snapshot = MonitoredActivitySnapshot(
            runningProcesses: [
                RunningProcess(pid: 34528, commandLine: "claude")
            ],
            codexQueuedFollowUpCount: 0,
            claudeTodoTaskCount: 0,
            claudeSessionPIDs: [34528]
        )

        let sources = MonitoredActivityMonitor.activeSources(in: snapshot)
        let status = MonitoredActivityMonitor.runtimeStatus(in: snapshot)

        XCTAssertEqual(sources, [])
        XCTAssertEqual(status.claudeCode, .idle)
    }

    func testKeepsWakeActiveDuringCooldownAfterWorkStops() {
        var monitor = MonitoredActivityMonitor(cooldownInterval: 60)
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let stoppedAt = Date(timeIntervalSince1970: 1_030)
        let expiredAt = Date(timeIntervalSince1970: 1_091)

        let activeDecision = monitor.update(
            snapshot: MonitoredActivitySnapshot(
                runningProcesses: [
                    RunningProcess(pid: 100, commandLine: "/opt/homebrew/bin/codex exec --full-auto")
                ],
                codexQueuedFollowUpCount: 0,
                claudeTodoTaskCount: 0,
                claudeSessionPIDs: []
            ),
            now: startedAt
        )

        let cooldownDecision = monitor.update(
            snapshot: MonitoredActivitySnapshot(
                runningProcesses: [],
                codexQueuedFollowUpCount: 0,
                claudeTodoTaskCount: 0,
                claudeSessionPIDs: []
            ),
            now: stoppedAt
        )

        let expiredDecision = monitor.update(
            snapshot: MonitoredActivitySnapshot(
                runningProcesses: [],
                codexQueuedFollowUpCount: 0,
                claudeTodoTaskCount: 0,
                claudeSessionPIDs: []
            ),
            now: expiredAt
        )

        XCTAssertTrue(activeDecision.shouldPreventSleep)
        XCTAssertTrue(cooldownDecision.shouldPreventSleep)
        XCTAssertTrue(cooldownDecision.isCoolingDown)
        XCTAssertFalse(expiredDecision.shouldPreventSleep)
        XCTAssertFalse(expiredDecision.isCoolingDown)
    }

    func testWakeDemandStartsWhenAutomaticMonitoringRequestsWake() {
        let decision = WakeDemandResolver.resolve(
            manualHoldRequested: false,
            autoHoldRequested: true,
            isAutoWakeEnabled: true,
            isWakeStackRunning: false,
            isWakeStackTransitioning: false
        )

        XCTAssertTrue(decision.shouldKeepWakeStackEnabled)
        XCTAssertTrue(decision.shouldStartWakeStack)
        XCTAssertFalse(decision.shouldStopWakeStack)
    }

    func testWakeDemandStaysEnabledWhenManualModeIsStillOn() {
        let decision = WakeDemandResolver.resolve(
            manualHoldRequested: true,
            autoHoldRequested: false,
            isAutoWakeEnabled: true,
            isWakeStackRunning: true,
            isWakeStackTransitioning: false
        )

        XCTAssertTrue(decision.shouldKeepWakeStackEnabled)
        XCTAssertFalse(decision.shouldStartWakeStack)
        XCTAssertFalse(decision.shouldStopWakeStack)
    }

    func testWakeDemandStopsAfterManualAndAutomaticModesClear() {
        let decision = WakeDemandResolver.resolve(
            manualHoldRequested: false,
            autoHoldRequested: false,
            isAutoWakeEnabled: true,
            isWakeStackRunning: true,
            isWakeStackTransitioning: false
        )

        XCTAssertFalse(decision.shouldKeepWakeStackEnabled)
        XCTAssertFalse(decision.shouldStartWakeStack)
        XCTAssertTrue(decision.shouldStopWakeStack)
    }

    func testWakeDemandDoesNotStartAgainWhileWakeStackTransitionIsInProgress() {
        let decision = WakeDemandResolver.resolve(
            manualHoldRequested: false,
            autoHoldRequested: true,
            isAutoWakeEnabled: true,
            isWakeStackRunning: false,
            isWakeStackTransitioning: true
        )

        XCTAssertTrue(decision.shouldKeepWakeStackEnabled)
        XCTAssertFalse(decision.shouldStartWakeStack)
        XCTAssertFalse(decision.shouldStopWakeStack)
    }

    func testWakeDemandIgnoresAutomaticRequestsWhenAutoAwakeIsDisabled() {
        let decision = WakeDemandResolver.resolve(
            manualHoldRequested: false,
            autoHoldRequested: true,
            isAutoWakeEnabled: false,
            isWakeStackRunning: false,
            isWakeStackTransitioning: false
        )

        XCTAssertFalse(decision.shouldKeepWakeStackEnabled)
        XCTAssertFalse(decision.shouldStartWakeStack)
        XCTAssertFalse(decision.shouldStopWakeStack)
    }

    func testRuntimeMonitorMarksCodexAsQueuedWithoutLiveProcess() {
        let snapshot = MonitoredActivitySnapshot(
            runningProcesses: [],
            codexQueuedFollowUpCount: 2,
            claudeTodoTaskCount: 0,
            claudeSessionPIDs: []
        )

        let status = MonitoredActivityMonitor.runtimeStatus(in: snapshot)

        XCTAssertEqual(status.codex, .queued)
        XCTAssertEqual(status.claudeCode, .idle)
    }

    func testRuntimeMonitorMarksCodexAsTaskingAndQueuedWhenTaskIsRunningAndQueueRemains() {
        let snapshot = MonitoredActivitySnapshot(
            runningProcesses: [
                RunningProcess(pid: 100, commandLine: "/Applications/Codex.app/Contents/Resources/codex app-server --analytics-default-enabled")
            ],
            codexQueuedFollowUpCount: 2,
            claudeTodoTaskCount: 0,
            claudeSessionPIDs: [],
            hasRecentCodexThreadActivity: true
        )

        let status = MonitoredActivityMonitor.runtimeStatus(in: snapshot)

        XCTAssertEqual(status.codex, .taskingAndQueued)
    }

    func testRuntimeMonitorMarksClaudeAsQueuedWhenTodosRemain() {
        let snapshot = MonitoredActivitySnapshot(
            runningProcesses: [],
            codexQueuedFollowUpCount: 0,
            claudeTodoTaskCount: 1,
            claudeSessionPIDs: []
        )

        let status = MonitoredActivityMonitor.runtimeStatus(in: snapshot)

        XCTAssertEqual(status.codex, .idle)
        XCTAssertEqual(status.claudeCode, .queued)
    }

    func testRuntimeMonitorMarksClaudeAsTaskingWhenRecentProjectActivityExistsWithoutQueuedTodos() {
        let snapshot = MonitoredActivitySnapshot(
            runningProcesses: [
                RunningProcess(pid: 200, commandLine: "claude")
            ],
            codexQueuedFollowUpCount: 0,
            claudeTodoTaskCount: 0,
            claudeSessionPIDs: [200],
            recentClaudeProjectActivityCount: 1
        )

        let status = MonitoredActivityMonitor.runtimeStatus(in: snapshot)

        XCTAssertEqual(status.claudeCode, .tasking)
    }

    func testRuntimeMonitorMarksBothToolsAsTaskingWhenLiveProcessesExist() {
        let snapshot = MonitoredActivitySnapshot(
            runningProcesses: [
                RunningProcess(pid: 100, commandLine: "/opt/homebrew/bin/codex exec --full-auto"),
                RunningProcess(pid: 200, commandLine: "claude")
            ],
            codexQueuedFollowUpCount: 0,
            claudeTodoTaskCount: 1,
            claudeSessionPIDs: [200],
            recentClaudeProjectActivityCount: 1
        )

        let status = MonitoredActivityMonitor.runtimeStatus(in: snapshot)

        XCTAssertEqual(status.codex, .tasking)
        XCTAssertEqual(status.claudeCode, .taskingAndQueued)
    }
}
