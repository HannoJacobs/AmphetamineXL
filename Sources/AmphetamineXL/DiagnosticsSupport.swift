import AppKit
import Foundation
import LaunchAtLogin
import os.log

let appSubsystem = "com.hannojacobs.AmphetamineXL"

enum WakeProfile: String, Codable {
    case fixedDefault = "fixed-default"
    case legacyMaxAwake = "legacy-max-awake"

    static let defaultsKey = "wakeProfile"
    static let activeRuntimeDefault: WakeProfile = .legacyMaxAwake

    static func resolved(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> WakeProfile {
        for (index, argument) in arguments.enumerated() {
            if argument == "--wake-profile", index + 1 < arguments.count {
                return WakeProfile(rawValue: arguments[index + 1]) ?? activeRuntimeDefault
            }

            if let value = argument.split(separator: "=", maxSplits: 1).last, argument.hasPrefix("--wake-profile=") {
                return WakeProfile(rawValue: String(value)) ?? activeRuntimeDefault
            }
        }

        return activeRuntimeDefault
    }
}

enum ShutdownReason: String, Codable {
    case toggleOff
    case menuQuit
    case willTerminate
    case launchRecovery
    case crashRecovery
    case deinitCleanup
}

struct CommandResult {
    let executablePath: String
    let arguments: [String]
    let terminationStatus: Int32
    let stdout: String
    let stderr: String

    var renderedCommand: String {
        ([executablePath] + arguments).joined(separator: " ")
    }

    var combinedOutput: String {
        if stdout.isEmpty && stderr.isEmpty {
            return ""
        }

        if stderr.isEmpty {
            return stdout
        }

        if stdout.isEmpty {
            return stderr
        }

        return stdout + "\n" + stderr
    }
}

enum CommandRunnerError: Error {
    case failedToLaunch(String)
}

final class CommandRunner {
    static let shared = CommandRunner()

