# Processing Service Implementation Plan

**Component:** Processing Service (Python LaunchAgent)

**Architecture Note:** The processing service is an independent Python script managed by a LaunchAgent:
- Runs independently of timeline viewer (Playback.app) and menu bar agent
- Scheduled execution every 5 minutes (configurable via settings)
- Controlled by menu bar agent via launchctl
- Only stopped when user clicks "Quit Playback" in menu bar

## Implementation Checklist

### Core Script Setup
- [ ] Create main script structure
  - Source: `src/scripts/build_chunks_from_temp.py`
  - Entry point: `main()` function with argparse
  - Modes: `--auto` (scheduled) and `--day YYYYMMDD` (manual)
  - Exit codes: 0 (success), 1 (partial), 2 (failure)
  - Script should be Python 3.8+ compatible
  - Use pathlib for cross-platform path handling

- [ ] Configure path resolution
  - Production: `~/Library/Application Support/Playback/data/`
  - Development: `<project>/com.playback.Playback/`
  - Environment variable: `PLAYBACK_CONFIG` for config path
  - Directory structure:
    - `temp/YYYYMM/DD/` - Temporary PNG frames
    - `chunks/YYYYMM/DD/` - Processed MP4 segments
    - `meta.sqlite3` - Metadata database
    - `config.json` - Configuration file

### Scheduled Processing (Auto Mode)
- [ ] Implement day detection
  - Function: `find_unprocessed_days() -> List[str]`
  - Strategy: Scan `temp/YYYYMM/` directories for subdirectories
  - Detection: Compare file creation time vs last processed timestamp in DB
  - Algorithm:
    1. List all `YYYYMM` directories in `temp/`
    2. For each, list subdirectories `DD` (01-31)
    3. Check if any file in `temp/YYYYMM/DD/` has st_birthtime > last_processed_ts
    4. Query database for last_processed_ts from segments table (MAX(end_ts) WHERE date=YYYYMMDD)
    5. If no DB entry or newer files exist, mark day as unprocessed

- [ ] Implement auto processing workflow
  - Iterate through all unprocessed days in chronological order
  - Process each day independently (atomic operations)
  - Continue on error (fail gracefully, log error, proceed to next day)
  - Apply cleanup policies after successful processing
  - Track success/failure counts for exit code determination
  - Exit code logic:
    - 0 if all days processed successfully
    - 1 if some days failed but at least one succeeded
    - 2 if all days failed or critical error occurred

- [ ] Configure 5-minute interval
  - Default: 300 seconds (5 minutes)
  - Configurable via config.json: `processing_interval_minutes`
  - LaunchAgent StartInterval updated dynamically via plutil
  - Reload command: `launchctl unload` + `launchctl load`
  - Validation: Interval must be between 60-3600 seconds

### Frame Loading and Scanning
- [ ] Implement frame loading
  - Function: `load_frames_for_day(day: str) -> List[FrameInfo]`
  - Source: Read from `temp/YYYYMM/DD/`
  - Implementation: Use `src/lib/paths.py` for path resolution
  - Filename format: `<timestamp_ms>_<app_id>.png` or `<timestamp_ms>.png`
  - Parse filename:
    - Extract timestamp: First part before underscore or dot
    - Extract app_id: Part between first underscore and .png (or None)
  - Get dimensions via ffprobe:
    ```bash
    ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 <file>
    ```
  - Use st_birthtime (Date Created) for timeline accuracy instead of filename timestamp
  - Sort frames by st_birthtime ascending
  - Validation checks:
    - File must be regular file (not directory/symlink)
    - File must have .png extension
    - File must not start with . (hidden files)
    - File must have valid dimensions from ffprobe

- [ ] Implement frame validation
  - Skip files without valid PNG dimensions (ffprobe returns non-zero)
  - Skip hidden files (.DS_Store, .*, etc.)
  - Log invalid files at WARNING level without breaking pipeline
  - Log format: "Skipping invalid frame: {path}, reason: {reason}"
  - Continue processing remaining frames

- [ ] Create FrameInfo dataclass
  - Fields:
    - path: Path - Absolute path to PNG file
    - ts: int - Timestamp in milliseconds (from st_birthtime)
    - app_id: Optional[str] - Application bundle ID or None
    - width: int - Frame width in pixels
    - height: int - Frame height in pixels
  - Implement __repr__ for debugging
  - Implement comparison operators for sorting

### Frame Grouping and Segmentation
- [ ] Implement segmentation logic
  - Function: `group_frames_by_count(frames: List[FrameInfo], max_frames_per_segment: int) -> List[List[FrameInfo]]`
  - Max frames: fps × segment_duration (default: 30 × 5 = 150 frames)
  - Segmentation algorithm (5-second chunks):
    1. Sort frames by timestamp ascending
    2. Initialize current_segment = []
    3. For each frame:
       - If current_segment is empty, add frame and continue
       - Check break conditions:
         a. Resolution change: frame.width != prev.width OR frame.height != prev.height
         b. Large gap: (frame.ts - prev.ts) > 60000 ms (60 seconds)
         c. Max frames: len(current_segment) >= max_frames_per_segment
       - If any break condition true:
         - Yield current_segment
         - Start new segment with current frame
       - Else:
         - Add frame to current_segment
    4. Yield final segment if non-empty
  - Gap handling rationale:
    - Gaps < 60s: Normal frame rate fluctuations, keep in same segment
    - Gaps >= 60s: Recording stopped/started, user activity break, new segment
  - Resolution change handling:
    - Different monitors have different resolutions
    - Cannot mix resolutions in single video file
    - Each resolution gets own segment(s)

- [ ] Configure segmentation parameters
  - Default FPS: 30 frames per second
  - Default segment duration: 5 seconds
  - Max frames calculation: fps × duration (30 × 5 = 150)
  - Configurable via CLI arguments: `--fps`, `--segment-duration`
  - Configurable via config.json: `default_fps`, `segment_duration_seconds`
  - Validation: fps must be 1-60, duration must be 1-60 seconds

### FFmpeg Video Generation
- [ ] Implement video encoding
  - Function: `run_ffmpeg_make_segment(frames: List[FrameInfo], fps: int, crf: int, preset: str, dest_without_ext: Path) -> Tuple[int, int, int]`
  - Implementation: Use `src/lib/video.py` FFmpeg wrappers
  - Process:
    1. Create temporary directory for sequential frames
    2. Copy/symlink frames to temp dir with sequential names: `frame_00001.png`, `frame_00002.png`, etc.
    3. Use ffmpeg concat demuxer with frame pattern input
    4. Output to `{dest_without_ext}.mp4`
    5. Clean up temporary directory
    6. Get output file size using os.stat
    7. Return (file_size_bytes, width, height)
  - FFmpeg command with exact parameters:
    ```bash
    ffmpeg -y \
      -framerate {fps} \
      -pattern_type glob -i 'frame_*.png' \
      -c:v libx264 \
      -preset veryfast \
      -crf 28 \
      -pix_fmt yuv420p \
      -movflags +faststart \
      output.mp4
    ```
  - Error handling:
    - Capture stderr for debugging
    - Check exit code (0 = success)
    - Log full command on failure
    - Re-raise exception for caller to handle

