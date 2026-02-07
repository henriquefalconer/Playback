# Storage and Cleanup Specification

**Component:** Storage Management and Cleanup
**Version:** 1.0
**Last Updated:** 2026-02-07

## Overview

Playback manages two types of storage: temporary screenshots (raw data) and processed video recordings (final output). Both have configurable retention policies to prevent unlimited disk usage growth.

## Directory Structure

### Base Directory

**Location:** `~/Library/Application Support/Playback/data/`

**Structure:**
```
data/
├── temp/                   # Temporary screenshots (raw PNG files)
│   ├── YYYYMM/             # Year-month folder (e.g., 202512)
│   │   ├── DD/             # Day folder (e.g., 22)
│   │   │   ├── YYYYMMDD-HHMMSS-<uuid>-<app>  # Screenshot files (no extension)
│   │   │   └── ...
│   │   └── ...
│   └── ...
├── chunks/                 # Processed video segments
│   ├── YYYYMM/             # Year-month folder
│   │   ├── DD/             # Day folder
│   │   │   ├── <segment_id>.mp4  # Video segment files
│   │   │   └── ...
│   │   └── ...
│   └── ...
└── meta.sqlite3            # Metadata database
```

### File Naming Conventions

**Temp Files:**
- Format: `YYYYMMDD-HHMMSS-<uuid>-<app_id>`
- Example: `20251222-143052-a3f8b29c-com.apple.Safari`
- No extension (raw PNG data)

**Video Files:**
- Format: `<segment_id>.mp4`
- Example: `a3f8b29c.mp4`
- Segment ID: 20-character hex string

## Storage Usage Calculation

### Temporary Screenshots

**Typical Size:** 200KB - 2MB per screenshot

**Daily Usage:**
- Screenshots per day: 43,200 (24 hours × 3600 seconds / 2 second interval)
- Storage per day: ~20GB - 50GB (depends on resolution and content)

**Calculation Function:**
```python
def calculate_temp_usage() -> int:
    """Returns total size in bytes."""
    total_size = 0
    for root, dirs, files in os.walk(TEMP_ROOT):
        for file in files:
            if not file.startswith('.'):
                total_size += os.path.getsize(os.path.join(root, file))
    return total_size
```

### Video Recordings

**Typical Size:** 1MB - 5MB per 5-second segment

**Daily Usage:**
- Segments per day: 17,280 (24 hours × 3600 seconds / 5 seconds)
- Storage per day: ~5GB - 20GB (70-90% compression vs. raw screenshots)

**Calculation Function:**
```python
def calculate_chunks_usage() -> int:
    """Returns total size in bytes."""
    total_size = 0
    for root, dirs, files in os.walk(CHUNKS_ROOT):
        for file in files:
            if file.endswith('.mp4'):
                total_size += os.path.getsize(os.path.join(root, file))
    return total_size
```

### Total Usage

**Function:**
```python
def calculate_total_usage() -> dict:
    return {
        "temp_bytes": calculate_temp_usage(),
        "chunks_bytes": calculate_chunks_usage(),
        "database_bytes": os.path.getsize(META_DB_PATH),
        "total_bytes": calculate_temp_usage() + calculate_chunks_usage() + os.path.getsize(META_DB_PATH)
    }
```

## Retention Policies

### Temp File Retention

**Policy Options:**
- `"never"` - Keep all temp files indefinitely
- `"1_day"` - Delete temp files older than 24 hours
- `"1_week"` - Delete temp files older than 7 days (default)
- `"1_month"` - Delete temp files older than 30 days

**Configuration:**
```json
{
  "temp_retention_policy": "1_week"
}
```

**Behavior:**
- Applied during processing run (after successful video generation)
- Only deletes files that have been successfully processed (segment exists in database)
- Preserves unprocessed files regardless of age

