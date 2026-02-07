"""Shared Python utilities for Playback services.

This package provides common functionality used across recording, processing,
and other background services:

- video: FFmpeg wrappers for video encoding and processing
- paths: Environment-aware path resolution
- timestamps: Filename parsing and timestamp generation
- macos: CoreGraphics and AppleScript integration
- database: SQLite operations and schema management
"""

from .database import (
    DatabaseManager,
    SegmentRecord,
    AppSegmentRecord,
    generate_segment_id,
    init_database,
)

__all__ = [
    "video",
    "paths",
    "timestamps",
    "macos",
    "database",
    "DatabaseManager",
    "SegmentRecord",
    "AppSegmentRecord",
    "generate_segment_id",
    "init_database",
]