- [ ] Configure encoding parameters
  - Codec: H.264 (libx264) - better compatibility than HEVC
    - Rationale: Universal playback support (QuickTime, AVPlayer, web browsers)
    - Alternative HEVC considered but rejected due to compatibility issues
  - Preset: veryfast (balance speed/compression)
    - Options: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow
    - veryfast chosen: ~10s for 150 frames vs ~25s for medium
    - Compression penalty: ~15% larger files vs medium (acceptable tradeoff)
  - CRF: 28 (constant rate factor)
    - Range: 0 (lossless) to 51 (worst quality)
    - 28 chosen: Visually lossless for screen recordings
    - Typical compression: 70-90% reduction from PNG frames
    - Example: 150 frames × 500KB = 75MB → ~7.5MB MP4
  - Pixel format: yuv420p (QuickTime/AVPlayer compatibility)
    - Required for macOS QuickTime Player and AVFoundation
    - Alternative yuv444p has better quality but incompatible
  - Additional flags:
    - `-movflags +faststart`: Move moov atom to beginning for streaming
    - `-y`: Overwrite output file without prompting

- [ ] Implement output organization
  - Destination: `chunks/YYYYMM/DD/<segment_id>.mp4`
  - Segment ID generation:
    - Use `secrets.token_hex(10)` for cryptographically random 20-char hex string
    - Ensures uniqueness across all segments
    - Example: `a1b2c3d4e5f6g7h8i9j0.mp4`
  - Directory creation:
    - Use `Path.mkdir(parents=True, exist_ok=True)`
    - Create year-month and day directories as needed
    - Handle race conditions gracefully (exist_ok=True)

### Database Operations
- [ ] Initialize database schema
  - Function: `init_meta_db(path: Path) -> sqlite3.Connection`
  - Implementation: Use `src/lib/database.py` schema initialization
  - Location: `meta.sqlite3` in data root
  - Schema - segments table (video metadata):
    ```sql
    CREATE TABLE IF NOT EXISTS segments (
      id TEXT PRIMARY KEY,
      date TEXT NOT NULL,
      start_ts INTEGER NOT NULL,
      end_ts INTEGER NOT NULL,
      frame_count INTEGER NOT NULL,
      fps INTEGER NOT NULL,
      width INTEGER NOT NULL,
      height INTEGER NOT NULL,
      file_size_bytes INTEGER NOT NULL,
      video_path TEXT NOT NULL,
      created_at INTEGER DEFAULT (strftime('%s', 'now'))
    );
    CREATE INDEX IF NOT EXISTS idx_segments_date ON segments(date);
    CREATE INDEX IF NOT EXISTS idx_segments_start_ts ON segments(start_ts);
    CREATE INDEX IF NOT EXISTS idx_segments_end_ts ON segments(end_ts);
    ```
  - Schema - appsegments table (app activity timeline):
    ```sql
    CREATE TABLE IF NOT EXISTS appsegments (
      id TEXT PRIMARY KEY,
      app_id TEXT,
      date TEXT NOT NULL,
      start_ts INTEGER NOT NULL,
      end_ts INTEGER NOT NULL,
      created_at INTEGER DEFAULT (strftime('%s', 'now'))
    );
    CREATE INDEX IF NOT EXISTS idx_appsegments_app_id ON appsegments(app_id);
    CREATE INDEX IF NOT EXISTS idx_appsegments_date ON appsegments(date);
    CREATE INDEX IF NOT EXISTS idx_appsegments_start_ts ON appsegments(start_ts);
    CREATE INDEX IF NOT EXISTS idx_appsegments_end_ts ON appsegments(end_ts);
    ```
  - Connection settings:
    - Enable WAL mode: `PRAGMA journal_mode=WAL`
    - Foreign keys: `PRAGMA foreign_keys=ON`
    - Cache size: `PRAGMA cache_size=-64000` (64MB)

