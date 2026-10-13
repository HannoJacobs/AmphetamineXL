import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            statusSection
            Divider()
            modePickerRow
            if appState.showsAutoAwakeMonitor {
                Divider()
                activityWindowSection
                Divider()
                monitorSection
            }
            Divider()
            launchAtLoginRow
            Divider()
            diagnosticsRow
            Divider()
            quitRow
        }
        .frame(width: 340)
        .onAppear {
            appState.menuDidAppear()
        }
        .onDisappear {
            appState.menuDidDisappear()
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(spacing: 6) {
            Image(systemName: appState.statusHeroIcon)
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(appState.isActive ? .yellow : Color.secondary)
                .padding(.top, 18)

            Text(appState.statusTitleText)
                .font(.headline)

            Text(appState.durationText)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(appState.monitoringStatusText)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
        }
    }

    private var modePickerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wake Mode")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker(
                "Wake Mode",
                selection: Binding(
                    get: { appState.wakeMode },
                    set: { appState.setWakeMode($0) }
                )
            ) {
                ForEach(WakeMode.allCases, id: \.rawValue) { mode in
                    Text(mode.controlLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(appState.wakeModeDescriptionText)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var activityWindowSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appState.activityWindowLabelText)
                .font(.caption)
                .foregroundColor(.secondary)

            Slider(
                value: Binding(
                    get: { appState.activityWindowSeconds },
                    set: { appState.setActivityWindowSeconds($0) }
                ),
                in: ActivityWindowSettings.minimumSeconds...ActivityWindowSettings.maximumSeconds,
                step: ActivityWindowSettings.stepSeconds
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var monitorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Auto-awake Monitor")
                .font(.caption)
                .foregroundColor(.secondary)

            monitorRow(
                title: "Codex",
                isEnabled: Binding(
                    get: { appState.isCodexMonitoringEnabled },
                    set: { appState.setCodexMonitoringEnabled($0) }
                ),
                state: appState.codexRuntimeLabel
            )
            monitorRow(
                title: "Claude Code",
                isEnabled: Binding(
                    get: { appState.isClaudeMonitoringEnabled },
                    set: { appState.setClaudeMonitoringEnabled($0) }
                ),
                state: appState.claudeRuntimeLabel
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func monitorRow(title: String, isEnabled: Binding<Bool>, state: String) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: isEnabled) {
                Text(title)
                    .foregroundColor(.primary)
            }
            .toggleStyle(.checkbox)

            Spacer()

            Circle()
                .fill(statusColor(for: state))
                .frame(width: 8, height: 8)

            Text(state)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func statusColor(for state: String) -> Color {
        switch state {
        case "Tasking", "Tasking + Queued":
            return .green
        case "Queued":
            return .orange
        default:
            return .secondary.opacity(0.5)
        }
    }

    // MARK: - Launch at Login Row

    private var launchAtLoginRow: some View {
        LaunchAtLoginRow()
    }

    // MARK: - Quit Row

    private var quitRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "power")
                .frame(width: 18)
                .foregroundColor(.primary)
            Text("Quit AmphetamineXL")
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.prepareForQuit()
            NSApplication.shared.terminate(nil)
        }
    }

    private var diagnosticsRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .frame(width: 18)
                .foregroundColor(.primary)
            Text("Open Diagnostics Logs")
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.openDiagnosticsLogs()
        }
    }
}

// MARK: - LaunchAtLoginRow

struct LaunchAtLoginRow: View {
    @State private var isEnabled = LaunchAtLogin.isEnabled

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.right.circle")
                .frame(width: 18)
                .foregroundColor(.primary)
            Text("Launch at Login")
                .foregroundColor(.primary)
            Spacer()
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .onChange(of: isEnabled) { _, newValue in
                    LaunchAtLogin.isEnabled = newValue
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
