# Logging & Diagnostics Implementation Plan

**Component:** Logging and Diagnostics System
**Last Updated:** 2026-02-07

## Implementation Checklist

### Python Logging Infrastructure

- [ ] Implement structured JSON logging format
  - Source: `src/scripts/logging.py` (new module)
  - Format: `{"timestamp": "ISO8601", "level": "INFO", "component": "recording", "message": "...", "metadata": {...}}`
  - Example:
    ```json
    {"timestamp": "2026-02-07T14:32:15.234Z", "level": "INFO", "component": "recording", "message": "Screenshot captured", "metadata": {"path": "/tmp/screenshots/1234567890.png", "size_kb": 245}}
    ```

- [ ] Create JSONFormatter class
  - Source: `src/scripts/logging.py`
  - Output: Newline-delimited JSON (one entry per line)
  - Timestamp: ISO 8601 with milliseconds
  - Example implementation:
    ```python
    import json
    import logging
    from datetime import datetime

    class JSONFormatter(logging.Formatter):
        def format(self, record):
            log_entry = {
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "level": record.levelname,
                "component": record.name,
                "message": record.getMessage(),
                "metadata": getattr(record, "metadata", {})
            }
            return json.dumps(log_entry)
    ```

- [ ] Set up log levels
  - Levels: DEBUG, INFO, WARNING, ERROR, CRITICAL
  - INFO: Normal operations (screenshot captured, service started)
    - Example: `"Screenshot captured"`, `"Recording service started"`
  - WARNING: Recoverable issues (fallback used, screenshot skipped)
    - Example: `"Screenshot skipped due to timeout"`, `"Using fallback screen capture method"`
  - ERROR: Non-critical failures (single screenshot failed)
    - Example: `"Failed to capture screenshot"`, `"Database write failed, retrying"`
  - CRITICAL: Service-stopping issues (permission denied, disk full)
    - Example: `"Screen recording permission denied"`, `"Disk space critically low, stopping recording"`

- [ ] Configure logging for recording service
  - Source: `src/scripts/record_screen.py`
  - Log file: `~/Library/Logs/Playback/recording.log`
  - Events: Service lifecycle, screenshot capture, skipped frames, failures
  - Example setup:
    ```python
    import logging
    from logging.handlers import RotatingFileHandler

    logger = logging.getLogger("recording")
    handler = RotatingFileHandler(
        "~/Library/Logs/Playback/recording.log",
        maxBytes=10*1024*1024,  # 10MB
        backupCount=5
    )
    handler.setFormatter(JSONFormatter())
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)

    # Usage
    logger.info("Screenshot captured", extra={"metadata": {"path": filepath, "size_kb": size}})
    ```

- [ ] Configure logging for processing service
  - Source: `src/scripts/build_chunks_from_temp.py`
  - Log file: `~/Library/Logs/Playback/processing.log`
  - Events: Processing runs, day processing, segment generation, cleanup
  - Example log entries:
    ```json
    {"timestamp": "2026-02-07T15:00:00.000Z", "level": "INFO", "component": "processing", "message": "Processing started", "metadata": {"days_pending": 3}}
    {"timestamp": "2026-02-07T15:00:45.123Z", "level": "INFO", "component": "processing", "message": "Day processing completed", "metadata": {"date": "2026-02-06", "duration_s": 45.1, "segments_created": 142, "cpu_avg_pct": 35.2, "memory_peak_mb": 512}}
    ```

### Log Rotation

- [ ] Implement size-based rotation
  - Handler: `logging.handlers.RotatingFileHandler`
  - Max size: 10 MB per file
  - Backup count: 5 (50 MB total per component)
  - Naming: `.log`, `.log.1`, `.log.2`, etc.
  - Example:
    ```python
    from logging.handlers import RotatingFileHandler

    handler = RotatingFileHandler(
        filename="recording.log",
        maxBytes=10 * 1024 * 1024,  # 10 MB
        backupCount=5
    )
    ```

- [ ] Set up rotation for all log files
  - `recording.log` (10MB × 5 = 50MB max)
  - `processing.log` (10MB × 5 = 50MB max)
  - `menubar.log` (10MB × 5 = 50MB max)
  - `playback.log` (10MB × 5 = 50MB max)

- [ ] Handle LaunchAgent stdout/stderr logs
  - Files: `recording.stdout.log`, `recording.stderr.log`, etc.
  - Location: `~/Library/Logs/Playback/`
  - Configured in: LaunchAgent plist files
  - Example plist entry:
    ```xml
    <key>StandardOutPath</key>
    <string>/Users/username/Library/Logs/Playback/recording.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/username/Library/Logs/Playback/recording.stderr.log</string>
    ```

### Resource Metrics Collection

