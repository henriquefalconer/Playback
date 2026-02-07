# Database Schema Implementation Plan

**Component:** SQLite Database Schema
**Version:** 1.0
**Last Updated:** 2026-02-07

## Implementation Checklist

### Schema Version Table
- [ ] Create schema_version table structure
  - Source: `scripts/build_chunks_from_temp.py` (init_meta_db function, line 209)
  - Table: `schema_version (version TEXT PRIMARY KEY, applied_at TIMESTAMP)`
  - Reference: Original spec line 27-33

- [ ] Implement version check function
  - Source: New function in `scripts/database.py` (create file)
  - Method: `get_schema_version() -> str`
  - Query: `SELECT version FROM schema_version ORDER BY applied_at DESC LIMIT 1`
  - Reference: Original spec line 304-316

- [ ] Add version insert on database initialization
  - Source: `scripts/build_chunks_from_temp.py` (init_meta_db function)
  - Statement: `INSERT OR IGNORE INTO schema_version (version) VALUES ('1.0')`
  - Reference: Original spec line 289-291

### Segments Table
- [ ] Create segments table with all columns
  - Source: `scripts/build_chunks_from_temp.py` (init_meta_db function, line 217-231)
  - Columns: id, date, start_ts, end_ts, frame_count, fps, width, height, file_size_bytes, video_path
  - Reference: Original spec line 42-54

- [ ] Create indexes for segments table
  - Source: `scripts/build_chunks_from_temp.py` (init_meta_db function, line 244)
  - Indexes: idx_segments_date, idx_segments_start_ts, idx_segments_end_ts
  - Reference: Original spec line 58-62

- [ ] Implement segment insertion
  - Source: `scripts/build_chunks_from_temp.py` (insert_segment_meta function, line 331-370)
  - Statement: `INSERT OR REPLACE INTO segments (...) VALUES (?...)`
  - Uses: Real timestamps from frame metadata (st_birthtime)
  - Reference: Original spec line 177-181

- [ ] Create Segment model in Swift
  - Source: `Playback/Playback/TimelineStore.swift` (Segment struct, line 5-65)
  - Properties: id, startTS, endTS, frameCount, fps, videoURL
  - Methods: duration, videoDuration, videoOffset, absoluteTime
  - Status: Already implemented

### AppSegments Table
- [ ] Create appsegments table with all columns
  - Source: `scripts/build_chunks_from_temp.py` (init_meta_db function, line 233-242)
  - Columns: id, app_id, date, start_ts, end_ts
  - Reference: Original spec line 99-106

- [ ] Create indexes for appsegments table
  - Source: `scripts/build_chunks_from_temp.py` (init_meta_db function, line 244)
  - Indexes: idx_appsegments_date, idx_appsegments_app_id, idx_appsegments_start_ts, idx_appsegments_end_ts
  - Reference: Original spec line 110-115

- [ ] Implement appsegment insertion
  - Source: `scripts/build_chunks_from_temp.py` (insert_appsegment_meta function, line 373-399)
  - Statement: `INSERT OR REPLACE INTO appsegments (...) VALUES (?...)`
  - Uses: Aggregated app_id timeline from frames
  - Reference: Original spec line 184-188

- [ ] Implement app segment aggregation logic
  - Source: `scripts/build_chunks_from_temp.py` (build_appsegments_for_day function, line 402-438)
  - Logic: Group continuous frames by app_id, handle transitions
  - Reference: Original spec line 402-438

- [ ] Create AppSegment model in Swift
  - Source: `Playback/Playback/TimelineStore.swift` (AppSegment struct, line 67-76)
  - Properties: id, startTS, endTS, appId
  - Status: Already implemented

### Database Initialization
- [ ] Implement init_meta_db function
  - Source: `scripts/build_chunks_from_temp.py` (init_meta_db function, line 209-246)
  - Creates: schema_version, segments, appsegments tables
  - Creates: All indexes
  - Reference: Original spec line 237-296

