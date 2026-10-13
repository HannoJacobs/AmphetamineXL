import Foundation

struct ActivityWindowSettings {
    static let defaultSeconds: Double = 30
    static let minimumSeconds: Double = 10
    static let maximumSeconds: Double = 120
    static let stepSeconds: Double = 5
    static let immediateSeconds: Double = 5

    static func normalize(_ rawValue: Double) -> Double {
        let clamped = min(max(rawValue, minimumSeconds), maximumSeconds)
        return (clamped / stepSeconds).rounded() * stepSeconds
    }
}

struct RunningProcess: Equatable {
    let pid: Int32
    let commandLine: String
}

enum MonitoredActivitySource: String, CaseIterable, Hashable {
    case codexApp
    case codexCLI
    case codexQueue
    case claudeCode

    var displayName: String {
        switch self {
        case .codexApp:
            return "Codex App"
        case .codexCLI:
            return "Codex CLI"
        case .codexQueue:
            return "Codex Queue"
        case .claudeCode:
            return "Claude Code"
        }
    }
}

struct MonitoredActivitySnapshot {
    let runningProcesses: [RunningProcess]
    let codexQueuedFollowUpCount: Int
    let claudeTodoTaskCount: Int
    let claudeSessionPIDs: [Int32]
    let hasRecentCodexThreadActivity: Bool
    let hasActiveCodexTurn: Bool
    let hasImmediateCodexThreadActivity: Bool
    let recentClaudeProjectActivityCount: Int
    let immediateClaudeProjectActivityCount: Int

    init(
        runningProcesses: [RunningProcess],
        codexQueuedFollowUpCount: Int,
        claudeTodoTaskCount: Int,
        claudeSessionPIDs: [Int32],
        hasRecentCodexThreadActivity: Bool = false,
        hasActiveCodexTurn: Bool = false,
        hasImmediateCodexThreadActivity: Bool = false,
        recentClaudeProjectActivityCount: Int = 0,
        immediateClaudeProjectActivityCount: Int = 0
    ) {
        self.runningProcesses = runningProcesses
        self.codexQueuedFollowUpCount = codexQueuedFollowUpCount
        self.claudeTodoTaskCount = claudeTodoTaskCount
        self.claudeSessionPIDs = claudeSessionPIDs
        self.hasRecentCodexThreadActivity = hasRecentCodexThreadActivity
        self.hasActiveCodexTurn = hasActiveCodexTurn
        self.hasImmediateCodexThreadActivity = hasImmediateCodexThreadActivity
        self.recentClaudeProjectActivityCount = recentClaudeProjectActivityCount
        self.immediateClaudeProjectActivityCount = immediateClaudeProjectActivityCount
    }
}

struct MonitoredActivityDecision {
    let activeSources: Set<MonitoredActivitySource>
    let shouldPreventSleep: Bool
    let isCoolingDown: Bool
    let cooldownExpiresAt: Date?
}

struct MonitoringSelection: Equatable {
    let codexEnabled: Bool
    let claudeEnabled: Bool

    static let all = MonitoringSelection(codexEnabled: true, claudeEnabled: true)
}

enum MonitoredRuntimeState: Equatable {
    case disabled
    case idle
    case queued
    case tasking
    case taskingAndQueued

    var label: String {
        switch self {
        case .disabled:
            return "Off"
        case .idle:
            return "Idle"
        case .queued:
            return "Queued"
        case .tasking:
            return "Tasking"
        case .taskingAndQueued:
            return "Tasking + Queued"
        }
    }
}

struct MonitoredRuntimeStatus: Equatable {
    let codex: MonitoredRuntimeState
    let claudeCode: MonitoredRuntimeState
}

struct WakeDemandDecision {
    let shouldKeepWakeStackEnabled: Bool
    let shouldStartWakeStack: Bool
    let shouldStopWakeStack: Bool
}

struct WakeDemandResolver {
    static func resolve(
        manualHoldRequested: Bool,
        autoHoldRequested: Bool,
        isAutoWakeEnabled: Bool,
        isWakeStackRunning: Bool,
        isWakeStackTransitioning: Bool
    ) -> WakeDemandDecision {
        let effectiveAutomaticHold = isAutoWakeEnabled && autoHoldRequested
        let shouldKeepWakeStackEnabled = manualHoldRequested || effectiveAutomaticHold
        return WakeDemandDecision(
            shouldKeepWakeStackEnabled: shouldKeepWakeStackEnabled,
            shouldStartWakeStack: shouldKeepWakeStackEnabled && !isWakeStackRunning && !isWakeStackTransitioning,
            shouldStopWakeStack: !shouldKeepWakeStackEnabled && isWakeStackRunning && !isWakeStackTransitioning
        )
    }
}

