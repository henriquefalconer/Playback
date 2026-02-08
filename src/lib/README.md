# Playback Shared Library

This directory contains shared Python modules used by Playback's background services (recording, processing, etc.).

## Modules

### `database.py` - SQLite Database Management

Comprehensive database management module providing a clean interface for all SQLite operations.

**Features:**
- Schema initialization with WAL mode for concurrent access
- Type-safe dataclasses for segments and appsegments
- Context manager for safe connection handling
- Comprehensive query functions (by date, timestamp, range)
- Maintenance operations (vacuum, integrity check, backup)
- Proper error handling and logging

**Example Usage:**

```python
from lib.database import init_database, generate_segment_id
from pathlib import Path

# Initialize database
db_path = Path("~/Library/Application Support/Playback/data/meta.sqlite3").expanduser()
db = init_database(db_path)

# Insert a segment
segment_id = generate_segment_id()
db.insert_segment(
    segment_id=segment_id,
    date_str="2026-02-07",
    start_ts=1770489683.7,
    end_ts=1770489743.7,
    frame_count=60,
    fps=1.0,
    file_size_bytes=1024 * 1024,
    video_path="chunks/202602/07/segment.mp4",
    width=1920,
    height=1080,
)

# Query segments
segments = db.get_all_segments()
for seg in segments:
    print(f"{seg.id}: {seg.start_ts} - {seg.end_ts}")

# Find segment at timestamp
segment = db.find_segment_at_timestamp(1770489700.0)
if segment:
    print(f"Found segment: {segment.id}")

# Get database statistics
stats = db.get_database_stats()
print(f"Total segments: {stats['segment_count']}")
print(f"Total size: {stats['total_video_bytes'] / 1024**3:.2f} GB")

# Maintenance operations
db.check_integrity()  # Verify database health
db.vacuum()           # Reclaim space after deletions
db.backup()           # Create timestamped backup
```

**Refactoring Existing Code:**

Before (in `build_chunks_from_temp.py`):
```python
def init_meta_db(path: Path) -> None:
    conn = sqlite3.connect(path)
    try:
        cur = conn.cursor()
        cur.execute("CREATE TABLE IF NOT EXISTS segments ...")
        # ... more setup
        conn.commit()
    finally:
        conn.close()

def insert_segment_meta(db_path, segment_id, date_str, frames, fps, ...):
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.cursor()
        cur.execute("INSERT OR REPLACE INTO segments ...", (...))
        conn.commit()
    finally:
        conn.close()
```

After:
```python
from lib.database import init_database, generate_segment_id

# Initialize once
db = init_database(META_DB_PATH)

# Insert segments directly
segment_id = generate_segment_id()
db.insert_segment(
    segment_id=segment_id,
    date_str=date_str,
    start_ts=frames[0].ts,
    end_ts=frames[-1].ts,
    frame_count=len(frames),
    fps=fps,
    file_size_bytes=size,
    video_path=rel_path,
    width=width,
    height=height,
)
```

**Benefits:**
- Type safety with dataclasses
- Automatic connection management
- Consistent error handling and logging
- No manual SQL query construction
- Easier testing and maintenance

### All Modules Implemented

All planned modules are now complete with comprehensive test coverage:

- ✅ `paths.py` - Environment-aware path resolution (dev vs production) - 32 tests
- ✅ `video.py` - FFmpeg wrappers for video encoding and processing - 34 tests
- ✅ `macos.py` - CoreGraphics and AppleScript integration - 6 tests
- ✅ `timestamps.py` - Filename parsing and timestamp generation - 35 tests
- ✅ `config.py` - Configuration management with validation - 49 tests
- ✅ `database.py` - SQLite operations and schema management - 51 tests
- ✅ `logging_config.py` - Structured JSON logging - 28 tests
- ✅ `utils.py` - Shared utility functions - 8 tests

**Total: 280 passing tests across all modules**

## Testing

Run the test suite:

```bash
# Test database module
python3 test_database.py

# Run Python unit tests (when available)
python3 -m pytest src/lib/tests/ -v

# Python linting
flake8 src/lib/ --max-line-length=120
```

## Design Principles

1. **Type Safety**: Use type hints for all function parameters and return values
2. **Context Managers**: Use context managers for resource cleanup (connections, files)
3. **Logging**: Use Python logging module with structured output
4. **Error Handling**: Specific exception types with clear error messages
5. **Documentation**: Docstrings for all public functions and classes
6. **Testability**: Pure functions where possible, injectable dependencies

## Database Schema

See `specs/database-schema.md` for complete schema documentation including:
- Table structures and constraints
- Index strategy and performance characteristics
- Example queries for common operations
- Migration patterns and maintenance procedures
