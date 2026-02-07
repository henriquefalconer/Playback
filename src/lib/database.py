#!/usr/bin/env python3
"""
Database management module for Playback application.

This module provides a comprehensive interface for SQLite database operations,
including segment and appsegment management, schema migrations, maintenance,
and backup functionality.

The database uses WAL mode for concurrent reads/writes, allowing the playback
app to read while the processing service writes.
"""

import logging
import os
import shutil
import sqlite3
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

logger = logging.getLogger(__name__)


SCHEMA_VERSION = "1.1"


@dataclass
class SegmentRecord:
    """Represents a video segment record from the database."""
    id: str
    date: str
    start_ts: float
    end_ts: float
    frame_count: int
    fps: float
    width: Optional[int]
    height: Optional[int]
    file_size_bytes: int
    video_path: str


@dataclass
class AppSegmentRecord:
    """Represents an application activity segment from the database."""
    id: str
    app_id: Optional[str]
    date: str
    start_ts: float
    end_ts: float


@dataclass
class OCRTextRecord:
    """Represents an OCR text extraction record from the database."""
    id: int
    frame_path: str
    segment_id: Optional[str]
    timestamp: float
    text_content: str
    confidence: float
    language: str
    created_at: str


class DatabaseManager:
    """
    Manages SQLite database operations for Playback metadata.

    This class provides a clean interface for all database operations including
    initialization, segment management, queries, migrations, and maintenance.
    """

    def __init__(self, db_path: Path):
        """
        Initialize database manager.

        Args:
            db_path: Path to the SQLite database file
        """
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)

        # Ensure database file is created with secure permissions if it's a new file
        self._ensure_secure_permissions()

    def _ensure_secure_permissions(self) -> None:
        """
        Ensure database file has secure permissions (0o600).

        This method is called during initialization and after database creation
        to prevent other users from accessing the database file.

        Sets permissions on:
            - Main database file (.sqlite3)
            - WAL file (.sqlite3-wal) if it exists
            - SHM file (.sqlite3-shm) if it exists
        """
        if self.db_path.exists():
            os.chmod(self.db_path, 0o600)

            # Also secure WAL and SHM files if they exist
            wal_path = self.db_path.with_suffix(self.db_path.suffix + "-wal")
            shm_path = self.db_path.with_suffix(self.db_path.suffix + "-shm")

            if wal_path.exists():
                os.chmod(wal_path, 0o600)
            if shm_path.exists():
                os.chmod(shm_path, 0o600)

    @contextmanager
    def _get_connection(self, read_only: bool = False):
        """
        Context manager for database connections.

        Args:
            read_only: If True, open connection in read-only mode

        Yields:
            sqlite3.Connection: Database connection

        Example:
            with db._get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT * FROM segments")
        """
        # Track if database file existed before connection
        db_existed = self.db_path.exists()

        if read_only and db_existed:
            uri = f"file:{self.db_path}?mode=ro"
            conn = sqlite3.connect(uri, uri=True)
        else:
            # Set restrictive umask before creating database
            old_umask = os.umask(0o077)
            try:
                conn = sqlite3.connect(self.db_path)
            finally:
                os.umask(old_umask)

            # Ensure secure permissions on newly created database
            if not db_existed:
                self._ensure_secure_permissions()

        try:
            conn.row_factory = sqlite3.Row

            # Set secure_delete for this connection
            # This ensures deleted data is overwritten with zeros for privacy
            if not read_only:
                conn.execute("PRAGMA secure_delete=ON")

            yield conn
        except Exception as e:
            conn.rollback()
            logger.error(f"Database error: {e}", exc_info=True)
            raise
        finally:
            conn.close()

    def initialize(self) -> None:
        """
        Initialize database schema with all tables and indexes.

        Creates schema_version, segments, and appsegments tables with appropriate
        indexes. Enables WAL mode for concurrent access and secure_delete for
        privacy. Safe to call multiple times.

        Raises:
            sqlite3.Error: If database initialization fails
        """
        with self._get_connection() as conn:
            cursor = conn.cursor()

            # Enable WAL mode for concurrent reads during writes
            cursor.execute("PRAGMA journal_mode=WAL")
            logger.info("WAL mode enabled for concurrent access")

            # Enable secure_delete to overwrite deleted data with zeros
            # This ensures deleted records are truly removed from disk, enhancing privacy
            cursor.execute("PRAGMA secure_delete=ON")
            logger.info("Secure delete enabled for privacy protection")

            # Create schema_version table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS schema_version (
                    version TEXT PRIMARY KEY,
                    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            # Insert initial schema version if not exists
            cursor.execute("""
                INSERT OR IGNORE INTO schema_version (version)
                VALUES (?)
            """, (SCHEMA_VERSION,))

            # Create segments table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS segments (
                    id TEXT PRIMARY KEY,
                    date TEXT NOT NULL,
                    start_ts REAL NOT NULL,
                    end_ts REAL NOT NULL,
                    frame_count INTEGER NOT NULL,
                    fps REAL,
                    width INTEGER,
                    height INTEGER,
                    file_size_bytes INTEGER NOT NULL,
                    video_path TEXT NOT NULL
                )
            """)

            # Create indexes for segments table
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_segments_date
                ON segments(date)
            """)
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_segments_start_ts
                ON segments(start_ts)
            """)
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_segments_end_ts
                ON segments(end_ts)
            """)

            # Create appsegments table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS appsegments (
                    id TEXT PRIMARY KEY,
                    app_id TEXT,
                    date TEXT NOT NULL,
                    start_ts REAL NOT NULL,
                    end_ts REAL NOT NULL
                )
            """)

            # Create indexes for appsegments table
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_appsegments_date
                ON appsegments(date)
            """)
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_appsegments_app_id
                ON appsegments(app_id)
            """)
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_appsegments_start_ts
                ON appsegments(start_ts)
            """)
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_appsegments_end_ts
                ON appsegments(end_ts)
            """)

            # Create ocr_text table (Phase 4.1: Text Search with OCR)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS ocr_text (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    frame_path TEXT NOT NULL,
                    segment_id TEXT,
                    timestamp REAL NOT NULL,
                    text_content TEXT NOT NULL,
                    confidence REAL,
                    language TEXT DEFAULT 'en',
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (segment_id) REFERENCES segments(id) ON DELETE CASCADE
                )
            """)

            # Create indexes for ocr_text table
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_ocr_timestamp
                ON ocr_text(timestamp)
            """)
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_ocr_segment
                ON ocr_text(segment_id)
            """)

            # Create FTS5 full-text search virtual table
            cursor.execute("""
                CREATE VIRTUAL TABLE IF NOT EXISTS ocr_search USING fts5(
                    text_content,
                    segment_id UNINDEXED,
                    timestamp UNINDEXED,
                    tokenize = 'porter unicode61'
                )
            """)

            conn.commit()
            logger.info(f"Database initialized at {self.db_path}")

            # Ensure secure permissions after initialization
            self._ensure_secure_permissions()

    def get_schema_version(self) -> str:
        """
        Get current database schema version.

        Returns:
            str: Schema version string (e.g., "1.0"), or "0.0" if table doesn't exist

        Example:
            version = db.get_schema_version()
            if version != "1.0":
                apply_migration(db)
        """
        try:
            with self._get_connection(read_only=True) as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT version FROM schema_version
                    ORDER BY applied_at DESC
                    LIMIT 1
                """)
                result = cursor.fetchone()
                return result["version"] if result else "0.0"
        except sqlite3.OperationalError:
            # Table doesn't exist (first time setup)
            return "0.0"

    def verify_secure_delete(self) -> bool:
        """
        Verify that secure_delete pragma is enabled.

        The secure_delete pragma causes SQLite to overwrite deleted content with zeros
        rather than leaving it in the database file. This enhances privacy by ensuring
        deleted data cannot be recovered through disk forensics.

        Returns:
            bool: True if secure_delete is ON, False otherwise

        Example:
            if not db.verify_secure_delete():
                logger.warning("secure_delete is not enabled")
        """
        try:
            with self._get_connection(read_only=True) as conn:
                cursor = conn.cursor()
                cursor.execute("PRAGMA secure_delete")
                result = cursor.fetchone()
                is_enabled = result[0] == 1
                if is_enabled:
                    logger.debug("secure_delete is enabled")
                else:
                    logger.warning("secure_delete is not enabled")
                return is_enabled
        except Exception as e:
            logger.error(f"Error checking secure_delete pragma: {e}", exc_info=True)
            return False

    def insert_segment(
        self,
        segment_id: str,
        date_str: str,
        start_ts: float,
        end_ts: float,
        frame_count: int,
        fps: float,
        file_size_bytes: int,
        video_path: str,
        width: Optional[int] = None,
        height: Optional[int] = None,
    ) -> None:
        """
        Insert or replace a video segment record.

        Args:
            segment_id: Unique segment identifier (20 hex chars)
            date_str: Date in YYYY-MM-DD format
            start_ts: Unix timestamp of first frame
            end_ts: Unix timestamp of last frame
            frame_count: Number of frames in segment
            fps: Frames per second
            file_size_bytes: Size of video file in bytes
            video_path: Relative path from data directory
            width: Video width in pixels (optional)
            height: Video height in pixels (optional)

        Raises:
            sqlite3.Error: If insertion fails
        """
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT OR REPLACE INTO segments
                (id, date, start_ts, end_ts, frame_count, fps, width, height, file_size_bytes, video_path)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                segment_id,
                date_str,
                start_ts,
                end_ts,
                frame_count,
                fps,
                width,
                height,
                file_size_bytes,
                video_path,
            ))
            conn.commit()
            logger.debug(f"Inserted segment {segment_id} [{start_ts:.1f} - {end_ts:.1f}]")

    def insert_appsegment(
        self,
        appsegment_id: str,
        date_str: str,
        start_ts: float,
        end_ts: float,
        app_id: Optional[str] = None,
    ) -> None:
        """
        Insert or replace an application activity segment record.

        Args:
            appsegment_id: Unique appsegment identifier (20 hex chars)
            date_str: Date in YYYY-MM-DD format
            start_ts: Unix timestamp when app became active
            end_ts: Unix timestamp when app became inactive
            app_id: Application bundle identifier (e.g., "com.apple.Safari"), None for unknown

        Raises:
            sqlite3.Error: If insertion fails
        """
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT OR REPLACE INTO appsegments
                (id, app_id, date, start_ts, end_ts)
                VALUES (?, ?, ?, ?, ?)
            """, (
                appsegment_id,
                app_id,
                date_str,
                start_ts,
                end_ts,
            ))
            conn.commit()
            logger.debug(f"Inserted appsegment {appsegment_id} [{app_id or 'unknown'}]")

    def segment_exists(self, segment_id: str) -> bool:
        """
        Check if a segment exists in the database.

        Args:
            segment_id: Segment identifier to check

        Returns:
            bool: True if segment exists, False otherwise
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT id FROM segments WHERE id = ?", (segment_id,))
            return cursor.fetchone() is not None

    def get_all_segments(self) -> List[SegmentRecord]:
        """
        Load all video segments ordered by start timestamp.

        Returns:
            List[SegmentRecord]: List of all segments in chronological order

        Example:
            segments = db.get_all_segments()
            for seg in segments:
                print(f"{seg.id}: {seg.start_ts} - {seg.end_ts}")
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, date, start_ts, end_ts, frame_count, fps, width, height,
                       file_size_bytes, video_path
                FROM segments
                ORDER BY start_ts ASC
            """)
            return [SegmentRecord(**dict(row)) for row in cursor.fetchall()]

    def get_all_appsegments(self) -> List[AppSegmentRecord]:
        """
        Load all application activity segments ordered by start timestamp.

        Returns:
            List[AppSegmentRecord]: List of all appsegments in chronological order

        Example:
            appsegments = db.get_all_appsegments()
            for appseg in appsegments:
                print(f"{appseg.app_id}: {appseg.start_ts} - {appseg.end_ts}")
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, app_id, date, start_ts, end_ts
                FROM appsegments
                ORDER BY start_ts ASC
            """)
            return [AppSegmentRecord(**dict(row)) for row in cursor.fetchall()]

    def get_segments_by_date(self, date_str: str) -> List[SegmentRecord]:
        """
        Get all segments for a specific date.

        Args:
            date_str: Date in YYYY-MM-DD format

        Returns:
            List[SegmentRecord]: List of segments for the specified date
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, date, start_ts, end_ts, frame_count, fps, width, height,
                       file_size_bytes, video_path
                FROM segments
                WHERE date = ?
                ORDER BY start_ts ASC
            """, (date_str,))
            return [SegmentRecord(**dict(row)) for row in cursor.fetchall()]

    def get_segments_by_date_range(
        self,
        start_date: str,
        end_date: str
    ) -> List[SegmentRecord]:
        """
        Get all segments within a date range (inclusive).

        Args:
            start_date: Start date in YYYY-MM-DD format
            end_date: End date in YYYY-MM-DD format

        Returns:
            List[SegmentRecord]: List of segments within the date range
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, date, start_ts, end_ts, frame_count, fps, width, height,
                       file_size_bytes, video_path
                FROM segments
                WHERE date >= ? AND date <= ?
                ORDER BY start_ts ASC
            """, (start_date, end_date))
            return [SegmentRecord(**dict(row)) for row in cursor.fetchall()]

    def find_segment_at_timestamp(
        self,
        timestamp: float
    ) -> Optional[SegmentRecord]:
        """
        Find segment that contains the specified timestamp.

        Args:
            timestamp: Unix timestamp to search for

        Returns:
            Optional[SegmentRecord]: Segment containing the timestamp, or None if not found
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, date, start_ts, end_ts, frame_count, fps, width, height,
                       file_size_bytes, video_path
                FROM segments
                WHERE start_ts <= ? AND end_ts >= ?
                ORDER BY start_ts ASC
                LIMIT 1
            """, (timestamp, timestamp))
            row = cursor.fetchone()
            return SegmentRecord(**dict(row)) if row else None

    def find_nearest_segment_forward(
        self,
        timestamp: float
    ) -> Optional[SegmentRecord]:
        """
        Find nearest segment at or after the specified timestamp.

        Args:
            timestamp: Unix timestamp to search from

        Returns:
            Optional[SegmentRecord]: Nearest segment forward, or None if not found
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, date, start_ts, end_ts, frame_count, fps, width, height,
                       file_size_bytes, video_path
                FROM segments
                WHERE start_ts >= ?
                ORDER BY start_ts ASC
                LIMIT 1
            """, (timestamp,))
            row = cursor.fetchone()
            return SegmentRecord(**dict(row)) if row else None

    def find_nearest_segment_backward(
        self,
        timestamp: float
    ) -> Optional[SegmentRecord]:
        """
        Find nearest segment at or before the specified timestamp.

        Args:
            timestamp: Unix timestamp to search from

        Returns:
            Optional[SegmentRecord]: Nearest segment backward, or None if not found
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, date, start_ts, end_ts, frame_count, fps, width, height,
                       file_size_bytes, video_path
                FROM segments
                WHERE end_ts <= ?
                ORDER BY start_ts DESC
                LIMIT 1
            """, (timestamp,))
            row = cursor.fetchone()
            return SegmentRecord(**dict(row)) if row else None

    def get_latest_timestamp(self) -> Optional[float]:
        """
        Get the latest timestamp (end of last segment).

        Returns:
            Optional[float]: Latest timestamp, or None if no segments exist
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT MAX(end_ts) as latest FROM segments")
            row = cursor.fetchone()
            return row["latest"] if row and row["latest"] else None

    def get_old_segments(self, cutoff_timestamp: float) -> List[Tuple[str, str]]:
        """
        Find segments older than the specified cutoff timestamp.

        Args:
            cutoff_timestamp: Unix timestamp cutoff for retention policy

        Returns:
            List[Tuple[str, str]]: List of (segment_id, video_path) tuples for old segments
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, video_path
                FROM segments
                WHERE start_ts < ?
                ORDER BY start_ts ASC
            """, (cutoff_timestamp,))
            return [(row["id"], row["video_path"]) for row in cursor.fetchall()]

    def delete_segment(self, segment_id: str) -> None:
        """
        Delete a segment from the database.

        Args:
            segment_id: Segment identifier to delete

        Note:
            This only deletes the database record. Video file cleanup is the
            caller's responsibility.
        """
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("DELETE FROM segments WHERE id = ?", (segment_id,))
            conn.commit()
            logger.debug(f"Deleted segment {segment_id}")

    def delete_appsegment(self, appsegment_id: str) -> None:
        """
        Delete an appsegment from the database.

        Args:
            appsegment_id: Appsegment identifier to delete
        """
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("DELETE FROM appsegments WHERE id = ?", (appsegment_id,))
            conn.commit()
            logger.debug(f"Deleted appsegment {appsegment_id}")

    def insert_ocr_text(
        self,
        frame_path: str,
        timestamp: float,
        text_content: str,
        confidence: float,
        segment_id: Optional[str] = None,
        language: str = "en",
    ) -> int:
        """
        Insert OCR text extraction result.

        Args:
            frame_path: Path to the screenshot frame
            timestamp: Unix timestamp of the frame
            text_content: Extracted text from OCR
            confidence: OCR confidence score (0.0 to 1.0)
            segment_id: Associated video segment ID (optional)
            language: Detected language code (default: 'en')

        Returns:
            int: ID of inserted OCR record

        Raises:
            sqlite3.Error: If insertion fails
        """
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO ocr_text
                (frame_path, segment_id, timestamp, text_content, confidence, language)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (frame_path, segment_id, timestamp, text_content, confidence, language))

            # Also insert into FTS5 index for full-text search
            ocr_id = cursor.lastrowid
            cursor.execute("""
                INSERT INTO ocr_search (rowid, text_content, segment_id, timestamp)
                VALUES (?, ?, ?, ?)
            """, (ocr_id, text_content, segment_id, timestamp))

            conn.commit()
            logger.debug(f"Inserted OCR text {ocr_id} [{len(text_content)} chars, confidence: {confidence:.2f}]")
            return ocr_id

    def insert_ocr_batch(
        self,
        ocr_records: List[Tuple[str, float, str, float, Optional[str], str]]
    ) -> int:
        """
        Insert multiple OCR records in a single transaction for performance.

        Args:
            ocr_records: List of tuples (frame_path, timestamp, text_content,
                        confidence, segment_id, language)

        Returns:
            int: Number of records inserted

        Example:
            records = [
                ("/path/frame1.png", 1234567890.0, "Hello", 0.95, "abc123", "en"),
                ("/path/frame2.png", 1234567892.0, "World", 0.92, "abc123", "en"),
            ]
            count = db.insert_ocr_batch(records)
        """
        if not ocr_records:
            return 0

        with self._get_connection() as conn:
            cursor = conn.cursor()

            # Insert into ocr_text table
            cursor.executemany("""
                INSERT INTO ocr_text
                (frame_path, timestamp, text_content, confidence, segment_id, language)
                VALUES (?, ?, ?, ?, ?, ?)
            """, ocr_records)

            # Get the IDs of inserted records
            first_id = cursor.lastrowid - len(ocr_records) + 1

            # Insert into FTS5 index
            fts_records = [
                (first_id + i, rec[2], rec[4], rec[1])
                for i, rec in enumerate(ocr_records)
            ]
            cursor.executemany("""
                INSERT INTO ocr_search (rowid, text_content, segment_id, timestamp)
                VALUES (?, ?, ?, ?)
            """, fts_records)

            conn.commit()
            logger.info(f"Batch inserted {len(ocr_records)} OCR records")
            return len(ocr_records)

    def search_ocr_text(
        self,
        query: str,
        limit: int = 100,
        min_confidence: float = 0.0
    ) -> List[Tuple[int, str, float, str, float]]:
        """
        Search OCR text using FTS5 full-text search.

        Args:
            query: Search query (supports FTS5 syntax: phrases, prefix, boolean)
            limit: Maximum number of results to return
            min_confidence: Minimum OCR confidence threshold (0.0 to 1.0)

        Returns:
            List[Tuple]: List of (id, text_content, timestamp, segment_id, confidence)
                        sorted by relevance (BM25 ranking)

        Example:
            results = db.search_ocr_text("important meeting")
            for id, text, ts, seg_id, conf in results:
                print(f"{ts}: {text} (confidence: {conf:.2f})")
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT
                    o.id,
                    o.text_content,
                    o.timestamp,
                    o.segment_id,
                    o.confidence,
                    s.rank
                FROM ocr_text o
                JOIN ocr_search s ON o.id = s.rowid
                WHERE s.text_content MATCH ?
                AND o.confidence >= ?
                ORDER BY s.rank
                LIMIT ?
            """, (query, min_confidence, limit))

            results = []
            for row in cursor.fetchall():
                results.append((
                    row[0],  # id
                    row[1],  # text_content
                    row[2],  # timestamp
                    row[3],  # segment_id
                    row[4],  # confidence
                ))

            logger.debug(f"Search query '{query}' returned {len(results)} results")
            return results

    def get_ocr_by_segment(self, segment_id: str) -> List[OCRTextRecord]:
        """
        Get all OCR text records for a specific segment.

        Args:
            segment_id: Segment identifier

        Returns:
            List[OCRTextRecord]: List of OCR records for the segment
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, frame_path, segment_id, timestamp, text_content,
                       confidence, language, created_at
                FROM ocr_text
                WHERE segment_id = ?
                ORDER BY timestamp ASC
            """, (segment_id,))
            return [OCRTextRecord(**dict(row)) for row in cursor.fetchall()]

    def get_ocr_by_timestamp_range(
        self,
        start_ts: float,
        end_ts: float
    ) -> List[OCRTextRecord]:
        """
        Get OCR text records within a timestamp range.

        Args:
            start_ts: Start timestamp
            end_ts: End timestamp

        Returns:
            List[OCRTextRecord]: List of OCR records within the range
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT id, frame_path, segment_id, timestamp, text_content,
                       confidence, language, created_at
                FROM ocr_text
                WHERE timestamp >= ? AND timestamp <= ?
                ORDER BY timestamp ASC
            """, (start_ts, end_ts))
            return [OCRTextRecord(**dict(row)) for row in cursor.fetchall()]

    def delete_ocr_by_segment(self, segment_id: str) -> int:
        """
        Delete all OCR records for a specific segment.

        Args:
            segment_id: Segment identifier

        Returns:
            int: Number of records deleted

        Note:
            This is automatically handled by CASCADE when segment is deleted,
            but can be called explicitly if needed.
        """
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("DELETE FROM ocr_text WHERE segment_id = ?", (segment_id,))
            deleted = cursor.rowcount
            conn.commit()
            logger.debug(f"Deleted {deleted} OCR records for segment {segment_id}")
            return deleted

    def get_database_stats(self) -> dict:
        """
        Get database statistics for diagnostics.

        Returns:
            dict: Statistics including segment count, date range, file size, etc.

        Example:
            stats = db.get_database_stats()
            print(f"Total segments: {stats['segment_count']}")
            print(f"Total size: {stats['total_video_bytes'] / 1024**3:.2f} GB")
        """
        with self._get_connection(read_only=True) as conn:
            cursor = conn.cursor()

            # Segment statistics
            cursor.execute("""
                SELECT
                    COUNT(*) as segment_count,
                    MIN(start_ts) as earliest_ts,
                    MAX(end_ts) as latest_ts,
                    SUM(file_size_bytes) as total_video_bytes,
                    SUM(frame_count) as total_frames
                FROM segments
            """)
            segment_stats = dict(cursor.fetchone())

            # AppSegment statistics
            cursor.execute("""
                SELECT
                    COUNT(*) as appsegment_count,
                    COUNT(DISTINCT app_id) as unique_app_count
                FROM appsegments
            """)
            appsegment_stats = dict(cursor.fetchone())

            # OCR statistics (if table exists)
            try:
                cursor.execute("""
                    SELECT
                        COUNT(*) as ocr_count,
                        AVG(confidence) as avg_confidence,
                        SUM(LENGTH(text_content)) as total_text_chars
                    FROM ocr_text
                """)
                ocr_stats = dict(cursor.fetchone())
            except sqlite3.OperationalError:
                # Table doesn't exist (schema < 1.1)
                ocr_stats = {
                    "ocr_count": 0,
                    "avg_confidence": 0.0,
                    "total_text_chars": 0
                }

            # Database file size
            db_size = self.db_path.stat().st_size if self.db_path.exists() else 0

            return {
                **segment_stats,
                **appsegment_stats,
                **ocr_stats,
                "database_size_bytes": db_size,
                "schema_version": self.get_schema_version(),
            }

    def vacuum(self) -> None:
        """
        Reclaim space from deleted records.

        This operation rebuilds the database file, removing unused space from
        deleted records. Should be run monthly or after large deletions.

        Warning:
            This operation may take several seconds on large databases and
            requires exclusive access.
        """
        logger.info("Starting database vacuum...")
        with self._get_connection() as conn:
            conn.execute("VACUUM")
        logger.info("Database vacuum completed")

    def check_integrity(self) -> bool:
        """
        Verify database integrity.

        Returns:
            bool: True if database is healthy, False if corrupted

        Example:
            if not db.check_integrity():
                logger.error("Database corruption detected!")
                restore_from_backup(db.db_path)
        """
        try:
            with self._get_connection(read_only=True) as conn:
                cursor = conn.cursor()
                cursor.execute("PRAGMA integrity_check")
                result = cursor.fetchone()
                is_ok = result[0] == "ok"
                if not is_ok:
                    logger.error(f"Integrity check failed: {result[0]}")
                return is_ok
        except Exception as e:
            logger.error(f"Integrity check error: {e}", exc_info=True)
            return False

    def backup(self, backup_dir: Optional[Path] = None) -> Path:
        """
        Create timestamped backup of database.

        Args:
            backup_dir: Directory for backup (default: same as database)

        Returns:
            Path: Path to created backup file

        Example:
            backup_path = db.backup()
            print(f"Backup created: {backup_path}")
        """
        timestamp = int(time.time())
        backup_name = f"{self.db_path.name}.backup.{timestamp}"

        if backup_dir is None:
            backup_dir = self.db_path.parent

        backup_path = backup_dir / backup_name
        shutil.copy2(self.db_path, backup_path)
        logger.info(f"Backup created: {backup_path}")
        return backup_path


def generate_segment_id() -> str:
    """
    Generate a unique segment or appsegment ID.

    Returns:
        str: 20 hex character identifier

    Example:
        segment_id = generate_segment_id()  # e.g., "1a2b3c4d5e6f7g8h9i0j"
    """
    return os.urandom(10).hex()


def init_database(db_path: Path) -> DatabaseManager:
    """
    Initialize and return a database manager instance.

    This is a convenience function that creates a DatabaseManager and initializes
    the schema. Safe to call multiple times.

    Args:
        db_path: Path to SQLite database file

    Returns:
        DatabaseManager: Initialized database manager instance

    Example:
        db = init_database(Path("~/Library/Application Support/Playback/data/meta.sqlite3"))
        db.insert_segment(...)
    """
    db = DatabaseManager(db_path)
    db.initialize()
    return db
