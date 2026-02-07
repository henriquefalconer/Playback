# Storage & Cleanup Implementation Plan

**Component:** Storage Management and Cleanup
**Last Updated:** 2026-02-07

## Implementation Checklist

### Directory Structure Setup
- [ ] Create base directory structure
  - Location: `~/Library/Application Support/Playback/data/`
  - Subdirectories: `temp/`, `chunks/`, `meta.sqlite3`
  - Reference: See original spec "Directory Structure"

- [ ] Implement date-based folder hierarchy
  - Structure: `temp/YYYYMM/DD/` and `chunks/YYYYMM/DD/`
  - Source: `src/scripts/build_chunks_from_temp.py`
  - Implementation: Use `src/lib/paths.py` for path resolution
  - Ensures organized storage and efficient cleanup by date ranges

- [ ] Set up development directory structure
  - Location: `<project>/dev_data/`
  - Mirror production structure: `temp/`, `chunks/`, `meta.sqlite3`
  - Reference: architecture.md "File System Organization"

### File Naming Conventions
- [ ] Implement temp file naming
  - Format: `YYYYMMDD-HHMMSS-<uuid>-<app_id>` (no extension)
  - Example: `20251222-143052-a3f8b29c-com.apple.Safari`
  - Source: See original spec "File Naming Conventions"

- [ ] Implement video file naming
  - Format: `<segment_id>.mp4`
  - Example: `a3f8b29c.mp4`
  - Segment ID: 20-character hex string from `os.urandom(10).hex()`
  - Source: `src/scripts/build_chunks_from_temp.py`

- [ ] Parse timestamp from filename
  - Source: `src/scripts/build_chunks_from_temp.py`
  - Implementation: Use `src/lib/timestamps.py` parsing functions
  - Pattern: `YYYYMMDD-HHMMSS` prefix extraction
  - Used for: Age calculation in retention policies

- [ ] Parse app_id from filename
  - Source: `src/scripts/build_chunks_from_temp.py`
  - Implementation: Use `src/lib/timestamps.py` parsing functions
  - Pattern: Extract app bundle ID after UUID
  - Used for: App-specific filtering and analytics

### Storage Usage Calculation
- [ ] Implement temp directory size calculation
  - Function: `calculate_temp_usage() -> int`
  - Implementation: Use `src/lib/paths.py` for directory traversal
  - Recursively walk `temp/` directory
  - Sum file sizes, skip hidden files (starting with `.`)
  - Return: Total bytes
  - Reference: See original spec "Storage Usage Calculation"

- [ ] Implement chunks directory size calculation
  - Function: `calculate_chunks_usage() -> int`
  - Recursively walk `chunks/` directory
  - Filter for `.mp4` files only
  - Return: Total bytes

- [ ] Implement database size calculation
  - Function: `os.path.getsize(META_DB_PATH)`
  - Single file size check
  - Return: Total bytes

- [ ] Implement total usage aggregation
  - Function: `calculate_total_usage() -> dict`
  - Returns: `{"temp_bytes": int, "chunks_bytes": int, "database_bytes": int, "total_bytes": int}`
  - Used by: Settings UI and cleanup preview

### Retention Policies - Temp Files
- [ ] Define temp retention policy options
  - `"never"` - Keep all temp files indefinitely
  - `"1_day"` - Delete after 24 hours
  - `"1_week"` - Delete after 7 days (default)
  - `"1_month"` - Delete after 30 days

- [ ] Implement temp file cleanup function
  - Function: `cleanup_temp_files(policy: str)`
  - Source: See original spec "Retention Policies"
  - Implementation: Use `src/lib/paths.py` and `src/lib/database.py`
  - Trigger: After successful video generation in processing service
  - Safety: Only delete files successfully processed (segment exists in database)
  - Verification: Check `is_processed(file)` before deletion

- [ ] Add temp cleanup logging
  - Log: Policy applied, files deleted, MB freed
  - Level: INFO
  - Format: Structured metadata JSON

