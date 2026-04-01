import Foundation

final class PowerProfileManager {
    private let commandRunner: CommandRunner
    private let diagnostics: DiagnosticsLogger
    private let supportedCustomKeys: Set<String>
    private let supportsDisableSleep: Bool

    init(diagnostics: DiagnosticsLogger, commandRunner: CommandRunner = .shared) {
        self.commandRunner = commandRunner
        self.diagnostics = diagnostics
        self.supportedCustomKeys = PowerProfileManager.discoverSupportedCustomKeys(commandRunner: commandRunner)
        self.supportsDisableSleep = PowerProfileManager.discoverDisableSleepSupport(commandRunner: commandRunner)

        diagnostics.notice("Detected supported pmset custom keys: \(supportedCustomKeys.sorted().joined(separator: ", "))")
        diagnostics.notice("Detected hidden disablesleep support: \(supportsDisableSleep)")

        if !supportedCustomKeys.contains("autopoweroff") {
            diagnostics.warning("pmset capability discovery did not expose autopoweroff; the app will not claim ownership of it on this machine")
        }
    }

    func apply(profile: WakeProfile, sessionState: inout AppSessionState) {
        let ownedKeys = effectiveOwnedKeys(for: profile)
        sessionState.profile = profile

        if sessionState.ownedPmsetPreviousValues.isEmpty {
            sessionState.ownedPmsetPreviousValues = captureCurrentValues(for: ownedKeys)
        }
        sessionState.ownedPmsetKeys = ownedKeys

        diagnostics.notice("Applying wake profile \(profile.rawValue) with owned keys: \(ownedKeys.joined(separator: ", "))")
        diagnostics.logMultiline(.notice, title: "pmset snapshot before apply", body: describe(values: sessionState.ownedPmsetPreviousValues))

        let customValues = desiredCustomValues(for: profile).filter { ownedKeys.contains($0.key) }
        if !customValues.isEmpty {
            runPmset(
                label: "apply \(profile.rawValue) custom values",
                requiresSudo: true,
                arguments: ["-a"] + flattenedArguments(customValues)
            )
        }

        if ownedKeys.contains("disablesleep") {
            let value = profile == .legacyMaxAwake ? "1" : "0"
            runPmset(
                label: "apply \(profile.rawValue) disablesleep",
                requiresSudo: true,
                arguments: ["disablesleep", value]
            )
        }

        diagnostics.logMultiline(.notice, title: "pmset snapshot after apply", body: describe(values: currentOwnedValues(for: sessionState)))
    }

    func restore(sessionState: inout AppSessionState, reason: ShutdownReason) {
        guard !sessionState.ownedPmsetKeys.isEmpty else {
            diagnostics.notice("No owned pmset keys to restore for \(reason.rawValue)")
            return
        }

        diagnostics.notice("Restoring owned pmset keys for \(reason.rawValue): \(sessionState.ownedPmsetKeys.joined(separator: ", "))")

        let acValues = restoredValues(from: sessionState.ownedPmsetPreviousValues, prefix: "ac:")
        if !acValues.isEmpty {
            runPmset(
                label: "restore AC pmset values for \(reason.rawValue)",
                requiresSudo: true,
                arguments: ["-c"] + flattenedArguments(acValues)
            )
        }

        let batteryValues = restoredValues(from: sessionState.ownedPmsetPreviousValues, prefix: "battery:")
        if !batteryValues.isEmpty {
            runPmset(
                label: "restore battery pmset values for \(reason.rawValue)",
                requiresSudo: true,
                arguments: ["-b"] + flattenedArguments(batteryValues)
            )
        }

        if let disableSleep = sessionState.ownedPmsetPreviousValues["live:disablesleep"] {
            runPmset(
                label: "restore disablesleep for \(reason.rawValue)",
                requiresSudo: true,
                arguments: ["disablesleep", disableSleep]
            )
        }

        sessionState.ownedPmsetKeys = []
        sessionState.ownedPmsetPreviousValues = [:]
    }

    func currentOwnedValues(for sessionState: AppSessionState) -> [String: String] {
        captureCurrentValues(for: sessionState.ownedPmsetKeys)
    }

    private func effectiveOwnedKeys(for profile: WakeProfile) -> [String] {
        var keys: [String]

        switch profile {
        case .fixedDefault:
            keys = ["standby", "hibernatemode", "autopoweroff"]
        case .legacyMaxAwake:
            keys = ["standby", "hibernatemode", "autopoweroff", "sleep", "displaysleep", "disablesleep"]
        }

        return keys.filter { key in
            if key == "disablesleep" {
                return supportsDisableSleep
            }

            return supportedCustomKeys.contains(key)
        }
    }