- [ ] Set database file location
  - Production: `~/Library/Application Support/Playback/data/meta.sqlite3`
  - Development: `<project>/com.playback.Playback/meta.sqlite3`
  - Source: `Playback/Playback/TimelineStore.swift` (line 94-100)
  - Reference: Original spec line 13

- [ ] Handle missing database gracefully
  - Source: `Playback/Playback/TimelineStore.swift` (loadSegments function, line 104-117)
  - Behavior: Print error and return empty segments
  - Reference: Original spec line 70-73 (error handling)

### WAL Mode Configuration
- [ ] Enable WAL mode for concurrent reads
  - Source: New in `scripts/build_chunks_from_temp.py` (init_meta_db function)
  - Command: `PRAGMA journal_mode=WAL`
  - Purpose: Allow playback app to read while processing service writes
  - Reference: Original spec line 412-421

- [ ] Test concurrent access
  - Test: Playback app reading while processing service writes
  - Expected: No locking errors, smooth playback
  - Reference: Original spec line 399-411

### Playback App Queries
- [ ] Implement load all segments query
  - Source: `Playback/Playback/TimelineStore.swift` (loadSegments function, line 120-160)
  - Query: `SELECT id, start_ts, end_ts, frame_count, fps, video_path FROM segments ORDER BY start_ts ASC`
  - Status: Already implemented
  - Reference: Original spec line 143-147

- [ ] Implement load all appsegments query
  - Source: `Playback/Playback/TimelineStore.swift` (loadSegments function, line 162-200)
  - Query: `SELECT id, app_id, start_ts, end_ts FROM appsegments ORDER BY start_ts ASC`
  - Status: Already implemented
  - Reference: Original spec line 149-154

- [ ] Implement find segment for timestamp
  - Source: `Playback/Playback/TimelineStore.swift` (segment function, line 212-310)
  - Logic: Binary search or linear scan with direction handling
  - Status: Already implemented (complex logic with gap handling)
  - Reference: Original spec line 156-162

- [ ] Implement get latest timestamp
  - Source: `Playback/Playback/TimelineStore.swift` (latestTS property, line 90-92)
  - Logic: `segments.last?.endTS`
  - Status: Already implemented
  - Reference: Original spec line 164-167

### Processing Service Queries
- [ ] Implement check segment exists
  - Source: New function in `scripts/database.py`
  - Query: `SELECT id FROM segments WHERE id = ?`
  - Purpose: Avoid duplicate segment creation
  - Reference: Original spec line 171-174

- [ ] Implement insert segment
  - Source: `scripts/build_chunks_from_temp.py` (insert_segment_meta function, line 331-370)
  - Query: `INSERT OR REPLACE INTO segments (...) VALUES (?...)`
  - Status: Already implemented
  - Reference: Original spec line 177-181

- [ ] Implement insert appsegment
  - Source: `scripts/build_chunks_from_temp.py` (insert_appsegment_meta function, line 373-399)
  - Query: `INSERT OR REPLACE INTO appsegments (...) VALUES (?...)`
  - Status: Already implemented
  - Reference: Original spec line 184-188

- [ ] Implement find old segments for cleanup
  - Source: New function in `scripts/database.py`
  - Query: `SELECT id, video_path FROM segments WHERE start_ts < ?`
  - Purpose: Retention policy enforcement
  - Reference: Original spec line 191-193

- [ ] Implement delete old segments
  - Source: New function in `scripts/database.py`
  - Queries: `DELETE FROM segments WHERE id = ?; DELETE FROM appsegments WHERE id = ?`
  - Reference: Original spec line 196-199

### Migration System
- [ ] Create migration function structure
  - Source: New file `scripts/migrations.py`
  - Functions: get_schema_version(), apply_migration()
  - Reference: Original spec line 299-338