- [ ] Implement resource monitoring for recording service
  - Library: `psutil`
  - Metrics: CPU %, memory MB, disk space GB, uptime hours
  - Frequency: Every 100 captures (~200 seconds)
  - Log entry type: "Resource metrics"
  - Example implementation:
    ```python
    import psutil
    import time

    start_time = time.time()
    capture_count = 0

    def log_resource_metrics():
        process = psutil.Process()
        uptime_hours = (time.time() - start_time) / 3600

        logger.info("Resource metrics", extra={"metadata": {
            "cpu_percent": process.cpu_percent(interval=1.0),
            "memory_mb": process.memory_info().rss / (1024 * 1024),
            "disk_free_gb": psutil.disk_usage('/').free / (1024**3),
            "uptime_hours": round(uptime_hours, 2),
            "captures_total": capture_count
        }})

    # Log every 100 captures
    if capture_count % 100 == 0:
        log_resource_metrics()
    ```

- [ ] Implement resource monitoring for processing service
  - Library: `psutil`
  - Metrics: Duration, CPU avg, memory peak, disk read/write MB
  - Frequency: Per day processed
  - Log entry type: Part of "Day processing completed"
  - Example:
    ```python
    import psutil
    import time

    def process_day(date):
        start_time = time.time()
        process = psutil.Process()
        start_io = process.io_counters()
        cpu_samples = []
        memory_peak = 0

        # During processing, periodically sample
        while processing:
            cpu_samples.append(process.cpu_percent(interval=1.0))
            memory_peak = max(memory_peak, process.memory_info().rss / (1024*1024))

        end_io = process.io_counters()
        duration = time.time() - start_time

        logger.info("Day processing completed", extra={"metadata": {
            "date": date,
            "duration_s": round(duration, 1),
            "segments_created": segment_count,
            "cpu_avg_pct": sum(cpu_samples) / len(cpu_samples),
            "memory_peak_mb": round(memory_peak),
            "disk_read_mb": (end_io.read_bytes - start_io.read_bytes) / (1024*1024),
            "disk_write_mb": (end_io.write_bytes - start_io.write_bytes) / (1024*1024)
        }})
    ```

- [ ] Add psutil dependency
  - Add to requirements.txt: `psutil>=5.9.0`
  - Install command: `pip3 install psutil`

### Swift Diagnostics Window

- [ ] Create DiagnosticsWindow.swift
  - Location: `src/Playback/Playback/Diagnostics/DiagnosticsWindow.swift`
  - SwiftUI view with tabs: Logs, Health, Export
  - Example structure:
    ```swift
    import SwiftUI

    struct DiagnosticsWindow: View {
        @State private var selectedTab = 0

        var body: some View {
            TabView(selection: $selectedTab) {
                LogViewer()
                    .tabItem {
                        Label("Logs", systemImage: "doc.text")
                    }
                    .tag(0)

                HealthView()
                    .tabItem {
                        Label("Health", systemImage: "heart.fill")
                    }
                    .tag(1)

                ExportView()
                    .tabItem {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .tag(2)
            }
            .frame(width: 900, height: 600)
        }
    }
    ```

- [ ] Implement log parsing
  - Source: `src/Playback/Playback/Diagnostics/LogParser.swift`
  - Parse JSON logs into `LogEntry` structs
  - Handle malformed entries gracefully
  - Example implementation:
    ```swift
    import Foundation

    struct LogParser {
        static func parseLogs(fromFile path: String) -> [LogEntry] {
            guard let content = try? String(contentsOfFile: path) else {
                return []
            }

            var entries: [LogEntry] = []
            var skippedCount = 0

            for line in content.components(separatedBy: "\n") {
                guard !line.isEmpty else { continue }

                if let data = line.data(using: .utf8),
                   let json = try? JSONDecoder().decode(LogEntry.self, from: data) {
                    entries.append(json)
                } else {
                    skippedCount += 1
                }
            }

            if skippedCount > 0 {
                print("Warning: Skipped \(skippedCount) malformed log entries")
            }

            return entries
        }
    }
    ```

- [ ] Create LogEntry model
  - Fields: id (UUID), timestamp (Date), level (enum), component, message, metadata
  - Enum: LogLevel (info, warning, error, critical)
  - Identifiable protocol for SwiftUI lists
  - Example:
    ```swift
    import Foundation

    enum LogLevel: String, Codable {
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case critical = "CRITICAL"
        case debug = "DEBUG"

        var color: Color {
            switch self {
            case .info: return .primary
            case .warning: return .orange
            case .error: return .red
            case .critical: return .purple
            case .debug: return .secondary
            }
        }
    }

    struct LogEntry: Identifiable, Codable {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let component: String
        let message: String
        let metadata: [String: AnyCodable]?

        private enum CodingKeys: String, CodingKey {
            case timestamp, level, component, message, metadata
        }
    }
    ```