    func run(_ executablePath: String, arguments: [String] = []) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw CommandRunnerError.failedToLaunch(error.localizedDescription)
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            executablePath: executablePath,
            arguments: arguments,
            terminationStatus: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: String(decoding: stderrData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

final class AppPaths {
    static let shared = AppPaths()

    let appSupportURL: URL
    let logsDirectoryURL: URL
    let sessionStateURL: URL
    let baselineSnapshotURL: URL
    let rollbackDirectoryURL: URL

    private init() {
        let fileManager = FileManager.default
        let supportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)

        appSupportURL = supportRoot.appendingPathComponent("AmphetamineXL", isDirectory: true)
        logsDirectoryURL = appSupportURL.appendingPathComponent("Logs", isDirectory: true)
        sessionStateURL = appSupportURL.appendingPathComponent("session-state.json")
        baselineSnapshotURL = appSupportURL.appendingPathComponent("baseline-snapshot.json")
        rollbackDirectoryURL = appSupportURL.appendingPathComponent("Rollback", isDirectory: true)

        try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        try? fileManager.createDirectory(at: rollbackDirectoryURL, withIntermediateDirectories: true, attributes: nil)
    }
}

struct AppSessionState: Codable {
    var sessionID: String
    var profile: WakeProfile
    var desiredActiveOnLaunch: Bool
    var shutdownClean: Bool
    var caffeinatePID: Int32?
    var ownedPmsetKeys: [String]
    var ownedPmsetPreviousValues: [String: String]
    var lastShutdownReason: ShutdownReason?
    var lastKnownLidState: Bool?
    var lastEventNumber: Int
    var lastLogFilePath: String?
    var startedAt: String
}

struct BaselineSnapshot: Codable {
    var capturedAt: String
    var appVersion: String
    var buildVersion: String
    var sessionID: String
    var wakeProfile: String
    var pmsetG: String
    var pmsetCustom: String
    var pmsetAssertions: String
    var pmsetLive: String
    var processSnapshot: String
}

final class SessionStateStore {
    private let paths: AppPaths
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(paths: AppPaths = .shared) {
        self.paths = paths
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> AppSessionState? {
        guard let data = try? Data(contentsOf: paths.sessionStateURL) else {
            return nil
        }

        return try? decoder.decode(AppSessionState.self, from: data)
    }

    func save(_ state: AppSessionState) {
        guard let data = try? encoder.encode(state) else {
            return
        }

        try? data.write(to: paths.sessionStateURL, options: .atomic)
    }

    func saveBaselineSnapshotIfMissing(
        sessionID: String,
        profile: WakeProfile,
        diagnostics: DiagnosticsLogger,
        commandRunner: CommandRunner = .shared
    ) {
        guard !FileManager.default.fileExists(atPath: paths.baselineSnapshotURL.path) else {
            return
        }

        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? bundleVersion

        let snapshot = BaselineSnapshot(
            capturedAt: Self.timestampString(),
            appVersion: bundleVersion,
            buildVersion: buildVersion,
            sessionID: sessionID,
            wakeProfile: profile.rawValue,
            pmsetG: Self.commandOutput(commandRunner, "/usr/bin/pmset", ["-g"]),
            pmsetCustom: Self.commandOutput(commandRunner, "/usr/bin/pmset", ["-g", "custom"]),
            pmsetAssertions: Self.commandOutput(commandRunner, "/usr/bin/pmset", ["-g", "assertions"]),
            pmsetLive: Self.commandOutput(commandRunner, "/usr/bin/pmset", ["-g", "live"]),
            processSnapshot: Self.commandOutput(commandRunner, "/usr/bin/pgrep", ["-fal", "AmphetamineXL|caffeinate|ScreenSaverEngine"])
        )

        guard let data = try? encoder.encode(snapshot) else {
            diagnostics.error("Failed to encode baseline snapshot for rollback capture")
            return
        }

        do {
            try data.write(to: paths.baselineSnapshotURL, options: .atomic)
            diagnostics.notice("Saved baseline rollback snapshot to \(paths.baselineSnapshotURL.path)")
        } catch {
            diagnostics.error("Failed to save baseline rollback snapshot: \(error.localizedDescription)")
        }
    }

    private static func commandOutput(_ runner: CommandRunner, _ executablePath: String, _ arguments: [String]) -> String {
        guard let result = try? runner.run(executablePath, arguments: arguments) else {
            return "failed to launch \(executablePath) " + arguments.joined(separator: " ")
        }

        if result.combinedOutput.isEmpty {
            return "exit \(result.terminationStatus)"
        }

        return result.combinedOutput
    }

    private static func timestampString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

enum AppLogLevel: String {
    case debug
    case info
    case notice
    case warning
    case error
    case critical
}

final class DiagnosticsLogger {
    static let shared = DiagnosticsLogger()

    private let logger = Logger(subsystem: appSubsystem, category: "SleepPrevention")
    private let paths: AppPaths
    private let queue = DispatchQueue(label: "com.hannojacobs.AmphetamineXL.diagnostics")
    private let maxLogFileSize: UInt64 = 2 * 1024 * 1024
    private let maxLogFiles = 10
    private let maxRecentTraceEntries = 300

    private var sessionID = "bootstrap"
    private var sessionFilePrefix = "bootstrap"
    private var eventNumber = 0
    private var fileSegment = 0
    private var currentLogURL: URL?
    private var currentFileHandle: FileHandle?
    private var currentFileSize: UInt64 = 0
    private var recentTraceEntries: [String] = []

    private init(paths: AppPaths = .shared) {
        self.paths = paths
    }

    var currentEventNumber: Int {
        queue.sync { eventNumber }
    }

    var currentLogFilePath: String? {
        queue.sync { currentLogURL?.path }
    }

    func configure(sessionID: String) {
        queue.sync {
            self.sessionID = sessionID
            self.sessionFilePrefix = Self.sessionFilePrefix(for: sessionID)
            self.eventNumber = 0
            self.fileSegment = 0
            self.recentTraceEntries.removeAll(keepingCapacity: true)
            closeCurrentLogLocked()
            openNextLogSegmentLocked()
        }

        notice("Diagnostics logger configured for session \(sessionID)")
    }

    func trace(_ message: String) {
        queue.sync {
            recentTraceEntries.append("[trace] \(timestamp()) \(message)")
            if recentTraceEntries.count > maxRecentTraceEntries {
                recentTraceEntries.removeFirst(recentTraceEntries.count - maxRecentTraceEntries)
            }
        }
    }

    func debug(_ message: String) {
        log(.debug, message)
    }

    func info(_ message: String) {
        log(.info, message)
    }

    func notice(_ message: String) {
        log(.notice, message)
    }

    func warning(_ message: String) {
        log(.warning, message)
    }

    func error(_ message: String) {
        log(.error, message)
    }

    func critical(_ message: String) {
        log(.critical, message, includeTraceDump: true)
    }

    func anomaly(_ message: String) {
        log(.critical, "ANOMALY: \(message)", includeTraceDump: true)
    }

    func logMultiline(_ level: AppLogLevel, title: String, body: String) {
        let lines = body.isEmpty ? ["<empty>"] : body.components(separatedBy: .newlines)
        for line in lines {
            log(level, "[\(title)] \(line)")
        }
    }

    func openCurrentLogInFinder() {
        let currentURL = queue.sync { currentLogURL }
        let directoryURL = paths.logsDirectoryURL
        DispatchQueue.main.async {
            if let currentURL {
                NSWorkspace.shared.activateFileViewerSelecting([currentURL])
            } else {
                NSWorkspace.shared.open(directoryURL)
            }
        }
    }

    private func log(_ level: AppLogLevel, _ message: String, includeTraceDump: Bool = false) {
        var traceDump: [String] = []
        let entry = queue.sync { () -> String in
            eventNumber += 1
            let timestamp = timestamp()
            let formatted = "\(timestamp) [\(level.rawValue.uppercased())] session=\(sessionID) event=\(eventNumber) \(message)"
            writeLineLocked(formatted)

            if includeTraceDump, !recentTraceEntries.isEmpty {
                traceDump = recentTraceEntries
                writeLineLocked("\(timestamp) [TRACE] session=\(sessionID) dumping \(recentTraceEntries.count) buffered trace events")
                for trace in recentTraceEntries {
                    writeLineLocked(trace)
                }
            }

            return formatted
        }

        switch level {
        case .debug:
            logger.debug("\(entry, privacy: .public)")
        case .info:
            logger.info("\(entry, privacy: .public)")
        case .notice:
            logger.notice("\(entry, privacy: .public)")
        case .warning:
            logger.warning("\(entry, privacy: .public)")
        case .error:
            logger.error("\(entry, privacy: .public)")
        case .critical:
            logger.critical("\(entry, privacy: .public)")
        }

        if includeTraceDump && !traceDump.isEmpty {
            logger.critical("Trace dump emitted with \(traceDump.count, privacy: .public) buffered entries")
        }
    }

    private func writeLineLocked(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else {
            return
        }

        if currentFileSize + UInt64(data.count) > maxLogFileSize {
            openNextLogSegmentLocked()
        }

        if currentFileHandle == nil {
            openNextLogSegmentLocked()
        }

        currentFileHandle?.write(data)
        currentFileSize += UInt64(data.count)
    }

    private func openNextLogSegmentLocked() {
        closeCurrentLogLocked()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "\(sessionFilePrefix)-\(timestamp)-part\(fileSegment).log"
        fileSegment += 1

        let fileURL = paths.logsDirectoryURL.appendingPathComponent(filename)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            handle.seekToEndOfFile()
            currentFileHandle = handle
            currentLogURL = fileURL
            currentFileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? UInt64) ?? 0
            enforceRotationLocked()
        } catch {
            currentFileHandle = nil
            currentLogURL = nil
            currentFileSize = 0
            logger.error("Failed to open rotating log file: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func enforceRotationLocked() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: paths.logsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let logFiles = urls.filter { $0.pathExtension == "log" }
        guard logFiles.count > maxLogFiles else {
            return
        }

        let sorted = logFiles.sorted {
            let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }

        for oldURL in sorted.prefix(logFiles.count - maxLogFiles) where oldURL != currentLogURL {
            try? FileManager.default.removeItem(at: oldURL)
        }
    }

    private func closeCurrentLogLocked() {
        try? currentFileHandle?.close()
        currentFileHandle = nil
    }

    private func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

private static func sessionFilePrefix(for sessionID: String) -> String {
        "session-\(sessionID.replacingOccurrences(of: "-", with: ""))"
    }
}

func isoTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

func currentAppVersion() -> String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
}

func currentBuildVersion() -> String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? currentAppVersion()
}

func currentLaunchAtLoginState() -> Bool {
    LaunchAtLogin.isEnabled
}
