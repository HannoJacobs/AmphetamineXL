import SwiftUI
import IOKit
import IOKit.pwr_mgt
import CoreGraphics

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

    // caffeinate -s as a backing process — required on Apple Silicon because
    // standby (SMC-level deep sleep) ignores IOKit assertions entirely.
    // caffeinate goes through a different kernel path that standby respects.
    private var caffeinateProcess: Process? = nil

    // Network keepalive — pings 1.1.1.1 every 5s to prevent iPhone hotspot
    // from dropping the connection when it thinks no traffic is flowing.
    private var keepaliveTimer: Timer? = nil

    // Simulated mouse movement — the key trick from Amphetamine.
    // Apple Silicon SMC ignores IOKit assertions for clamshell sleep,
    // but respects HID activity. By posting a tiny CGEvent mouse move
    // every few seconds, the system thinks a user is present.
    private var mouseJiggleTimer: Timer? = nil

    var menuBarIcon: String {
        isActive ? "bolt.fill" : "bolt.slash"
    }

    init() {
        // Default ON — user must explicitly disable. Fall back to true if key not yet set.
        let hasSetPref = UserDefaults.standard.object(forKey: "amphetamine_active") != nil
        let savedState = hasSetPref ? UserDefaults.standard.bool(forKey: "amphetamine_active") : true
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

        let reason = "AmphetamineXL preventing sleep" as CFString

        var idleID = IOPMAssertionID(0)
        IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &idleID
        )

        var systemID = IOPMAssertionID(0)
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &systemID
        )

        var displayID = IOPMAssertionID(0)
        IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displayID
        )

        assertionIDIdleSystem = idleID
        assertionIDSystemSleep = systemID
        assertionIDDisplaySleep = displayID

        // Launch caffeinate -s to block standby/clamshell at kernel level
        startCaffeinate()

        // Start network keepalive to prevent iPhone hotspot from dropping
        startKeepalive()

        // Start mouse jiggle — the real clamshell sleep prevention
        startMouseJiggle()

        isActive = true
        activeSince = Date()
        UserDefaults.standard.set(true, forKey: "amphetamine_active")

        updateDurationText()
        startDurationTimer()
    }

    func disableCaffeine() {
        guard isActive else { return }

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
    }

    // MARK: - caffeinate subprocess

    private func startCaffeinate() {
        stopCaffeinate()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-s"]  // -s = PreventSystemSleep, survives standby
        try? p.run()
        caffeinateProcess = p
    }

    private func stopCaffeinate() {
        caffeinateProcess?.terminate()
        caffeinateProcess = nil
    }

    // MARK: - Network keepalive (prevents iPhone hotspot from dropping)

    // Rotate through multiple lightweight network probes to keep
    // any connection (hotspot, Wi-Fi, etc.) from going idle.
    private var keepaliveCounter: Int = 0

    private let keepaliveHosts = [
        "1.1.1.1",           // Cloudflare DNS
        "8.8.8.8",           // Google DNS
        "9.9.9.9",           // Quad9 DNS
        "208.67.222.222",    // OpenDNS
        "1.0.0.1",           // Cloudflare secondary
    ]

    private func startKeepalive() {
        stopKeepalive()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            let counter = self.keepaliveCounter
            self.keepaliveCounter += 1

            Task.detached(priority: .utility) {
                // Rotate through hosts so traffic looks varied
                let host = self.keepaliveHosts[counter % self.keepaliveHosts.count]

                // 1. DNS lookup — generates a UDP packet
                var hints = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_socktype = Int32(SOCK_DGRAM)
                var res: UnsafeMutablePointer<addrinfo>?
                getaddrinfo(host, nil, &hints, &res)
                if res != nil { freeaddrinfo(res) }

                // 2. Quick TCP connect attempt to port 53 (DNS) — generates
                //    a SYN packet which is enough to show network activity.
                //    Immediately closed, no data sent.
                let sock = socket(AF_INET, SOCK_STREAM, 0)
                if sock >= 0 {
                    var addr = sockaddr_in()
                    addr.sin_family = sa_family_t(AF_INET)
                    addr.sin_port = UInt16(53).bigEndian
                    inet_pton(AF_INET, host, &addr.sin_addr)

                    // Non-blocking connect — we don't care if it succeeds
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

    private func startMouseJiggle() {
        stopMouseJiggle()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            // Get current mouse position
            let currentPos = CGEvent(source: nil)?.location ?? CGPoint(x: 100, y: 100)

            // Move 1px right then back — invisible to the user but enough
            // to register as HID activity with the SMC
            let moved = CGPoint(x: currentPos.x + 1, y: currentPos.y)

            if let moveEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: moved,
                mouseButton: .left
            ) {
                moveEvent.post(tap: .cghidEventTap)
            }

            // Move back after a tiny delay
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