- [ ] Implement log filtering
  - By level: All, INFO only, WARNING+, ERROR+, CRITICAL only
  - By time range: Last Hour, Last 24 Hours, Last Week, All Time
  - By search: Full-text across message and metadata (case-insensitive)
  - Example:
    ```swift
    struct LogFilter {
        var minimumLevel: LogLevel?
        var timeRange: TimeRange?
        var searchText: String = ""

        enum TimeRange {
            case lastHour
            case last24Hours
            case lastWeek
            case allTime

            var cutoffDate: Date? {
                switch self {
                case .lastHour: return Date().addingTimeInterval(-3600)
                case .last24Hours: return Date().addingTimeInterval(-86400)
                case .lastWeek: return Date().addingTimeInterval(-604800)
                case .allTime: return nil
                }
            }
        }

        func matches(entry: LogEntry) -> Bool {
            // Filter by level
            if let minLevel = minimumLevel {
                let levelOrder: [LogLevel] = [.debug, .info, .warning, .error, .critical]
                guard let entryIndex = levelOrder.firstIndex(of: entry.level),
                      let minIndex = levelOrder.firstIndex(of: minLevel),
                      entryIndex >= minIndex else {
                    return false
                }
            }

            // Filter by time
            if let cutoff = timeRange?.cutoffDate, entry.timestamp < cutoff {
                return false
            }

            // Filter by search text
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                let messageMatch = entry.message.lowercased().contains(searchLower)
                let componentMatch = entry.component.lowercased().contains(searchLower)
                let metadataMatch = entry.metadata?.values.contains { value in
                    "\(value)".lowercased().contains(searchLower)
                } ?? false

                return messageMatch || componentMatch || metadataMatch
            }

            return true
        }
    }
    ```

- [ ] Create log viewer UI
  - Source: `src/Playback/Playback/Diagnostics/LogViewer.swift`
  - List view with color-coded levels
  - Search bar with live filtering
  - Level and time range pickers
  - Detail view showing metadata
  - Example:
    ```swift
    struct LogViewer: View {
        @State private var logs: [LogEntry] = []
        @State private var filter = LogFilter()

        var filteredLogs: [LogEntry] {
            logs.filter { filter.matches(entry: $0) }
        }

        var body: some View {
            VStack(spacing: 0) {
                // Filter controls
                HStack {
                    TextField("Search...", text: $filter.searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Picker("Level", selection: $filter.minimumLevel) {
                        Text("All").tag(nil as LogLevel?)
                        Text("INFO+").tag(LogLevel.info as LogLevel?)
                        Text("WARNING+").tag(LogLevel.warning as LogLevel?)
                        Text("ERROR+").tag(LogLevel.error as LogLevel?)
                    }
                    .frame(width: 120)

                    Picker("Time", selection: $filter.timeRange) {
                        Text("All Time").tag(LogFilter.TimeRange.allTime as LogFilter.TimeRange?)
                        Text("Last Hour").tag(LogFilter.TimeRange.lastHour as LogFilter.TimeRange?)
                        Text("Last 24h").tag(LogFilter.TimeRange.last24Hours as LogFilter.TimeRange?)
                        Text("Last Week").tag(LogFilter.TimeRange.lastWeek as LogFilter.TimeRange?)
                    }
                    .frame(width: 120)
                }
                .padding()

                Divider()

                // Log list
                List(filteredLogs) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.timestamp, style: .time)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(entry.level.rawValue)
                                .font(.caption.bold())
                                .foregroundColor(entry.level.color)

                            Text(entry.component)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(entry.message)
                            .font(.body)

                        if let metadata = entry.metadata, !metadata.isEmpty {
                            Text(formatMetadata(metadata))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .onAppear {
                loadLogs()
            }
        }

        func loadLogs() {
            logs = LogParser.parseLogs(fromFile: "~/Library/Logs/Playback/recording.log")
        }

        func formatMetadata(_ metadata: [String: AnyCodable]) -> String {
            metadata.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        }
    }
    ```

### Health Monitoring

- [ ] Implement resource metrics extraction
  - Source: `src/Playback/Playback/Diagnostics/MetricsParser.swift`
  - Parse "Resource metrics" log entries
  - Build time series data for charts
  - Example:
    ```swift
    struct ResourceMetrics {
        let timestamp: Date
        let cpuPercent: Double
        let memoryMB: Double
        let diskFreeGB: Double
        let uptimeHours: Double
    }

    struct MetricsParser {
        static func extractResourceMetrics(from logs: [LogEntry]) -> [ResourceMetrics] {
            return logs
                .filter { $0.message == "Resource metrics" }
                .compactMap { entry in
                    guard let metadata = entry.metadata,
                          let cpu = metadata["cpu_percent"]?.doubleValue,
                          let memory = metadata["memory_mb"]?.doubleValue,
                          let disk = metadata["disk_free_gb"]?.doubleValue,
                          let uptime = metadata["uptime_hours"]?.doubleValue else {
                        return nil
                    }

                    return ResourceMetrics(
                        timestamp: entry.timestamp,
                        cpuPercent: cpu,
                        memoryMB: memory,
                        diskFreeGB: disk,
                        uptimeHours: uptime
                    )
                }
        }
    }
    ```

