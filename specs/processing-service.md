# Processing Service Specification

**Component:** Processing Service (Python)
**Version:** 1.0
**Last Updated:** 2026-02-07

## Overview

The Processing Service is a Python script that runs periodically as a macOS LaunchAgent, converting raw screenshots from the `temp/` directory into compressed video segments in the `chunks/` directory. It maintains a SQLite database with segment metadata and optionally cleans up processed files.

## Responsibilities

1. Run automatically every 5 minutes (configurable)
2. Scan `temp/` directory for unprocessed screenshots
3. Group screenshots by day and segment duration (5 seconds @ 30fps)
4. Generate H.264/MP4 videos using FFmpeg
5. Update SQLite database with segment and app segment metadata
6. Track and log resource utilization (CPU, memory, duration)
7. Optionally delete processed temp files based on retention policy
8. Handle errors gracefully without blocking future runs

## LaunchAgent Configuration

### Plist File

**Location:** `~/Library/LaunchAgents/com.playback.processing.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.playback.processing</string>

    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>/Applications/Playback.app/Contents/Resources/scripts/build_chunks_from_temp.py</string>
        <string>--auto</string>
    </array>

    <key>StartInterval</key>
    <integer>300</integer>  <!-- 300 seconds = 5 minutes -->

    <key>RunAtLoad</key>
    <true/>  <!-- Run once immediately when loaded -->

    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/Playback/processing.stdout.log</string>

    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/Playback/processing.stderr.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PLAYBACK_CONFIG</key>
        <string>$HOME/Library/Application Support/Playback/config.json</string>
    </dict>

    <key>ProcessType</key>
    <string>Background</string>

    <key>Nice</key>
    <integer>10</integer>  <!-- Lower priority (higher nice value) -->

    <key>LowPriorityIO</key>
    <true/>  <!-- Reduce disk I/O priority -->
</dict>
</plist>
```

### Dynamic Interval Configuration

The `StartInterval` key is dynamically updated when user changes processing frequency in settings:

```bash
# User selects "Every 10 minutes" in settings
plutil -replace StartInterval -integer 600 ~/Library/LaunchAgents/com.playback.processing.plist
launchctl unload ~/Library/LaunchAgents/com.playback.processing.plist
launchctl load ~/Library/LaunchAgents/com.playback.processing.plist
```

### Loading/Unloading

**Enable Processing:**
```bash
launchctl load ~/Library/LaunchAgents/com.playback.processing.plist
```

**Disable Processing:**
```bash
launchctl unload ~/Library/LaunchAgents/com.playback.processing.plist
```

**Manual Trigger:**
```bash
launchctl start com.playback.processing
```

## Script Behavior

### Auto Mode

**Trigger:** LaunchAgent interval (default: 5 minutes)

**Workflow:**
1. Scan `temp/` for all days with unprocessed files
2. For each day:
   - Load all frames for that day
   - Process frames into video segments
   - Update database
   - Optionally cleanup temp files
3. Log metrics and exit

**Exit Codes:**
- `0`: Success (all days processed)
- `1`: Partial success (some days failed)
- `2`: Complete failure (no days processed)

### Manual Mode

**Trigger:** User command with explicit date

```bash
python3 build_chunks_from_temp.py --day 20251222
```

**Workflow:**
1. Process only the specified day
2. Update database
3. Do NOT cleanup temp files (manual mode preserves originals)
4. Log metrics and exit

### Day Detection

**Strategy:** Scan `temp/YYYYMM/` directories for subdirectories

```python
def find_unprocessed_days():
    days = []
    for yearmonth_dir in TEMP_ROOT.iterdir():
        if not yearmonth_dir.is_dir():
            continue
        for day_dir in yearmonth_dir.iterdir():
            if not day_dir.is_dir():
                continue
            # Check if day has unprocessed files
            if has_unprocessed_frames(day_dir):
                days.append(day_dir.name)  # e.g., "20251222"
    return sorted(days)
```

**Unprocessed Detection:**
- Check database for last processed timestamp for this day
- If any files have creation time > last processed time, day is unprocessed

### Frame Loading

**Function:** `load_frames_for_day(day: str) -> List[FrameInfo]`

**Process:**
1. Find directory: `temp/YYYYMM/DD/`
2. List all files in directory
3. For each file:
   - Extract timestamp from filename
   - Extract app ID from filename
   - Get image dimensions via `ffprobe`
   - Read file creation time (st_birthtime on macOS)