- [ ] Implement segment insertion
  - Function: `insert_segment_meta(conn: sqlite3.Connection, segment_id: str, date: str, frames: List[FrameInfo], fps: int, file_size: int, video_path: Path)`
  - Implementation: Use `src/lib/database.py` insertion functions
  - SQL: `INSERT OR REPLACE INTO segments (id, date, start_ts, end_ts, frame_count, fps, width, height, file_size_bytes, video_path) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  - Field values:
    - id: segment_id (random hex from output organization)
    - date: YYYYMMDD format string
    - start_ts: First frame timestamp (milliseconds)
    - end_ts: Last frame timestamp (milliseconds)
    - frame_count: len(frames)
    - fps: Encoding FPS (usually 30)
    - width: Frame width (pixels)
    - height: Frame height (pixels)
    - file_size_bytes: Output MP4 file size
    - video_path: Relative path from data root (chunks/YYYYMM/DD/id.mp4)
  - Use INSERT OR REPLACE for idempotency (reprocessing same day)
  - Commit after each segment for durability

- [ ] Implement app segment generation
  - Function: `build_appsegments_for_day(frames: List[FrameInfo]) -> List[Tuple[Optional[str], int, int]]`
  - Algorithm:
    1. Sort frames by timestamp
    2. Initialize current_app_id = None, segment_start_ts = None
    3. For each frame:
       - If app_id != current_app_id:
         - If segment_start_ts is not None:
           - Yield (current_app_id, segment_start_ts, prev_frame_ts)
         - Start new segment: current_app_id = frame.app_id, segment_start_ts = frame.ts
       - Else:
         - Continue current segment
    4. Yield final segment: (current_app_id, segment_start_ts, last_frame_ts)
  - Group consecutive frames by app_id
  - Break on app change (different bundle ID)
  - Handle None app_id (unknown app periods, e.g., screen locked)
  - Result: List of (app_id, start_ts, end_ts) tuples

- [ ] Implement app segment insertion
  - Function: `insert_appsegment_meta(conn: sqlite3.Connection, date: str, app_segments: List[Tuple[Optional[str], int, int]])`
  - SQL: `INSERT OR REPLACE INTO appsegments (id, app_id, date, start_ts, end_ts) VALUES (?, ?, ?, ?, ?)`
  - Field values:
    - id: `secrets.token_hex(10)` (unique per appsegment)
    - app_id: Application bundle ID or NULL
    - date: YYYYMMDD format string
    - start_ts: Segment start timestamp (milliseconds)
    - end_ts: Segment end timestamp (milliseconds)
  - One appsegment per continuous app usage period
  - Batch insert for efficiency: `executemany()`
  - Commit after all appsegments for day

- [ ] Add database error handling
  - Retry mechanism:
    - On sqlite3.OperationalError (database locked, disk I/O error):
      - Wait 1 second
      - Retry once
      - If retry fails, log error and skip segment
  - Critical errors (exit code 2):
    - sqlite3.DatabaseError: Corrupted database
    - Multiple consecutive write failures (> 5 in single run)
    - Schema version mismatch
  - Log all database errors with:
    - Error type and message
    - SQL statement (if applicable)
    - Stack trace
    - Segment/day being processed

### Cleanup Policies
- [ ] Implement temp file cleanup
  - Function: `cleanup_temp_files(day: str, policy: str, conn: sqlite3.Connection, data_root: Path)`
  - Implementation: Use `src/lib/paths.py` for directory traversal
  - Policies:
    - "never": No cleanup, keep all temp files
    - "1_day": Delete temp files older than 24 hours
    - "1_week": Delete temp files older than 7 days
    - "1_month": Delete temp files older than 30 days
  - Implementation:
    1. Calculate cutoff timestamp: now - policy_duration
    2. Query segments table for all segments with date=day
    3. For each segment, find corresponding temp frames by timestamp range
    4. Verify temp file exists and matches segment frame list
    5. Only delete files successfully processed (in database)
    6. Calculate disk space freed: sum(file_size for deleted files)
    7. Delete files using os.unlink()
    8. Remove empty directories (day, month)
  - Safety checks:
    - Never delete if segment not in database
    - Skip files modified after cutoff (reprocessing in progress)
    - Verify file is in temp/ directory (prevent accidental deletion)
  - Logging:
    - INFO: "Cleaned up {count} temp files for {day}, freed {mb}MB"
    - WARNING: "Skipped {count} temp files (not in database)"

- [ ] Implement recording cleanup
  - Function: `cleanup_old_recordings(policy: str, conn: sqlite3.Connection, data_root: Path)`
  - Policies:
    - "never": No cleanup, keep all recordings (default)
    - "1_day": Delete recordings older than 24 hours
    - "1_week": Delete recordings older than 7 days
    - "1_month": Delete recordings older than 30 days
  - Implementation:
    1. Calculate cutoff timestamp: now - policy_duration
    2. Query segments table: `SELECT id, video_path, file_size_bytes FROM segments WHERE end_ts < ?`
    3. For each old segment:
       a. Delete video file: `os.unlink(data_root / video_path)`
       b. Delete database row: `DELETE FROM segments WHERE id=?`
    4. Query appsegments table: `DELETE FROM appsegments WHERE end_ts < ?`
    5. Calculate total disk space freed
    6. Vacuum database to reclaim space: `VACUUM`
  - Safety checks:
    - Verify video_path is in chunks/ directory
    - Skip if file doesn't exist (already deleted)
    - Transaction rollback on error (atomic operation)
  - Logging:
    - INFO: "Cleaned up {count} recordings, freed {mb}MB"
    - WARNING: "Failed to delete {path}: {error}"

- [ ] Read cleanup config
  - Config file: `config.json` in data root
  - Schema:
    ```json
    {
      "temp_retention_policy": "1_week",
      "recording_retention_policy": "never",
      "processing_interval_minutes": 5,
      "default_fps": 30,
      "segment_duration_seconds": 5
    }
    ```
  - Defaults:
    - temp_retention_policy: "1_week" (keep temp files for 7 days)
    - recording_retention_policy: "never" (keep recordings forever)
  - Validation:
    - Policy must be one of: "never", "1_day", "1_week", "1_month"
    - Invalid policy: Log warning, use default
    - Missing config.json: Use all defaults, create file
  - Policy duration mapping:
    - "1_day": 86400 seconds (24 hours)
    - "1_week": 604800 seconds (7 days)
    - "1_month": 2592000 seconds (30 days)
    - "never": No cleanup (skip cleanup functions)

### LaunchAgent Configuration
- [ ] Create plist file
  - Location: `~/Library/LaunchAgents/com.playback.processing.plist`
  - Full plist structure:
    ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>com.playback.processing</string>

      <key>ProgramArguments</key>
      <array>
        <string>/usr/bin/python3</string>
        <string>/path/to/src/scripts/build_chunks_from_temp.py</string>
        <string>--auto</string>
      </array>

      <key>StartInterval</key>
      <integer>300</integer>

      <key>RunAtLoad</key>
      <true/>

      <key>StandardOutPath</key>
      <string>/Users/username/Library/Logs/Playback/processing.stdout.log</string>

      <key>StandardErrorPath</key>
      <string>/Users/username/Library/Logs/Playback/processing.stderr.log</string>

      <key>ProcessType</key>
      <string>Background</string>

      <key>Nice</key>
      <integer>10</integer>

      <key>LowPriorityIO</key>
      <true/>

      <key>EnvironmentVariables</key>
      <dict>
        <key>PLAYBACK_CONFIG</key>
        <string>/Users/username/Library/Application Support/Playback/data/config.json</string>
      </dict>
    </dict>
    </plist>
    ```
  - Installation:
    - Copy plist to `~/Library/LaunchAgents/`
    - Set permissions: `chmod 644 com.playback.processing.plist`
    - Load: `launchctl load ~/Library/LaunchAgents/com.playback.processing.plist`
  - Key fields:
    - Label: Unique identifier for LaunchAgent
    - ProgramArguments: Full path to python3 + script + --auto flag
    - StartInterval: Seconds between runs (300 = 5 minutes)
    - RunAtLoad: Start immediately when loaded

- [ ] Configure logging
  - StandardOutPath: `~/Library/Logs/Playback/processing.stdout.log`
  - StandardErrorPath: `~/Library/Logs/Playback/processing.stderr.log`
  - Create log directory on first run:
    ```python
    log_dir = Path.home() / "Library/Logs/Playback"
    log_dir.mkdir(parents=True, exist_ok=True)
    ```
  - Log rotation:
    - Not handled by LaunchAgent (logs append forever)
    - Implement manual rotation or use newsyslog
    - Example newsyslog.conf entry:
      ```
      /Users/*/Library/Logs/Playback/*.log 644 5 1000 * J
      ```

- [ ] Configure process priority
  - ProcessType: Background
    - Runs at lower priority than user-interactive apps
    - Allows system to throttle if resources constrained
  - Nice: 10 (lower CPU priority)
    - Range: -20 (highest) to 20 (lowest)
    - 10 = significantly lower than default (0)
    - Prevents processing from impacting user experience
  - LowPriorityIO: true (reduce disk I/O priority)
    - Disk reads/writes deprioritized
    - Prevents stuttering in other apps during video encoding
    - Critical for user experience during active recording

- [ ] Add environment variables
  - PLAYBACK_CONFIG: Path to config.json
  - Resolved at runtime by LaunchAgent
  - Used by script to find data root
  - Alternative: Hard-code production path in script

- [ ] Support dynamic interval changes
  - Use plutil to update StartInterval in plist:
    ```bash
    plutil -replace StartInterval -integer 600 ~/Library/LaunchAgents/com.playback.processing.plist
    ```
  - Reload LaunchAgent to apply changes:
    ```bash
    launchctl unload ~/Library/LaunchAgents/com.playback.processing.plist
    launchctl load ~/Library/LaunchAgents/com.playback.processing.plist
    ```
  - Called from settings UI when user changes interval
  - Validation: Interval must be 60-3600 seconds (1 minute to 1 hour)
  - Implementation notes:
    - Changes take effect on next scheduled run
    - Current run not interrupted
    - Use launchctl list to verify reload succeeded