**Implementation:**
```python
def cleanup_temp_files(policy: str):
    if policy == "never":
        return

    thresholds = {
        "1_day": 86400,
        "1_week": 604800,
        "1_month": 2592000
    }
    threshold = thresholds.get(policy, 604800)
    cutoff_time = time.time() - threshold

    deleted_count = 0
    freed_bytes = 0

    for root, dirs, files in os.walk(TEMP_ROOT):
        for file in files:
            if file.startswith('.'):
                continue

            path = os.path.join(root, file)
            mtime = os.path.getmtime(path)

            if mtime < cutoff_time and is_processed(file):
                size = os.path.getsize(path)
                os.remove(path)
                deleted_count += 1
                freed_bytes += size

    log_info("Temp cleanup completed", metadata={
        "policy": policy,
        "files_deleted": deleted_count,
        "freed_mb": freed_bytes / (1024 * 1024)
    })
```

### Recording Retention

**Policy Options:**
- `"never"` - Keep all recordings indefinitely (default)
- `"1_day"` - Delete recordings older than 24 hours
- `"1_week"` - Delete recordings older than 7 days
- `"1_month"` - Delete recordings older than 30 days

**Configuration:**
```json
{
  "recording_retention_policy": "never"
}
```

**Behavior:**
- Applied during processing run
- Deletes video files AND database entries
- Uses segment `start_ts` field for age calculation

**Implementation:**
```python
def cleanup_old_recordings(policy: str):
    if policy == "never":
        return

    thresholds = {
        "1_day": 86400,
        "1_week": 604800,
        "1_month": 2592000
    }
    threshold = thresholds.get(policy, None)
    if threshold is None:
        return

    cutoff_ts = time.time() - threshold

    # Query segments older than cutoff
    conn = sqlite3.connect(META_DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT id, video_path FROM segments WHERE start_ts < ?", (cutoff_ts,))
    old_segments = cursor.fetchall()

    deleted_count = 0
    freed_bytes = 0

    for segment_id, video_path in old_segments:
        # Delete video file
        full_path = PLAYBACK_ROOT / video_path
        if full_path.exists():
            size = full_path.stat().st_size
            full_path.unlink()
            freed_bytes += size

        # Delete database entries
        cursor.execute("DELETE FROM segments WHERE id = ?", (segment_id,))
        cursor.execute("DELETE FROM appsegments WHERE id = ?", (segment_id,))
        deleted_count += 1

    conn.commit()
    conn.close()

    log_info("Recording cleanup completed", metadata={
        "policy": policy,
        "segments_deleted": deleted_count,
        "freed_mb": freed_bytes / (1024 * 1024)
    })
```

## Manual Cleanup

### Clean Up Now Button

**Location:** Settings window → Storage tab

**Behavior:**
1. Calculate current usage
2. Preview what will be deleted (file count, disk space)
3. Show confirmation dialog
4. Execute cleanup
5. Show results (files deleted, space freed)

**Implementation:**
```swift
func performManualCleanup(tempPolicy: String, recordingPolicy: String) {
    // Preview
    let preview = calculateCleanupPreview(tempPolicy: tempPolicy, recordingPolicy: recordingPolicy)

    // Confirmation
    let alert = NSAlert()
    alert.messageText = "Confirm Cleanup"
    alert.informativeText = """
    This will delete:
    - \(preview.tempFiles) temporary screenshots (\(preview.tempSizeMB) MB)
    - \(preview.recordingSegments) video segments (\(preview.recordingSizeMB) MB)

    Total space freed: \(preview.totalSizeMB) MB
    """
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .warning

    if alert.runModal() == .alertFirstButtonReturn {
        // Execute
        let task = Process()
        task.launchPath = "/usr/bin/python3"
        task.arguments = [
            scriptsDir + "/cleanup.py",
            "--temp-policy", tempPolicy,
            "--recording-policy", recordingPolicy
        ]
        task.launch()
        task.waitUntilExit()

        // Show results
        showNotification(title: "Cleanup Complete", body: "Freed \(preview.totalSizeMB) MB")
    }
}
```

## Disk Space Monitoring

### Availability Check

**Function:**
```python
def get_disk_space_available() -> int:
    """Returns available disk space in bytes."""
    import shutil
    stat = shutil.disk_usage(str(PLAYBACK_ROOT))
    return stat.free
```

**Threshold:** 1 GB minimum

**Check Frequency:**
- Recording service: Every 100 captures (~200 seconds)
- Processing service: Before starting each day

