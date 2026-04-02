import Darwin
import IOKit
import IOKit.pwr_mgt
import CoreGraphics
import SwiftUI

@Observable
@MainActor
final class AppState {
    private(set) var isActive: Bool = false
    private(set) var activeSince: Date? = nil
    private(set) var durationText: String = "Inactive"

    private var assertionIDIdleSystem = IOPMAssertionID(0)
    private var assertionIDSystemSleep = IOPMAssertionID(0)
    private var assertionIDDisplaySleep = IOPMAssertionID(0)

    private var durationTimer: Timer?
    private var heartbeatTimer: Timer?
    private var keepaliveTimer: Timer?
    private var mouseJiggleTimer: Timer?
    private var lidCheckTimer: Timer?

    private var caffeinateProcess: Process?
    private var mouseJiggleCount = 0
    private var keepaliveCount = 0
    private var keepaliveCounter = 0
    private var lastJiggleTime: Date?
    private var isDisplayAsleep = false
    private var isShuttingDownWakeStack = false
    private var terminationHandled = false
    private var notificationObservers: [NSObjectProtocol] = []

    private var sessionState: AppSessionState

    private let diagnostics = DiagnosticsLogger.shared
    private let sessionStore = SessionStateStore()
    private let commandRunner = CommandRunner.shared
    private let keepaliveHosts = [
        "1.1.1.1",
        "8.8.8.8",
        "9.9.9.9",
        "208.67.222.222",
        "1.0.0.1",
    ]
    private let powerProfileManager: PowerProfileManager

    var menuBarIcon: String {
        // Keep the menu bar item clearly visible even when caffeine is off.
        isActive ? "bolt.fill" : "bolt.circle"
    }

    init() {
        let previousState = sessionStore.load()
        let hasSetPref = UserDefaults.standard.object(forKey: "amphetamine_active") != nil
        let savedDesiredState = hasSetPref ? UserDefaults.standard.bool(forKey: "amphetamine_active") : true
        let resolvedProfile = WakeProfile.resolved()
        let newSessionID = UUID().uuidString

        sessionState = AppSessionState(
            sessionID: newSessionID,
            profile: resolvedProfile,
            desiredActiveOnLaunch: savedDesiredState,
            shutdownClean: false,
            caffeinatePID: nil,
            ownedPmsetKeys: [],
            ownedPmsetPreviousValues: [:],
            lastShutdownReason: nil,
            lastKnownLidState: nil,
            lastEventNumber: 0,
            lastLogFilePath: nil,
            startedAt: isoTimestamp(Date())
        )

        diagnostics.configure(sessionID: newSessionID)
        powerProfileManager = PowerProfileManager(diagnostics: diagnostics)

        diagnostics.notice("AmphetamineXL initializing version=\(currentAppVersion()) build=\(currentBuildVersion()) pid=\(ProcessInfo.processInfo.processIdentifier)")
        diagnostics.notice(
            "Launch settings: desiredActiveOnLaunch=\(savedDesiredState) " +
            "hasLegacyUserDefault=\(hasSetPref) wakeProfile=\(resolvedProfile.rawValue)"
        )
        diagnostics.notice("Launch at login enabled=\(currentLaunchAtLoginState())")

        persistSessionState()
        sessionStore.saveBaselineSnapshotIfMissing(sessionID: newSessionID, profile: resolvedProfile, diagnostics: diagnostics, commandRunner: commandRunner)
        captureStartupDiagnostics(stage: "pre-recovery", previousState: previousState)

        setupSudoersIfNeeded()
        recoverPreviousSession(previousState)

        registerSleepWakeNotifications()
        isDisplayAsleep = isLidClosed()
        sessionState.lastKnownLidState = isDisplayAsleep
        diagnostics.notice("Initial lid state closed=\(isDisplayAsleep)")
        persistSessionState()
        captureStartupDiagnostics(stage: "post-recovery", previousState: previousState)

        if savedDesiredState {
            enableCaffeine()
        } else {
            updateDurationText()
        }
    }

    func toggle() {
        if isActive {
            disableCaffeine()
        } else {
            enableCaffeine()
        }
    }

    func prepareForQuit() {
        diagnostics.notice("Menu requested app quit")
        terminationHandled = true
        shutdown(reason: .menuQuit, desiredActiveOverride: sessionState.desiredActiveOnLaunch)
    }

    func handleApplicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        if terminationHandled {
            diagnostics.notice("applicationShouldTerminate arrived after termination was already handled")
            return .terminateNow
        }

