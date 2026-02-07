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

            PerformanceTab(controller: controller)
                .tabItem {
                    Label("Performance", systemImage: "speedometer")
                }
                .tag(2)

            ReportsTab(controller: controller)
                .tabItem {
                    Label("Reports", systemImage: "chart.bar.doc.horizontal")
                }
                .tag(3)
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

struct PerformanceTab: View {
    @ObservedObject var controller: DiagnosticsController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PerformanceOverviewCard(controller: controller)

                ServiceMetricsSection(controller: controller)

                ResourceUsageChartsSection(controller: controller)
            }
            .padding()
        }
    }
}

struct PerformanceOverviewCard: View {
    @ObservedObject var controller: DiagnosticsController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "speedometer")
                    .font(.system(size: 36))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Performance Metrics")
                        .font(.headline)

                    Text("Resource usage and performance statistics from service logs")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()

            let metrics = calculateAverageMetrics()

            HStack(spacing: 30) {
                MetricColumn(title: "Avg CPU", value: String(format: "%.1f%%", metrics.avgCpu), icon: "cpu")
                MetricColumn(title: "Avg Memory", value: String(format: "%.0f MB", metrics.avgMemory), icon: "memorychip")
                MetricColumn(title: "Disk Free", value: String(format: "%.1f GB", metrics.avgDiskFree), icon: "externaldrive")
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func calculateAverageMetrics() -> (avgCpu: Double, avgMemory: Double, avgDiskFree: Double) {
        let metricsEntries = controller.logEntries.filter { entry in
            entry.message.contains("Resource metrics") || entry.message.contains("metrics")
        }.prefix(50)

        var cpuSum = 0.0
        var memorySum = 0.0
        var diskFreeSum = 0.0
        var count = 0

        for entry in metricsEntries {
            guard let metadata = entry.metadata else { continue }

            if let cpuStr = metadata["cpu_percent"], let cpu = Double(cpuStr) {
                cpuSum += cpu
                count += 1
            }
            if let memStr = metadata["memory_mb"], let mem = Double(memStr) {
                memorySum += mem
            }
            if let diskStr = metadata["disk_free_gb"], let disk = Double(diskStr) {
                diskFreeSum += disk
            }
        }

        let avgCount = max(count, 1)
        return (cpuSum / Double(avgCount), memorySum / Double(avgCount), diskFreeSum / Double(avgCount))
    }
}

struct MetricColumn: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
            }
        }
    }
}

struct ServiceMetricsSection: View {
    @ObservedObject var controller: DiagnosticsController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Service Metrics")
                .font(.headline)

            let serviceStats = calculateServiceMetrics()

            VStack(spacing: 8) {
                ForEach(Array(serviceStats.keys.sorted()), id: \.self) { service in
                    if let stats = serviceStats[service] {
                        ServiceMetricRow(service: service, stats: stats)
                    }
                }
            }
        }
    }

    private func calculateServiceMetrics() -> [String: ServiceStats] {
        var stats: [String: ServiceStats] = [:]

        for component in ["recording", "processing", "cleanup", "export"] {
            let componentEntries = controller.logEntries.filter { $0.component == component }

            let errorCount = componentEntries.filter { $0.level == .error || $0.level == .critical }.count
            let warningCount = componentEntries.filter { $0.level == .warning }.count

            var cpuValues: [Double] = []
            var memoryValues: [Double] = []

            for entry in componentEntries.prefix(100) {
                if let metadata = entry.metadata {
                    if let cpuStr = metadata["cpu_percent"], let cpu = Double(cpuStr) {
                        cpuValues.append(cpu)
                    }
                    if let memStr = metadata["memory_mb"], let mem = Double(memStr) {
                        memoryValues.append(mem)
                    }
                }
            }

            stats[component] = ServiceStats(
                errorCount: errorCount,
                warningCount: warningCount,
                avgCpu: cpuValues.isEmpty ? 0 : cpuValues.reduce(0, +) / Double(cpuValues.count),
                avgMemory: memoryValues.isEmpty ? 0 : memoryValues.reduce(0, +) / Double(memoryValues.count),
                totalLogs: componentEntries.count
            )
        }

        return stats
    }
}

struct ServiceStats {
    let errorCount: Int
    let warningCount: Int
    let avgCpu: Double
    let avgMemory: Double
    let totalLogs: Int
}

struct ServiceMetricRow: View {
    let service: String
    let stats: ServiceStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(service.capitalized)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if stats.errorCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text("\(stats.errorCount)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                if stats.warningCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text("\(stats.warningCount)")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
            }

            HStack(spacing: 20) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f%%", stats.avgCpu))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "memorychip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0f MB", stats.avgMemory))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(stats.totalLogs) logs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ResourceUsageChartsSection: View {
    @ObservedObject var controller: DiagnosticsController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Resource Usage")
                .font(.headline)

            Text("CPU and memory usage from the last 50 metric entries")
                .font(.caption)
                .foregroundColor(.secondary)

            let metrics = extractRecentMetrics()

            if metrics.isEmpty {
                VStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No performance metrics available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Metrics are collected automatically by background services")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    SimpleBarChart(title: "CPU Usage (%)", values: metrics.map { $0.cpu }, maxValue: 100, color: .blue)
                    SimpleBarChart(title: "Memory Usage (MB)", values: metrics.map { $0.memory }, maxValue: nil, color: .green)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    private func extractRecentMetrics() -> [(timestamp: Date, cpu: Double, memory: Double)] {
        let metricsEntries = controller.logEntries
            .filter { entry in
                entry.message.contains("Resource metrics") || entry.message.contains("metrics")
            }
            .prefix(50)

        var metrics: [(Date, Double, Double)] = []

        for entry in metricsEntries {
            guard let metadata = entry.metadata else { continue }

            if let cpuStr = metadata["cpu_percent"], let cpu = Double(cpuStr),
               let memStr = metadata["memory_mb"], let mem = Double(memStr) {
                metrics.append((entry.timestamp, cpu, mem))
            }
        }

        return metrics.reversed()
    }
}

struct SimpleBarChart: View {
    let title: String
    let values: [Double]
    let maxValue: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            if values.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                let max = maxValue ?? values.max() ?? 1.0
                let avg = values.reduce(0, +) / Double(values.count)
                let minVal = values.min() ?? 0

                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        Rectangle()
                            .fill(color)
                            .frame(width: 8, height: max(2, CGFloat(value / max) * 60))
                    }
                }
                .frame(height: 70)

                HStack {
                    Text("Min: \(String(format: "%.1f", minVal))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Avg: \(String(format: "%.1f", avg))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Max: \(String(format: "%.1f", max))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