- [ ] Create resource charts
  - Source: `src/Playback/Playback/Diagnostics/ResourceChartsView.swift`
  - Framework: SwiftUI Charts
  - Charts: CPU %, memory MB, processing duration, screenshots/hour
  - Example:
    ```swift
    import SwiftUI
    import Charts

    struct ResourceChartsView: View {
        let metrics: [ResourceMetrics]

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    // CPU Usage Chart
                    VStack(alignment: .leading) {
                        Text("CPU Usage")
                            .font(.headline)

                        Chart(metrics) { metric in
                            LineMark(
                                x: .value("Time", metric.timestamp),
                                y: .value("CPU %", metric.cpuPercent)
                            )
                            .foregroundStyle(.blue)
                        }
                        .frame(height: 150)
                        .chartYScale(domain: 0...100)
                    }

                    // Memory Usage Chart
                    VStack(alignment: .leading) {
                        Text("Memory Usage")
                            .font(.headline)

                        Chart(metrics) { metric in
                            LineMark(
                                x: .value("Time", metric.timestamp),
                                y: .value("Memory MB", metric.memoryMB)
                            )
                            .foregroundStyle(.green)
                        }
                        .frame(height: 150)
                    }

                    // Disk Space Chart
                    VStack(alignment: .leading) {
                        Text("Free Disk Space")
                            .font(.headline)

                        Chart(metrics) { metric in
                            LineMark(
                                x: .value("Time", metric.timestamp),
                                y: .value("Disk GB", metric.diskFreeGB)
                            )
                            .foregroundStyle(.orange)
                        }
                        .frame(height: 150)
                    }
                }
                .padding()
            }
        }
    }
    ```

- [ ] Implement health checks
  - Check: Recent logs exist (service running)
  - Check: No CRITICAL errors in last hour
  - Check: Disk space > 1GB
  - Check: Recording rate > 0 (if enabled)
  - Status: Healthy, Warning, Critical
  - Example:
    ```swift
    enum HealthStatus {
        case healthy
        case warning
        case critical

        var color: Color {
            switch self {
            case .healthy: return .green
            case .warning: return .orange
            case .critical: return .red
            }
        }
    }

    struct HealthChecker {
        func checkHealth(logs: [LogEntry], metrics: [ResourceMetrics]) -> HealthStatus {
            // Check 1: Recent logs exist (within last 5 minutes)
            let recentLogs = logs.filter {
                $0.timestamp > Date().addingTimeInterval(-300)
            }
            guard !recentLogs.isEmpty else {
                return .critical // Service not running
            }

            // Check 2: No CRITICAL errors in last hour
            let recentCritical = logs.filter {
                $0.level == .critical &&
                $0.timestamp > Date().addingTimeInterval(-3600)
            }
            if !recentCritical.isEmpty {
                return .critical
            }

            // Check 3: Disk space > 1GB
            if let latestMetric = metrics.last {
                if latestMetric.diskFreeGB < 1.0 {
                    return .critical
                }
                if latestMetric.diskFreeGB < 5.0 {
                    return .warning // Low space warning
                }
            }

            // Check 4: Any ERROR logs in last hour
            let recentErrors = logs.filter {
                $0.level == .error &&
                $0.timestamp > Date().addingTimeInterval(-3600)
            }
            if !recentErrors.isEmpty {
                return .warning
            }

            return .healthy
        }
    }
    ```

- [ ] Create health dashboard
  - Source: `src/Playback/Playback/Diagnostics/HealthView.swift`
  - Display: Current status, last error, service uptimes
  - Actions: Restart services, clear errors, open logs folder
  - Example:
    ```swift
    struct HealthView: View {
        @State private var status: HealthStatus = .healthy
        @State private var logs: [LogEntry] = []
        @State private var metrics: [ResourceMetrics] = []

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    // Status indicator
                    HStack {
                        Circle()
                            .fill(status.color)
                            .frame(width: 20, height: 20)

                        Text("System Status: \(status)")
                            .font(.title2.bold())
                    }

                    Divider()

                    // Service uptimes
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Service Status")
                            .font(.headline)

                        ServiceUptimeRow(service: "Recording", uptime: getUptime(for: "recording"))
                        ServiceUptimeRow(service: "Processing", uptime: getUptime(for: "processing"))
                    }

                    Divider()

                    // Recent errors
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent Issues")
                            .font(.headline)

                        let errors = logs.filter { $0.level == .error || $0.level == .critical }
                            .prefix(5)

                        if errors.isEmpty {
                            Text("No recent errors")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(errors)) { error in
                                HStack {
                                    Text(error.timestamp, style: .time)
                                        .font(.caption)
                                    Text(error.message)
                                        .font(.body)
                                }
                            }
                        }
                    }

                    Divider()

                    // Resource charts
                    ResourceChartsView(metrics: metrics)

                    Divider()

                    // Actions
                    HStack(spacing: 20) {
                        Button("Restart Recording Service") {
                            restartService("recording")
                        }

                        Button("Restart Processing Service") {
                            restartService("processing")
                        }

                        Button("Open Logs Folder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: "~/Library/Logs/Playback"))
                        }
                    }
                }
                .padding()
            }
            .onAppear {
                loadHealthData()
            }
        }

        func loadHealthData() {
            logs = LogParser.parseLogs(fromFile: "~/Library/Logs/Playback/recording.log")
            metrics = MetricsParser.extractResourceMetrics(from: logs)
            status = HealthChecker().checkHealth(logs: logs, metrics: metrics)
        }
    }
    ```

### Export Functionality

