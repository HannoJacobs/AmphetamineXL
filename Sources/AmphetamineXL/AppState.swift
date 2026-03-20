import SwiftUI
import IOKit
import IOKit.pwr_mgt

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

    var menuBarIcon: String {
        isActive ? "bolt.fill" : "bolt.slash"
    }

    init() {
        let savedState = UserDefaults.standard.bool(forKey: "amphetamine_active")
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
        let resultIdle = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &idleID
        )

        var systemID = IOPMAssertionID(0)
        let resultSystem = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &systemID
        )

        var displayID = IOPMAssertionID(0)
        let resultDisplay = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &displayID
        )

        guard resultIdle == kIOReturnSuccess && resultSystem == kIOReturnSuccess && resultDisplay == kIOReturnSuccess else {
            if resultIdle == kIOReturnSuccess { IOPMAssertionRelease(idleID) }
            if resultSystem == kIOReturnSuccess { IOPMAssertionRelease(systemID) }
            if resultDisplay == kIOReturnSuccess { IOPMAssertionRelease(displayID) }
            return
        }

        assertionIDIdleSystem = idleID
        assertionIDSystemSleep = systemID
        assertionIDDisplaySleep = displayID
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

        isActive = false
        activeSince = nil
        durationText = "Inactive"
        UserDefaults.standard.set(false, forKey: "amphetamine_active")

        stopDurationTimer()
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