4. Sort frames by creation time (ascending)
5. Return list of FrameInfo objects

**Frame Info:**
```python
@dataclass
class FrameInfo:
    path: Path
    ts: float  # epoch seconds (from st_birthtime)
    app_id: Optional[str]
    width: Optional[int]
    height: Optional[int]
```

### Segmentation

**Strategy:** Group frames into fixed-duration segments

**Parameters:**
- `fps`: 30 (frames per second in output video)
- `segment_duration`: 5 seconds
- `max_frames_per_segment`: fps × segment_duration = 150 frames

**Function:** `group_frames_by_count(frames, max_frames_per_segment)`

**Rules:**
1. Group consecutive frames up to `max_frames_per_segment`
2. Start new segment if resolution changes (different monitor)
3. Start new segment if gap between frames > 60 seconds (recording stopped/started)

**Output:** List of frame groups, each representing one video segment

### Video Generation

**Function:** `run_ffmpeg_make_segment(frames, fps, crf, preset, dest_without_ext)`

**Process:**
1. Create temporary directory
2. Copy frames to temp dir with sequential names: `frame_00001.png`, `frame_00002.png`, ...
3. Run FFmpeg command:
   ```bash
   ffmpeg -y \
     -framerate 30 \
     -i frame_%05d.png \
     -c:v libx264 \
     -preset veryfast \
     -crf 28 \
     -pix_fmt yuv420p \
     output.mp4
   ```
4. Move output file to final location: `chunks/YYYYMM/DD/<id>.mp4`
5. Clean up temporary directory
6. Return file size and video dimensions

**Encoding Parameters:**
- **Codec:** H.264 (libx264) - Better compatibility than HEVC
- **Preset:** `veryfast` - Balance between speed and compression
- **CRF:** 28 - Constant Rate Factor (lower = better quality, larger files)
- **Pixel Format:** yuv420p - Maximum compatibility with QuickTime/AVPlayer

**Filename:** `<segment_id>.mp4` (e.g., `a3f8b29c.mp4`)

### Database Updates

**Tables:**

1. **segments** - Video segment metadata
2. **appsegments** - App activity timeline

**Segment Insert:**
```sql
INSERT OR REPLACE INTO segments
(id, date, start_ts, end_ts, frame_count, fps, width, height, file_size_bytes, video_path)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
```

**Fields:**
- `id`: Random hex string (10 bytes = 20 chars)
- `date`: ISO date string (e.g., "2025-12-22")
- `start_ts`: Timestamp of first frame (epoch seconds)
- `end_ts`: Timestamp of last frame (epoch seconds)
- `frame_count`: Number of frames in segment
- `fps`: Video framerate (30.0)
- `width`, `height`: Video dimensions
- `file_size_bytes`: Size of .mp4 file
- `video_path`: Relative path from data directory (e.g., "chunks/202512/22/a3f8b29c.mp4")

**App Segment Generation:**

Function: `build_appsegments_for_day(frames) -> List[(app_id, start_ts, end_ts)]`

**Strategy:**
1. Group consecutive frames with same app_id
2. Each app change creates new segment
3. Use actual frame timestamps (not video timestamps)

**App Segment Insert:**
```sql
INSERT OR REPLACE INTO appsegments
(id, app_id, date, start_ts, end_ts)
VALUES (?, ?, ?, ?, ?)
```

### Temp File Cleanup

**Configuration:**
```json
{
  "temp_retention_policy": "1_week"  // Options: "1_day", "1_week", "1_month", "never"
}
```

**Behavior:**
- After successful video generation, check retention policy
- If policy != "never":
  - Delete temp files older than policy threshold
  - Only delete files that have been successfully processed (exists in database)
- Log deletion count and freed disk space

**Implementation:**
```python
def cleanup_temp_files(day: str, policy: str):
    if policy == "never":
        return

    threshold = {
        "1_day": 86400,
        "1_week": 604800,
        "1_month": 2592000
    }[policy]

    now = time.time()
    day_dir = TEMP_ROOT / day[:6] / day[6:]

    for file in day_dir.iterdir():
        age = now - file.stat().st_mtime
        if age > threshold:
            # Check if file was processed (segment exists in DB)
            if is_processed(file):
                file.unlink()
                log(f"Deleted temp file: {file}")
```

### Recording Cleanup

**Configuration:**
```json
{
  "recording_retention_policy": "never"  // Options: "1_day", "1_week", "1_month", "never"
}
```