- [ ] Implement log export
  - Source: `src/Playback/Playback/Diagnostics/LogExporter.swift`
  - Formats: JSON (original), Plain Text (human-readable), CSV (spreadsheet)
  - Date range selection
  - Save location picker (NSOpenPanel)
  - Example:
    ```swift
    enum ExportFormat {
        case json
        case plainText
        case csv
    }

    struct LogExporter {
        func export(logs: [LogEntry], format: ExportFormat, to url: URL) throws {
            let content: String

            switch format {
            case .json:
                // Keep original JSON format
                content = logs.map { entry in
                    """
                    {"timestamp": "\(entry.timestamp.iso8601)", "level": "\(entry.level.rawValue)", "component": "\(entry.component)", "message": "\(entry.message)", "metadata": \(formatMetadataJSON(entry.metadata))}
                    """
                }.joined(separator: "\n")

            case .plainText:
                // Human-readable format
                content = logs.map { entry in
                    "[\(entry.timestamp)] \(entry.level.rawValue) [\(entry.component)] \(entry.message)"
                }.joined(separator: "\n")

            case .csv:
                // Spreadsheet format
                var lines = ["Timestamp,Level,Component,Message,Metadata"]
                lines += logs.map { entry in
                    "\(entry.timestamp.iso8601),\(entry.level.rawValue),\(entry.component),\"\(escapeCsv(entry.message))\",\"\(formatMetadataCSV(entry.metadata))\""
                }
                content = lines.joined(separator: "\n")
            }

            try content.write(to: url, atomically: true, encoding: .utf8)
        }

        private func escapeCsv(_ text: String) -> String {
            text.replacingOccurrences(of: "\"", with: "\"\"")
        }

        private func formatMetadataJSON(_ metadata: [String: AnyCodable]?) -> String {
            guard let metadata = metadata,
                  let data = try? JSONEncoder().encode(metadata),
                  let json = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return json
        }

        private func formatMetadataCSV(_ metadata: [String: AnyCodable]?) -> String {
            guard let metadata = metadata else { return "" }
            return metadata.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
        }
    }
    ```

- [ ] Create diagnostics package export
  - Source: `src/Playback/Playback/Diagnostics/DiagnosticsExporter.swift`
  - Contents: All logs, config.json, database schema, system info
  - Format: ZIP file named `Playback-Diagnostics-<timestamp>.zip`
  - Optional: Password protection
  - Example:
    ```swift
    import Foundation
    import Compression

    struct DiagnosticsExporter {
        func exportDiagnosticsPackage(to destinationURL: URL) throws {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let zipName = "Playback-Diagnostics-\(timestamp).zip"
            let zipURL = destinationURL.appendingPathComponent(zipName)

            // Create temporary directory for package contents
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("diagnostics-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Copy all log files
            let logsDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/Playback")
            try? FileManager.default.copyItem(
                at: logsDir,
                to: tempDir.appendingPathComponent("logs")
            )

            // Copy config.json
            let configPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/playback/config.json")
            try? FileManager.default.copyItem(
                at: configPath,
                to: tempDir.appendingPathComponent("config.json")
            )

            // Export database schema
            let schemaPath = tempDir.appendingPathComponent("database-schema.txt")
            try exportDatabaseSchema(to: schemaPath)

            // Collect system info
            let sysInfoPath = tempDir.appendingPathComponent("system-info.txt")
            try collectSystemInfo(to: sysInfoPath)

            // Create ZIP archive
            try createZipArchive(from: tempDir, to: zipURL)

            // Cleanup temp directory
            try? FileManager.default.removeItem(at: tempDir)
        }

        private func collectSystemInfo(to url: URL) throws {
            let info = """
            Playback Diagnostics Package
            Generated: \(Date())

            System Information:
            - macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)
            - Hardware: \(getHardwareInfo())
            - App Version: \(getAppVersion())
            - Installation Date: \(getInstallationDate())

            Display Information:
            - Resolution: \(getDisplayResolution())
            - Scale Factor: \(getScaleFactor())

            Disk Space:
            - Total: \(getDiskSpace().total) GB
            - Available: \(getDiskSpace().available) GB
            """

            try info.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    ```

- [ ] Implement system info collection
  - macOS version
  - Hardware specs (CPU, RAM, display resolution)
  - App version and build number
  - Installation date
  - Example helper functions:
    ```swift
    func getHardwareInfo() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
        process.arguments = ["-n", "machdep.cpu.brand_string"]

        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
    }

    func getAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (build \(build))"
    }
    ```

### Menu Bar Integration

- [ ] Add diagnostics menu item
  - Location: `src/Playback/Playback/MenuBar/MenuBarView.swift`
  - Action: Open diagnostics window
  - Shortcut: Cmd+D
  - Example:
    ```swift
    Menu {
        Button("Open Diagnostics...") {
            openDiagnosticsWindow()
        }
        .keyboardShortcut("d", modifiers: .command)

        // ... other menu items
    }
    ```

