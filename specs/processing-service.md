# Processing Service Specification

**Component:** In-Process Video Generation (Swift — to be implemented)

## Overview

The processing service converts temporary screenshot PNGs into MP4 video segments. It runs in-process inside Playback.app on a fixed 5-minute interval.

## Architecture

- **Runs in:** Playback.app process (background Task/DispatchQueue)
- **Interval:** 5 minutes (hardcoded, not configurable)
- **Input:** `temp/YYYYMM/DD/*.png` screenshots
- **Output:** `chunks/YYYYMM/DD/<segment_id>.mp4` video files + SQLite metadata

## Processing Pipeline

Each 5-minute cycle:

1. **Find pending days** — scan `temp/` for directories with unprocessed PNGs
2. **Load frames** — read PNGs from `temp/YYYYMM/DD/`, sort by filename timestamp
3. **Group frames** — split into segments by resolution changes and max frame count
4. **Create video** — encode PNG sequence to MP4 using AVFoundation (AVAssetWriter)
5. **Build app segments** — group consecutive frames by app bundle ID
6. **Write to database** — insert segment and appsegment records into SQLite
7. **Clean up** — delete processed temp PNGs

## Video Encoding

Using AVFoundation instead of FFmpeg:

- **API:** AVAssetWriter with AVAssetWriterInput
- **Codec:** H.264 (hardware-accelerated via VideoToolbox)
- **Pixel format:** YUV 420p
- **Quality:** Balanced for screen content (equivalent to CRF 28)
- **FPS:** Derived from capture interval (effectively 0.5 fps real-time, stored as 30 fps playback)

## Frame Grouping

- Parse timestamp from filename: `YYYYMMDD-HHMMSS` prefix
- Parse app ID from filename: last component after UUID
- Split on resolution changes (width/height differs from previous frame)
- Maximum frames per segment: configurable internally

## Database Writes

For each processed segment:

```sql
INSERT INTO segments (id, date, start_ts, end_ts, frame_count, fps, width, height, file_size_bytes, video_path)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
```

For each app activity span:

```sql
INSERT INTO appsegments (id, app_id, date, start_ts, end_ts)
VALUES (?, ?, ?, ?, ?);
```

## Segment ID Generation

20-character hex string: `Data.random(count: 10).map { String(format: "%02x", $0) }.joined()`

## Output Structure

```
chunks/YYYYMM/DD/<segment_id>.mp4
```

Example: `chunks/202603/15/a3f8b29c4d5e6f7890ab.mp4`

## Error Handling

- Frame loading failure: skip frame, continue with remaining
- Video encoding failure: log error, preserve temp files for retry
- Database write failure: log error, skip segment
- Never crash the app on processing errors
