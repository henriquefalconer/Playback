// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI

struct DiagnosticsView: View {
    @StateObject private var controller = DiagnosticsController()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            LogsTab(controller: controller)
                .tabItem {
                    Label("Logs", systemImage: "doc.text")
                }
                .tag(0)

            HealthTab(controller: controller)
                .tabItem {
                    Label("Health", systemImage: "heart.text.square")
                }
                .tag(1)

            ReportsTab(controller: controller)
                .tabItem {
                    Label("Reports", systemImage: "chart.bar.doc.horizontal")
                }
                .tag(2)
        }
        .frame(width: 900, height: 600)
    }
}

struct LogsTab: View {
    @ObservedObject var controller: DiagnosticsController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Component", selection: $controller.selectedComponent) {
                    ForEach(controller.availableComponents, id: \.self) { component in
                        Text(component.capitalized).tag(component)
                    }
                }
                .frame(width: 150)

                Picker("Level", selection: $controller.selectedLevel) {
                    Text("All Levels").tag(nil as LogEntry.LogLevel?)
                    ForEach(LogEntry.LogLevel.allCases, id: \.self) { level in
                        HStack {
                            Image(systemName: level.icon)
                            Text(level.rawValue)
                        }
                        .tag(level as LogEntry.LogLevel?)
                    }
                }
                .frame(width: 150)

                TextField("Search logs...", text: $controller.searchText)
                    .textFieldStyle(.roundedBorder)

                Spacer()

                Button(action: controller.refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }

                Button(action: {
                    showClearConfirmation()
                }) {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(controller.selectedComponent == "all")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if controller.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading logs...")
                    Spacer()
                }
            } else if controller.filteredEntries.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No log entries found")
                        .font(.headline)
                        .padding(.top, 8)
                    if !controller.searchText.isEmpty {
                        Text("Try adjusting your search or filters")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            } else {
                LogEntriesListView(entries: controller.filteredEntries)
            }
        }
    }

    private func showClearConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Clear logs for \(controller.selectedComponent)?"
        alert.informativeText = "This will permanently delete all log entries for this component."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear Logs")

        if alert.runModal() == .alertSecondButtonReturn {
            controller.clearLogs(for: controller.selectedComponent)
        }
    }
}

struct LogEntriesListView: View {
    let entries: [LogEntry]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    LogEntryRowView(entry: entry)
                }
            }
            .padding()
        }
    }
}

struct LogEntryRowView: View {
    let entry: LogEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: entry.level.icon)
                    .foregroundColor(colorForLevel(entry.level))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.component)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)

                        Text(formatTimestamp(entry.timestamp))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        if entry.exception != nil || entry.metadata != nil {
                            Button(action: { isExpanded.toggle() }) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text(entry.message)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    if isExpanded {
                        if let metadata = entry.metadata, !metadata.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Metadata:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                ForEach(Array(metadata.keys.sorted()), id: \.self) { key in
                                    HStack {
                                        Text(key + ":")
                                            .font(.caption.monospaced())
                                            .foregroundColor(.secondary)
                                        Text(metadata[key] ?? "")
                                            .font(.caption.monospaced())
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }

                        if let exception = entry.exception {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Exception:")
                                    .font(.caption)
                                    .foregroundColor(.red)

                                Text(exception)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.red)
                                    .padding(8)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func colorForLevel(_ level: LogEntry.LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .yellow
        case .error: return .orange
        case .critical: return .red
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct HealthTab: View {
    @ObservedObject var controller: DiagnosticsController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HealthStatusCard(status: controller.healthStatus, errorCount: controller.errorCount, warningCount: controller.warningCount)

                ServiceStatusSection()

                LogStatisticsSection(controller: controller)
            }
            .padding()
        }
    }
}

struct HealthStatusCard: View {
    let status: DiagnosticsController.HealthStatus
    let errorCount: Int
    let warningCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: status.icon)
                    .font(.system(size: 36))
                    .foregroundColor(colorForStatus(status))

                VStack(alignment: .leading, spacing: 4) {
                    Text("System Health")
                        .font(.headline)

                    Text(status.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()

            HStack(spacing: 30) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Errors")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("\(errorCount)")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Warnings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("\(warningCount)")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func colorForStatus(_ status: DiagnosticsController.HealthStatus) -> Color {
        switch status {
        case .healthy: return .green
        case .degraded: return .yellow
        case .unhealthy: return .red
        case .unknown: return .gray
        }
    }
}

struct ServiceStatusSection: View {
    @State private var recordingStatus: LaunchAgentManager.AgentStatus?
    @State private var processingStatus: LaunchAgentManager.AgentStatus?
    @State private var cleanupStatus: LaunchAgentManager.AgentStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service Status")
                .font(.headline)

            VStack(spacing: 8) {
                if let status = recordingStatus {
                    ServiceStatusRow(name: "Recording Service", status: status)
                }
                if let status = processingStatus {
                    ServiceStatusRow(name: "Processing Service", status: status)
                }
                if let status = cleanupStatus {
                    ServiceStatusRow(name: "Cleanup Service", status: status)
                }
            }
        }
        .onAppear {
            loadServiceStatus()
        }
    }

    private func loadServiceStatus() {
        let manager = LaunchAgentManager.shared
        recordingStatus = manager.getAgentStatus(.recording)
        processingStatus = manager.getAgentStatus(.processing)
        cleanupStatus = manager.getAgentStatus(.cleanup)
    }
}

struct ServiceStatusRow: View {
    let name: String
    let status: LaunchAgentManager.AgentStatus

    var body: some View {
        HStack {
            Circle()
                .fill(status.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            Text(name)
                .font(.body)

            Spacer()

            if status.isRunning {
                Text("Running")
                    .font(.caption)
                    .foregroundColor(.green)
                if let pid = status.pid {
                    Text("PID: \(pid)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Stopped")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct LogStatisticsSection: View {
    @ObservedObject var controller: DiagnosticsController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log Statistics")
                .font(.headline)

            let stats = calculateStatistics()

            VStack(spacing: 8) {
                ForEach(Array(stats.keys.sorted()), id: \.self) { component in
                    if let count = stats[component] {
                        HStack {
                            Text(component.capitalized)
                                .font(.body)
                            Spacer()
                            Text("\(count) entries")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    private func calculateStatistics() -> [String: Int] {
        var stats: [String: Int] = [:]

        for entry in controller.logEntries {
            stats[entry.component, default: 0] += 1
        }

        return stats
    }
}

struct ReportsTab: View {
    @ObservedObject var controller: DiagnosticsController
    @State private var showExportSuccess = false
    @State private var exportedURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Diagnostic Reports")
                    .font(.headline)

                Text("Export a comprehensive diagnostic report containing system health, service status, and recent log entries.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button(action: exportReport) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export Diagnostic Report")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                if showExportSuccess, let url = exportedURL {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Report exported successfully")
                        Spacer()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            Spacer()
        }
        .padding()
    }

    private func exportReport() {
        if let url = controller.exportDiagnosticReport() {
            exportedURL = url
            showExportSuccess = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                showExportSuccess = false
            }
        }
    }
}