struct MonitoredActivityMonitor {
    let cooldownInterval: TimeInterval
    private(set) var lastActiveAt: Date?

    init(cooldownInterval: TimeInterval = 60, lastActiveAt: Date? = nil) {
        self.cooldownInterval = cooldownInterval
        self.lastActiveAt = lastActiveAt
    }

    mutating func update(
        snapshot: MonitoredActivitySnapshot,
        now: Date,
        selection: MonitoringSelection = .all
    ) -> MonitoredActivityDecision {
        let sources = Self.activeSources(in: snapshot, selection: selection)
        if !sources.isEmpty {
            lastActiveAt = now
            return MonitoredActivityDecision(
                activeSources: sources,
                shouldPreventSleep: true,
                isCoolingDown: false,
                cooldownExpiresAt: now.addingTimeInterval(cooldownInterval)
            )
        }

        guard let lastActiveAt else {
            return MonitoredActivityDecision(
                activeSources: [],
                shouldPreventSleep: false,
                isCoolingDown: false,
                cooldownExpiresAt: nil
            )
        }

        let cooldownExpiresAt = lastActiveAt.addingTimeInterval(cooldownInterval)
        if now < cooldownExpiresAt {
            return MonitoredActivityDecision(
                activeSources: [],
                shouldPreventSleep: true,
                isCoolingDown: true,
                cooldownExpiresAt: cooldownExpiresAt
            )
        }

        self.lastActiveAt = nil
        return MonitoredActivityDecision(
            activeSources: [],
            shouldPreventSleep: false,
            isCoolingDown: false,
            cooldownExpiresAt: nil
        )
    }

    static func activeSources(
        in snapshot: MonitoredActivitySnapshot,
        selection: MonitoringSelection = .all
    ) -> Set<MonitoredActivitySource> {
        var sources = Set<MonitoredActivitySource>()
        let liveClaudePIDs = Set(snapshot.claudeSessionPIDs)
        let hasCodexAppTask = selection.codexEnabled && snapshot.runningProcesses.contains { process in
            let command = process.commandLine.lowercased()
            return matchesCodexApp(command) && (snapshot.hasActiveCodexTurn || snapshot.hasRecentCodexThreadActivity)
        }
        let hasCodexCLITask = selection.codexEnabled && snapshot.runningProcesses.contains { process in
            matchesCodexCLI(process.commandLine.lowercased())
        }
        let hasLiveClaudeTaskProcess = snapshot.runningProcesses.contains { process in
            liveClaudePIDs.contains(process.pid) && matchesClaudeCode(process.commandLine.lowercased())
        }
        let hasClaudeTasking = selection.claudeEnabled && hasLiveClaudeTaskProcess && snapshot.recentClaudeProjectActivityCount > 0

        if hasCodexAppTask {
            sources.insert(.codexApp)
        }

        if hasCodexCLITask {
            sources.insert(.codexCLI)
        }

        if selection.codexEnabled && snapshot.codexQueuedFollowUpCount > 0 {
            sources.insert(.codexQueue)
        }

        if hasClaudeTasking {
            sources.insert(.claudeCode)
        }

        return sources
    }

    static func runtimeStatus(
        in snapshot: MonitoredActivitySnapshot,
        selection: MonitoringSelection = .all
    ) -> MonitoredRuntimeStatus {
        let codexIsTasking = selection.codexEnabled && snapshot.runningProcesses.contains(where: { process in
            let command = process.commandLine.lowercased()
            return matchesCodexCLI(command)
                || (snapshot.hasActiveCodexTurn && matchesCodexApp(command))
        })
        let codex: MonitoredRuntimeState
        codex = selection.codexEnabled
            ? combine(tasking: codexIsTasking, queued: snapshot.codexQueuedFollowUpCount > 0)
            : .disabled

        let liveClaudePIDs = Set(snapshot.claudeSessionPIDs)
        let claudeIsTasking = selection.claudeEnabled && snapshot.runningProcesses.contains(where: { process in
            liveClaudePIDs.contains(process.pid) && matchesClaudeCode(process.commandLine.lowercased())
        }) && snapshot.immediateClaudeProjectActivityCount > 0
        let claudeCode: MonitoredRuntimeState
        claudeCode = selection.claudeEnabled
            ? combine(tasking: claudeIsTasking, queued: snapshot.claudeTodoTaskCount > 0)
            : .disabled

        return MonitoredRuntimeStatus(codex: codex, claudeCode: claudeCode)
    }

