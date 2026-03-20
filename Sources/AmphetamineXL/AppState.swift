import SwiftUI
import IOKit
import IOKit.pwr_mgt
import CoreGraphics
import os.log

private let logger = Logger(subsystem: "com.hannojacobs.AmphetamineXL", category: "SleepPrevention")

@Observable
@MainActor
final class AppState {
    private(set) var isActive: Bool = false
    private(set) var activeSince: Date? = nil
    private(set) var durationText: String = "Inactive"

    private var assertionIDIdleSystem: IOPMAssertionID = IOPMAssertionID(0)
    private var assertionIDSystemSleep: IOPMAssertionID = IOPMAssertionID(0)
    private var assertionIDDisplaySleep: IOPMAssertionID = IOPMAssertionID(0)
    private var durationTimer: Timer? = nil

    private var caffeinateProcess: Process? = nil
    private var keepaliveTimer: Timer? = nil
    private var mouseJiggleTimer: Timer? = nil

    // Track stats for debugging
    private var mouseJiggleCount: Int = 0
    private var keepaliveCount: Int = 0
    private var keepaliveCounter: Int = 0
    private var lastJiggleTime: Date? = nil

    private let keepaliveHosts = [
        "1.1.1.1",           // Cloudflare DNS
        "8.8.8.8",           // Google DNS
        "9.9.9.9",           // Quad9 DNS
        "208.67.222.222",    // OpenDNS
        "1.0.0.1",           // Cloudflare secondary
    ]

    var menuBarIcon: String {
        isActive ? "bolt.fill" : "bolt.slash"
    }

    init() {
        logger.notice("🚀 AmphetamineXL initializing")

        // Register for sleep/wake notifications
        registerSleepWakeNotifications()

        let hasSetPref = UserDefaults.standard.object(forKey: "amphetamine_active") != nil
        let savedState = hasSetPref ? UserDefaults.standard.bool(forKey: "amphetamine_active") : true
        logger.notice("📋 Saved state: \(savedState), hasSetPref: \(hasSetPref)")
        if savedState {
            enableCaffeine()
        }
    }

    func toggle() {
        if isActive {
            disableCaffeine()
        } else {
            enableCaffeine()
        }
    }

    func enableCaffeine() {
        guard !isActive else { return }
        logger.notice("⚡ Enabling caffeine — creating assertions")

        let reason = "AmphetamineXL preventing sleep" as CFString

        var idleID = IOPMAssertionID(0)
        let r1 = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &idleID
        )
        logger.notice("  PreventUserIdleSystemSleep: \(r1 == kIOReturnSuccess ? "✅" : "❌ error \(r1)")")