- [ ] Implement version check before migration
  - Source: `scripts/migrations.py`
  - Logic: Check current version, compare with target
  - Handle: Missing table (version 0.0), unknown version
  - Reference: Original spec line 304-316

- [ ] Create example migration (1.0 to 1.1)
  - Source: `scripts/migrations.py` (migrate_1_0_to_1_1 function)
  - Example: Add codec column with ALTER TABLE
  - Updates: schema_version table
  - Reference: Original spec line 319-338

- [ ] Add migration tests
  - Test: Migrate from 1.0 to 1.1
  - Test: Handle missing schema_version table
  - Test: Detect unknown version
  - Reference: Original spec line 319-338

### Vacuum and Maintenance
- [ ] Implement vacuum function
  - Source: New function in `scripts/database.py`
  - Command: `VACUUM`
  - Usage: After large deletions, monthly schedule
  - Reference: Original spec line 343-359

- [ ] Implement integrity check function
  - Source: New function in `scripts/database.py`
  - Command: `PRAGMA integrity_check`
  - Returns: bool (True if ok)
  - Reference: Original spec line 362-381

- [ ] Schedule periodic maintenance
  - Location: LaunchAgent plist or cron
  - Frequency: Monthly vacuum, weekly integrity check
  - Reference: Original spec line 343-381

### Backup Functionality
- [ ] Implement database backup function
  - Source: New function in `scripts/database.py`
  - Method: `shutil.copy2(META_DB_PATH, backup_path)`
  - Naming: `meta.sqlite3.backup` with timestamp
  - Reference: Original spec line 384-395

- [ ] Create backup before migrations
  - Source: `scripts/migrations.py` (apply_migration function)
  - Timing: Before ALTER TABLE or schema changes
  - Reference: Original spec line 384-395

- [ ] Implement backup retention policy
  - Source: New function in `scripts/database.py`
  - Policy: Keep last N backups, delete older
  - Reference: Not in original spec (enhancement)

## Database Schema Details

### Database File Location and Format

**Production Location:**
```
~/Library/Application Support/Playback/data/meta.sqlite3
```

**Development Location:**
```
<project>/com.playback.Playback/meta.sqlite3
```

**Format:**
- SQLite 3.x database
- WAL (Write-Ahead Logging) mode enabled for concurrent reads/writes
- UTF-8 encoding
- Typical size: 10-50 MB for 30 days of data

### Complete Table Structures

#### 1. schema_version Table

Tracks database schema version for migration management.

```sql
CREATE TABLE IF NOT EXISTS schema_version (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Columns:**
- `version` (TEXT, PRIMARY KEY): Schema version string (e.g., "1.0", "1.1")
- `applied_at` (TIMESTAMP): When this version was applied, defaults to current timestamp

**Usage:**
```sql
-- Insert initial version
INSERT OR IGNORE INTO schema_version (version) VALUES ('1.0');

-- Query current version
SELECT version FROM schema_version ORDER BY applied_at DESC LIMIT 1;
```

#### 2. segments Table

Stores video segment metadata for timeline playback.

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

-- Indexes for query performance
CREATE INDEX IF NOT EXISTS idx_segments_date ON segments(date);
CREATE INDEX IF NOT EXISTS idx_segments_start_ts ON segments(start_ts);
CREATE INDEX IF NOT EXISTS idx_segments_end_ts ON segments(end_ts);
```

**Columns:**
- `id` (TEXT, PRIMARY KEY): Unique segment identifier, 20 hex chars generated with `os.urandom(10).hex()`
- `date` (TEXT, NOT NULL): Date in YYYY-MM-DD format for organization and retention policies
- `start_ts` (REAL, NOT NULL): Unix timestamp (seconds with fractional part) of first frame
- `end_ts` (REAL, NOT NULL): Unix timestamp of last frame
- `frame_count` (INTEGER, NOT NULL): Number of frames in the video segment
- `fps` (REAL, NULL): Frames per second, optional (default to 1.0 if missing)
- `width` (INTEGER, NULL): Video width in pixels, optional
- `height` (INTEGER, NULL): Video height in pixels, optional
- `file_size_bytes` (INTEGER, NULL): Size of video file in bytes, optional
- `video_path` (TEXT, NOT NULL): Relative path from data directory (e.g., "2024-01-15/segment_abc123.mp4")