    static func hasImmediateTaskingActivity(
        in snapshot: MonitoredActivitySnapshot,
        selection: MonitoringSelection = .all
    ) -> Bool {
        let liveClaudePIDs = Set(snapshot.claudeSessionPIDs)
        let hasImmediateCodexTask = selection.codexEnabled && snapshot.runningProcesses.contains(where: { process in
            let command = process.commandLine.lowercased()
            return matchesCodexCLI(command)
                || (snapshot.hasActiveCodexTurn && matchesCodexApp(command))
        })
        let hasImmediateClaudeTask = selection.claudeEnabled && snapshot.runningProcesses.contains(where: { process in
            liveClaudePIDs.contains(process.pid) && matchesClaudeCode(process.commandLine.lowercased())
        }) && snapshot.immediateClaudeProjectActivityCount > 0

        return hasImmediateCodexTask || hasImmediateClaudeTask
    }

    private static func combine(tasking: Bool, queued: Bool) -> MonitoredRuntimeState {
        switch (tasking, queued) {
        case (true, true):
            return .taskingAndQueued
        case (true, false):
            return .tasking
        case (false, true):
            return .queued
        case (false, false):
            return .idle
        }
    }

    private static func matchesCodexApp(_ command: String) -> Bool {
        command.contains("codex app-server") && command.contains("/codex.app/")
    }

    private static func matchesCodexCLI(_ command: String) -> Bool {
        if command.contains("/applications/codex.app/")
            || command.contains("codex app-server")
            || command.contains("codex helper")
            || command.contains("crashpad_handler") {
            return false
        }

        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "codex"
            || trimmed.hasPrefix("codex ")
            || trimmed.hasSuffix("/codex")
            || trimmed.contains("/codex ")
    }

    private static func matchesClaudeCode(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "claude"
            || trimmed.hasPrefix("claude ")
            || trimmed.hasSuffix("/claude")
            || trimmed.contains("/claude ")
    }
}

final class MonitoredActivityProbe: @unchecked Sendable {
    private let fileManager: FileManager
    private let commandRunner: CommandRunner
    private let homeDirectoryURL: URL

    init(
        fileManager: FileManager = .default,
        commandRunner: CommandRunner = .shared,
        homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.homeDirectoryURL = homeDirectoryURL
    }

    func snapshot(activityWindow: TimeInterval = ActivityWindowSettings.defaultSeconds) -> MonitoredActivitySnapshot {
        let claudeSessions = claudeSessions()
        return MonitoredActivitySnapshot(
            runningProcesses: runningProcesses(),
            codexQueuedFollowUpCount: codexQueuedFollowUpCount(),
            claudeTodoTaskCount: claudeTodoTaskCount(),
            claudeSessionPIDs: claudeSessions.map(\.pid),
            hasRecentCodexThreadActivity: hasRecentCodexThreadActivity(activityWindow: activityWindow),
            hasActiveCodexTurn: hasActiveCodexTurn(),
            hasImmediateCodexThreadActivity: hasRecentCodexThreadActivity(activityWindow: ActivityWindowSettings.immediateSeconds),
            recentClaudeProjectActivityCount: recentClaudeProjectActivityCount(
                for: claudeSessions,
                activityWindow: activityWindow
            ),
            immediateClaudeProjectActivityCount: recentClaudeProjectActivityCount(
                for: claudeSessions,
                activityWindow: ActivityWindowSettings.immediateSeconds
            )
        )
    }