- [ ] Implement menu bar logging
  - Source: Menu bar app code
  - Log file: `~/Library/Logs/Playback/menubar.log`
  - Events: App launched, recording toggled, settings changed, manual processing
  - Example log entries:
    ```json
    {"timestamp": "2026-02-07T09:00:00.000Z", "level": "INFO", "component": "menubar", "message": "App launched", "metadata": {"version": "1.0.0"}}
    {"timestamp": "2026-02-07T09:05:30.123Z", "level": "INFO", "component": "menubar", "message": "Recording toggled", "metadata": {"enabled": true, "user_initiated": true}}
    {"timestamp": "2026-02-07T09:10:15.456Z", "level": "INFO", "component": "menubar", "message": "Settings changed", "metadata": {"setting": "capture_interval", "old_value": 2, "new_value": 3}}
    {"timestamp": "2026-02-07T09:15:00.789Z", "level": "INFO", "component": "menubar", "message": "Manual processing triggered", "metadata": {"pending_days": 2}}
    ```

### Playback App Integration

- [ ] Implement playback app logging
  - Source: Timeline/playback code
  - Log file: `~/Library/Logs/Playback/playback.log`
  - Events: App launched/closed, segment loaded, video file missing
  - Example log entries:
    ```json
    {"timestamp": "2026-02-07T10:00:00.000Z", "level": "INFO", "component": "playback", "message": "App launched", "metadata": {"version": "1.0.0"}}
    {"timestamp": "2026-02-07T10:00:05.123Z", "level": "INFO", "component": "playback", "message": "Timeline loaded", "metadata": {"date_range_start": "2026-02-01", "date_range_end": "2026-02-07", "total_segments": 4567}}
    {"timestamp": "2026-02-07T10:00:10.456Z", "level": "INFO", "component": "playback", "message": "Segment loaded", "metadata": {"timestamp": "2026-02-07T09:30:00Z", "duration_s": 300, "file_size_mb": 45}}
    {"timestamp": "2026-02-07T10:00:15.789Z", "level": "ERROR", "component": "playback", "message": "Video file missing", "metadata": {"expected_path": "/path/to/video.mp4", "segment_timestamp": "2026-02-07T08:00:00Z"}}
    {"timestamp": "2026-02-07T10:30:00.000Z", "level": "INFO", "component": "playback", "message": "App closed", "metadata": {"session_duration_s": 1800}}
    ```

- [ ] Add log viewer shortcut
  - Keyboard: Cmd+Shift+D
  - Menu: Help > View Diagnostics
  - Example:
    ```swift
    .commands {
        CommandGroup(replacing: .help) {
            Button("View Diagnostics...") {
                openDiagnosticsWindow()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
    ```

### Development Mode Support

- [ ] Configure dev log paths
  - Base: `<project>/dev_logs/`
  - When: `PLAYBACK_DEV_MODE=1` environment variable set
  - Create directory if doesn't exist
  - Example:
    ```python
    import os

    def get_log_directory():
        if os.getenv("PLAYBACK_DEV_MODE") == "1":
            # Development mode: use project directory
            project_dir = os.path.dirname(os.path.dirname(__file__))
            log_dir = os.path.join(project_dir, "dev_logs")
        else:
            # Production mode: use standard location
            log_dir = os.path.expanduser("~/Library/Logs/Playback")

        # Create directory if it doesn't exist
        os.makedirs(log_dir, exist_ok=True)
        return log_dir
    ```

- [ ] Add log path resolution
  - Function: `getLogPath(component:)` in ConfigManager
  - Returns dev or prod path based on environment
  - Example:
    ```swift
    class ConfigManager {
        static func getLogPath(for component: String) -> String {
            let isDevelopment = ProcessInfo.processInfo.environment["PLAYBACK_DEV_MODE"] == "1"

            if isDevelopment {
                // Development: use project directory
                let projectDir = Bundle.main.bundlePath
                    .replacingOccurrences(of: "/Build/Products/", with: "/")
                return "\(projectDir)/dev_logs/\(component).log"
            } else {
                // Production: use standard location
                let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
                return "\(homeDir)/Library/Logs/Playback/\(component).log"
            }
        }
    }
    ```

### Error Recovery

- [ ] Implement automatic log cleanup
  - Trigger: Disk space < 1GB
  - Action: Delete oldest rotated logs first
  - Notification: Warn user about low space
  - Example:
    ```python
    import psutil
    import os
    import glob

    def check_disk_space_and_cleanup():
        disk = psutil.disk_usage('/')
        free_gb = disk.free / (1024**3)

        if free_gb < 1.0:
            logger.warning("Low disk space detected", extra={"metadata": {
                "free_gb": round(free_gb, 2),
                "initiating_cleanup": True
            }})

            # Find all rotated logs (.log.1, .log.2, etc.)
            log_dir = os.path.expanduser("~/Library/Logs/Playback")
            rotated_logs = []
            for pattern in ["*.log.[0-9]", "*.log.[0-9][0-9]"]:
                rotated_logs.extend(glob.glob(os.path.join(log_dir, pattern)))

            # Sort by modification time (oldest first)
            rotated_logs.sort(key=os.path.getmtime)

            # Delete oldest logs until we have >1GB free
            deleted_count = 0
            for log_file in rotated_logs:
                if psutil.disk_usage('/').free / (1024**3) > 1.0:
                    break

                os.remove(log_file)
                deleted_count += 1
                logger.info("Deleted old log file", extra={"metadata": {
                    "file": log_file
                }})

            logger.warning("Log cleanup completed", extra={"metadata": {
                "deleted_files": deleted_count,
                "free_gb_after": round(psutil.disk_usage('/').free / (1024**3), 2)
            }})

            # Notify user
            notify_user("Low Disk Space",
                       f"Deleted {deleted_count} old log files to free space.")
    ```