**Constraints:**
- `start_ts < end_ts` (logical constraint, enforced by application)
- `frame_count > 0` (logical constraint, enforced by application)

**Example Data:**
```sql
INSERT INTO segments (id, date, start_ts, end_ts, frame_count, fps, width, height, file_size_bytes, video_path)
VALUES (
    '1a2b3c4d5e6f7g8h9i0j',
    '2024-01-15',
    1705329600.5,
    1705329660.5,
    60,
    1.0,
    1920,
    1080,
    5242880,
    '2024-01-15/segment_1a2b3c4d5e6f7g8h9i0j.mp4'
);
```

#### 3. appsegments Table

Stores application activity timeline for color-coded visualization.

```sql
CREATE TABLE IF NOT EXISTS appsegments (
    id TEXT PRIMARY KEY,
    app_id TEXT,
    date TEXT NOT NULL,
    start_ts REAL NOT NULL,
    end_ts REAL NOT NULL
);

-- Indexes for query performance
CREATE INDEX IF NOT EXISTS idx_appsegments_date ON appsegments(date);
CREATE INDEX IF NOT EXISTS idx_appsegments_app_id ON appsegments(app_id);
CREATE INDEX IF NOT EXISTS idx_appsegments_start_ts ON appsegments(start_ts);
CREATE INDEX IF NOT EXISTS idx_appsegments_end_ts ON appsegments(end_ts);
```

**Columns:**
- `id` (TEXT, PRIMARY KEY): Unique appsegment identifier, 20 hex chars generated with `os.urandom(10).hex()`
- `app_id` (TEXT, NULL): Application bundle identifier (e.g., "com.apple.Safari"), NULL for unknown
- `date` (TEXT, NOT NULL): Date in YYYY-MM-DD format for organization
- `start_ts` (REAL, NOT NULL): Unix timestamp when app became active
- `end_ts` (REAL, NOT NULL): Unix timestamp when app became inactive

**Notes:**
- AppSegments are independent from segments (no foreign key relationship)
- Multiple appsegments can overlap same time range if processing detected multiple apps
- NULL app_id indicates screen recording was active but no specific app detected

**Example Data:**
```sql
INSERT INTO appsegments (id, app_id, date, start_ts, end_ts)
VALUES (
    'a1b2c3d4e5f6g7h8i9j0',
    'com.apple.Safari',
    '2024-01-15',
    1705329600.5,
    1705329660.5
);
```

### Example Queries

#### Playback App Queries

**Load All Segments (Timeline Initialization):**
```sql
SELECT id, start_ts, end_ts, frame_count, fps, video_path
FROM segments
ORDER BY start_ts ASC;
```

**Load All AppSegments (App Timeline):**
```sql
SELECT id, app_id, start_ts, end_ts
FROM appsegments
ORDER BY start_ts ASC;
```

**Find Segment for Specific Timestamp:**
```sql
-- Direct match
SELECT id, start_ts, end_ts, frame_count, fps, video_path
FROM segments
WHERE start_ts <= ? AND end_ts >= ?
ORDER BY start_ts ASC
LIMIT 1;

-- Nearest segment (forward)
SELECT id, start_ts, end_ts, frame_count, fps, video_path
FROM segments
WHERE start_ts >= ?
ORDER BY start_ts ASC
LIMIT 1;

-- Nearest segment (backward)
SELECT id, start_ts, end_ts, frame_count, fps, video_path
FROM segments
WHERE end_ts <= ?
ORDER BY start_ts DESC
LIMIT 1;
```

**Get Latest Timestamp:**
```sql
SELECT MAX(end_ts) FROM segments;
```

