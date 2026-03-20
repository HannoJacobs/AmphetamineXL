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

    private func startKeepalive() {
        stopKeepalive()
        let timer = Timer(timeInterval: 5, repeats: true) { _ in
            Task {
                // Lightweight DNS lookup — barely any data, just enough to show activity
                var hints = addrinfo()
                hints.ai_family = AF_INET
                hints.ai_socktype = Int32(SOCK_DGRAM)
                var res: UnsafeMutablePointer<addrinfo>?
                getaddrinfo("1.1.1.1", nil, &hints, &res)
                if res != nil { freeaddrinfo(res) }
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
        let timer = Timer(timeInterval: 4, repeats: true) { _ in
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
