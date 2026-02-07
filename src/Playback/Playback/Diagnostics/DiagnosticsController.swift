// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import Combine

@MainActor
final class DiagnosticsController: ObservableObject {
    @Published var logEntries: [LogEntry] = []
    @Published var filteredEntries: [LogEntry] = []
    @Published var selectedComponent: String = "all"
    @Published var selectedLevel: LogEntry.LogLevel? = nil
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorCount: Int = 0
    @Published var warningCount: Int = 0
    @Published var healthStatus: HealthStatus = .unknown

    enum HealthStatus {
        case healthy
        case degraded
        case unhealthy
        case unknown

        var color: String {
            switch self {
            case .healthy: return "green"
            case .degraded: return "yellow"
            case .unhealthy: return "red"
            case .unknown: return "gray"
            }
        }

        var icon: String {
            switch self {
            case .healthy: return "checkmark.circle.fill"
            case .degraded: return "exclamationmark.triangle.fill"
            case .unhealthy: return "xmark.circle.fill"
            case .unknown: return "questionmark.circle.fill"
            }
        }

        var description: String {
            switch self {
            case .healthy: return "All services running normally"
            case .degraded: return "Some warnings detected"
            case .unhealthy: return "Errors detected - attention required"
            case .unknown: return "Status unknown"
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    let availableComponents = ["all", "recording", "processing", "cleanup", "export"]

    init() {
        setupBindings()
        loadLogs()
        startAutoRefresh()
    }

    private func setupBindings() {
        Publishers.CombineLatest3($logEntries, $selectedComponent, $selectedLevel)
            .sink { [weak self] entries, component, level in
                self?.applyFilters(entries: entries, component: component, level: level)
            }
            .store(in: &cancellables)

        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.applyFilters(entries: self.logEntries, component: self.selectedComponent, level: self.selectedLevel)
            }
            .store(in: &cancellables)

        $logEntries
            .sink { [weak self] entries in
                self?.updateHealthStatus(from: entries)
            }
            .store(in: &cancellables)
    }

    func loadLogs() {
        isLoading = true

        Task {
            do {
                let entries = try await loadLogEntriesFromDisk()
                await MainActor.run {
                    self.logEntries = entries.sorted { $0.timestamp > $1.timestamp }
                    self.isLoading = false
                }
            } catch {
                print("[Diagnostics] Failed to load logs: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    private func loadLogEntriesFromDisk() async throws -> [LogEntry] {
        let logDir = Environment.isDevelopment
            ? URL(fileURLWithPath: "\(Paths.projectRoot())/dev_logs")
            : URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Logs/Playback")

        guard FileManager.default.fileExists(atPath: logDir.path) else {
            return []
        }

        let logFiles = try FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "log" || $0.lastPathComponent.contains(".log") }

        var allEntries: [LogEntry] = []

        for logFile in logFiles {
            let entries = try await parseLogFile(logFile)
            allEntries.append(contentsOf: entries)
        }

        return allEntries
    }

    private func parseLogFile(_ url: URL) async throws -> [LogEntry] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let lines = contents.split(separator: "\n")

        var entries: [LogEntry] = []

        for line in lines {
            guard !line.isEmpty else { continue }

            do {
                let data = Data(line.utf8)
                let decoder = JSONDecoder()
                let entry = try decoder.decode(LogEntry.self, from: data)
                entries.append(entry)
            } catch {
                continue
            }
        }

        return entries
    }

    private func applyFilters(entries: [LogEntry], component: String, level: LogEntry.LogLevel?) {
        var filtered = entries

        if component != "all" {
            filtered = filtered.filter { $0.component == component }
        }

        if let level = level {
            filtered = filtered.filter { $0.level == level }
        }

        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            filtered = filtered.filter {
                $0.message.lowercased().contains(searchLower) ||
                $0.component.lowercased().contains(searchLower) ||
                ($0.metadata?.values.joined(separator: " ").lowercased().contains(searchLower) ?? false)
            }
        }

        filteredEntries = filtered
    }

    private func updateHealthStatus(from entries: [LogEntry]) {
        let recentEntries = entries.prefix(1000)

        let errorCount = recentEntries.filter { $0.level == .error || $0.level == .critical }.count
        let warningCount = recentEntries.filter { $0.level == .warning }.count

        self.errorCount = errorCount
        self.warningCount = warningCount

        if errorCount > 10 {
            healthStatus = .unhealthy
        } else if errorCount > 0 || warningCount > 20 {
            healthStatus = .degraded
        } else if !entries.isEmpty {
            healthStatus = .healthy
        } else {
            healthStatus = .unknown
        }
    }

    func clearLogs(for component: String) {
        Task {
            do {
                let logDir = Environment.isDevelopment
                    ? URL(fileURLWithPath: "\(Paths.projectRoot())/dev_logs")
                    : URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Logs/Playback")

                let logFile = logDir.appendingPathComponent("\(component).log")

                if FileManager.default.fileExists(atPath: logFile.path) {
                    try FileManager.default.removeItem(at: logFile)
                }

                await MainActor.run {
                    loadLogs()
                }
            } catch {
                print("[Diagnostics] Failed to clear logs: \(error)")
            }
        }
    }

    func exportDiagnosticReport() -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let fileName = "playback_diagnostics_\(timestamp).txt"
        let tempDir = FileManager.default.temporaryDirectory
        let reportURL = tempDir.appendingPathComponent(fileName)

        var report = """
        Playback Diagnostics Report
        Generated: \(Date())

        === Health Status ===
        Status: \(healthStatus.description)
        Errors: \(errorCount)
        Warnings: \(warningCount)
        Total Log Entries: \(logEntries.count)

        === Service Status ===
        """

        let launchAgentManager = LaunchAgentManager.shared
        for agentType in [LaunchAgentManager.AgentType.recording, .processing, .cleanup] {
            let status = launchAgentManager.getAgentStatus(agentType)
            report += """

            \(agentType):
              Loaded: \(status.isLoaded)
              Running: \(status.isRunning)
              PID: \(status.pid?.description ?? "N/A")
              Last Exit Status: \(status.lastExitStatus?.description ?? "N/A")
            """
        }

        report += "\n\n=== Recent Log Entries (last 100) ===\n\n"

        for entry in logEntries.prefix(100) {
            report += """
            [\(entry.timestamp)] [\(entry.level.rawValue)] [\(entry.component)]
            \(entry.message)

            """
        }

        do {
            try report.write(to: reportURL, atomically: true, encoding: .utf8)
            return reportURL
        } catch {
            print("[Diagnostics] Failed to write report: \(error)")
            return nil
        }
    }

    func refresh() {
        loadLogs()
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadLogs()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }
}