**Get Segments for Date Range:**
```sql
SELECT id, start_ts, end_ts, frame_count, fps, video_path
FROM segments
WHERE date >= ? AND date <= ?
ORDER BY start_ts ASC;
```

#### Processing Service Queries

**Check if Segment Exists:**
```sql
SELECT id FROM segments WHERE id = ?;
```

**Insert Segment (With Replace on Conflict):**
```sql
INSERT OR REPLACE INTO segments
(id, date, start_ts, end_ts, frame_count, fps, width, height, file_size_bytes, video_path)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
```

**Insert AppSegment:**
```sql
INSERT OR REPLACE INTO appsegments
(id, app_id, date, start_ts, end_ts)
VALUES (?, ?, ?, ?, ?);
```

**Find Old Segments for Cleanup (Retention Policy):**
```sql
SELECT id, video_path
FROM segments
WHERE start_ts < ?
ORDER BY start_ts ASC;
```

**Delete Old Segments:**
```sql
DELETE FROM segments WHERE id = ?;
DELETE FROM appsegments WHERE id = ?;
```

#### Analytics Queries (Future Features)

**Daily Screen Time:**
```sql
SELECT
    date,
    SUM(end_ts - start_ts) as total_seconds,
    COUNT(*) as segment_count
FROM segments
WHERE date >= ? AND date <= ?
GROUP BY date
ORDER BY date ASC;
```

**App Usage Statistics:**
```sql
SELECT
    app_id,
    SUM(end_ts - start_ts) as total_seconds,
    COUNT(*) as session_count
FROM appsegments
WHERE date >= ? AND date <= ?
    AND app_id IS NOT NULL
GROUP BY app_id
ORDER BY total_seconds DESC;
```

**Hourly Activity Pattern:**
```sql
SELECT
    CAST(strftime('%H', datetime(start_ts, 'unixepoch', 'localtime')) AS INTEGER) as hour,
    SUM(end_ts - start_ts) as total_seconds
FROM segments
WHERE date >= ? AND date <= ?
GROUP BY hour
ORDER BY hour ASC;
```

### Indexing Strategy

**Purpose of Each Index:**

1. **idx_segments_date**: Fast filtering by date for retention policies and date range queries
2. **idx_segments_start_ts**: Efficient timeline ordering and binary search for timestamp lookups
3. **idx_segments_end_ts**: Quick gap detection and range overlap queries
4. **idx_appsegments_date**: Date-based filtering for app timeline
5. **idx_appsegments_app_id**: Fast filtering by specific application
6. **idx_appsegments_start_ts**: Timeline ordering for app segments
7. **idx_appsegments_end_ts**: Range queries and overlap detection

**Performance Impact:**
- Query time with 10,000 segments: < 200ms
- Query time with 100,000 segments: < 1s
- Index overhead: ~10-20% of database size
- Insertion time penalty: < 1ms per segment

### WAL Mode Configuration

**Enable WAL Mode:**
```sql
PRAGMA journal_mode=WAL;
```

**Benefits:**
- Concurrent reads while processing service writes
- Better performance for multiple readers
- Reduced file system I/O

**Implementation:**
```python
def init_meta_db(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Enable WAL mode for concurrent access
    cursor.execute("PRAGMA journal_mode=WAL")

    # Create tables...
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS schema_version (
            version TEXT PRIMARY KEY,
            applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # More table creation...

    conn.commit()
    conn.close()
```

**Concurrent Access Pattern:**
- Playback app: Multiple read connections
- Processing service: Single write connection
- No locking errors with WAL mode enabled
- Smooth playback during segment creation

**WAL Files:**
- `meta.sqlite3-wal`: Write-ahead log file
- `meta.sqlite3-shm`: Shared memory index
- Both automatically managed by SQLite

### Migration Examples