**Behavior:**
- After processing, check retention policy
- If policy != "never":
  - Find all segments older than threshold
  - Delete video files
  - Delete database rows
- Log deletion count and freed disk space

**Implementation:**
```python
def cleanup_old_recordings(policy: str):
    if policy == "never":
        return

    threshold = {
        "1_day": 86400,
        "1_week": 604800,
        "1_month": 2592000
    }[policy]

    cutoff_ts = time.time() - threshold

    # Query segments older than cutoff
    segments = db.query("SELECT * FROM segments WHERE start_ts < ?", cutoff_ts)

    for segment in segments:
        # Delete video file
        video_path = PLAYBACK_ROOT / segment.video_path
        if video_path.exists():
            video_path.unlink()

        # Delete database row
        db.execute("DELETE FROM segments WHERE id = ?", segment.id)

    log(f"Deleted {len(segments)} old segments")
```

## Logging

### Log File

**Location:** `~/Library/Logs/Playback/processing.log`

**Format:** Structured JSON lines

```json
{"timestamp": "2025-12-22T14:35:00Z", "level": "INFO", "component": "processing", "message": "Processing started", "metadata": {"mode": "auto", "days_to_process": 1}}
{"timestamp": "2025-12-22T14:35:02Z", "level": "INFO", "component": "processing", "message": "Day processing started", "metadata": {"day": "20251222", "frame_count": 3600}}
{"timestamp": "2025-12-22T14:35:45Z", "level": "INFO", "component": "processing", "message": "Segment generated", "metadata": {"segment_id": "a3f8b29c", "frame_count": 150, "duration_ms": 42340, "file_size_mb": 2.3}}
{"timestamp": "2025-12-22T14:36:30Z", "level": "INFO", "component": "processing", "message": "Day processing completed", "metadata": {"day": "20251222", "segments_generated": 24, "total_duration_ms": 85230, "cpu_avg": 65.2, "memory_peak_mb": 234.5}}
{"timestamp": "2025-12-22T14:36:30Z", "level": "INFO", "component": "processing", "message": "Processing completed", "metadata": {"days_processed": 1, "total_segments": 24, "total_duration_ms": 85230}}
```

### Logged Events

1. **Processing started**
   - Mode (auto/manual), days to process

2. **Day processing started**
   - Day, frame count, estimated duration

3. **Segment generated**
   - Segment ID, frame count, FFmpeg duration, file size

4. **Day processing completed**
   - Day, segments generated, total duration, resource usage

5. **Processing completed**
   - Days processed, total segments, total duration

6. **Cleanup completed**
   - Files deleted, disk space freed

7. **Error occurred**
   - Error type, details, stack trace

### Resource Metrics

**Collected per day:**
- Start time
- End time
- Total duration (seconds)
- CPU usage (average %)
- Memory usage (peak MB)
- Disk I/O (read MB, write MB)

**Collection Method:**
```python
import psutil
import time

process = psutil.Process()
start_time = time.time()
start_cpu = process.cpu_percent()
start_memory = process.memory_info().rss / 1024 / 1024

# ... process day ...

end_time = time.time()
end_cpu = process.cpu_percent()
end_memory = process.memory_info().rss / 1024 / 1024

metrics = {
    "duration_ms": (end_time - start_time) * 1000,
    "cpu_avg": (start_cpu + end_cpu) / 2,
    "memory_peak_mb": max(start_memory, end_memory)
}
```

## Error Handling

### FFmpeg Failure

**Scenario:** FFmpeg command returns non-zero exit code

**Behavior:**
1. Log error with stderr output
2. Skip this segment
3. Continue with remaining segments
4. Mark day as partially processed

**Recovery:** Manual re-run for failed day

### Database Write Failure

**Scenario:** SQLite INSERT fails (disk full, corruption)

**Behavior:**
1. Log error
2. Retry once after 1 second delay
3. If retry fails: Skip segment, continue
4. If multiple failures: Exit with code 2

**Recovery:** Manual intervention required (check disk space, repair database)

### Disk Full

**Scenario:** Video write fails due to no disk space

**Behavior:**
1. Log critical error with disk space info
2. Show macOS notification: "Playback processing failed: Disk full"
3. Exit with code 2
4. Next scheduled run will retry (may succeed if space freed)

### No Frames Found

**Scenario:** Day directory exists but contains no valid frames

**Behavior:**
1. Log warning: "No frames found for day X"
2. Skip day
3. Continue with remaining days

**Not an Error:** Normal if recording was disabled that day

