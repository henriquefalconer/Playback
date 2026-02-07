# Logging and Diagnostics Specification

**Component:** Logging and Diagnostics System
**Version:** 1.0
**Last Updated:** 2026-02-07

## Overview

Playback implements structured logging across all components with detailed resource utilization tracking. Logs are written in JSON format for easy parsing and displayed in the diagnostics window for user troubleshooting.

## Log Files

### File Locations

**Base Directory:** `~/Library/Logs/Playback/`

**Files:**
- `recording.log` - Recording service logs
- `recording.stdout.log` - Recording service stdout (LaunchAgent)
- `recording.stderr.log` - Recording service stderr (LaunchAgent)
- `processing.log` - Processing service logs
- `processing.stdout.log` - Processing service stdout (LaunchAgent)
- `processing.stderr.log` - Processing service stderr (LaunchAgent)
- `menubar.log` - Menu bar app logs
- `playback.log` - Playback app logs

### Log Format

**Structured JSON** (one entry per line, newline-delimited):

```json
{"timestamp": "2025-12-22T14:30:52.234Z", "level": "INFO", "component": "recording", "message": "Screenshot captured", "metadata": {"display": 1, "app": "com.apple.Safari", "path": "temp/202512/22/20251222-143052-a3f8b29c-com.apple.Safari", "duration_ms": 234}}
```

**Fields:**
- `timestamp` (string, ISO 8601): Event timestamp with milliseconds
- `level` (string): Log level (INFO, WARNING, ERROR, CRITICAL)
- `component` (string): Component name (recording, processing, menubar, playback)
- `message` (string): Human-readable description
- `metadata` (object, optional): Additional context-specific data

### Log Levels

**INFO** - Normal operations
- Screenshot captured
- Processing completed
- Service started/stopped
- Configuration loaded

**WARNING** - Recoverable issues
- Fallback used (display detection failed)
- Screenshot skipped (screensaver active)
- Frame ignored (invalid format)

**ERROR** - Non-critical failures
- Single screenshot failed
- FFmpeg encoding error (single segment)
- Database write retry

**CRITICAL** - Service-stopping issues
- Permission denied
- Disk full
- Database corruption

## Recording Service Logs

### Events Logged

**Service Lifecycle:**
```json
{"timestamp": "2025-12-22T14:00:00.000Z", "level": "INFO", "component": "recording", "message": "Service started", "metadata": {"version": "1.0", "python_version": "3.10.8", "macos_version": "13.0"}}
{"timestamp": "2025-12-22T18:00:00.000Z", "level": "INFO", "component": "recording", "message": "Service stopped", "metadata": {"reason": "user_request", "uptime_seconds": 14400, "screenshots_captured": 7200}}
```

**Screenshot Capture:**
```json
{"timestamp": "2025-12-22T14:30:52.234Z", "level": "INFO", "component": "recording", "message": "Screenshot captured", "metadata": {"display": 1, "app": "com.apple.Safari", "path": "temp/202512/22/20251222-143052-a3f8b29c", "duration_ms": 234, "file_size_kb": 543}}
```

**Screenshot Skipped:**
```json
{"timestamp": "2025-12-22T14:30:54.123Z", "level": "INFO", "component": "recording", "message": "Screenshot skipped", "metadata": {"reason": "screensaver_active"}}
{"timestamp": "2025-12-22T14:30:56.456Z", "level": "INFO", "component": "recording", "message": "Screenshot skipped", "metadata": {"reason": "excluded_app", "app": "com.apple.Keychain"}}
{"timestamp": "2025-12-22T14:30:58.789Z", "level": "INFO", "component": "recording", "message": "Screenshot skipped", "metadata": {"reason": "playback_visible"}}
```

**Screenshot Failed:**
```json
{"timestamp": "2025-12-22T14:31:00.012Z", "level": "ERROR", "component": "recording", "message": "Screenshot failed", "metadata": {"error": "CalledProcessError", "return_code": 1, "stderr": "screencapture: error..."}}
```

**Resource Metrics (every 100 captures):**
```json
{"timestamp": "2025-12-22T14:35:00.000Z", "level": "INFO", "component": "recording", "message": "Resource metrics", "metadata": {"captures_last_interval": 100, "cpu_percent": 2.3, "memory_mb": 45.2, "disk_space_gb": 123.4, "uptime_hours": 0.58}}
```

### Resource Monitoring

**Metrics Collected:**
- CPU usage (percentage, averaged over interval)
- Memory usage (MB, current)
- Disk space available (GB, at temp directory)
- Uptime (hours since service start)
- Capture count (last interval)