**Check Current Schema Version:**
```python
def get_schema_version(db_path):
    """Returns current schema version or '0.0' if table doesn't exist."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    try:
        cursor.execute("""
            SELECT version FROM schema_version
            ORDER BY applied_at DESC
            LIMIT 1
        """)
        result = cursor.fetchone()
        version = result[0] if result else '0.0'
    except sqlite3.OperationalError:
        # Table doesn't exist (first time setup)
        version = '0.0'
    finally:
        conn.close()

    return version
```

**Example Migration (1.0 to 1.1 - Add Codec Column):**
```python
def migrate_1_0_to_1_1(db_path):
    """Migrate from schema version 1.0 to 1.1."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    try:
        # Add new column to segments table
        cursor.execute("""
            ALTER TABLE segments
            ADD COLUMN codec TEXT DEFAULT 'h264'
        """)

        # Update schema version
        cursor.execute("""
            INSERT INTO schema_version (version)
            VALUES ('1.1')
        """)

        conn.commit()
        print("Successfully migrated to schema version 1.1")
        return True

    except Exception as e:
        conn.rollback()
        print(f"Migration failed: {e}")
        return False

    finally:
        conn.close()
```

**Migration Strategy:**
```python
def apply_migration(db_path, target_version='1.1'):
    """Apply database migration with backup."""
    current_version = get_schema_version(db_path)

    if current_version == target_version:
        print(f"Already at version {target_version}")
        return True

    # Create backup before migration
    backup_path = f"{db_path}.backup.{int(time.time())}"
    shutil.copy2(db_path, backup_path)
    print(f"Created backup: {backup_path}")

    # Apply migration based on current version
    if current_version == '1.0' and target_version == '1.1':
        success = migrate_1_0_to_1_1(db_path)
    else:
        print(f"Unknown migration path: {current_version} -> {target_version}")
        return False

    if not success:
        print("Restoring from backup...")
        shutil.copy2(backup_path, db_path)
        return False

    return True
```

### Performance Characteristics

**Database Operations Benchmarks:**

| Operation | Dataset Size | Expected Time |
|-----------|-------------|---------------|
| Load all segments | 1,000 segments | < 50ms |
| Load all segments | 10,000 segments | < 200ms |
| Load all segments | 100,000 segments | < 1s |
| Insert single segment | N/A | < 5ms |
| Batch insert | 1,000 segments | < 100ms |
| Find segment by timestamp | Any size | < 10ms (linear) |
| Delete old segments | 1,000 segments | < 50ms |
| VACUUM | 50MB database | 1-2s |

**Memory Usage:**
- Baseline: ~5-10 MB
- With 10,000 segments loaded: ~20-30 MB
- With 100,000 segments loaded: ~100-150 MB

**File Size Growth:**
- ~1-2 KB per segment entry
- ~500 bytes per appsegment entry
- 10,000 segments + 50,000 appsegments ≈ 35 MB
- 30 days of continuous recording ≈ 10-50 MB

**Optimization Patterns:**

1. **Use Prepared Statements:**
```python
# Good - prepared statement
cursor.execute("INSERT INTO segments VALUES (?, ?, ?)", (id, date, path))

# Bad - string concatenation (SQL injection risk)
cursor.execute(f"INSERT INTO segments VALUES ('{id}', '{date}', '{path}')")
```

2. **Batch Operations:**
```python
# Good - single transaction for multiple inserts
conn = sqlite3.connect(db_path)
cursor = conn.cursor()
for segment in segments:
    cursor.execute("INSERT INTO segments VALUES (?...)", segment)
conn.commit()  # Single commit

# Bad - commit after each insert
for segment in segments:
    cursor.execute("INSERT INTO segments VALUES (?...)", segment)
    conn.commit()  # Multiple commits (slow)
```

3. **Index-Aware Queries:**
```python
# Good - uses idx_segments_start_ts
cursor.execute("SELECT * FROM segments WHERE start_ts >= ? ORDER BY start_ts")

# Bad - full table scan
cursor.execute("SELECT * FROM segments WHERE CAST(start_ts AS INTEGER) = ?")
```