### Error Handling
- [ ] Handle FFmpeg failures
  - Catch subprocess.CalledProcessError (non-zero exit code)
  - Log ERROR level with:
    - FFmpeg command executed
    - Exit code
    - stderr output (last 500 chars)
    - Segment details (frame count, resolution, duration)
  - Skip failed segment (do not insert into database)
  - Continue with remaining segments in day
  - Mark day as partially processed (affects exit code)
  - Common FFmpeg errors:
    - Corrupted PNG file: Skip segment
    - Unsupported pixel format: Check ffprobe output
    - Out of memory: Reduce segment size
  - Recovery:
    - Partial success: Exit code 1
    - Reprocessing same day will retry failed segments

- [ ] Handle disk full errors
  - Detection:
    - Catch OSError with errno.ENOSPC during file write
    - Check available space before encoding: `shutil.disk_usage()`
  - Response:
    1. Log CRITICAL error with:
       - Available disk space
       - Required space estimate
       - Current operation (video encoding, frame copy, etc.)
    2. Show macOS notification:
       ```python
       os.system('osascript -e \'display notification "Disk full. Free up space and try again." with title "Playback Processing Failed"\'')
       ```
    3. Clean up partial files (incomplete video, temp frames)
    4. Exit with code 2 (critical failure)
  - Prevention:
    - Check disk space before processing day
    - Minimum required: 1GB free
    - Log WARNING if space < 5GB

- [ ] Handle missing frames
  - Detection: Day directory exists but contains no valid PNG files
  - Response:
    - Log INFO level: "No frames found for {day}, skipping"
    - Skip day without error (not a failure)
    - Continue with remaining days
    - Do not affect exit code
  - Normal scenarios:
    - Recording disabled for entire day
    - Day directory created but recording never started
    - All frames already processed and cleaned up
  - Edge cases:
    - Hidden files only (.DS_Store): Treat as no frames
    - Subdirectories: Ignore (frames must be directly in DD/)

- [ ] Handle invalid images
  - Detection: ffprobe returns non-zero exit code or invalid output
  - Response:
    - Log WARNING level with:
      - File path
      - ffprobe error message
      - File size (for debugging)
    - Skip frame (exclude from segment)
    - Continue with remaining frames
  - Causes:
    - Corrupted PNG (incomplete write during capture)
    - Wrong file extension (not actually PNG)
    - Permission issues (rare with own files)
  - Prevention:
    - Validate frame after capture (in capture service)
    - Verify PNG signature (first 8 bytes)

- [ ] Handle database schema issues
  - Detection:
    - Query sqlite_master for table schemas
    - Compare with expected schemas
    - Check for missing columns, wrong types
  - Schema version tracking:
    - Create metadata table:
      ```sql
      CREATE TABLE IF NOT EXISTS _metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
      ```
    - Store schema_version: "1" (current)
  - Migration logic:
    - If schema_version missing: Assume version 0, migrate to 1
    - If schema_version < current: Run migration scripts
    - If schema_version > current: CRITICAL error (newer version, unsupported)
  - Response to mismatch:
    1. Log CRITICAL error with versions
    2. Attempt automatic migration (if supported)
    3. If migration fails or unsupported:
       - Exit with code 2
       - Show notification: "Playback database needs update. Please reinstall."
    4. If migration succeeds:
       - Log INFO: "Database migrated from v{old} to v{new}"
       - Update schema_version
       - Continue processing

### Logging and Metrics
- [ ] Implement structured logging
  - Format: JSON lines (one JSON object per line)
  - Location: `~/Library/Logs/Playback/processing.log`
  - Schema:
    ```json
    {
      "timestamp": "2026-02-07T14:32:15.123Z",
      "level": "INFO",
      "component": "processing",
      "message": "Day processing completed",
      "metadata": {
        "day": "20260207",
        "segments_generated": 42,
        "duration_ms": 12450,
        "cpu_avg_percent": 72.3,
        "memory_peak_mb": 387.2
      }
    }
    ```
  - Implementation:
    - Use Python logging module with custom formatter
    - Configure handler: `logging.FileHandler(log_path)`
    - Set level: DEBUG for development, INFO for production
    - Rotate logs: Use TimedRotatingFileHandler (daily, keep 30 days)
  - Fields:
    - timestamp: ISO 8601 with milliseconds and timezone
    - level: DEBUG, INFO, WARNING, ERROR, CRITICAL
    - component: "processing" (or subcomponent like "ffmpeg", "database")
    - message: Human-readable event description
    - metadata: Dictionary with event-specific data (optional)

- [ ] Log key events
  - Processing started:
    ```json
    {"level": "INFO", "message": "Processing started", "metadata": {"mode": "auto", "days_to_process": 3}}
    ```
  - Day processing started:
    ```json
    {"level": "INFO", "message": "Day processing started", "metadata": {"day": "20260207", "frame_count": 1247}}
    ```
  - Segment generated:
    ```json
    {"level": "DEBUG", "message": "Segment generated", "metadata": {"segment_id": "a1b2c3d4e5f6g7h8i9j0", "frame_count": 150, "duration_ms": 5000, "file_size_mb": 7.3, "resolution": "1920x1080"}}
    ```
  - Day processing completed:
    ```json
    {"level": "INFO", "message": "Day processing completed", "metadata": {"day": "20260207", "segments_generated": 42, "duration_ms": 12450, "cpu_avg_percent": 72.3, "memory_peak_mb": 387.2, "disk_read_mb": 124.5, "disk_write_mb": 306.7}}
    ```
  - Processing completed:
    ```json
    {"level": "INFO", "message": "Processing completed", "metadata": {"days_processed": 3, "total_segments": 128, "total_duration_ms": 38920}}
    ```
  - Cleanup completed:
    ```json
    {"level": "INFO", "message": "Cleanup completed", "metadata": {"temp_files_deleted": 1247, "temp_space_freed_mb": 623.5, "recordings_deleted": 0, "recording_space_freed_mb": 0.0}}
    ```
  - Errors with stack traces:
    ```json
    {"level": "ERROR", "message": "FFmpeg encoding failed", "metadata": {"segment_id": "abc...", "error": "Command failed with exit code 1", "stderr": "...", "stack_trace": "..."}}
    ```

