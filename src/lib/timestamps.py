#!/usr/bin/env python3
"""
Filename parsing and generation utilities for Playback.

This module provides functions for working with timestamp-based filenames used
throughout the Playback system. Filenames follow the format:
    YYYYMMDD-HHMMSS-<uuid>-<app_id>

Functions:
    - parse_timestamp_from_name: Extract epoch timestamp from filename
    - parse_app_from_name: Extract app bundle ID from filename
    - generate_chunk_name: Generate new filename with timestamp and app ID
    - sanitize_app_id: Normalize app bundle ID for filename usage
"""

import re
import uuid
from datetime import datetime
from typing import Optional


DATE_RE = re.compile(r"^(?P<date>\d{8})-(?P<time>\d{6})")


def parse_timestamp_from_name(name: str) -> Optional[float]:
    """
    Extract timestamp from filename in format YYYYMMDD-HHMMSS-...

    Args:
        name: Filename (with or without extension) to parse

    Returns:
        Timestamp in epoch seconds, or None if format doesn't match

    Examples:
        >>> parse_timestamp_from_name("20250207-143022-abc123-com.example.app")
        1707318622.0
        >>> parse_timestamp_from_name("invalid-name")
        None
    """
    m = DATE_RE.match(name)
    if not m:
        return None

    date_str = m.group("date")
    time_str = m.group("time")

    try:
        dt = datetime.strptime(date_str + time_str, "%Y%m%d%H%M%S")
        return dt.timestamp()
    except ValueError:
        return None


def parse_app_from_name(name: str) -> Optional[str]:
    """
    Extract app bundle ID from filename in format YYYYMMDD-HHMMSS-<uuid>-<app_id>

    Args:
        name: Filename (with or without extension) to parse

    Returns:
        App bundle ID string, or None if not present in filename

    Examples:
        >>> parse_app_from_name("20250207-143022-abc123-com.example.app")
        'com.example.app'
        >>> parse_app_from_name("20250207-143022-abc123")
        None
        >>> parse_app_from_name("20250207-143022-abc123-")
        None
        >>> parse_app_from_name("20250207-143022-abc123-com.example.app.png")
        'com.example.app'
    """
    m = DATE_RE.match(name)
    if not m:
        return None

    rest = name[m.end():]
    if not rest.startswith("-"):
        return None

    rest = rest[1:]
    parts = rest.split("-", 1)
    if len(parts) != 2:
        return None

    app_id = parts[1] or None
    if not app_id:
        return None

    if "." in app_id:
        base_parts = app_id.rsplit(".", 1)
        if base_parts[-1] in ("png", "jpg", "jpeg", "mp4", "mov"):
            app_id = base_parts[0]

    return app_id if app_id else None


def sanitize_app_id(app_id: str) -> str:
    """
    Normalize app bundle ID for safe use in filenames.

    Keeps letters, digits, and dots; replaces everything else with underscores.
    Empty strings are converted to "unknown".

    Args:
        app_id: Raw app bundle identifier (e.g., from NSWorkspace)

    Returns:
        Sanitized app ID safe for filename usage

    Examples:
        >>> sanitize_app_id("com.example.app")
        'com.example.app'
        >>> sanitize_app_id("My App!@#")
        'My_App___'
        >>> sanitize_app_id("")
        'unknown'
    """
    if not app_id:
        return "unknown"
    return re.sub(r"[^A-Za-z0-9.]+", "_", app_id)


def generate_chunk_name(timestamp: datetime, app_id: Optional[str] = None) -> str:
    """
    Generate unique filename for a screenshot chunk.

    Format: YYYYMMDD-HHMMSS-<uuid>-<app_id>
    The timestamp makes it easy to parse later, and the UUID ensures uniqueness
    even if multiple screenshots are taken in the same second.

    Args:
        timestamp: DateTime when the screenshot was captured
        app_id: Optional bundle ID of the frontmost application

    Returns:
        Filename string (without extension)

    Examples:
        >>> dt = datetime(2025, 2, 7, 14, 30, 22)
        >>> name = generate_chunk_name(dt, "com.example.app")
        >>> name.startswith("20250207-143022-")
        True
        >>> name.endswith("-com.example.app")
        True
    """
    date_part = timestamp.strftime("%Y%m%d")
    time_part = timestamp.strftime("%H%M%S")
    short_uuid = uuid.uuid4().hex[:8]
    sanitized_app = sanitize_app_id(app_id or "unknown")

    return f"{date_part}-{time_part}-{short_uuid}-{sanitized_app}"