4. **Limit Result Sets:**
```python
# Good - limit early for pagination
cursor.execute("""
    SELECT * FROM segments
    WHERE date = ?
    ORDER BY start_ts
    LIMIT ? OFFSET ?
""", (date, page_size, offset))

# Bad - fetch all then slice in Python
cursor.execute("SELECT * FROM segments WHERE date = ?", (date,))
all_results = cursor.fetchall()
page = all_results[offset:offset+page_size]
```

### Maintenance Operations

**VACUUM (Reclaim Space After Deletions):**
```python
def vacuum_database(db_path):
    """Reclaim space from deleted records."""
    conn = sqlite3.connect(db_path)
    conn.execute("VACUUM")
    conn.close()
    print("Database vacuumed successfully")
```

**Usage:** Run monthly or after large deletions (retention policy cleanup)

**Integrity Check:**
```python
def check_integrity(db_path):
    """Verify database integrity."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("PRAGMA integrity_check")
    result = cursor.fetchone()
    conn.close()

    is_ok = result[0] == 'ok'
    if not is_ok:
        print(f"Integrity check failed: {result[0]}")
    return is_ok
```

**Usage:** Run weekly or after unexpected crashes

**Backup:**
```python
def backup_database(db_path):
    """Create timestamped backup of database."""
    timestamp = int(time.time())
    backup_path = f"{db_path}.backup.{timestamp}"
    shutil.copy2(db_path, backup_path)
    print(f"Backup created: {backup_path}")
    return backup_path
```

**Usage:** Before migrations, weekly automated backups

**Backup Retention:**
```python
def cleanup_old_backups(db_path, keep_count=5):
    """Keep only the N most recent backups."""
    backup_dir = os.path.dirname(db_path)
    backup_pattern = f"{os.path.basename(db_path)}.backup.*"

    backups = sorted(
        glob.glob(os.path.join(backup_dir, backup_pattern)),
        key=os.path.getmtime,
        reverse=True
    )

    for old_backup in backups[keep_count:]:
        os.remove(old_backup)
        print(f"Removed old backup: {old_backup}")
```

### Implementation Notes

**Key Source Files:**
- `Playback/Playback/TimelineStore.swift` - Segment/AppSegment models, database loading
- `scripts/build_chunks_from_temp.py` - Database initialization, segment insertion
- `scripts/record_screen.py` - Frame capture with app_id metadata
- `~/Library/Application Support/Playback/data/meta.sqlite3` - Production database location

**Timestamp Handling:**
- Use `st_birthtime` (macOS Date Created) for accurate frame timestamps
- Fallback to `st_mtime` if `st_birthtime` unavailable
- Store as REAL (Unix timestamp with fractional seconds)
- Always use UTC internally, convert to local time for display

**ID Generation:**
```python
import os
segment_id = os.urandom(10).hex()  # 20 hex characters
```

**Path Handling:**
- Store video_path as relative path from data directory
- Example: "2024-01-15/segment_abc123.mp4"
- Enables data directory relocation without database updates
- Reconstruct full path: `os.path.join(data_dir, segment.video_path)`

**Security:**
- Always use parameterized queries (prepared statements)
- Never concatenate user input into SQL strings
- Validate file paths before file system operations
- Set appropriate file permissions (0600) on database file

**Error Handling:**
- Handle missing database gracefully (return empty segments)
- Detect and report corruption via integrity_check
- Provide clear error messages for missing video files
- Log all database errors for debugging

## Testing Checklist

### Unit Tests
- [ ] Test database initialization
  - Create tables on fresh database
  - Verify indexes exist
  - Check schema_version is set to '1.0'

- [ ] Test segment insertion (valid data)
  - Insert segment with all fields
  - Verify data retrieved correctly
  - Check timestamps preserved accurately

- [ ] Test segment insertion (duplicate ID)
  - Insert same ID twice
  - Verify `INSERT OR REPLACE` updates existing row