- [ ] Collect resource metrics
  - Use psutil library for monitoring:
    ```python
    import psutil
    process = psutil.Process()
    ```
  - Metrics to collect per day:
    - Duration: Start time to end time (milliseconds)
    - CPU average: `process.cpu_percent(interval=1)` sampled throughout
    - Memory peak: Max of `process.memory_info().rss / (1024*1024)` MB
    - Disk I/O:
      - Read MB: `io_counters().read_bytes / (1024*1024)`
      - Write MB: `io_counters().write_bytes / (1024*1024)`
  - Sampling strategy:
    - CPU: Sample every 5 seconds during processing, average at end
    - Memory: Track high-water mark, update on each sample
    - Disk I/O: Measure at start and end of day, calculate delta
  - Log with day completion event (see above)
  - Performance baselines (for monitoring regressions):
    - 1000 frames typical day: 20-30 seconds
    - CPU usage: 60-80% during encoding
    - Memory peak: 300-500 MB
    - Disk read: ~500 MB (1000 frames × 500KB avg)
    - Disk write: ~300 MB (70-90% compression)

### Manual Mode Support
- [ ] Implement manual trigger
  - CLI: `python3 build_chunks_from_temp.py --day YYYYMMDD`
  - Process only specified day (single day, not auto-discovery)
  - Workflow:
    1. Validate day format (YYYYMMDD)
    2. Check if temp/YYYYMM/DD/ exists
    3. Load frames for day
    4. Generate segments (same logic as auto mode)
    5. Update database
    6. Skip cleanup (preserve temp files for debugging)
  - Do NOT cleanup temp files (preserve originals for manual inspection)
  - Update database normally (same as auto mode)
  - Exit codes:
    - 0: Day processed successfully
    - 1: Partial success (some segments failed)
    - 2: Complete failure or critical error
  - Use cases:
    - Reprocess corrupted day
    - Test processing without waiting for schedule
    - Debug specific date with verbose logging
  - Example:
    ```bash
    python3 build_chunks_from_temp.py --day 20260207 --verbose
    ```