- [ ] Integrate temp cleanup into processing service
  - Location: `src/scripts/build_chunks_from_temp.py`
  - Call after: `process_day()` completes successfully
  - Config: Read `temp_retention_policy` from config.json

### Retention Policies - Recordings
- [ ] Define recording retention policy options
  - `"never"` - Keep all recordings indefinitely (default)
  - `"1_day"` - Delete after 24 hours
  - `"1_week"` - Delete after 7 days
  - `"1_month"` - Delete after 30 days

- [ ] Implement recording cleanup function
  - Function: `cleanup_old_recordings(policy: str)`
  - Source: See original spec "Retention Policies"
  - Implementation: Use `src/lib/database.py` for queries, `src/lib/paths.py` for file deletion
  - Query: `SELECT id, video_path FROM segments WHERE start_ts < ?`
  - Delete: Video files AND database entries (segments + appsegments)
  - Uses: `start_ts` field from segments table

- [ ] Add recording cleanup logging
  - Log: Policy applied, segments deleted, MB freed
  - Level: INFO
  - Format: Structured metadata JSON

- [ ] Integrate recording cleanup into processing service
  - Location: `src/scripts/build_chunks_from_temp.py`
  - Call after: `process_day()` completes successfully
  - Config: Read `recording_retention_policy` from config.json

### Manual Cleanup UI
- [ ] Create Storage settings tab
  - Location: `Playback/Settings/StorageTab.swift`
  - Display: Current usage breakdown (temp, chunks, database, total)
  - Display: Available disk space
  - Reference: See original spec "Storage UI Display"

- [ ] Implement storage usage display view
  - Component: `StorageUsageView` SwiftUI view
  - Source: See original spec "Storage UI Display" (lines 354-408)
  - Updates: On view appear
  - Format: ByteCountFormatter with GB/MB units

- [ ] Add retention policy pickers
  - UI: Dropdown for temp retention policy
  - UI: Dropdown for recording retention policy
  - Options: "never", "1_day", "1_week", "1_month"
  - Saves to: `config.json`

- [ ] Implement cleanup preview calculation
  - Function: `calculateCleanupPreview(tempPolicy:recordingPolicy:) -> CleanupPreview`
  - Returns: File counts and size estimates for confirmation dialog
  - Does NOT delete files, only calculates impact

- [ ] Add "Clean Up Now" button
  - Location: Storage settings tab
  - Function: `performManualCleanup(tempPolicy:recordingPolicy:)`
  - Source: See original spec "Manual Cleanup" (lines 248-282)
  - Flow: Preview → Confirmation dialog → Execute → Show results

- [ ] Create confirmation dialog
  - Type: NSAlert with warning style
  - Content: File counts, size to be freed
  - Buttons: "Delete" (primary), "Cancel"
  - Source: See original spec "Manual Cleanup" (lines 253-264)

- [ ] Show cleanup completion notification
  - Type: macOS notification
  - Title: "Cleanup Complete"
  - Body: "Freed X MB"
  - Trigger: After cleanup script completes successfully

### Automatic Cleanup on Processing
- [ ] Add cleanup calls to processing service
  - Location: `src/scripts/build_chunks_from_temp.py` (after `process_day()`)
  - Call: `cleanup_temp_files(config['temp_retention_policy'])`
  - Call: `cleanup_old_recordings(config['recording_retention_policy'])`
  - Timing: After successful video generation