- [ ] Test appsegment insertion
  - Insert appsegment with app_id
  - Insert appsegment with NULL app_id
  - Verify retrieval and ordering

- [ ] Test query segments by date
  - Insert segments across multiple dates
  - Query for specific date
  - Verify only matching segments returned

- [ ] Test query segments by timestamp range
  - Insert segments with various timestamps
  - Query for range [start, end]
  - Verify overlap detection works

- [ ] Test find segment for timestamp
  - Test within segment bounds
  - Test in gap between segments
  - Test before first segment
  - Test after last segment
  - Test with direction parameter (forward/backward)

- [ ] Test delete old segments
  - Insert segments with various timestamps
  - Delete segments older than cutoff
  - Verify only old segments deleted

- [ ] Test vacuum database
  - Insert and delete many segments
  - Run VACUUM
  - Verify file size reduced

- [ ] Test integrity check
  - Run on healthy database (expect "ok")
  - Simulate corruption (expect failure)

- [ ] Test backup creation
  - Create backup
  - Verify backup file exists
  - Verify backup is valid SQLite database

### Integration Tests
- [ ] Test concurrent reads during writes (WAL mode)
  - Playback app reads segments
  - Processing service writes new segment simultaneously
  - Verify no locking errors
  - Verify playback continues smoothly

- [ ] Test database recovery from corruption
  - Detect corrupted database
  - Restore from backup
  - Verify data integrity

- [ ] Test migration from old schema version
  - Create database with schema 1.0
  - Run migration to 1.1
  - Verify new column exists
  - Verify old data preserved
  - Verify schema_version updated

- [ ] Test full pipeline (recording → processing → playback)
  - Run record_screen.py (create frames)
  - Run build_chunks_from_temp.py (create segments)
  - Launch Playback app (load segments)
  - Verify timeline displays correctly

- [ ] Test app segment timeline accuracy
  - Capture frames with different apps
  - Process into segments and appsegments
  - Verify appsegments match app transitions
  - Verify timeline colors match apps

- [ ] Test performance with large datasets
  - Load database with 10,000+ segments
  - Load database with 50,000+ appsegments
  - Verify query performance < 100ms
  - Verify memory usage reasonable

### Performance Tests
- [ ] Benchmark segment loading time
  - Database with 1,000 segments: < 50ms
  - Database with 10,000 segments: < 200ms
  - Database with 100,000 segments: < 1s

- [ ] Benchmark segment insertion time
  - Single insert: < 5ms
  - Batch insert (1000 segments): < 100ms

- [ ] Benchmark find segment for timestamp
  - Linear scan: < 10ms
  - Binary search (optional): < 1ms

- [ ] Test under continuous recording (24+ hours)
  - Monitor database file size growth
  - Monitor query performance over time
  - Verify no memory leaks

- [ ] Test with 30+ days of data
  - Total database size: 10-50 MB typical
  - Load time on app launch: < 500ms
  - Scrubbing responsiveness: < 16ms per frame (60fps)

### Edge Case Tests
- [ ] Test empty database
  - App launch with no segments
  - Verify graceful handling (empty timeline)

- [ ] Test missing video files
  - Segments in database but video files deleted
  - Verify app handles missing files gracefully

- [ ] Test segments with missing fps/width/height
  - Insert segment with NULL optional fields
  - Verify playback falls back to defaults

- [ ] Test very long segments (> 1 hour)
  - Unusual case (processing failure/recovery)
  - Verify timeline mapping works correctly

- [ ] Test zero-frame segments
  - Edge case from processing errors
  - Verify app skips or handles gracefully

- [ ] Test appsegments without corresponding segments
  - AppSegments can exist independently
  - Verify timeline visualization handles gaps

- [ ] Test timestamp ordering issues
  - Segments inserted out of order
  - Verify `ORDER BY start_ts` maintains timeline correctness