- [ ] Handle missing log files
  - Diagnostics window: Show "No logs found" message
  - Parser: Return empty array instead of crashing
  - Health checks: Mark as "Unknown" status
  - Example:
    ```swift
    struct LogParser {
        static func parseLogs(fromFile path: String) -> [LogEntry] {
            guard FileManager.default.fileExists(atPath: path) else {
                print("Log file not found: \(path)")
                return []
            }

            guard let content = try? String(contentsOfFile: path) else {
                print("Could not read log file: \(path)")
                return []
            }

            // Parse logs...
            return entries
        }
    }

    struct LogViewer: View {
        var body: some View {
            if logs.isEmpty {
                VStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No logs found")
                        .font(.headline)
                    Text("Logs will appear here once services start running")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // Show log list...
            }
        }
    }
    ```

- [ ] Handle corrupted log entries
  - Parser: Skip malformed JSON lines
  - Log warning: "Skipped N corrupted entries"
  - Show in UI: "Some log entries could not be parsed"
  - Example:
    ```swift
    struct LogParser {
        static func parseLogs(fromFile path: String) -> (entries: [LogEntry], skippedCount: Int) {
            guard let content = try? String(contentsOfFile: path) else {
                return ([], 0)
            }

            var entries: [LogEntry] = []
            var skippedCount = 0

            for (lineNumber, line) in content.components(separatedBy: "\n").enumerated() {
                guard !line.isEmpty else { continue }

                if let data = line.data(using: .utf8),
                   let entry = try? JSONDecoder().decode(LogEntry.self, from: data) {
                    entries.append(entry)
                } else {
                    skippedCount += 1
                    print("Warning: Skipped malformed log entry at line \(lineNumber + 1)")
                }
            }

            return (entries, skippedCount)
        }
    }

    struct LogViewer: View {
        var body: some View {
            VStack {
                if skippedCount > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Some log entries could not be parsed (\(skippedCount) skipped)")
                            .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
                }

                // Show log list...
            }
        }
    }
    ```

## Logging System Details

### Structured JSON Log Format

All logs use newline-delimited JSON format where each line is a complete JSON object:

```json
{"timestamp": "2026-02-07T14:32:15.234Z", "level": "INFO", "component": "recording", "message": "Screenshot captured", "metadata": {"path": "/tmp/screenshots/1234567890.png", "size_kb": 245}}
{"timestamp": "2026-02-07T14:32:17.456Z", "level": "INFO", "component": "recording", "message": "Screenshot captured", "metadata": {"path": "/tmp/screenshots/1234567892.png", "size_kb": 238}}
{"timestamp": "2026-02-07T14:32:19.789Z", "level": "WARNING", "component": "recording", "message": "Screenshot skipped due to timeout", "metadata": {"timeout_ms": 5000, "consecutive_skips": 1}}
{"timestamp": "2026-02-07T14:35:00.123Z", "level": "INFO", "component": "recording", "message": "Resource metrics", "metadata": {"cpu_percent": 15.2, "memory_mb": 234, "disk_free_gb": 45.3, "uptime_hours": 2.5, "captures_total": 900}}
```

**Required Fields:**
- `timestamp`: ISO 8601 format with milliseconds and Z suffix (UTC)
- `level`: One of DEBUG, INFO, WARNING, ERROR, CRITICAL
- `component`: Service name (recording, processing, menubar, playback)
- `message`: Brief description of the event

**Optional Fields:**
- `metadata`: Object containing event-specific data (paths, sizes, durations, etc.)

### Log Rotation Configuration

**Size-based rotation with RotatingFileHandler:**
- Maximum size per file: 10 MB
- Backup count: 5 files
- Total storage per component: 50 MB (10 MB × 5 files)
- Naming convention: `.log` (current), `.log.1` (most recent), `.log.2`, `.log.3`, `.log.4`, `.log.5` (oldest)

**When rotation occurs:**
1. Current `.log` file reaches 10 MB
2. Existing backups are renamed (.log.1 → .log.2, .log.2 → .log.3, etc.)
3. Current `.log` is renamed to `.log.1`
4. New empty `.log` file is created
5. Oldest backup (`.log.5`) is deleted if it exists

### Resource Metrics Collection

**Recording Service (using psutil):**
- **Frequency:** Every 100 captures (~200 seconds at 2-second interval)
- **Metrics collected:**
  - CPU usage percentage (process-specific)
  - Memory usage in MB (RSS - Resident Set Size)
  - Free disk space in GB
  - Service uptime in hours
  - Total captures count

**Processing Service (using psutil):**
- **Frequency:** Per day processed
- **Metrics collected:**
  - Processing duration in seconds
  - Average CPU usage during processing
  - Peak memory usage during processing
  - Disk bytes read/written in MB
  - Number of segments created

### Diagnostics Window Implementation