    private func runningProcesses() -> [RunningProcess] {
        guard let result = try? commandRunner.run("/usr/bin/pgrep", arguments: ["-fal", "codex|claude"]) else {
            return []
        }

        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { rawLine -> RunningProcess? in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return nil }

                let pieces = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard pieces.count == 2, let pid = Int32(pieces[0]) else {
                    return nil
                }

                return RunningProcess(pid: pid, commandLine: String(pieces[1]))
            }
    }

    private func codexQueuedFollowUpCount() -> Int {
        let stateURL = homeDirectoryURL.appendingPathComponent(".codex/.codex-global-state.json")
        guard
            let data = try? Data(contentsOf: stateURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return 0
        }

        if let queued = object["queued-follow-ups"] as? [String: Any] {
            return queued.count
        }

        if let queued = object["queued-follow-ups"] as? [Any] {
            return queued.count
        }

        return 0
    }

    private func claudeSessions() -> [ClaudeSessionRecord] {
        let sessionsDirectoryURL = homeDirectoryURL.appendingPathComponent(".claude/sessions", isDirectory: true)
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: sessionsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        return fileURLs.compactMap { fileURL in
            guard
                let data = try? Data(contentsOf: fileURL),
                let session = try? decoder.decode(ClaudeSessionRecord.self, from: data)
            else {
                return nil
            }

            return session
        }
    }

    private func claudeTodoTaskCount() -> Int {
        let todosDirectoryURL = homeDirectoryURL.appendingPathComponent(".claude/todos", isDirectory: true)
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: todosDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        let decoder = JSONDecoder()
        return fileURLs.reduce(into: 0) { count, fileURL in
            guard
                let data = try? Data(contentsOf: fileURL),
                let todos = try? decoder.decode([ClaudeTodoRecord].self, from: data)
            else {
                return
            }

            count += todos.count
        }
    }

    private func hasRecentCodexThreadActivity(
        activityWindow: TimeInterval = ActivityWindowSettings.defaultSeconds,
        now: Date = Date()
    ) -> Bool {
        let databaseURL = homeDirectoryURL.appendingPathComponent(".codex/state_5.sqlite")
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return false
        }

        let cutoff = Int(now.timeIntervalSince1970 - activityWindow)
        guard let result = try? commandRunner.run(
            "/usr/bin/sqlite3",
            arguments: [
                databaseURL.path,
                "select count(*) from threads where archived = 0 and updated_at >= \(cutoff);"
            ]
        ) else {
            return false
        }

        return (Int(result.stdout) ?? 0) > 0
    }

    private func hasActiveCodexTurn() -> Bool {
        let databaseURL = homeDirectoryURL.appendingPathComponent(".codex/state_5.sqlite")
        guard
            fileManager.fileExists(atPath: databaseURL.path),
            let result = try? commandRunner.run(
                "/usr/bin/sqlite3",
                arguments: [
                    databaseURL.path,
                    "select rollout_path from threads where archived = 0 order by updated_at desc limit 1;"
                ]
            )
        else {
            return false
        }

        let rolloutPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rolloutPath.isEmpty else {
            return false
        }

        let rolloutURL = URL(fileURLWithPath: rolloutPath)
        guard let handle = try? FileHandle(forReadingFrom: rolloutURL) else {
            return false
        }
        defer { try? handle.close() }

        let data = (try? handle.readToEnd()) ?? Data()
        guard let content = String(data: data, encoding: .utf8) else {
            return false
        }

        return Self.hasActiveCodexTurn(inRolloutContent: content)
    }

    static func hasActiveCodexTurn(inRolloutContent content: String) -> Bool {
        var latestLifecycleEventType: String?

        for line in content.split(separator: "\n") {
            guard
                let jsonData = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                object["type"] as? String == "event_msg",
                let payload = object["payload"] as? [String: Any],
                let eventType = payload["type"] as? String,
                ["task_started", "task_complete", "turn_aborted"].contains(eventType)
            else {
                continue
            }

            latestLifecycleEventType = eventType
        }

        return latestLifecycleEventType == "task_started"
    }

    private func recentClaudeProjectActivityCount(
        for sessions: [ClaudeSessionRecord],
        activityWindow: TimeInterval = ActivityWindowSettings.defaultSeconds,
        now: Date = Date()
    ) -> Int {
        let cutoff = now.addingTimeInterval(-activityWindow)
        return sessions.reduce(into: 0) { count, session in
            let projectDirectoryName = projectDirectoryName(for: session.cwd)
            let projectFileURL = homeDirectoryURL
                .appendingPathComponent(".claude/projects", isDirectory: true)
                .appendingPathComponent(projectDirectoryName, isDirectory: true)
                .appendingPathComponent("\(session.sessionId).jsonl")

            guard
                let attributes = try? fileManager.attributesOfItem(atPath: projectFileURL.path),
                let modifiedAt = attributes[.modificationDate] as? Date,
                modifiedAt >= cutoff
            else {
                return
            }

            count += 1
        }
    }

    private func projectDirectoryName(for cwd: String) -> String {
        cwd.replacingOccurrences(of: "/", with: "-")
    }
}

private struct ClaudeSessionRecord: Decodable {
    let pid: Int32
    let sessionId: String
    let cwd: String
}

private struct ClaudeTodoRecord: Decodable {}