**Collection Method:**
```python
import psutil
import time

process = psutil.Process()

# Every 100 captures (~200 seconds)
metrics = {
    "captures_last_interval": captures_since_last_log,
    "cpu_percent": process.cpu_percent(interval=0.1),
    "memory_mb": process.memory_info().rss / 1024 / 1024,
    "disk_space_gb": psutil.disk_usage(str(TEMP_ROOT)).free / (1024**3),
    "uptime_hours": (time.time() - start_time) / 3600
}
log_info("Resource metrics", metadata=metrics)
```

## Processing Service Logs

### Events Logged

**Processing Run Lifecycle:**
```json
{"timestamp": "2025-12-22T14:30:00.000Z", "level": "INFO", "component": "processing", "message": "Processing started", "metadata": {"mode": "auto", "days_to_process": 1}}
{"timestamp": "2025-12-22T14:31:30.000Z", "level": "INFO", "component": "processing", "message": "Processing completed", "metadata": {"days_processed": 1, "total_segments": 24, "total_duration_ms": 90123}}
```

**Day Processing:**
```json
{"timestamp": "2025-12-22T14:30:02.000Z", "level": "INFO", "component": "processing", "message": "Day processing started", "metadata": {"day": "20251222", "frame_count": 3600, "estimated_duration_ms": 30000}}
{"timestamp": "2025-12-22T14:31:28.000Z", "level": "INFO", "component": "processing", "message": "Day processing completed", "metadata": {"day": "20251222", "segments_generated": 24, "appsegments_generated": 45, "duration_ms": 86234, "cpu_avg": 65.2, "memory_peak_mb": 234.5, "disk_read_mb": 1234, "disk_write_mb": 145}}
```

**Segment Generation:**
```json
{"timestamp": "2025-12-22T14:30:45.000Z", "level": "INFO", "component": "processing", "message": "Segment generated", "metadata": {"segment_id": "a3f8b29c", "frame_count": 150, "start_ts": 1703258400.0, "end_ts": 1703258700.0, "ffmpeg_duration_ms": 42340, "file_size_mb": 2.3, "resolution": "3840x2160"}}
```

**Cleanup:**
```json
{"timestamp": "2025-12-22T14:31:29.000Z", "level": "INFO", "component": "processing", "message": "Cleanup completed", "metadata": {"temp_files_deleted": 150, "recordings_deleted": 0, "disk_space_freed_mb": 543}}
```

### Resource Monitoring

**Metrics Collected (per day):**
- Start time (epoch seconds)
- End time (epoch seconds)
- Duration (milliseconds)
- CPU usage (average percentage during processing)
- Memory usage (peak MB during processing)
- Disk read (MB)
- Disk write (MB)

**Collection Method:**
```python
import psutil
import time

process = psutil.Process()
start_time = time.time()
start_cpu = process.cpu_percent()
start_memory = process.memory_info().rss / 1024 / 1024
start_io = process.io_counters()

# ... process day ...

end_time = time.time()
end_cpu = process.cpu_percent()
end_memory = process.memory_info().rss / 1024 / 1024
end_io = process.io_counters()

metrics = {
    "duration_ms": int((end_time - start_time) * 1000),
    "cpu_avg": (start_cpu + end_cpu) / 2,
    "memory_peak_mb": max(start_memory, end_memory),
    "disk_read_mb": (end_io.read_bytes - start_io.read_bytes) / 1024 / 1024,
    "disk_write_mb": (end_io.write_bytes - start_io.write_bytes) / 1024 / 1024
}
log_info("Day processing completed", metadata={**day_info, **metrics})
```

## Menu Bar App Logs

### Events Logged

```json
{"timestamp": "2025-12-22T10:00:00.000Z", "level": "INFO", "component": "menubar", "message": "App launched", "metadata": {"version": "1.0"}}
{"timestamp": "2025-12-22T10:00:05.000Z", "level": "INFO", "component": "menubar", "message": "Recording enabled", "metadata": {"user_action": true}}
{"timestamp": "2025-12-22T10:00:10.000Z", "level": "INFO", "component": "menubar", "message": "Recording disabled", "metadata": {"user_action": true}}
{"timestamp": "2025-12-22T10:00:15.000Z", "level": "INFO", "component": "menubar", "message": "Settings changed", "metadata": {"field": "processing_interval_minutes", "old_value": 5, "new_value": 10}}
{"timestamp": "2025-12-22T10:00:20.000Z", "level": "INFO", "component": "menubar", "message": "Manual processing triggered", "metadata": {"user_action": true}}
```

## Playback App Logs

### Events Logged