        var systemID = IOPMAssertionID(0)
        let r2 = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &systemID
        )
        logger.notice("  PreventSystemSleep: \(r2 == kIOReturnSuccess ? "✅" : "❌ error \(r2)")")

        var displayID = IOPMAssertionID(0)
        let r3 = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displayID
        )
        logger.notice("  PreventUserIdleDisplaySleep: \(r3 == kIOReturnSuccess ? "✅" : "❌ error \(r3)")")

        assertionIDIdleSystem = idleID
        assertionIDSystemSleep = systemID
        assertionIDDisplaySleep = displayID

        startCaffeinate()
        startKeepalive()
        startMouseJiggle()

        isActive = true
        activeSince = Date()
        mouseJiggleCount = 0
        keepaliveCount = 0
        UserDefaults.standard.set(true, forKey: "amphetamine_active")

        updateDurationText()
        startDurationTimer()
        logger.notice("⚡ Caffeine ENABLED — all systems go")
    }

    func disableCaffeine() {
        guard isActive else { return }
        logger.notice("💤 Disabling caffeine")

        IOPMAssertionRelease(assertionIDIdleSystem)
        IOPMAssertionRelease(assertionIDSystemSleep)
        IOPMAssertionRelease(assertionIDDisplaySleep)
        assertionIDIdleSystem = IOPMAssertionID(0)
        assertionIDSystemSleep = IOPMAssertionID(0)
        assertionIDDisplaySleep = IOPMAssertionID(0)

        stopCaffeinate()
        stopKeepalive()
        stopMouseJiggle()

        isActive = false
        activeSince = nil
        durationText = "Inactive"
        UserDefaults.standard.set(false, forKey: "amphetamine_active")

        stopDurationTimer()
        logger.notice("💤 Caffeine DISABLED")
    }

    // MARK: - Sleep/Wake notifications

    private func registerSleepWakeNotifications() {
        let wsnc = NSWorkspace.shared.notificationCenter

        wsnc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            logger.critical("🛑 SYSTEM WILL SLEEP — jiggle count: \(self.mouseJiggleCount), keepalive count: \(self.keepaliveCount), last jiggle: \(self.lastJiggleTime?.description ?? "never")")
            // Try one last-ditch mouse event
            self.postMouseJiggle(label: "last-ditch-before-sleep")
        }

        wsnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            logger.critical("🟢 SYSTEM DID WAKE — resuming all timers")
            // Restart everything on wake in case timers got killed
            if self.isActive {
                self.startMouseJiggle()
                self.startKeepalive()
                // Make sure caffeinate is still alive
                if let p = self.caffeinateProcess, !p.isRunning {
                    logger.warning("⚠️ caffeinate died during sleep — restarting")
                    self.startCaffeinate()
                }
            }
        }

        wsnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
            logger.notice("🖥️ DISPLAY SLEEP (lid closed or display off)")
        }

        wsnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
            logger.notice("🖥️ DISPLAY WAKE (lid opened or display on)")
        }

        logger.notice("📡 Registered for sleep/wake/display notifications")
    }

    // MARK: - caffeinate subprocess

    private func startCaffeinate() {
        stopCaffeinate()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-s"]
        do {
            try p.run()
            caffeinateProcess = p
            logger.notice("☕ caffeinate -s started (PID \(p.processIdentifier))")
        } catch {
            logger.error("❌ Failed to start caffeinate: \(error.localizedDescription)")
        }
    }

    private func stopCaffeinate() {
        if let p = caffeinateProcess {
            logger.notice("☕ Stopping caffeinate (PID \(p.processIdentifier))")
            p.terminate()
        }
        caffeinateProcess = nil
    }

    // MARK: - Network keepalive

    private func startKeepalive() {
        stopKeepalive()
        logger.notice("🌐 Starting network keepalive (3s interval, \(self.keepaliveHosts.count) hosts)")
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            let counter = self.keepaliveCounter
            self.keepaliveCounter += 1
            self.keepaliveCount += 1

            Task.detached(priority: .utility) {
                let host = self.keepaliveHosts[counter % self.keepaliveHosts.count]

                // 1. DNS lookup
                var hints = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_socktype = Int32(SOCK_DGRAM)
                var res: UnsafeMutablePointer<addrinfo>?
                getaddrinfo(host, nil, &hints, &res)
                if res != nil { freeaddrinfo(res) }

                // 2. TCP SYN to port 53
                let sock = socket(AF_INET, SOCK_STREAM, 0)
                if sock >= 0 {
                    var addr = sockaddr_in()
                    addr.sin_family = sa_family_t(AF_INET)
                    addr.sin_port = UInt16(53).bigEndian
                    inet_pton(AF_INET, host, &addr.sin_addr)

                    var flags = fcntl(sock, F_GETFL, 0)
                    flags |= O_NONBLOCK
                    fcntl(sock, F_SETFL, flags)

                    withUnsafePointer(to: &addr) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                    close(sock)
                }

                // Log every 100 keepalives (~5 min)
                if counter % 100 == 0 {
                    logger.info("🌐 Keepalive #\(counter) → \(host)")
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

    // MARK: - Mouse jiggle (prevents clamshell sleep on Apple Silicon)

    private func postMouseJiggle(label: String = "tick") {
        let currentPos = CGEvent(source: nil)?.location ?? CGPoint(x: 100, y: 100)
        let moved = CGPoint(x: currentPos.x + 1, y: currentPos.y)

        if let moveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: moved,
            mouseButton: .left
        ) {
            moveEvent.post(tap: .cghidEventTap)
        } else {
            logger.error("❌ CGEvent creation FAILED for mouse move (\(label))")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let backEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: currentPos,
                mouseButton: .left
            ) {
                backEvent.post(tap: .cghidEventTap)
            }
        }
    }

    private func startMouseJiggle() {
        stopMouseJiggle()
        logger.notice("🖱️ Starting mouse jiggle (1s interval)")
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.mouseJiggleCount += 1
            self.lastJiggleTime = Date()
            self.postMouseJiggle()

            // Log every 60 jiggle (1 min)
            if self.mouseJiggleCount % 60 == 0 {
                logger.info("🖱️ Jiggle #\(self.mouseJiggleCount) (running \(self.mouseJiggleCount)s)")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseJiggleTimer = timer
    }

    private func stopMouseJiggle() {
        mouseJiggleTimer?.invalidate()
        mouseJiggleTimer = nil
    }

    // MARK: - Duration timer

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

    private func updateDurationText() {
        guard let since = activeSince else {
            durationText = "Inactive"
            return
        }

        let elapsed = Int(Date().timeIntervalSince(since))
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
}