**Tab Structure:**
1. **Logs Tab**
   - Filterable list of all log entries
   - Color-coded by log level (INFO=primary, WARNING=orange, ERROR=red, CRITICAL=purple)
   - Search bar for full-text search across messages and metadata
   - Level picker (All, INFO+, WARNING+, ERROR+, CRITICAL)
   - Time range picker (All Time, Last Hour, Last 24h, Last Week)
   - Detail view showing full metadata in expandable rows

2. **Health Tab**
   - Overall system status indicator (Healthy/Warning/Critical)
   - Service uptime displays for each component
   - Recent errors list (last 5 ERROR/CRITICAL entries)
   - Resource usage charts (CPU %, Memory MB, Disk Space GB)
   - Quick actions (Restart Services, Open Logs Folder)

3. **Export Tab**
   - Log export with format selection (JSON, Plain Text, CSV)
   - Date range selector for filtered export
   - Diagnostics package export (ZIP file with all logs, config, system info)
   - Export location picker

**Filter Algorithms:**
- **Level filtering:** Compares log level against minimum threshold using ordered enum
- **Time filtering:** Compares entry timestamp against calculated cutoff date
- **Search filtering:** Case-insensitive substring match across message, component, and all metadata values

**Chart Implementation:**
- Uses SwiftUI Charts framework (macOS 13+)
- LineMark for time-series data
- X-axis: Timestamp values
- Y-axis: Metric values with appropriate scales
- Auto-refreshes every 5 seconds when window is visible

### Health Check Algorithms

**Health Status Determination:**

1. **Recent Activity Check:**
   - Look for any log entries in the last 5 minutes
   - If none found: Return CRITICAL (service not running)

2. **Critical Error Check:**
   - Search for CRITICAL level logs in last hour
   - If found: Return CRITICAL

3. **Disk Space Check:**
   - Get latest disk space metric from resource logs
   - If < 1 GB free: Return CRITICAL
   - If < 5 GB free: Return WARNING

4. **Error Check:**
   - Search for ERROR level logs in last hour
   - If found: Return WARNING

5. **Default:**
   - If all checks pass: Return HEALTHY

## Testing Checklist

### Unit Tests

- [ ] Test JSON log parsing
  - Valid entries
  - Malformed JSON (should skip)
  - Missing fields (should use defaults)
  - Invalid timestamp (should use current time)

- [ ] Test log level filtering
  - Filter by exact level
  - Filter by minimum level (WARNING+, ERROR+)
  - Filter with no matches

- [ ] Test time range filtering
  - Last hour
  - Last 24 hours
  - Custom range
  - Edge cases (midnight boundary)

- [ ] Test search functionality
  - Case-insensitive message search
  - Metadata key/value search
  - Multiple search terms
  - Special characters in search

- [ ] Test resource metric extraction
  - Parse valid resource log entries
  - Handle missing metrics fields
  - Build time series data
  - Calculate averages and peaks

- [ ] Test log export
  - JSON format (preserve original)
  - Plain text format (human-readable)
  - CSV format (proper escaping)
  - Empty log file
  - Large log file (>10MB)

### Integration Tests

- [ ] Test log rotation
  - Write >10MB to log file
  - Verify .log.1 created
  - Continue writing, verify .log.2 created
  - Verify old backups deleted after 5 rotations

- [ ] Test concurrent writes
  - Recording service writes
  - Processing service writes simultaneously
  - Verify no corruption
  - Verify all entries present

- [ ] Test diagnostics window
  - Open with existing logs
  - Open with no logs (empty state)
  - Filter and search with 1000+ entries
  - Export while logs are being written

- [ ] Test LaunchAgent log capture
  - Verify stdout redirected to .stdout.log
  - Verify stderr redirected to .stderr.log
  - Verify structured logs go to .log file
  - Test print() statements in Python code

### Performance Tests

- [ ] Test log parsing performance
  - 10MB log file parsing time
  - 50MB total logs (5 rotations)
  - 10,000+ entries in memory
  - Filtering and search responsiveness

- [ ] Test resource metrics overhead
  - CPU usage of psutil calls
  - Memory usage of metrics collection
  - Impact on screenshot capture timing
  - Impact on processing speed

- [ ] Test real-time log monitoring
  - Tail -f style updates
  - Refresh every 5 seconds
  - CPU usage while monitoring
  - Memory usage with 24h of logs loaded

### Manual Testing

- [ ] Verify log readability
  - Open log files in text editor
  - Verify JSON is valid and parseable
  - Verify timestamps are correct
  - Verify metadata is useful for debugging

- [ ] Test diagnostics workflow
  - User reports issue
  - Open diagnostics window
  - Filter to ERROR+ logs
  - Export diagnostics package
  - Verify package contains all needed files

- [ ] Test error scenarios
  - Disk full during logging (should handle gracefully)
  - Corrupted log file (should skip bad entries)
  - Missing log directory (should create)
  - Permission denied (should notify user)

- [ ] Verify metrics accuracy
  - Compare CPU % with Activity Monitor
  - Compare memory MB with Activity Monitor
  - Verify disk space matches Finder
  - Verify capture count matches database