```json
{"timestamp": "2025-12-22T14:00:00.000Z", "level": "INFO", "component": "playback", "message": "App launched", "metadata": {"segments_loaded": 288, "timespan_hours": 24}}
{"timestamp": "2025-12-22T14:00:05.000Z", "level": "INFO", "component": "playback", "message": "Segment loaded", "metadata": {"segment_id": "a3f8b29c", "load_time_ms": 234}}
{"timestamp": "2025-12-22T14:00:10.000Z", "level": "WARNING", "component": "playback", "message": "Video file missing", "metadata": {"segment_id": "b4f9c30d", "expected_path": "chunks/202512/22/b4f9c30d.mp4"}}
{"timestamp": "2025-12-22T14:05:00.000Z", "level": "INFO", "component": "playback", "message": "App closed", "metadata": {"session_duration_seconds": 300}}
```

## Log Rotation

### Strategy

**Size-Based Rotation:**
- Max file size: 10 MB
- When exceeded: Rotate to `.log.1`, `.log.2`, etc.
- Keep last 5 rotations (50 MB total per component)

**Implementation:**
```python
import logging
from logging.handlers import RotatingFileHandler

def setup_logging(log_path: str):
    handler = RotatingFileHandler(
        log_path,
        maxBytes=10 * 1024 * 1024,  # 10 MB
        backupCount=5
    )
    handler.setFormatter(JSONFormatter())
    logger = logging.getLogger()
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
```

### Cleanup

**Automatic:** Old rotated logs deleted when max count exceeded

**Manual:** User can clear logs via Diagnostics window

## Diagnostics Window Integration

### Log Parsing

**Function:** Parse JSON logs into structured entries

```swift
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let component: String
    let message: String
    let metadata: [String: Any]

    enum LogLevel: String {
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case critical = "CRITICAL"
    }
}

func parseLogFile(path: String) -> [LogEntry] {
    guard let content = try? String(contentsOfFile: path) else {
        return []
    }

    return content.split(separator: "\n").compactMap { line in
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return LogEntry(
            timestamp: formatter.date(from: json["timestamp"] as? String ?? "") ?? Date(),
            level: LogEntry.LogLevel(rawValue: json["level"] as? String ?? "INFO") ?? .info,
            component: json["component"] as? String ?? "unknown",
            message: json["message"] as? String ?? "",
            metadata: json["metadata"] as? [String: Any] ?? [:]
        )
    }
}
```

### Filtering

**By Level:**
- All
- INFO only
- WARNING+ (WARNING, ERROR, CRITICAL)
- ERROR+ (ERROR, CRITICAL)
- CRITICAL only

**By Time Range:**
- Last Hour
- Last 24 Hours
- Last Week
- All Time

**By Search:**
- Full-text search across message and metadata
- Case-insensitive
- Highlight matches

### Resource Charts

**Data Source:** Parse resource metrics from logs

**Rendering:** SwiftUI Charts (line graphs)

**Metrics Displayed:**
- CPU usage over time
- Memory usage over time
- Processing duration per run
- Screenshots captured per hour

## Export Functionality

### Export Logs

**Format Options:**
- JSON (original format)
- Plain text (human-readable)
- CSV (for spreadsheet analysis)

**Export Process:**
1. User clicks "Export" in Diagnostics window
2. Select format and time range
3. Choose save location
4. Combine selected logs into single file
5. Show success notification

**Implementation:**
```swift
func exportLogs(format: ExportFormat, dateRange: DateRange, to url: URL) {
    let logs = parseLogFile(path: logPath)
        .filter { dateRange.contains($0.timestamp) }

    let content: String
    switch format {
    case .json:
        content = logs.map { $0.toJSON() }.joined(separator: "\n")
    case .plainText:
        content = logs.map { $0.toPlainText() }.joined(separator: "\n")
    case .csv:
        content = logs.toCSV()
    }

    try? content.write(to: url, atomically: true, encoding: .utf8)
}
```

### Export Diagnostics Package

**Contents:**
- All log files
- Configuration file
- Database schema (without video files)
- System information (macOS version, hardware specs)

**Packaging:**
- Zip file: `Playback-Diagnostics-<timestamp>.zip`
- Password protected (optional)

## Testing

### Unit Tests

- JSON log parsing
- Log level filtering
- Time range filtering
- Resource metric extraction

### Integration Tests

- Log file rotation (write > 10MB)
- Concurrent writes (multiple processes)
- Export functionality (all formats)

## Future Enhancements

### Potential Features

1. **Remote Logging** - Send logs to external service for monitoring
2. **Log Analytics** - Automatic issue detection and suggestions
3. **Performance Profiling** - Detailed timing breakdowns
4. **Crash Reporting** - Automatic crash log collection and analysis
5. **Real-Time Streaming** - Live log viewer with tail -f style updates