### Disk Full Handling

**Recording Service:**
1. Detect disk space < 1 GB
2. Log critical error
3. Show macOS notification: "Playback stopped: Disk full"
4. Set `recording_enabled: false` in config
5. Exit gracefully

**Processing Service:**
1. Detect disk space < 1 GB
2. Log critical error
3. Show macOS notification: "Processing failed: Disk full"
4. Skip remaining work
5. Exit with error code

**Implementation:**
```python
def check_disk_space() -> bool:
    """Returns True if sufficient disk space available."""
    available_gb = get_disk_space_available() / (1024**3)
    if available_gb < 1.0:
        log_critical("Insufficient disk space", metadata={
            "available_gb": available_gb
        })
        show_notification(
            "Playback: Disk Full",
            f"Only {available_gb:.1f} GB available. Recording stopped."
        )
        return False
    return True
```

## Storage UI Display

### Settings Window

**Storage Tab Content:**
```
Current Usage
  Screenshots (temp):    2.3 GB
  Videos (chunks):      45.7 GB
  Database:              12 MB
  ────────────────────────────
  Total:                48.0 GB

Available Disk Space:  123.4 GB
```

**Implementation:**
```swift
struct StorageUsageView: View {
    @State private var usage: StorageUsage?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Current Usage")
                .font(.headline)

            if let usage = usage {
                HStack {
                    Text("Screenshots (temp):")
                    Spacer()
                    Text(formatBytes(usage.tempBytes))
                }
                HStack {
                    Text("Videos (chunks):")
                    Spacer()
                    Text(formatBytes(usage.chunksBytes))
                }
                HStack {
                    Text("Database:")
                    Spacer()
                    Text(formatBytes(usage.databaseBytes))
                }
                Divider()
                HStack {
                    Text("Total:")
                        .font(.headline)
                    Spacer()
                    Text(formatBytes(usage.totalBytes))
                        .font(.headline)
                }

                Spacer().frame(height: 20)

                HStack {
                    Text("Available Disk Space:")
                    Spacer()
                    Text(formatBytes(usage.availableBytes))
                }
            }
        }
        .onAppear {
            calculateUsage()
        }
    }

    func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
```

## Database Cleanup

### Orphaned Entries

**Scenario:** Segment entry exists in database but video file is missing

**Detection:**
```sql
SELECT s.id, s.video_path
FROM segments s
WHERE NOT EXISTS (
    SELECT 1 FROM chunks WHERE path = s.video_path
)
```

**Cleanup:**
```python
def cleanup_orphaned_segments():
    conn = sqlite3.connect(META_DB_PATH)
    cursor = conn.cursor()

    cursor.execute("""
        SELECT id, video_path FROM segments
    """)

    orphaned = []
    for segment_id, video_path in cursor.fetchall():
        full_path = PLAYBACK_ROOT / video_path
        if not full_path.exists():
            orphaned.append(segment_id)

    for segment_id in orphaned:
        cursor.execute("DELETE FROM segments WHERE id = ?", (segment_id,))
        cursor.execute("DELETE FROM appsegments WHERE id = ?", (segment_id,))

    conn.commit()
    conn.close()

    log_info("Orphaned segments cleaned", metadata={"count": len(orphaned)})
```

### Database Vacuum

**Purpose:** Reclaim space from deleted rows

**Trigger:** Monthly or on-demand

**Implementation:**
```python
def vacuum_database():
    conn = sqlite3.connect(META_DB_PATH)
    conn.execute("VACUUM")
    conn.close()
    log_info("Database vacuumed")
```

## Testing

### Unit Tests

- Storage calculation accuracy
- Retention policy application (correct files deleted)
- Disk space threshold detection

### Integration Tests

- Cleanup with active recording/processing
- Orphaned entry cleanup
- Manual cleanup via UI

## Future Enhancements

1. **Smart Cleanup** - Delete least-important segments first (based on activity)
2. **External Storage** - Support for external drives or network storage
3. **Compression** - Additional compression for old recordings
4. **Archiving** - Move old recordings to cold storage (lower priority access)