- [ ] Add error handling for cleanup failures
  - Pattern: Log error, continue (don't block processing)
  - Level: ERROR
  - Impact: Processing continues even if cleanup fails

- [ ] Add configuration loading
  - Source: Load from `config.json`
  - Fields: `temp_retention_policy`, `recording_retention_policy`
  - Defaults: `"1_week"`, `"never"`

### Disk Space Monitoring
- [ ] Implement disk space availability check
  - Function: `get_disk_space_available() -> int`
  - Source: See original spec "Disk Space Monitoring" (lines 290-295)
  - Library: `shutil.disk_usage()`
  - Returns: Free bytes available

- [ ] Define disk space threshold
  - Threshold: 1 GB minimum
  - Constant: `MIN_DISK_SPACE_GB = 1.0`
  - Reference: See original spec "Disk Space Monitoring" (line 297)

- [ ] Add disk space check to recording service
  - Location: `src/scripts/record_screen.py`
  - Frequency: Every 100 captures (~200 seconds at 2s interval)
  - Action on failure: Disable recording, show notification, exit
  - Source: See original spec "Disk Full Handling"

- [ ] Add disk space check to processing service
  - Location: `src/scripts/build_chunks_from_temp.py`
  - Frequency: Before starting each day
  - Action on failure: Log error, show notification, skip work, exit with error
  - Source: See original spec "Disk Full Handling"

- [ ] Implement disk space check function
  - Function: `check_disk_space() -> bool`
  - Source: See original spec "Disk Full Handling" (lines 321-334)
  - Logs: Critical error with available GB
  - Notification: "Playback: Disk Full" with space available

- [ ] Add disk full notification
  - Title: "Playback stopped: Disk full" (recording) or "Processing failed: Disk full" (processing)
  - Body: "Only X GB available. Recording stopped."
  - Type: macOS system notification
  - Action: User must free space manually

- [ ] Update config on disk full
  - Recording service: Set `recording_enabled: false` in config
  - Location: `~/Library/Application Support/Playback/config.json`
  - Prevents: Auto-restart by LaunchAgent

### Database Cleanup
- [ ] Implement orphaned segment cleanup
  - Function: `cleanup_orphaned_segments()`
  - Source: See original spec "Database Cleanup"
  - Implementation: Use `src/lib/database.py` for queries and deletions
  - Detects: Segment entries where video file is missing
  - Deletes: Database entries (segments + appsegments)

- [ ] Add orphaned segment cleanup to processing
  - Location: `src/scripts/build_chunks_from_temp.py`
  - Trigger: Weekly or on-demand
  - Timing: After retention policy cleanup

- [ ] Implement database vacuum
  - Function: `vacuum_database()`
  - Source: See original spec "Database Cleanup"
  - Implementation: Use `src/lib/database.py` vacuum function
  - SQL: `VACUUM`
  - Purpose: Reclaim space from deleted rows

- [ ] Add vacuum to processing schedule
  - Trigger: Monthly or on-demand
  - Timing: After all cleanup operations complete
  - Logging: "Database vacuumed"

## Storage Management Details

### Shared Utilities

Storage and cleanup operations use common functionality from `src/lib/`:

- **Path resolution** (`src/lib/paths.py`) - Environment-aware path resolution for dev/prod, directory traversal
- **Database operations** (`src/lib/database.py`) - SQLite queries for segment verification and deletion
- **Timestamp handling** (`src/lib/timestamps.py`) - Filename parsing for age calculation

These utilities consolidate logic across recording, processing, and cleanup operations.

### Directory Structure

The storage system uses a date-based hierarchy for organizing captured data:

```
~/Library/Application Support/Playback/data/
├── temp/
│   └── YYYYMM/
│       └── DD/
│           └── YYYYMMDD-HHMMSS-<uuid>-<app_id>
├── chunks/
│   └── YYYYMM/
│       └── DD/
│           └── <segment_id>.mp4
└── meta.sqlite3
```

**Temp Directory (`temp/YYYYMM/DD/`):**
- Stores raw captured frames before processing
- Date-based folders created dynamically: year-month (6 digits) / day (2 digits)
- Example: `temp/202602/07/` for February 7, 2026
- No file extensions on temp files
- Cleaned up after successful processing based on retention policy

**Chunks Directory (`chunks/YYYYMM/DD/`):**
- Stores processed video segments
- Mirrors temp directory date hierarchy
- Contains `.mp4` files with segment ID names
- Cleaned up based on recording retention policy

**Database (`meta.sqlite3`):**
- SQLite database storing segment metadata
- Tables: `segments`, `appsegments`
- Tracks video file paths, timestamps, app associations
- Size grows with recording history

**Development Environment:**
- Location: `<project>/dev_data/`
- Mirrors production structure for testing
- Allows safe development without affecting user data

### File Naming Conventions

**Temp Files:**
- Format: `YYYYMMDD-HHMMSS-<uuid>-<app_id>`
- No file extension
- Components:
  - `YYYYMMDD`: Date (e.g., `20260207`)
  - `HHMMSS`: Time (e.g., `143052`)
  - `<uuid>`: Random UUID for uniqueness
  - `<app_id>`: Application bundle identifier (e.g., `com.apple.Safari`)
- Example: `20260207-143052-a3f8b29c-com.apple.Safari`

**Parsing Timestamp from Temp File:**
```python
def parse_timestamp_from_name(filename: str) -> datetime:
    """Extract timestamp from temp filename."""
    # Pattern: YYYYMMDD-HHMMSS at start of filename
    timestamp_str = filename[:15]  # "YYYYMMDD-HHMMSS"
    return datetime.strptime(timestamp_str, "%Y%m%d-%H%M%S")
```

**Parsing App ID from Temp File:**
```python
def parse_app_from_name(filename: str) -> str:
    """Extract app bundle ID from temp filename."""
    # Pattern: after UUID, following last hyphen
    parts = filename.split('-')
    if len(parts) >= 4:
        return parts[-1]  # App ID is last component
    return "unknown"
```

**Video Files:**
- Format: `<segment_id>.mp4`
- Segment ID: 20-character hexadecimal string
- Generation: `os.urandom(10).hex()` (10 bytes → 20 hex chars)
- Example: `a3f8b29c4d5e6f7890ab.mp4`
- Stored in date-based chunks directory

### Storage Calculation Algorithms

**Temp Directory Size:**
```python
def calculate_temp_usage() -> int:
    """Calculate total size of temp directory in bytes."""
    total_bytes = 0
    temp_dir = os.path.join(DATA_DIR, "temp")

    for root, dirs, files in os.walk(temp_dir):
        for file in files:
            # Skip hidden files (e.g., .DS_Store)
            if file.startswith('.'):
                continue

            file_path = os.path.join(root, file)
            try:
                total_bytes += os.path.getsize(file_path)
            except (OSError, FileNotFoundError):
                # File may have been deleted, skip
                pass

    return total_bytes
```

**Chunks Directory Size:**
```python
def calculate_chunks_usage() -> int:
    """Calculate total size of chunks directory in bytes."""
    total_bytes = 0
    chunks_dir = os.path.join(DATA_DIR, "chunks")

    for root, dirs, files in os.walk(chunks_dir):
        for file in files:
            # Only count .mp4 files
            if not file.endswith('.mp4'):
                continue

            file_path = os.path.join(root, file)
            try:
                total_bytes += os.path.getsize(file_path)
            except (OSError, FileNotFoundError):
                pass

    return total_bytes
```

**Database Size:**
```python
def calculate_database_usage() -> int:
    """Calculate database file size in bytes."""
    db_path = os.path.join(DATA_DIR, "meta.sqlite3")
    try:
        return os.path.getsize(db_path)
    except (OSError, FileNotFoundError):
        return 0
```

**Total Usage Aggregation:**
```python
def calculate_total_usage() -> dict:
    """Calculate all storage usage metrics."""
    temp_bytes = calculate_temp_usage()
    chunks_bytes = calculate_chunks_usage()
    database_bytes = calculate_database_usage()

    return {
        "temp_bytes": temp_bytes,
        "chunks_bytes": chunks_bytes,
        "database_bytes": database_bytes,
        "total_bytes": temp_bytes + chunks_bytes + database_bytes
    }
```

### Retention Policy Implementation Logic

**Temp File Retention Policies:**
- `"never"`: Keep all temp files indefinitely
- `"1_day"`: Delete files older than 24 hours
- `"1_week"`: Delete files older than 7 days (default)
- `"1_month"`: Delete files older than 30 days

**Temp File Cleanup Function:**
```python
def cleanup_temp_files(policy: str):
    """
    Clean up temp files based on retention policy.
    Only deletes files that have been successfully processed.
    """
    if policy == "never":
        return

    # Calculate age threshold
    age_days = {
        "1_day": 1,
        "1_week": 7,
        "1_month": 30
    }[policy]

    cutoff_time = datetime.now() - timedelta(days=age_days)
    temp_dir = os.path.join(DATA_DIR, "temp")

    deleted_count = 0
    freed_bytes = 0

    for root, dirs, files in os.walk(temp_dir):
        for file in files:
            if file.startswith('.'):
                continue

            file_path = os.path.join(root, file)

            # Parse timestamp from filename
            try:
                file_time = parse_timestamp_from_name(file)
            except ValueError:
                continue  # Skip malformed filenames

            # Check if file is old enough to delete
            if file_time < cutoff_time:
                # Verify file has been processed
                if is_processed(file):
                    try:
                        file_size = os.path.getsize(file_path)
                        os.remove(file_path)
                        deleted_count += 1
                        freed_bytes += file_size
                    except OSError as e:
                        logging.error(f"Failed to delete {file_path}: {e}")

    logging.info(f"Temp cleanup: policy={policy}, deleted={deleted_count}, freed_mb={freed_bytes / 1024 / 1024:.2f}")
```

**Recording Retention Policies:**
- `"never"`: Keep all recordings indefinitely (default)
- `"1_day"`: Delete recordings older than 24 hours
- `"1_week"`: Delete recordings older than 7 days
- `"1_month"`: Delete recordings older than 30 days

**Recording Cleanup Function:**
```python
def cleanup_old_recordings(policy: str):
    """
    Clean up old video recordings based on retention policy.
    Deletes both video files and database entries.
    """
    if policy == "never":
        return

    # Calculate age threshold
    age_days = {
        "1_day": 1,
        "1_week": 7,
        "1_month": 30
    }[policy]

    cutoff_timestamp = int((datetime.now() - timedelta(days=age_days)).timestamp())

    conn = sqlite3.connect(META_DB_PATH)
    cursor = conn.cursor()

    # Find old segments
    cursor.execute(
        "SELECT id, video_path FROM segments WHERE start_ts < ?",
        (cutoff_timestamp,)
    )
    old_segments = cursor.fetchall()

    deleted_count = 0
    freed_bytes = 0

    for segment_id, video_path in old_segments:
        # Delete video file
        full_path = os.path.join(DATA_DIR, "chunks", video_path)
        try:
            if os.path.exists(full_path):
                file_size = os.path.getsize(full_path)
                os.remove(full_path)
                freed_bytes += file_size
        except OSError as e:
            logging.error(f"Failed to delete {full_path}: {e}")

        # Delete database entries
        try:
            cursor.execute("DELETE FROM appsegments WHERE segment_id = ?", (segment_id,))
            cursor.execute("DELETE FROM segments WHERE id = ?", (segment_id,))
            deleted_count += 1
        except sqlite3.Error as e:
            logging.error(f"Failed to delete segment {segment_id}: {e}")

    conn.commit()
    conn.close()

    logging.info(f"Recording cleanup: policy={policy}, deleted={deleted_count}, freed_mb={freed_bytes / 1024 / 1024:.2f}")
```

**Verification Function for Temp Files:**
```python
def is_processed(temp_filename: str) -> bool:
    """
    Check if a temp file has been successfully processed.
    Returns True if corresponding segment exists in database.
    """
    # Extract timestamp and app from filename
    try:
        file_time = parse_timestamp_from_name(temp_filename)
        app_id = parse_app_from_name(temp_filename)
    except ValueError:
        return False

    # Query database for segment in time range
    conn = sqlite3.connect(META_DB_PATH)
    cursor = conn.cursor()

    start_ts = int(file_time.timestamp())
    end_ts = start_ts + 300  # 5 minute window

    cursor.execute(
        """
        SELECT COUNT(*) FROM segments s
        JOIN appsegments a ON s.id = a.segment_id
        WHERE s.start_ts BETWEEN ? AND ?
        AND a.app_id = ?
        """,
        (start_ts, end_ts, app_id)
    )

    count = cursor.fetchone()[0]
    conn.close()

    return count > 0
```

### Disk Space Monitoring Thresholds

**Disk Space Check Function:**
```python
def get_disk_space_available() -> int:
    """Get available disk space in bytes."""
    import shutil
    usage = shutil.disk_usage(DATA_DIR)
    return usage.free
```

**Disk Space Threshold:**
- Minimum required: 1 GB (1,073,741,824 bytes)
- Constant: `MIN_DISK_SPACE_GB = 1.0`
- Check frequency:
  - Recording service: Every 100 captures (~200 seconds)
  - Processing service: Before starting each day's work

**Disk Space Check Implementation:**
```python
MIN_DISK_SPACE_GB = 1.0
MIN_DISK_SPACE_BYTES = int(MIN_DISK_SPACE_GB * 1024 * 1024 * 1024)

def check_disk_space() -> bool:
    """
    Check if sufficient disk space is available.
    Returns True if enough space, False if below threshold.
    """
    available = get_disk_space_available()

    if available < MIN_DISK_SPACE_BYTES:
        available_gb = available / (1024 ** 3)
        logging.critical(
            f"Insufficient disk space: {available_gb:.2f} GB available, "
            f"{MIN_DISK_SPACE_GB} GB required"
        )

        # Show notification to user
        show_notification(
            title="Playback: Disk Full",
            body=f"Only {available_gb:.2f} GB available. Please free up space."
        )

        return False

    return True
```

**Recording Service Disk Check:**
```python
# In record_screen.py
capture_count = 0

while recording_enabled:
    # Capture frame...

    capture_count += 1

    # Check disk space every 100 captures
    if capture_count % 100 == 0:
        if not check_disk_space():
            # Disable recording and exit
            update_config(recording_enabled=False)
            logging.critical("Recording stopped due to insufficient disk space")
            sys.exit(1)
```

**Processing Service Disk Check:**
```python
# In build_chunks_from_temp.py
def process_day(date_str):
    # Check disk space before processing
    if not check_disk_space():
        logging.error(f"Skipping {date_str}: insufficient disk space")
        show_notification(
            title="Processing failed: Disk full",
            body="Free up space to resume processing."
        )
        sys.exit(1)

    # Continue with processing...
```

### Cleanup Execution Workflow

**Automatic Cleanup (Integrated into Processing):**
1. Processing service completes `process_day()` successfully
2. Load retention policies from config.json:
   - `temp_retention_policy` (default: "1_week")
   - `recording_retention_policy` (default: "never")
3. Execute temp file cleanup: `cleanup_temp_files(temp_policy)`
   - Walks temp directory recursively
   - Identifies files older than threshold
   - Verifies files have been processed
   - Deletes files and logs results
4. Execute recording cleanup: `cleanup_old_recordings(recording_policy)`
   - Queries database for old segments
   - Deletes video files from chunks directory
   - Removes database entries (segments + appsegments)
   - Logs results
5. On error: Log but continue (don't block processing)

**Manual Cleanup (User-Initiated):**
1. User opens Settings → Storage tab
2. View displays current usage:
   - Temp directory size
   - Chunks directory size
   - Database size
   - Total usage
   - Available disk space
3. User selects retention policies from dropdowns
4. User clicks "Clean Up Now" button
5. System calculates cleanup preview:
   - Count of temp files to delete
   - Count of recordings to delete
   - Estimated space to be freed
6. Confirmation dialog appears with preview information
7. User confirms or cancels
8. If confirmed, cleanup executes:
   - Run `cleanup_temp_files(temp_policy)`
   - Run `cleanup_old_recordings(recording_policy)`
   - Calculate actual space freed
9. Success notification displays freed space
10. Storage view refreshes to show updated usage

**Manual Cleanup Preview Function:**
```python
def calculate_cleanup_preview(temp_policy: str, recording_policy: str) -> dict:
    """
    Calculate cleanup impact without actually deleting files.
    Returns file counts and size estimates.
    """
    preview = {
        "temp_files": 0,
        "temp_bytes": 0,
        "recordings": 0,
        "recordings_bytes": 0
    }

    # Calculate temp file cleanup
    if temp_policy != "never":
        age_days = {"1_day": 1, "1_week": 7, "1_month": 30}[temp_policy]
        cutoff_time = datetime.now() - timedelta(days=age_days)

        temp_dir = os.path.join(DATA_DIR, "temp")
        for root, dirs, files in os.walk(temp_dir):
            for file in files:
                if file.startswith('.'):
                    continue
                try:
                    file_time = parse_timestamp_from_name(file)
                    if file_time < cutoff_time and is_processed(file):
                        file_path = os.path.join(root, file)
                        preview["temp_files"] += 1
                        preview["temp_bytes"] += os.path.getsize(file_path)
                except (ValueError, OSError):
                    pass

    # Calculate recording cleanup
    if recording_policy != "never":
        age_days = {"1_day": 1, "1_week": 7, "1_month": 30}[recording_policy]
        cutoff_timestamp = int((datetime.now() - timedelta(days=age_days)).timestamp())

        conn = sqlite3.connect(META_DB_PATH)
        cursor = conn.cursor()
        cursor.execute(
            "SELECT video_path FROM segments WHERE start_ts < ?",
            (cutoff_timestamp,)
        )

        for (video_path,) in cursor.fetchall():
            full_path = os.path.join(DATA_DIR, "chunks", video_path)
            if os.path.exists(full_path):
                preview["recordings"] += 1
                preview["recordings_bytes"] += os.path.getsize(full_path)

        conn.close()

    return preview
```

**Database Cleanup (Orphaned Segments):**
```python
def cleanup_orphaned_segments():
    """
    Remove database entries for segments with missing video files.
    Runs weekly or on-demand.
    """
    conn = sqlite3.connect(META_DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT id, video_path FROM segments")
    segments = cursor.fetchall()

    orphaned_count = 0

    for segment_id, video_path in segments:
        full_path = os.path.join(DATA_DIR, "chunks", video_path)
        if not os.path.exists(full_path):
            # Video file is missing, delete database entries
            try:
                cursor.execute("DELETE FROM appsegments WHERE segment_id = ?", (segment_id,))
                cursor.execute("DELETE FROM segments WHERE id = ?", (segment_id,))
                orphaned_count += 1
            except sqlite3.Error as e:
                logging.error(f"Failed to delete orphaned segment {segment_id}: {e}")

    conn.commit()
    conn.close()

    logging.info(f"Cleaned up {orphaned_count} orphaned segments")
```

**Database Vacuum (Space Reclamation):**
```python
def vacuum_database():
    """
    Reclaim space from deleted rows in database.
    Runs monthly or on-demand.
    """
    conn = sqlite3.connect(META_DB_PATH)

    # Get size before vacuum
    size_before = os.path.getsize(META_DB_PATH)

    # Execute vacuum
    conn.execute("VACUUM")
    conn.close()

    # Get size after vacuum
    size_after = os.path.getsize(META_DB_PATH)
    freed_mb = (size_before - size_after) / (1024 * 1024)

    logging.info(f"Database vacuumed: freed {freed_mb:.2f} MB")
```

**Configuration Storage:**
```json
{
  "recording_enabled": true,
  "temp_retention_policy": "1_week",
  "recording_retention_policy": "never"
}
```

Location: `~/Library/Application Support/Playback/config.json`

## Testing Checklist

### Unit Tests
- [ ] Test storage calculation accuracy
  - Verify: `calculate_temp_usage()` returns correct byte count
  - Verify: `calculate_chunks_usage()` returns correct byte count
  - Verify: `calculate_total_usage()` aggregates correctly
  - Test with: Empty directories, single file, multiple files

- [ ] Test retention policy logic
  - Verify: Correct files selected for deletion based on age
  - Verify: Processed files only deleted (temp cleanup)
  - Verify: Database entries correctly identified (recording cleanup)
  - Test with: Each policy option ("never", "1_day", "1_week", "1_month")

- [ ] Test disk space threshold detection
  - Verify: `check_disk_space()` returns true when space available
  - Verify: Returns false when below 1 GB
  - Mock: `shutil.disk_usage()` for test scenarios

- [ ] Test file parsing functions
  - Verify: `parse_timestamp_from_name()` extracts correct timestamps
  - Verify: `parse_app_from_name()` extracts correct app IDs
  - Test with: Valid filenames, malformed filenames, edge cases

### Integration Tests
- [ ] Test cleanup with active recording
  - Scenario: Recording service running during cleanup
  - Verify: No conflicts, files not locked, cleanup completes
  - Verify: Recent unprocessed files preserved

- [ ] Test cleanup with active processing
  - Scenario: Processing service running during manual cleanup
  - Verify: No database lock conflicts
  - Verify: Cleanup waits or skips locked files

- [ ] Test orphaned entry cleanup
  - Setup: Create database entries without corresponding video files
  - Verify: `cleanup_orphaned_segments()` removes entries
  - Verify: No errors for missing files

- [ ] Test manual cleanup via UI
  - Scenario: User clicks "Clean Up Now" button
  - Verify: Preview shows correct counts
  - Verify: Confirmation dialog appears
  - Verify: Cleanup executes on confirmation
  - Verify: Results notification shows correct freed space

- [ ] Test disk full scenario
  - Mock: Disk space below 1 GB
  - Verify: Recording service stops and disables recording
  - Verify: Processing service skips work and exits with error
  - Verify: Notifications displayed to user
  - Verify: Config updated (`recording_enabled: false`)

### Performance Tests
- [ ] Test cleanup with large datasets
  - Setup: 30+ days of temp files (>500GB)
  - Verify: Cleanup completes within reasonable time (<5 minutes)
  - Verify: No memory issues during recursive directory walk
  - Monitor: CPU and memory usage during cleanup

- [ ] Test storage calculation performance
  - Setup: Large directory structures with many files
  - Verify: Calculation completes quickly (<10 seconds)
  - Verify: UI remains responsive during calculation

- [ ] Test database vacuum performance
  - Setup: Database with 100,000+ deleted segments
  - Verify: `VACUUM` completes within reasonable time (<60 seconds)
  - Measure: Space reclaimed from deleted rows

### Edge Case Tests
- [ ] Test cleanup with empty directories
  - Verify: No errors when temp/ or chunks/ is empty
  - Verify: Correct behavior when no files match retention policy

- [ ] Test cleanup with partial processing
  - Scenario: Some temp files processed, others not
  - Verify: Only processed temp files deleted
  - Verify: Unprocessed files preserved regardless of age

- [ ] Test cleanup with mixed file types
  - Scenario: Hidden files (`.DS_Store`), invalid files in temp/
  - Verify: Hidden files ignored in calculations and cleanup
  - Verify: Invalid files don't break processing

- [ ] Test retention policy edge cases
  - Test: Files exactly at threshold age (24 hours, 7 days, 30 days)
  - Test: Files in different timezones
  - Verify: Consistent behavior at threshold boundaries