    private func desiredCustomValues(for profile: WakeProfile) -> [String: String] {
        switch profile {
        case .fixedDefault:
            return [
                "standby": "0",
                "hibernatemode": "0",
                "autopoweroff": "0",
            ]
        case .legacyMaxAwake:
            return [
                "standby": "0",
                "hibernatemode": "0",
                "autopoweroff": "0",
                "sleep": "0",
                "displaysleep": "0",
            ]
        }
    }

    private func captureCurrentValues(for keys: [String]) -> [String: String] {
        guard !keys.isEmpty else {
            return [:]
        }

        let customValues = readCustomValues()
        let liveValues = readLiveValues()
        var values: [String: String] = [:]

        for key in keys {
            if key == "disablesleep" {
                if let value = liveValues[key] {
                    values["live:\(key)"] = value
                }
                continue
            }

            if let batteryValue = customValues["battery"]?[key] {
                values["battery:\(key)"] = batteryValue
            }

            if let acValue = customValues["ac"]?[key] {
                values["ac:\(key)"] = acValue
            }
        }

        return values
    }

    private func readCustomValues() -> [String: [String: String]] {
        let result = runPmset(
            label: "read pmset custom values",
            requiresSudo: false,
            arguments: ["-g", "custom"]
        )

        var source: String?
        var parsed: [String: [String: String]] = [:]

        for rawLine in result.stdout.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "Battery Power:" {
                source = "battery"
                continue
            }

            if line == "AC Power:" {
                source = "ac"
                continue
            }

            guard let source else {
                continue
            }

            let components = line.split(whereSeparator: \.isWhitespace)
            guard components.count >= 2 else {
                continue
            }

            let key = String(components[0])
            if supportedCustomKeys.contains(key) {
                parsed[source, default: [:]][key] = String(components[1])
            }
        }

        return parsed
    }

    private func readLiveValues() -> [String: String] {
        let result = runPmset(
            label: "read pmset live values",
            requiresSudo: false,
            arguments: ["-g", "live"]
        )

        var values: [String: String] = [:]
        for rawLine in result.stdout.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("SleepDisabled") {
                let components = line.split(whereSeparator: \.isWhitespace)
                if components.count >= 2 {
                    values["disablesleep"] = String(components[1])
                }
            }
        }

        return values
    }

    private func restoredValues(from values: [String: String], prefix: String) -> [String: String] {
        var restored: [String: String] = [:]
        for (key, value) in values where key.hasPrefix(prefix) {
            restored[String(key.dropFirst(prefix.count))] = value
        }
        return restored
    }

    private func flattenedArguments(_ values: [String: String]) -> [String] {
        values.keys.sorted().flatMap { [$0, values[$0] ?? ""] }
    }

    @discardableResult
    private func runPmset(label: String, requiresSudo: Bool, arguments: [String]) -> CommandResult {
        let executablePath = requiresSudo ? "/usr/bin/sudo" : "/usr/bin/pmset"
        let commandArguments = requiresSudo ? ["-n", "/usr/bin/pmset"] + arguments : arguments

        do {
            let result = try commandRunner.run(executablePath, arguments: commandArguments)
            diagnostics.notice("[pmset] \(label) -> exit \(result.terminationStatus) :: \(result.renderedCommand)")
            if !result.stdout.isEmpty {
                diagnostics.logMultiline(.notice, title: "\(label) stdout", body: result.stdout)
            }
            if !result.stderr.isEmpty {
                diagnostics.logMultiline(.warning, title: "\(label) stderr", body: result.stderr)
            }
            return result
        } catch {
            diagnostics.error("[pmset] \(label) failed to launch: \(error.localizedDescription)")
            return CommandResult(
                executablePath: executablePath,
                arguments: commandArguments,
                terminationStatus: -1,
                stdout: "",
                stderr: error.localizedDescription
            )
        }
    }

    private func describe(values: [String: String]) -> String {
        if values.isEmpty {
            return "<none>"
        }

        return values.keys.sorted().map { "\($0)=\(values[$0] ?? "")" }.joined(separator: "\n")
    }

    private static func discoverSupportedCustomKeys(commandRunner: CommandRunner) -> Set<String> {
        guard let result = try? commandRunner.run("/usr/bin/pmset", arguments: ["-g", "cap"]) else {
            return ["standby", "hibernatemode", "sleep", "displaysleep"]
        }

        var keys = Set<String>()
        for rawLine in result.stdout.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let token = line.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            if !token.isEmpty {
                keys.insert(token)
            }
        }

        return keys
    }

    private static func discoverDisableSleepSupport(commandRunner: CommandRunner) -> Bool {
        guard let result = try? commandRunner.run("/usr/bin/pmset", arguments: ["-g", "live"]) else {
            return false
        }

        return result.stdout.contains("SleepDisabled")
    }
}
