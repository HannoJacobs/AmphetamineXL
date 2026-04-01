import SwiftUI
import LaunchAtLogin

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            statusSection
            Divider()
            toggleRow
            Divider()
            launchAtLoginRow
            Divider()
            diagnosticsRow
            Divider()
            quitRow
        }
        .frame(width: 280)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(spacing: 6) {
            Image(systemName: appState.isActive ? "bolt.fill" : "bolt.slash")
                .font(.system(size: 38, weight: .medium))
                .foregroundColor(appState.isActive ? .yellow : Color.secondary)
                .padding(.top, 18)

            Text(appState.isActive ? "Caffeinated 💊" : "Sleeping 😴")
                .font(.headline)

            Text(appState.durationText)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 14)
        }
    }

    // MARK: - Toggle Row

    // Uses onTapGesture instead of Button to avoid MenuBarExtra window dismiss on click.
    private var toggleRow: some View {
        HStack(spacing: 10) {
            Image(systemName: appState.isActive ? "bolt.slash" : "bolt.fill")
                .frame(width: 18)
                .foregroundColor(.primary)
            Text(appState.isActive ? "Disable Caffeine" : "Enable Caffeine")
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.toggle()
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
