#!/usr/bin/env python3
"""
Shared utility functions for Playback.

This module provides common utility functions used across multiple scripts
and services in the Playback system.

Functions:
    - format_size: Format byte count as human-readable string
"""


def format_size(bytes_count: int) -> str:
    """
    Format byte count as human-readable string.

    Converts raw byte counts into human-readable format with appropriate
    units (B, KB, MB, GB). Uses 1024-based units (binary prefixes).

    Args:
        bytes_count: Number of bytes to format

    Returns:
        Formatted string (e.g., "1.5 GB", "250 MB", "42 B")

    Examples:
        >>> format_size(512)
        '512 B'
        >>> format_size(2048)
        '2.0 KB'
        >>> format_size(1572864)
        '1.5 MB'
        >>> format_size(1610612736)
        '1.50 GB'
    """
    if bytes_count < 1024:
        return f"{bytes_count} B"
    elif bytes_count < 1024 ** 2:
        return f"{bytes_count / 1024:.1f} KB"
    elif bytes_count < 1024 ** 3:
        return f"{bytes_count / (1024 ** 2):.1f} MB"
    else:
        return f"{bytes_count / (1024 ** 3):.2f} GB"