### Image Dimension Detection Failure

**Scenario:** `ffprobe` fails to read image dimensions

**Behavior:**
1. Log warning: "Invalid image: X"
2. Skip frame
3. Continue with remaining frames

**Cause:** Corrupted PNG, partial write, non-image file

### Database Schema Mismatch

**Scenario:** Database schema version incompatible

**Behavior:**
1. Log critical error
2. Attempt automatic migration
3. If migration fails: Exit with code 2
4. Show notification: "Playback database needs migration"

**Recovery:** Run migration script manually

## Performance Characteristics

### Processing Time

**Depends on:**
- Number of frames
- Video resolution
- CPU speed
- Disk I/O speed

**Estimates:**
- 100 frames (single segment): 1-3 seconds
- 1000 frames (full day): 10-30 seconds
- 10000 frames (multiple days backlog): 2-5 minutes

### CPU Usage

- **Encoding Phase:** 60-80% (FFmpeg)
- **Database Phase:** 5-10%
- **Overall:** High but brief

### Memory Usage

- **Baseline:** ~50MB
- **Per Segment:** ~100MB (frame buffers)
- **Peak:** 200-500MB (depends on segment size)

### Disk I/O

- **Read:** All frames for day (500MB - 2GB)
- **Write:** Compressed videos (50MB - 200MB per day)
- **Net Savings:** 70-90% compression

## Configuration

### Config File

**Location:** `~/Library/Application Support/Playback/config.json`

**Relevant Fields:**
```json
{
  "processing_interval_minutes": 5,
  "temp_retention_policy": "1_week",
  "recording_retention_policy": "never",
  "ffmpeg_preset": "veryfast",
  "ffmpeg_crf": 28
}
```

### Processing Interval

**Options:** 1, 5, 10, 15, 30, 60 minutes

**UI:** Dropdown in settings window

**Implementation:** Updates LaunchAgent plist and reloads

### Retention Policies

**Options:** "never", "1_day", "1_week", "1_month"

**UI:** Two separate dropdowns in settings window

**Implementation:** Applied during cleanup phase

## Dependencies

### System

- macOS 12.0+ (Monterey or later)
- Python 3.8+
- FFmpeg 4.0+ (must be in PATH)
- SQLite 3.35+ (system version)

### Python Packages

- **Standard Library:**
  - `subprocess` - Run FFmpeg
  - `sqlite3` - Database access
  - `pathlib` - File operations
  - `dataclasses` - Frame info structure
  - `argparse` - CLI parsing
  - `tempfile` - Temp directory management
  - `shutil` - File copy operations

- **Optional:**
  - `psutil` - Resource monitoring (install via pip)

### FFmpeg Installation

**Check:**
```bash
which ffmpeg
# Should output: /usr/local/bin/ffmpeg or similar
```

**Install (if missing):**
```bash
brew install ffmpeg
```

**Required Codecs:**
- libx264 (H.264 encoder)
- libx265 (HEVC encoder, future use)

## Testing

### Unit Tests

- `test_frame_loading()`
- `test_segmentation()`
- `test_app_segment_generation()`
- `test_retention_policy()`

### Integration Tests

- `test_full_processing_cycle()` - Mock FFmpeg, verify database updates
- `test_cleanup()` - Verify temp files deleted
- `test_ffmpeg_failure()` - Mock FFmpeg failure, verify recovery
- `test_disk_full()` - Mock filesystem full, verify error handling

### Performance Tests

- `benchmark_1000_frames()` - Measure processing time for typical day
- `benchmark_memory_usage()` - Verify no memory leaks
- `benchmark_10day_backlog()` - Stress test with large backlog

## Future Enhancements

### Potential Features

1. **Incremental Processing** - Process only new frames since last run
2. **Parallel Processing** - Process multiple days simultaneously
3. **GPU Acceleration** - Use VideoToolbox for faster encoding
4. **Adaptive Quality** - Adjust CRF based on content complexity
5. **Smart Segmentation** - Break on scene changes instead of time
6. **Metadata Extraction** - Parse window titles, URLs from screenshots

### Performance Optimizations

1. **Frame Caching** - Keep decoded frames in memory between segments
2. **Batch Database Inserts** - Single transaction for all segments
3. **Async I/O** - Pipeline reading, encoding, writing

### Reliability Improvements

1. **Atomic Operations** - Use temp files + rename for crash safety
2. **Checkpointing** - Resume partial processing after crash
3. **Validation** - Verify video integrity after encoding