        diagnostics.notice("Handling applicationShouldTerminate with terminateLater")
        terminationHandled = true
        let desiredActiveOnLaunch = sessionState.desiredActiveOnLaunch

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                app.reply(toApplicationShouldTerminate: true)
                return
            }

            self.shutdown(reason: .willTerminate, desiredActiveOverride: desiredActiveOnLaunch)
            self.diagnostics.notice("Replying to applicationShouldTerminate after cleanup finished")
            app.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    func handleAppWillTerminate() {
        if terminationHandled {
            diagnostics.notice("applicationWillTerminate arrived after termination was already handled")
            return
        }

        diagnostics.warning("applicationWillTerminate arrived without prior applicationShouldTerminate handling")
    }

    func openDiagnosticsLogs() {
        diagnostics.notice("Opening diagnostics logs in Finder")
        diagnostics.openCurrentLogInFinder()
    }

    func enableCaffeine() {
        guard !isActive else {
            diagnostics.notice("enableCaffeine ignored because the wake stack is already active")
            return
        }

        isShuttingDownWakeStack = false
        sessionState.desiredActiveOnLaunch = true
        sessionState.shutdownClean = false
        sessionState.lastShutdownReason = nil
        UserDefaults.standard.set(true, forKey: "amphetamine_active")

        diagnostics.notice("Enabling wake stack with profile \(sessionState.profile.rawValue)")
        diagnostics.trace("enable start profile=\(sessionState.profile.rawValue) displayAsleep=\(isDisplayAsleep)")

        let reason = "AmphetamineXL preventing sleep" as CFString

        var idleID = IOPMAssertionID(0)
        let idleResult = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &idleID
        )
        diagnostics.notice("PreventUserIdleSystemSleep result=\(idleResult)")

        var systemID = IOPMAssertionID(0)
        let systemResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &systemID
        )
        diagnostics.notice("PreventSystemSleep result=\(systemResult)")

        assertionIDIdleSystem = idleID
        assertionIDSystemSleep = systemID

        if isDisplayAsleep {
            holdDisplayAssertion()
        }

        powerProfileManager.apply(profile: sessionState.profile, sessionState: &sessionState)
        startCaffeinate()
        startKeepalive()
        startLidCheck()
        if isDisplayAsleep {
            startMouseJiggle()
        }

        isActive = true
        activeSince = Date()
        mouseJiggleCount = 0
        keepaliveCount = 0
        keepaliveCounter = 0

        updateDurationText()
        startDurationTimer()
        startHeartbeatTimer()
        persistSessionState()
        diagnostics.notice("Wake stack enabled successfully")
        emitHeartbeat(reason: "post-enable")
    }

    func disableCaffeine() {
        diagnostics.notice("User requested wake stack disable")
        shutdown(reason: .toggleOff, desiredActiveOverride: false)
    }

    private func shutdown(reason: ShutdownReason, desiredActiveOverride: Bool?) {
        if isShuttingDownWakeStack {
            diagnostics.notice("shutdown ignored because shutdown is already in progress reason=\(reason.rawValue)")
            return
        }

        isShuttingDownWakeStack = true
        diagnostics.notice("Shutting down wake stack reason=\(reason.rawValue) desiredActiveOverride=\(String(describing: desiredActiveOverride)) active=\(isActive)")
        diagnostics.trace("shutdown start reason=\(reason.rawValue)")

        if let desiredActiveOverride {
            sessionState.desiredActiveOnLaunch = desiredActiveOverride
            UserDefaults.standard.set(desiredActiveOverride, forKey: "amphetamine_active")
        }

        releaseSystemAssertions()
        stopMouseJiggle()
        stopKeepalive()
        stopLidCheck()
        stopDurationTimer()
        stopHeartbeatTimer()
        stopCaffeinate()
        powerProfileManager.restore(sessionState: &sessionState, reason: reason)

        isActive = false
        activeSince = nil
        durationText = "Inactive"
        sessionState.shutdownClean = true
        sessionState.lastShutdownReason = reason
        sessionState.lastKnownLidState = isDisplayAsleep
        persistSessionState()

        diagnostics.notice("Wake stack shutdown complete reason=\(reason.rawValue)")
        isShuttingDownWakeStack = false
    }

    private func persistSessionState() {
        sessionState.lastEventNumber = diagnostics.currentEventNumber
        sessionState.lastLogFilePath = diagnostics.currentLogFilePath
        sessionStore.save(sessionState)
    }

    private func recoverPreviousSession(_ previousState: AppSessionState?) {
        guard var previousState else {
            diagnostics.notice("No previous session state found for launch recovery")
            return
        }

        diagnostics.notice(
            "Loaded previous session id=\(previousState.sessionID) clean=\(previousState.shutdownClean) " +
            "desiredActive=\(previousState.desiredActiveOnLaunch) profile=\(previousState.profile.rawValue) " +
            "recordedCaffeinatePID=\(String(describing: previousState.caffeinatePID))"
        )

        if let recordedPID = previousState.caffeinatePID {
            if processExists(pid: recordedPID) {
                diagnostics.anomaly("Recorded caffeinate PID \(recordedPID) survived into a new launch; terminating it during recovery")
                terminatePID(recordedPID, label: "recovery caffeinate")
            } else {
                diagnostics.notice("Recorded caffeinate PID \(recordedPID) is no longer running")
            }
        }

        logRelevantProcesses(label: "launch recovery process scan")

        if !previousState.shutdownClean {
            diagnostics.anomaly("Previous session ended uncleanly; restoring any owned pmset values before continuing")
            powerProfileManager.restore(sessionState: &previousState, reason: .launchRecovery)
            previousState.shutdownClean = true
            previousState.lastShutdownReason = .launchRecovery
            previousState.caffeinatePID = nil
            sessionStore.save(previousState)
        }
    }

    private func captureStartupDiagnostics(stage: String, previousState: AppSessionState?) {
        let previousSummary: String
        if let previousState {
            previousSummary = "previousSession id=\(previousState.sessionID) clean=\(previousState.shutdownClean) desiredActive=\(previousState.desiredActiveOnLaunch) profile=\(previousState.profile.rawValue) lastReason=\(String(describing: previousState.lastShutdownReason?.rawValue))"
        } else {
            previousSummary = "previousSession none"
        }

        let body = [
            "stage=\(stage)",
            "appVersion=\(currentAppVersion())",
            "buildVersion=\(currentBuildVersion())",
            "pid=\(ProcessInfo.processInfo.processIdentifier)",
            "sessionID=\(sessionState.sessionID)",
            "wakeProfile=\(sessionState.profile.rawValue)",
            "desiredActiveOnLaunch=\(sessionState.desiredActiveOnLaunch)",
            "launchAtLogin=\(currentLaunchAtLoginState())",
            previousSummary,
            "pmset -g:",
            commandSnapshot("/usr/bin/pmset", ["-g"]),
            "pmset -g custom:",
            commandSnapshot("/usr/bin/pmset", ["-g", "custom"]),
            "pmset -g assertions:",
            commandSnapshot("/usr/bin/pmset", ["-g", "assertions"]),
            "pmset -g live:",
            commandSnapshot("/usr/bin/pmset", ["-g", "live"]),
            "processes:",
            commandSnapshot("/usr/bin/pgrep", ["-fal", "AmphetamineXL|caffeinate|ScreenSaverEngine"]),
        ].joined(separator: "\n")

        diagnostics.logMultiline(.notice, title: "startup diagnostics \(stage)", body: body)
    }

    private func commandSnapshot(_ executablePath: String, _ arguments: [String]) -> String {
        do {
            let result = try commandRunner.run(executablePath, arguments: arguments)
            if result.combinedOutput.isEmpty {
                return "exit \(result.terminationStatus)"
            }
            return "exit \(result.terminationStatus)\n\(result.combinedOutput)"
        } catch {
            return "failed to launch: \(error.localizedDescription)"
        }
    }

    private func logRelevantProcesses(label: String) {
        diagnostics.logMultiline(
            .notice,
            title: label,
            body: commandSnapshot("/usr/bin/pgrep", ["-fal", "AmphetamineXL|caffeinate|ScreenSaverEngine"])
        )
    }

    private func setupSudoersIfNeeded() {
        let sudoersPath = "/etc/sudoers.d/amphetaminexl"
        guard !FileManager.default.fileExists(atPath: sudoersPath) else {
            diagnostics.notice("sudoers entry already exists at \(sudoersPath)")
            return
        }

        diagnostics.notice("Requesting first-launch sudoers setup for passwordless pmset access")
        let script = """
            do shell script "echo 'ALL ALL=(ALL) NOPASSWD: /usr/bin/pmset' | sudo tee /etc/sudoers.d/amphetaminexl > /dev/null && sudo chmod 440 /etc/sudoers.d/amphetaminexl" with administrator privileges
            """

        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        appleScript?.executeAndReturnError(&error)

        if let error {
            diagnostics.error("sudoers setup failed: \(error)")
        } else {
            diagnostics.notice("sudoers entry created successfully")
        }
    }

    private func registerSleepWakeNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationObservers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.diagnostics.anomaly(
                        "SYSTEM WILL SLEEP mouseJiggleCount=\(self.mouseJiggleCount) keepaliveCount=\(self.keepaliveCount) " +
                        "lastJiggle=\(self.lastJiggleTime.map(isoTimestamp) ?? "never")"
                    )
                    self.postMouseJiggle(label: "last-ditch-before-sleep")
                }
            }
        )

        notificationObservers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.diagnostics.anomaly("SYSTEM DID WAKE displayAsleep=\(self.isDisplayAsleep) restarting wake stack helpers")
                    if self.isActive {
                        if self.isDisplayAsleep {
                            self.startMouseJiggle()
                        }
                        self.startKeepalive()
                        if let process = self.caffeinateProcess, !process.isRunning {
                            self.diagnostics.warning("caffeinate was not running after wake; restarting it")
                            self.startCaffeinate()
                        }
                        self.emitHeartbeat(reason: "post-wake")
                    }
                }
            }
        )

        notificationObservers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.diagnostics.notice("DISPLAY SLEEP notification received")
                    self.isDisplayAsleep = true
                    self.sessionState.lastKnownLidState = true
                    self.persistSessionState()
                    if self.isActive {
                        self.lockScreen()
                        self.startMouseJiggle()
                        self.holdDisplayAssertion()
                    }
                }
            }
        )

        notificationObservers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.diagnostics.notice("DISPLAY WAKE notification received")
                    self.isDisplayAsleep = false
                    self.sessionState.lastKnownLidState = false
                    self.persistSessionState()
                    self.stopMouseJiggle()
                    self.releaseDisplayAssertion()
                }
            }
        )

        diagnostics.notice("Registered sleep, wake, and display notifications")
    }

    private func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        if service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            if let property = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0) {
                return property.takeRetainedValue() as? Bool ?? false
            }
        }

        return false
    }

    private func startLidCheck() {
        stopLidCheck()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                let lidClosed = self.isLidClosed()
                self.sessionState.lastKnownLidState = lidClosed
                self.persistSessionState()
                self.diagnostics.trace("lid-check closed=\(lidClosed) displayAsleep=\(self.isDisplayAsleep)")

                if lidClosed && !self.isDisplayAsleep {
                    self.diagnostics.notice("Lid check detected lid close; activating clamshell mode")
                    self.isDisplayAsleep = true
                    self.lockScreen()
                    self.startMouseJiggle()
                    self.holdDisplayAssertion()
                } else if !lidClosed && self.isDisplayAsleep {
                    self.diagnostics.notice("Lid check detected lid open; deactivating clamshell mode")
                    self.isDisplayAsleep = false
                    self.stopMouseJiggle()
                    self.releaseDisplayAssertion()
                }
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        lidCheckTimer = timer
    }

    private func stopLidCheck() {
        lidCheckTimer?.invalidate()
        lidCheckTimer = nil
    }

    private func lockScreen() {
        diagnostics.notice("Locking screen with ScreenSaverEngine followed by displaysleepnow")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "ScreenSaverEngine"]
        do {
            try task.run()
            diagnostics.notice("ScreenSaverEngine launched for lock workflow")
        } catch {
            diagnostics.error("Failed to launch ScreenSaverEngine: \(error.localizedDescription)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let sleepTask = Process()
            sleepTask.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            sleepTask.arguments = ["displaysleepnow"]
            do {
                try sleepTask.run()
                self.diagnostics.notice("pmset displaysleepnow executed successfully")
            } catch {
                self.diagnostics.warning("pmset displaysleepnow failed: \(error.localizedDescription)")
            }
        }
    }

    private func holdDisplayAssertion() {
        guard assertionIDDisplaySleep == IOPMAssertionID(0) else { return }

        var displayID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "AmphetamineXL preventing display sleep" as CFString,
            &displayID
        )
        assertionIDDisplaySleep = displayID
        diagnostics.notice("PreventUserIdleDisplaySleep result=\(result)")
    }

    private func releaseDisplayAssertion() {
        guard assertionIDDisplaySleep != IOPMAssertionID(0) else { return }

        IOPMAssertionRelease(assertionIDDisplaySleep)
        assertionIDDisplaySleep = IOPMAssertionID(0)
        diagnostics.notice("Released display sleep assertion")
    }

    private func releaseSystemAssertions() {
        if assertionIDIdleSystem != IOPMAssertionID(0) {
            IOPMAssertionRelease(assertionIDIdleSystem)
            assertionIDIdleSystem = IOPMAssertionID(0)
            diagnostics.notice("Released PreventUserIdleSystemSleep assertion")
        }

        if assertionIDSystemSleep != IOPMAssertionID(0) {
            IOPMAssertionRelease(assertionIDSystemSleep)
            assertionIDSystemSleep = IOPMAssertionID(0)
            diagnostics.notice("Released PreventSystemSleep assertion")
        }

        releaseDisplayAssertion()
    }

    private func startCaffeinate() {
        stopCaffeinate()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-s", "-w", "\(ProcessInfo.processInfo.processIdentifier)"]
        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let status = terminatedProcess.terminationStatus
                let pid = terminatedProcess.processIdentifier
                self.diagnostics.notice("caffeinate termination observed pid=\(pid) status=\(status) isShuttingDown=\(self.isShuttingDownWakeStack)")
                if self.caffeinateProcess?.processIdentifier == pid {
                    self.caffeinateProcess = nil
                }
                self.sessionState.caffeinatePID = nil
                self.persistSessionState()
                if self.isActive && !self.isShuttingDownWakeStack {
                    self.diagnostics.anomaly("caffeinate exited unexpectedly while active; restarting it immediately")
                    self.startCaffeinate()
                }
            }
        }

        do {
            try process.run()
            caffeinateProcess = process
            sessionState.caffeinatePID = process.processIdentifier
            persistSessionState()
            diagnostics.notice("Started caffeinate with pid=\(process.processIdentifier) command=/usr/bin/caffeinate -s -w \(ProcessInfo.processInfo.processIdentifier)")
        } catch {
            diagnostics.error("Failed to start caffeinate: \(error.localizedDescription)")
        }
    }

    private func stopCaffeinate() {
        if let process = caffeinateProcess {
            diagnostics.notice("Stopping caffeinate pid=\(process.processIdentifier)")
            terminatePID(process.processIdentifier, label: "caffeinate")
        } else if let recordedPID = sessionState.caffeinatePID, processExists(pid: recordedPID) {
            diagnostics.notice("Stopping recorded caffeinate pid=\(recordedPID) without a live Process handle")
            terminatePID(recordedPID, label: "recorded caffeinate")
        }

        caffeinateProcess = nil
        sessionState.caffeinatePID = nil
        persistSessionState()
    }

    private func startKeepalive() {
        stopKeepalive()
        diagnostics.notice("Starting keepalive timer interval=3 hostCount=\(keepaliveHosts.count)")

        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let counter = self.keepaliveCounter
                self.keepaliveCounter += 1
                self.keepaliveCount += 1
                let host = self.keepaliveHosts[counter % self.keepaliveHosts.count]
                self.diagnostics.trace("keepalive tick counter=\(counter) host=\(host)")

                Task.detached(priority: .utility) {
                    var hints = addrinfo()
                    hints.ai_family = AF_INET
                    hints.ai_socktype = Int32(SOCK_DGRAM)
                    var resultPointer: UnsafeMutablePointer<addrinfo>?
                    getaddrinfo(host, nil, &hints, &resultPointer)
                    if let resultPointer {
                        freeaddrinfo(resultPointer)
                    }

                    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
                    if socketFD >= 0 {
                        var address = sockaddr_in()
                        address.sin_family = sa_family_t(AF_INET)
                        address.sin_port = UInt16(53).bigEndian
                        inet_pton(AF_INET, host, &address.sin_addr)

                        var flags = fcntl(socketFD, F_GETFL, 0)
                        flags |= O_NONBLOCK
                        _ = fcntl(socketFD, F_SETFL, flags)

                        _ = withUnsafePointer(to: &address) { pointer in
                            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                                connect(socketFD, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                        close(socketFD)
                    }
                }

                if counter % 100 == 0 {
                    self.diagnostics.info("Keepalive tick counter=\(counter) host=\(host)")
                }
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        keepaliveTimer = timer
    }

    private func stopKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
    }

    private func postMouseJiggle(label: String = "tick") {
        let currentPosition = CGEvent(source: nil)?.location ?? CGPoint(x: 100, y: 100)
        let movedPosition = CGPoint(x: currentPosition.x + 1, y: currentPosition.y)

        diagnostics.trace("mouse jiggle label=\(label) current=\(currentPosition.x),\(currentPosition.y)")

        guard let moveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: movedPosition,
            mouseButton: .left
        ) else {
            diagnostics.error("Failed to create forward mouse move event for label=\(label)")
            return
        }

        moveEvent.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let backEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: currentPosition,
                mouseButton: .left
            ) else {
                self.diagnostics.error("Failed to create return mouse move event for label=\(label)")
                return
            }

            backEvent.post(tap: .cghidEventTap)
        }
    }

    private func startMouseJiggle() {
        stopMouseJiggle()
        diagnostics.notice("Starting mouse jiggle timer interval=1")

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mouseJiggleCount += 1
                self.lastJiggleTime = Date()
                self.postMouseJiggle()

                if self.mouseJiggleCount % 60 == 0 {
                    self.diagnostics.info("Mouse jiggle count=\(self.mouseJiggleCount)")
                } else {
                    self.diagnostics.trace("mouse jiggle tick count=\(self.mouseJiggleCount)")
                }
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        mouseJiggleTimer = timer
    }

    private func stopMouseJiggle() {
        mouseJiggleTimer?.invalidate()
        mouseJiggleTimer = nil
    }

    private func startDurationTimer() {
        stopDurationTimer()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDurationText()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        durationTimer = timer
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func startHeartbeatTimer() {
        stopHeartbeatTimer()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.emitHeartbeat(reason: "timer")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func stopHeartbeatTimer() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func emitHeartbeat(reason: String) {
        let caffeinatePIDDescription = sessionState.caffeinatePID.map(String.init) ?? "nil"
        let caffeinateRunning = sessionState.caffeinatePID.map(processExists(pid:)) ?? false
        let ownedValues = powerProfileManager.currentOwnedValues(for: sessionState)
        let body = [
            "reason=\(reason)",
            "profile=\(sessionState.profile.rawValue)",
            "active=\(isActive)",
            "displayAsleep=\(isDisplayAsleep)",
            "lidClosed=\(isLidClosed())",
            "caffeinatePID=\(caffeinatePIDDescription)",
            "caffeinateRunning=\(caffeinateRunning)",
            "mouseJiggleCount=\(mouseJiggleCount)",
            "keepaliveCount=\(keepaliveCount)",
            "lastJiggle=\(lastJiggleTime.map(isoTimestamp) ?? "never")",
            "ownedPmsetKeys=\(sessionState.ownedPmsetKeys.joined(separator: ", "))",
            "ownedPmsetValues=",
            ownedValues.isEmpty ? "<none>" : ownedValues.keys.sorted().map { "\($0)=\(ownedValues[$0] ?? "")" }.joined(separator: "\n"),
        ].joined(separator: "\n")
        diagnostics.logMultiline(.notice, title: "heartbeat", body: body)
    }

    private func updateDurationText() {
        guard let activeSince else {
            durationText = "Inactive"
            return
        }

        let elapsed = Int(Date().timeIntervalSince(activeSince))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60

        if hours > 0 {
            durationText = "Active for \(hours)h \(minutes)m"
        } else if minutes > 0 {
            durationText = "Active for \(minutes)m"
        } else {
            durationText = "Active for <1m"
        }
    }

    private func processExists(pid: Int32) -> Bool {
        if pid <= 0 {
            return false
        }

        if kill(pid, 0) == 0 {
            return true
        }

        return errno != ESRCH
    }

    private func terminatePID(_ pid: Int32, label: String) {
        guard pid > 0 else {
            return
        }

        diagnostics.notice("Sending SIGTERM to \(label) pid=\(pid)")
        if kill(pid, SIGTERM) != 0 && errno != ESRCH {
            diagnostics.error("Failed to SIGTERM \(label) pid=\(pid) errno=\(errno)")
        }

        usleep(200_000)

        if processExists(pid: pid) {
            diagnostics.warning("\(label) pid=\(pid) survived SIGTERM; escalating to SIGKILL")
            if kill(pid, SIGKILL) != 0 && errno != ESRCH {
                diagnostics.error("Failed to SIGKILL \(label) pid=\(pid) errno=\(errno)")
            }
        }
    }

}