- [ ] Support launchctl manual trigger
  - Command: `launchctl start com.playback.processing`
  - Behavior:
    - Runs immediately outside schedule (doesn't wait for StartInterval)
    - Uses same --auto mode (processes all unprocessed days)
    - Cleanup policies applied normally
    - Next scheduled run unaffected
  - Use cases:
    - Force immediate processing after bulk import
    - Trigger processing from UI button
    - Test LaunchAgent configuration
  - Verification:
    ```bash
    launchctl list | grep com.playback.processing
    tail -f ~/Library/Logs/Playback/processing.stdout.log
    ```
  - Alternative manual triggers:
    - `launchctl kickstart -k gui/$(id -u)/com.playback.processing` (restart if running)
    - Direct python execution (not via LaunchAgent)

### Dependencies and Requirements
- [ ] Verify FFmpeg installation
  - Check: `which ffmpeg` (should return `/usr/local/bin/ffmpeg` or `/opt/homebrew/bin/ffmpeg`)
  - Required version: 4.0+ (5.0+ recommended)
  - Required codecs:
    - libx264 (H.264 encoding): `ffmpeg -codecs | grep 264`
    - libx265 (HEVC encoding, optional): `ffmpeg -codecs | grep 265`
  - Installation via Homebrew:
    ```bash
    brew install ffmpeg
    ```
  - Verification:
    ```bash
    ffmpeg -version
    ffmpeg -codecs | grep -E "(264|265)"
    ```
  - Expected output includes:
    ```
    DEV.LS h264     H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10 (encoders: libx264 libx264rgb)
    ```
  - Troubleshooting:
    - Command not found: Add Homebrew bin to PATH
    - Missing libx264: Reinstall ffmpeg with `--with-x264`
    - Permission denied: Check file permissions

- [ ] Install Python dependencies
  - Required Python version: 3.8+ (3.10+ recommended)
  - Standard library modules (no installation needed):
    - subprocess: Run FFmpeg commands
    - sqlite3: Database operations
    - pathlib: Cross-platform path handling
    - dataclasses: FrameInfo structure
    - argparse: CLI argument parsing
    - tempfile: Temporary directories for encoding
    - shutil: File operations, disk usage
    - json: Config file parsing
    - os: File system operations
    - secrets: Random ID generation
    - logging: Structured logging
  - Optional dependencies:
    - psutil: Resource monitoring (CPU, memory, disk I/O)
      ```bash
      pip3 install psutil
      ```
    - If psutil unavailable: Skip resource metrics, log warning
  - Dependency management:
    - No requirements.txt needed (standard library only)
    - psutil optional, gracefully degrade if missing
    - Consider vendoring psutil for production

- [ ] Verify system requirements
  - Operating system: macOS 12.0+ (Monterey or later)
    - Check: `sw_vers -productVersion`
    - Minimum: 12.0 (required for AVFoundation APIs)
    - Recommended: 13.0+ (Ventura, better performance)
  - SQLite version: 3.35+ (system version)
    - Check: `sqlite3 --version`
    - Required for WAL mode improvements
    - macOS 12+ ships with SQLite 3.37+
  - Disk space requirements:
    - Minimum free: 1GB (for processing)
    - Recommended: 10GB+ (for typical usage)
    - Calculation per day:
      - Temp frames: ~1000 frames × 500KB = 500MB
      - Chunks: ~500MB × 0.15 compression = 75MB
      - Overhead: ~25MB for temporary encoding files
      - Total per day: ~600MB (reduced to ~75MB after cleanup)
  - CPU requirements:
    - Minimum: Intel Core i5 or Apple M1
    - Recommended: Apple M1 Pro/Max or Intel Core i7+
    - Video encoding is CPU-intensive (60-80% usage)
  - Memory requirements:
    - Minimum: 4GB RAM
    - Recommended: 8GB+ RAM
    - Peak usage: ~500MB per processing run

## Processing Pipeline Details

This section provides comprehensive technical details about the processing pipeline implementation.

### Shared Utilities

Processing service uses common functionality from `src/lib/`:

- **Path resolution** (`src/lib/paths.py`) - Environment-aware path resolution for dev/prod
- **Database operations** (`src/lib/database.py`) - SQLite access and schema management
- **Video processing** (`src/lib/video.py`) - FFmpeg wrappers for video generation
- **Timestamp handling** (`src/lib/timestamps.py`) - Filename parsing and generation

These utilities consolidate logic previously duplicated across scripts, ensuring consistent behavior across recording and processing services.

### Frame Scanning and Validation Logic

**Frame Discovery Process:**
1. Scan `temp/YYYYMM/DD/` directory for PNG files
2. For each file, extract metadata:
   - Filename format: `<timestamp_ms>_<app_id>.png` or `<timestamp_ms>.png`
   - Use st_birthtime (file creation time) as authoritative timestamp
   - Parse app_id from filename (optional, may be None)
3. Validate frame with ffprobe:
   ```bash
   ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 <file>
   ```
   - Expected output: `1920x1080` (width × height)
   - Non-zero exit code or invalid output: Skip frame, log warning
4. Create FrameInfo object with metadata
5. Sort all frames by st_birthtime ascending

**Validation Rules:**
- File must have .png extension (case-insensitive)
- File must be regular file (not directory, symlink, device)
- File must not start with . (hidden files like .DS_Store)
- File must have valid dimensions from ffprobe (non-zero width and height)
- Files failing validation are skipped with WARNING log, processing continues

**Edge Cases:**
- Empty directory: Log INFO "No frames found", skip day without error
- All frames invalid: Log WARNING "No valid frames", skip day without error
- Mixed valid/invalid frames: Process valid frames only, log skipped count
- Duplicate timestamps: Allowed, sorted by st_birthtime (filesystem handles uniqueness)

### Segmentation Algorithm (5-second chunks)

**Algorithm Overview:**
The segmentation algorithm groups frames into 5-second video segments, breaking on resolution changes, large gaps, or frame count limits.

**Detailed Steps:**
```python
def group_frames_by_count(frames: List[FrameInfo], max_frames: int) -> List[List[FrameInfo]]:
    """
    Group frames into segments based on:
    1. Max frames per segment (fps × duration)
    2. Resolution changes (different monitors)
    3. Large gaps (60+ seconds between frames)
    """
    if not frames:
        return []

    segments = []
    current_segment = []

    for frame in frames:
        if not current_segment:
            # Start new segment
            current_segment.append(frame)
            continue

        prev_frame = current_segment[-1]

        # Check break conditions
        resolution_changed = (frame.width != prev_frame.width or
                             frame.height != prev_frame.height)
        large_gap = (frame.ts - prev_frame.ts) > 60000  # 60 seconds
        max_frames_reached = len(current_segment) >= max_frames

        if resolution_changed or large_gap or max_frames_reached:
            # Finalize current segment, start new one
            segments.append(current_segment)
            current_segment = [frame]
        else:
            # Continue current segment
            current_segment.append(frame)

    # Add final segment
    if current_segment:
        segments.append(current_segment)

    return segments
```

**Break Conditions Explained:**

1. **Resolution Change** (resolution_changed):
   - **Why**: Cannot mix different resolutions in single video file
   - **When**: User switches monitors, changes display resolution
   - **Example**: Frame at 1920×1080 followed by frame at 2560×1440
   - **Action**: Finalize segment at 1920×1080, start new segment at 2560×1440

2. **Large Gap** (large_gap > 60 seconds):
   - **Why**: Indicates recording stopped/started or significant user inactivity
   - **When**: Screen locked, computer sleep, recording disabled temporarily
   - **Rationale**: Gaps < 60s are normal (frame rate fluctuations, brief pauses)
   - **Example**: Frame at 14:32:15.123 followed by frame at 14:33:30.456 (75 seconds gap)
   - **Action**: Finalize segment before gap, start new segment after gap

3. **Max Frames Reached** (max_frames_reached):
   - **Why**: Limits segment size for performance and seekability
   - **Default**: 150 frames (30 fps × 5 seconds)
   - **Rationale**: 5-second segments balance file size, seeking precision, encoding overhead
   - **Example**: Segment reaches 150 frames at consistent 1920×1080 resolution
   - **Action**: Finalize segment at 150 frames, start new segment

**Segmentation Examples:**

*Example 1: Normal recording (single monitor, continuous)*
- Input: 450 frames at 1920×1080, 30 fps, no gaps > 60s
- Output: 3 segments (150 frames each, 5 seconds each)

*Example 2: Monitor switch*
- Input: 100 frames at 1920×1080, then 200 frames at 2560×1440
- Output: 2 segments
  - Segment 1: 100 frames at 1920×1080
  - Segment 2: 150 frames at 2560×1440
  - Segment 3: 50 frames at 2560×1440

*Example 3: Recording gap*
- Input: 150 frames, then 90-second gap, then 150 frames
- Output: 2 segments (gap triggers break)

### FFmpeg Command with Exact Parameters

**Complete FFmpeg Command:**
```bash
ffmpeg -y \
  -framerate 30 \
  -pattern_type glob -i '/tmp/processing_abc123/frame_*.png' \
  -c:v libx264 \
  -preset veryfast \
  -crf 28 \
  -pix_fmt yuv420p \
  -movflags +faststart \
  '/path/to/chunks/202602/07/a1b2c3d4e5f6g7h8i9j0.mp4'
```

**Parameter Breakdown:**

- **`-y`**: Overwrite output file without prompting
  - Required for scripting (non-interactive)
  - Safe because output path is unique (random segment ID)

- **`-framerate 30`**: Input frame rate (30 frames per second)
  - Defines playback speed of output video
  - Configurable: Default 30, can be 15-60
  - Higher FPS: Smoother playback, larger files
  - Lower FPS: Choppier playback, smaller files

- **`-pattern_type glob -i 'frame_*.png'`**: Input specification
  - Uses glob pattern to match frame files
  - Frames must be named sequentially: frame_00001.png, frame_00002.png, etc.
  - Alternative: Use concat demuxer with file list

- **`-c:v libx264`**: Video codec (H.264)
  - Choice rationale:
    - Universal compatibility (QuickTime, browsers, mobile)
    - Good compression ratio (70-90% reduction)
    - Hardware acceleration on most platforms
    - Alternative: libx265 (HEVC) has better compression but compatibility issues
  - Requires ffmpeg built with libx264 support

- **`-preset veryfast`**: Encoding speed preset
  - Presets (slowest to fastest): veryslow, slower, slow, medium, fast, faster, veryfast, superfast, ultrafast
  - Choice rationale:
    - veryfast: ~10 seconds for 150 frames (5-second video)
    - medium: ~25 seconds for same video (2.5× slower)
    - Compression penalty: ~15% larger files vs medium
    - User experience: Processing keeps up with recording rate
  - Tradeoff: Speed vs compression (acceptable for screen recordings)

- **`-crf 28`**: Constant Rate Factor (quality level)
  - Range: 0 (lossless) to 51 (worst quality)
  - Choice rationale:
    - 28: Visually lossless for screen recordings
    - Screen content: Text, UI elements, high contrast
    - Lower CRF: Unnecessarily large files (CRF 18-23 for photography)
    - Higher CRF: Visible artifacts in text
  - Typical results: 75MB PNG → 7.5MB MP4 (90% compression)

- **`-pix_fmt yuv420p`**: Pixel format (YUV 4:2:0)
  - Choice rationale:
    - Required for QuickTime Player and AVFoundation compatibility
    - Alternative yuv444p: Better quality, incompatible with macOS native playback
    - Compatibility: Works with all browsers, mobile devices
  - Color accuracy: Sufficient for screen recordings (not photography)

- **`-movflags +faststart`**: MP4 optimization
  - Moves moov atom (metadata) to beginning of file
  - Enables streaming playback (start before full download)
  - Required for web playback and seeking
  - Small overhead: ~0.1s extra encoding time

**Output File:**
- Format: MP4 container (MPEG-4 Part 14)
- Extension: .mp4 (required for macOS compatibility)
- Path: `chunks/YYYYMM/DD/<segment_id>.mp4`
- Segment ID: 20-character hex string from `secrets.token_hex(10)`

**Performance Characteristics:**
- Encoding time: ~10 seconds for 150 frames (5-second video) on M1 Pro
- CPU usage: 60-80% of one core (libx264 is single-threaded per encode)
- Memory usage: ~50MB peak per encode
- Disk I/O: Read 75MB PNG, write 7.5MB MP4 (typical compression)

### Database Schema Details

**Database File:**
- Location: `meta.sqlite3` in data root
- Format: SQLite 3.35+
- Configuration:
  ```sql
  PRAGMA journal_mode=WAL;  -- Write-Ahead Logging for concurrency
  PRAGMA foreign_keys=ON;    -- Enforce referential integrity
  PRAGMA cache_size=-64000;  -- 64MB cache for performance
  ```

**segments Table (Video Metadata):**
```sql
CREATE TABLE IF NOT EXISTS segments (
  id TEXT PRIMARY KEY,              -- Random 20-char hex (segment_id)
  date TEXT NOT NULL,               -- YYYYMMDD format
  start_ts INTEGER NOT NULL,        -- Start timestamp (milliseconds since epoch)
  end_ts INTEGER NOT NULL,          -- End timestamp (milliseconds since epoch)
  frame_count INTEGER NOT NULL,     -- Number of frames in segment
  fps INTEGER NOT NULL,             -- Frames per second (usually 30)
  width INTEGER NOT NULL,           -- Frame width in pixels
  height INTEGER NOT NULL,          -- Frame height in pixels
  file_size_bytes INTEGER NOT NULL, -- MP4 file size in bytes
  video_path TEXT NOT NULL,         -- Relative path: chunks/YYYYMM/DD/id.mp4
  created_at INTEGER DEFAULT (strftime('%s', 'now'))  -- Insert timestamp
);

CREATE INDEX IF NOT EXISTS idx_segments_date ON segments(date);
CREATE INDEX IF NOT EXISTS idx_segments_start_ts ON segments(start_ts);
CREATE INDEX IF NOT EXISTS idx_segments_end_ts ON segments(end_ts);
```

**Field Descriptions:**
- **id**: Unique identifier, same as MP4 filename (without extension)
- **date**: Recording date for quick day-based queries
- **start_ts/end_ts**: Timestamp range for timeline queries
- **frame_count**: Number of original PNG frames (not video frames after encoding)
- **fps**: Output video frame rate (configurable, default 30)
- **width/height**: Frame dimensions (resolution)
- **file_size_bytes**: Actual MP4 file size for storage tracking
- **video_path**: Relative path for file access (prepend data root)
- **created_at**: Database insert time for auditing

**appsegments Table (App Activity Timeline):**
```sql
CREATE TABLE IF NOT EXISTS appsegments (
  id TEXT PRIMARY KEY,              -- Random 20-char hex (unique per appsegment)
  app_id TEXT,                      -- Application bundle ID (e.g., com.apple.Safari) or NULL
  date TEXT NOT NULL,               -- YYYYMMDD format
  start_ts INTEGER NOT NULL,        -- Segment start timestamp (milliseconds)
  end_ts INTEGER NOT NULL,          -- Segment end timestamp (milliseconds)
  created_at INTEGER DEFAULT (strftime('%s', 'now'))  -- Insert timestamp
);

CREATE INDEX IF NOT EXISTS idx_appsegments_app_id ON appsegments(app_id);
CREATE INDEX IF NOT EXISTS idx_appsegments_date ON appsegments(date);
CREATE INDEX IF NOT EXISTS idx_appsegments_start_ts ON appsegments(start_ts);
CREATE INDEX IF NOT EXISTS idx_appsegments_end_ts ON appsegments(end_ts);
```

**Field Descriptions:**
- **id**: Unique identifier for appsegment (different from segment ID)
- **app_id**: Application bundle ID or NULL (unknown/locked screen)
- **date**: Recording date for quick day-based queries
- **start_ts/end_ts**: Time range when app was active
- **created_at**: Database insert time for auditing

**Schema Version Tracking:**
```sql
CREATE TABLE IF NOT EXISTS _metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT OR REPLACE INTO _metadata (key, value) VALUES ('schema_version', '1');
```

**Query Examples:**

*Find all segments for a specific day:*
```sql
SELECT * FROM segments WHERE date = '20260207' ORDER BY start_ts;
```

*Find segments in a time range:*
```sql
SELECT * FROM segments
WHERE start_ts >= 1707321600000 AND end_ts <= 1707325200000
ORDER BY start_ts;
```

*Calculate storage used per day:*
```sql
SELECT date, SUM(file_size_bytes) / (1024*1024) as size_mb, COUNT(*) as segment_count
FROM segments
GROUP BY date
ORDER BY date DESC;
```

*Find app usage for a day:*
```sql
SELECT app_id,
       SUM(end_ts - start_ts) / 1000 as duration_seconds,
       COUNT(*) as session_count
FROM appsegments
WHERE date = '20260207' AND app_id IS NOT NULL
GROUP BY app_id
ORDER BY duration_seconds DESC;
```

### Cleanup Policy Implementation

**Cleanup Overview:**
Two independent cleanup policies control data retention:
1. **Temp File Cleanup**: Deletes original PNG frames after processing
2. **Recording Cleanup**: Deletes old MP4 videos and database entries

**Policy Options:**
- `"never"`: No cleanup (keep forever)
- `"1_day"`: Delete after 24 hours (86400 seconds)
- `"1_week"`: Delete after 7 days (604800 seconds)
- `"1_month"`: Delete after 30 days (2592000 seconds)

**Temp File Cleanup Implementation:**

```python
def cleanup_temp_files(day: str, policy: str, conn: sqlite3.Connection, data_root: Path):
    """
    Delete PNG frames for a specific day based on retention policy.
    Only deletes files successfully processed (in database).
    """
    if policy == "never":
        return

    # Calculate cutoff timestamp
    policy_seconds = {"1_day": 86400, "1_week": 604800, "1_month": 2592000}
    cutoff_ts = int(time.time() * 1000) - (policy_seconds[policy] * 1000)

    # Get all segments for this day
    cursor = conn.execute(
        "SELECT start_ts, end_ts FROM segments WHERE date = ? ORDER BY start_ts",
        (day,)
    )
    segments = cursor.fetchall()

    if not segments:
        # No segments in database, don't delete anything
        return

    # Find temp files for this day
    temp_dir = data_root / "temp" / day[:6] / day[6:]
    if not temp_dir.exists():
        return

    deleted_count = 0
    space_freed = 0

    for file_path in temp_dir.glob("*.png"):
        # Check if file is old enough
        file_stat = file_path.stat()
        file_ts = int(file_stat.st_birthtime * 1000)

        if file_ts > cutoff_ts:
            continue  # Too recent, skip

        # Verify file was processed (in a segment)
        processed = any(
            start_ts <= file_ts <= end_ts
            for start_ts, end_ts in segments
        )

        if not processed:
            # Not in database, don't delete (may be unprocessed)
            continue

        # Delete file
        try:
            file_size = file_path.stat().st_size
            file_path.unlink()
            deleted_count += 1
            space_freed += file_size
        except OSError as e:
            logging.warning(f"Failed to delete {file_path}: {e}")

    # Remove empty directories
    if not any(temp_dir.iterdir()):
        temp_dir.rmdir()
        month_dir = temp_dir.parent
        if not any(month_dir.iterdir()):
            month_dir.rmdir()

    if deleted_count > 0:
        space_mb = space_freed / (1024 * 1024)
        logging.info(f"Cleaned up {deleted_count} temp files for {day}, freed {space_mb:.1f}MB")
```

**Recording Cleanup Implementation:**

```python
def cleanup_old_recordings(policy: str, conn: sqlite3.Connection, data_root: Path):
    """
    Delete old MP4 recordings and database entries based on retention policy.
    """
    if policy == "never":
        return

    # Calculate cutoff timestamp
    policy_seconds = {"1_day": 86400, "1_week": 604800, "1_month": 2592000}
    cutoff_ts = int(time.time() * 1000) - (policy_seconds[policy] * 1000)

    # Find old segments
    cursor = conn.execute(
        "SELECT id, video_path, file_size_bytes FROM segments WHERE end_ts < ?",
        (cutoff_ts,)
    )
    old_segments = cursor.fetchall()

    deleted_count = 0
    space_freed = 0

    # Begin transaction for atomic cleanup
    conn.execute("BEGIN")

    try:
        for segment_id, video_path, file_size in old_segments:
            # Delete video file
            video_file = data_root / video_path

            if video_file.exists():
                try:
                    video_file.unlink()
                    space_freed += file_size
                except OSError as e:
                    logging.warning(f"Failed to delete {video_file}: {e}")
                    continue

            # Delete database row
            conn.execute("DELETE FROM segments WHERE id = ?", (segment_id,))
            deleted_count += 1

        # Delete old appsegments
        conn.execute("DELETE FROM appsegments WHERE end_ts < ?", (cutoff_ts,))

        # Commit transaction
        conn.commit()

        # Vacuum to reclaim space
        conn.execute("VACUUM")

        if deleted_count > 0:
            space_mb = space_freed / (1024 * 1024)
            logging.info(f"Cleaned up {deleted_count} recordings, freed {space_mb:.1f}MB")

    except Exception as e:
        conn.rollback()
        logging.error(f"Recording cleanup failed: {e}")
        raise
```

**Cleanup Execution Flow:**
1. Auto mode processing completes for day
2. Check temp_retention_policy from config
3. If policy != "never", call `cleanup_temp_files(day, policy, conn, data_root)`
4. After all days processed, check recording_retention_policy
5. If policy != "never", call `cleanup_old_recordings(policy, conn, data_root)`

**Safety Guarantees:**
- Only deletes files successfully in database (no data loss)
- Atomic transactions for recording cleanup (all-or-nothing)
- Verifies file paths (prevents accidental deletion outside temp/chunks)
- Graceful error handling (logs warnings, continues)
- Manual mode skips cleanup (preserves temp files for debugging)

**Storage Impact Examples:**

*Typical day (1000 frames):*
- Before processing: 500MB (temp PNG files)
- After processing: 500MB temp + 75MB chunks = 575MB
- After temp cleanup (1_week policy): 75MB (chunks only)
- After recording cleanup (1_month policy): 0MB

*30 days with 1_week temp cleanup:*
- Temp: Last 7 days only (~3.5GB)
- Chunks: All 30 days (~2.25GB)
- Total: ~5.75GB

*30 days with 1_week temp cleanup and 1_month recording cleanup:*
- Temp: Last 7 days (~3.5GB)
- Chunks: Last 30 days (~2.25GB)
- Total: ~5.75GB (same, but auto-deletes after 30 days)

## Testing Checklist

### Unit Tests
- [ ] Test frame loading from temp directory
  - Verify timestamp extraction from filenames
  - Verify app_id extraction from filenames
  - Verify dimension detection via ffprobe
  - Test with missing/corrupted files

- [ ] Test segmentation logic
  - Verify max frames per segment enforcement
  - Verify resolution change triggers new segment
  - Verify 60+ second gap triggers new segment
  - Test with mixed resolutions (multiple monitors)

- [ ] Test app segment generation
  - Verify grouping by consecutive app_id
  - Verify app change creates new segment
  - Verify handling of None app_id
  - Test with single-app and multi-app days

- [ ] Test retention policies
  - Verify age thresholds (1_day, 1_week, 1_month)
  - Verify "never" policy skips cleanup
  - Verify only processed files are deleted
  - Test disk space calculation

- [ ] Test database operations
  - Verify schema creation
  - Verify segment insertion and retrieval
  - Verify app segment insertion and retrieval
  - Test INSERT OR REPLACE idempotency

### Integration Tests
- [ ] Test full processing cycle
  - Create mock temp files
  - Run processing in auto mode
  - Verify video generation in chunks/
  - Verify database populated correctly
  - Verify cleanup applied

- [ ] Test FFmpeg failure handling
  - Mock FFmpeg to return non-zero exit
  - Verify segment skipped
  - Verify processing continues
  - Verify partial success exit code

- [ ] Test disk full scenario
  - Mock filesystem full during video write
  - Verify critical error logged
  - Verify notification shown
  - Verify exit code 2

- [ ] Test database write failure
  - Mock SQLite write failure
  - Verify retry mechanism
  - Verify graceful skip on retry failure
  - Verify exit code 2 on multiple failures

- [ ] Test LaunchAgent integration
  - Install plist file
  - Verify scheduled execution
  - Verify logging to correct paths
  - Verify unload/reload on config change

### Performance Tests
- [ ] Benchmark 1000 frames (typical day)
  - Measure processing time
  - Verify under 30 seconds
  - Monitor CPU usage (should be 60-80% during encoding)
  - Monitor memory usage (should peak under 500MB)

- [ ] Benchmark 10-day backlog
  - Measure total processing time
  - Verify under 5 minutes
  - Monitor resource usage throughout
  - Verify no memory leaks

- [ ] Test memory usage
  - Process multiple segments
  - Verify memory released between segments
  - Monitor for leaks during cleanup

- [ ] Test disk I/O efficiency
  - Measure read/write volumes
  - Verify 70-90% compression ratio
  - Verify low-priority I/O setting effective

### Manual Testing
- [ ] Test manual mode
  - Run: `python3 src/scripts/build_chunks_from_temp.py --day YYYYMMDD`
  - Verify only specified day processed
  - Verify temp files NOT deleted
  - Verify database updated

- [ ] Test dynamic interval changes
  - Change interval via settings UI
  - Verify plist updated
  - Verify LaunchAgent reloaded
  - Verify new schedule takes effect

- [ ] Test multiple monitor handling
  - Record on different monitors
  - Verify segments split by resolution
  - Verify all resolutions preserved in videos

- [ ] Test recording gaps
  - Create 60+ second gap in frames
  - Verify new segment created
  - Verify timestamps correct in database
