# Database Schema Specification

**Component:** SQLite Database

## Overview

Playback uses a single SQLite database (`meta.sqlite3`) to store video segment metadata and app activity data. WAL mode enables concurrent reads during writes.

## Location

- **Production:** `~/Library/Application Support/Playback/data/meta.sqlite3`
- **Development:** `<project>/dev_data/meta.sqlite3`
- **Permissions:** 0600 (user read/write only)

## Tables

### schema_version

Tracks database schema version.

```sql
CREATE TABLE IF NOT EXISTS schema_version (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### segments

Video segment metadata for timeline playback.

```sql
CREATE TABLE IF NOT EXISTS segments (
    id TEXT PRIMARY KEY,
    date TEXT NOT NULL,
    start_ts REAL NOT NULL,
    end_ts REAL NOT NULL,
    frame_count INTEGER NOT NULL,
    fps REAL,
    width INTEGER,
    height INTEGER,
    file_size_bytes INTEGER,
    video_path TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_segments_date ON segments(date);
CREATE INDEX IF NOT EXISTS idx_segments_start_ts ON segments(start_ts);
CREATE INDEX IF NOT EXISTS idx_segments_end_ts ON segments(end_ts);
```

**Columns:**
- `id` — 20 hex chars (`Data.random(count: 10).hex`)
- `date` — YYYY-MM-DD format
- `start_ts` / `end_ts` — Unix timestamp (REAL, fractional seconds)
- `frame_count` — number of frames in the video
- `fps` — frames per second (nullable, default 1.0)
- `width` / `height` — video dimensions (nullable)
- `file_size_bytes` — video file size (nullable)
- `video_path` — relative path from data directory (e.g., `202603/15/abc123.mp4`)

### appsegments

Application activity timeline for color-coded visualization.

```sql
CREATE TABLE IF NOT EXISTS appsegments (
    id TEXT PRIMARY KEY,
    app_id TEXT,
    date TEXT NOT NULL,
    start_ts REAL NOT NULL,
    end_ts REAL NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_appsegments_date ON appsegments(date);
CREATE INDEX IF NOT EXISTS idx_appsegments_app_id ON appsegments(app_id);
CREATE INDEX IF NOT EXISTS idx_appsegments_start_ts ON appsegments(start_ts);
CREATE INDEX IF NOT EXISTS idx_appsegments_end_ts ON appsegments(end_ts);
```

**Note:** AppSegments are independent from segments (no foreign key). NULL app_id means unknown app.

## Initialization

```sql
PRAGMA journal_mode=WAL;
PRAGMA secure_delete=ON;
```

## Key Queries

**Load all segments (timeline init):**
```sql
SELECT id, start_ts, end_ts, frame_count, fps, video_path
FROM segments ORDER BY start_ts ASC;
```

**Load all appsegments:**
```sql
SELECT id, app_id, start_ts, end_ts
FROM appsegments ORDER BY start_ts ASC;
```

**Find segment at timestamp:**
```sql
SELECT id, start_ts, end_ts, frame_count, fps, video_path
FROM segments WHERE start_ts <= ? AND end_ts >= ?
ORDER BY start_ts ASC LIMIT 1;
```

**Get latest timestamp:**
```sql
SELECT MAX(end_ts) FROM segments;
```

**Get available dates (for DateTimePicker):**
```sql
SELECT DISTINCT date FROM segments ORDER BY date;
```

**Get segments for date (for DateTimePicker):**
```sql
SELECT start_ts FROM segments WHERE date = ? ORDER BY start_ts;
```

## Concurrent Access

- WAL mode allows the timeline viewer to read while the processing service writes
- No locking errors during normal operation
- Both reader and writer run in the same app process

## Performance

| Operation | 10K segments | 100K segments |
|---|---|---|
| Load all segments | <200ms | <1s |
| Single insert | <5ms | <5ms |
| Find by timestamp | <10ms | <10ms |
| Batch insert (1000) | <100ms | <100ms |
