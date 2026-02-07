#!/usr/bin/env python3
"""
Storage cleanup service for Playback application.

This script implements retention policies for temporary screenshots and video
recordings. It can be run manually or scheduled via LaunchAgent.

Features:
- Automatic cleanup based on retention policies from config.json
- Manual cleanup with policy override
- Dry-run mode for previewing deletions
- Storage usage calculation and reporting
- Database cleanup (orphaned segments, vacuum)
- Safe cleanup with error handling and logging

Retention Policies:
- "never": Keep all files indefinitely
- "1_day": Delete files older than 24 hours
- "1_week": Delete files older than 7 days
- "1_month": Delete files older than 30 days
"""

import argparse
import os
import shutil
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Tuple

# Add parent directory to path for lib imports
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib.config import load_config_with_defaults
from lib.database import init_database
from lib.paths import (
    get_base_data_directory,
    get_chunks_directory,
    get_database_path,
    get_temp_directory,
)


def format_size(bytes_count: int) -> str:
    """
    Format byte count as human-readable string.

    Args:
        bytes_count: Number of bytes

    Returns:
        Formatted string (e.g., "1.5 GB", "250 MB")
    """
    if bytes_count < 1024:
        return f"{bytes_count} B"
    elif bytes_count < 1024 ** 2:
        return f"{bytes_count / 1024:.1f} KB"
    elif bytes_count < 1024 ** 3:
        return f"{bytes_count / (1024 ** 2):.1f} MB"
    else:
        return f"{bytes_count / (1024 ** 3):.2f} GB"


def calculate_storage_usage() -> Dict[str, int]:
    """
    Calculate storage usage for all Playback data.

    Returns:
        Dictionary with usage breakdown:
        - temp_bytes: Size of temp directory
        - chunks_bytes: Size of chunks directory
        - database_bytes: Size of database file
        - total_bytes: Total storage used
    """
    usage = {
        "temp_bytes": 0,
        "chunks_bytes": 0,
        "database_bytes": 0,
        "total_bytes": 0,
    }

    # Calculate temp directory size
    temp_dir = get_temp_directory()
    if temp_dir.exists():
        for root, dirs, files in os.walk(temp_dir):
            for file in files:
                if file.startswith('.'):
                    continue
                try:
                    file_path = Path(root) / file
                    usage["temp_bytes"] += file_path.stat().st_size
                except (OSError, FileNotFoundError):
                    pass

    # Calculate chunks directory size
    chunks_dir = get_chunks_directory()
    if chunks_dir.exists():
        for root, dirs, files in os.walk(chunks_dir):
            for file in files:
                if not file.endswith('.mp4'):
                    continue
                try:
                    file_path = Path(root) / file
                    usage["chunks_bytes"] += file_path.stat().st_size
                except (OSError, FileNotFoundError):
                    pass

    # Calculate database size
    db_path = get_database_path()
    if db_path.exists():
        usage["database_bytes"] = db_path.stat().st_size

    usage["total_bytes"] = (
        usage["temp_bytes"] + usage["chunks_bytes"] + usage["database_bytes"]
    )

    return usage


def get_disk_space_available() -> int:
    """
    Get available disk space in bytes.

    Returns:
        Number of free bytes available on disk
    """
    data_dir = get_base_data_directory()
    usage = shutil.disk_usage(data_dir)
    return usage.free


def calculate_cutoff_timestamp(policy: str) -> float:
    """
    Calculate cutoff timestamp for retention policy.

    Args:
        policy: Retention policy ("never", "1_day", "1_week", "1_month")

    Returns:
        Unix timestamp cutoff (files older than this should be deleted)

    Raises:
        ValueError: If policy is invalid
    """
    if policy == "never":
        # Return timestamp far in the future so nothing gets deleted
        return float('inf')

    age_days = {
        "1_day": 1,
        "1_week": 7,
        "1_month": 30,
    }

    if policy not in age_days:
        raise ValueError(f"Invalid retention policy: {policy}")

    cutoff_time = datetime.now() - timedelta(days=age_days[policy])
    return cutoff_time.timestamp()


def cleanup_temp_files(
    policy: str,
    dry_run: bool = False,
    verbose: bool = False
) -> Tuple[int, int]:
    """
    Clean up temporary screenshot files based on retention policy.

    Args:
        policy: Retention policy to apply
        dry_run: If True, only preview deletions without actually deleting
        verbose: If True, print detailed information

    Returns:
        Tuple of (files_deleted, bytes_freed)
    """
    if policy == "never":
        if verbose:
            print("[cleanup] Temp retention policy is 'never', skipping cleanup")
        return 0, 0

    cutoff_ts = calculate_cutoff_timestamp(policy)
    temp_dir = get_temp_directory()

    if not temp_dir.exists():
        if verbose:
            print(f"[cleanup] Temp directory does not exist: {temp_dir}")
        return 0, 0

    deleted_count = 0
    freed_bytes = 0

    for root, dirs, files in os.walk(temp_dir):
        for file in files:
            # Skip hidden files
            if file.startswith('.'):
                continue

            file_path = Path(root) / file

            try:
                # Use file creation time (or modification time as fallback)
                stat = file_path.stat()
                file_ts = getattr(stat, 'st_birthtime', stat.st_mtime)

                if file_ts < cutoff_ts:
                    file_size = stat.st_size

                    if verbose:
                        file_date = datetime.fromtimestamp(file_ts).strftime('%Y-%m-%d %H:%M:%S')
                        print(f"[cleanup] {'Would delete' if dry_run else 'Deleting'}: {file} ({format_size(file_size)}, {file_date})")

                    if not dry_run:
                        file_path.unlink()

                    deleted_count += 1
                    freed_bytes += file_size

            except Exception as e:
                print(f"[cleanup] Error processing {file_path}: {e}")

    # Clean up empty directories
    if not dry_run:
        for root, dirs, files in os.walk(temp_dir, topdown=False):
            for dir_name in dirs:
                dir_path = Path(root) / dir_name
                try:
                    # Check if directory is empty (ignoring hidden files)
                    remaining = [f for f in dir_path.iterdir() if not f.name.startswith('.')]
                    if not remaining:
                        dir_path.rmdir()
                        if verbose:
                            print(f"[cleanup] Removed empty directory: {dir_path}")
                except Exception as e:
                    if verbose:
                        print(f"[cleanup] Could not remove directory {dir_path}: {e}")

    return deleted_count, freed_bytes


def cleanup_old_recordings(
    policy: str,
    dry_run: bool = False,
    verbose: bool = False
) -> Tuple[int, int]:
    """
    Clean up old video recordings based on retention policy.

    Deletes both video files and database entries (segments + appsegments).

    Args:
        policy: Retention policy to apply
        dry_run: If True, only preview deletions without actually deleting
        verbose: If True, print detailed information

    Returns:
        Tuple of (segments_deleted, bytes_freed)
    """
    if policy == "never":
        if verbose:
            print("[cleanup] Recording retention policy is 'never', skipping cleanup")
        return 0, 0

    cutoff_ts = calculate_cutoff_timestamp(policy)
    db = init_database(get_database_path())

    # Find old segments
    old_segments = db.get_old_segments(cutoff_ts)

    if not old_segments:
        if verbose:
            print("[cleanup] No old segments found to delete")
        return 0, 0

    deleted_count = 0
    freed_bytes = 0
    base_data_dir = get_database_path().parent

    for segment_id, video_path in old_segments:
        full_path = base_data_dir / video_path

        try:
            # Get file size before deletion
            file_size = 0
            if full_path.exists():
                file_size = full_path.stat().st_size

                if verbose:
                    segment_date = datetime.fromtimestamp(cutoff_ts).strftime('%Y-%m-%d %H:%M:%S')
                    print(f"[cleanup] {'Would delete' if dry_run else 'Deleting'}: {video_path} ({format_size(file_size)})")

                # Delete video file
                if not dry_run:
                    full_path.unlink()

                freed_bytes += file_size

            # Delete database entries
            if not dry_run:
                # Note: We don't have a direct method to delete appsegments by segment_id
                # We'll delete the segment, and rely on database constraints or manual cleanup
                db.delete_segment(segment_id)

            deleted_count += 1

        except Exception as e:
            print(f"[cleanup] Error deleting segment {segment_id}: {e}")

    # Clean up empty directories
    if not dry_run:
        chunks_dir = get_chunks_directory()
        for root, dirs, files in os.walk(chunks_dir, topdown=False):
            for dir_name in dirs:
                dir_path = Path(root) / dir_name
                try:
                    # Check if directory is empty (ignoring hidden files)
                    remaining = [f for f in dir_path.iterdir() if not f.name.startswith('.')]
                    if not remaining:
                        dir_path.rmdir()
                        if verbose:
                            print(f"[cleanup] Removed empty directory: {dir_path}")
                except Exception as e:
                    if verbose:
                        print(f"[cleanup] Could not remove directory {dir_path}: {e}")

    return deleted_count, freed_bytes


def cleanup_orphaned_segments(
    dry_run: bool = False,
    verbose: bool = False
) -> int:
    """
    Remove database entries for segments with missing video files.

    Args:
        dry_run: If True, only preview deletions without actually deleting
        verbose: If True, print detailed information

    Returns:
        Number of orphaned segments removed
    """
    db = init_database(get_database_path())
    segments = db.get_all_segments()

    orphaned_count = 0
    base_data_dir = get_database_path().parent

    for segment in segments:
        full_path = base_data_dir / segment.video_path

        if not full_path.exists():
            if verbose:
                print(f"[cleanup] {'Would remove' if dry_run else 'Removing'} orphaned segment: {segment.id} ({segment.video_path})")

            if not dry_run:
                db.delete_segment(segment.id)

            orphaned_count += 1

    return orphaned_count


def vacuum_database(verbose: bool = False) -> int:
    """
    Reclaim space from deleted rows in database.

    Args:
        verbose: If True, print detailed information

    Returns:
        Number of bytes freed by vacuum operation
    """
    db_path = get_database_path()

    if not db_path.exists():
        if verbose:
            print("[cleanup] Database does not exist, skipping vacuum")
        return 0

    # Get size before vacuum
    size_before = db_path.stat().st_size

    if verbose:
        print(f"[cleanup] Database size before vacuum: {format_size(size_before)}")

    # Execute vacuum
    db = init_database(db_path)
    db.vacuum()

    # Get size after vacuum
    size_after = db_path.stat().st_size
    freed_bytes = size_before - size_after

    if verbose:
        print(f"[cleanup] Database size after vacuum: {format_size(size_after)}")
        print(f"[cleanup] Space freed by vacuum: {format_size(freed_bytes)}")

    return freed_bytes


def print_storage_report(verbose: bool = False) -> None:
    """
    Print storage usage report.

    Args:
        verbose: If True, include additional details
    """
    usage = calculate_storage_usage()
    available = get_disk_space_available()

    print("\n=== Storage Usage Report ===")
    print(f"Temp files:     {format_size(usage['temp_bytes'])}")
    print(f"Video chunks:   {format_size(usage['chunks_bytes'])}")
    print(f"Database:       {format_size(usage['database_bytes'])}")
    print(f"Total used:     {format_size(usage['total_bytes'])}")
    print(f"Disk available: {format_size(available)}")
    print("============================\n")


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Clean up old temporary files and video recordings based on retention policies"
    )

    parser.add_argument(
        "--auto",
        action="store_true",
        help="Automatic cleanup based on retention policies in config.json"
    )

    parser.add_argument(
        "--policy",
        type=str,
        choices=["never", "1_day", "1_week", "1_month"],
        help="Override retention policy for both temp and recordings"
    )

    parser.add_argument(
        "--temp-policy",
        type=str,
        choices=["never", "1_day", "1_week", "1_month"],
        help="Override retention policy for temp files only"
    )

    parser.add_argument(
        "--recording-policy",
        type=str,
        choices=["never", "1_day", "1_week", "1_month"],
        help="Override retention policy for recordings only"
    )

    parser.add_argument(
        "--orphaned",
        action="store_true",
        help="Clean up orphaned segments (database entries without video files)"
    )

    parser.add_argument(
        "--vacuum",
        action="store_true",
        help="Vacuum database to reclaim space"
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview what would be deleted without actually deleting"
    )

    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print detailed information during cleanup"
    )

    parser.add_argument(
        "--report",
        action="store_true",
        help="Print storage usage report"
    )

    return parser.parse_args()


def main() -> None:
    """Main entry point for cleanup script."""
    args = parse_args()

    # Print storage report if requested
    if args.report:
        print_storage_report(verbose=args.verbose)

    # If no action specified and not auto mode, print usage
    if not (args.auto or args.policy or args.temp_policy or args.recording_policy or args.orphaned or args.vacuum):
        print("No action specified. Use --auto, --policy, --orphaned, --vacuum, or --report")
        sys.exit(0)

    # Load config for automatic mode
    config = load_config_with_defaults()

    # Determine policies to use
    if args.policy:
        temp_policy = args.policy
        recording_policy = args.policy
    else:
        temp_policy = args.temp_policy if args.temp_policy else config.temp_retention_policy
        recording_policy = args.recording_policy if args.recording_policy else config.recording_retention_policy

    if args.dry_run:
        print("[cleanup] DRY RUN MODE - No files will be deleted")
        print()

    total_files_deleted = 0
    total_bytes_freed = 0

    # Clean up temp files
    if args.auto or args.policy or args.temp_policy:
        if args.verbose:
            print(f"[cleanup] Cleaning temp files with policy: {temp_policy}")

        temp_deleted, temp_freed = cleanup_temp_files(
            policy=temp_policy,
            dry_run=args.dry_run,
            verbose=args.verbose
        )

        total_files_deleted += temp_deleted
        total_bytes_freed += temp_freed

        print(f"[cleanup] Temp cleanup: {temp_deleted} files deleted, {format_size(temp_freed)} freed")

    # Clean up old recordings
    if args.auto or args.policy or args.recording_policy:
        if args.verbose:
            print(f"[cleanup] Cleaning recordings with policy: {recording_policy}")

        recordings_deleted, recordings_freed = cleanup_old_recordings(
            policy=recording_policy,
            dry_run=args.dry_run,
            verbose=args.verbose
        )

        total_files_deleted += recordings_deleted
        total_bytes_freed += recordings_freed

        print(f"[cleanup] Recording cleanup: {recordings_deleted} segments deleted, {format_size(recordings_freed)} freed")

    # Clean up orphaned segments
    if args.orphaned:
        if args.verbose:
            print("[cleanup] Cleaning orphaned segments")

        orphaned_count = cleanup_orphaned_segments(
            dry_run=args.dry_run,
            verbose=args.verbose
        )

        print(f"[cleanup] Orphaned segments: {orphaned_count} removed")

    # Vacuum database
    if args.vacuum and not args.dry_run:
        if args.verbose:
            print("[cleanup] Vacuuming database")

        vacuum_freed = vacuum_database(verbose=args.verbose)

        total_bytes_freed += vacuum_freed

        print(f"[cleanup] Database vacuum: {format_size(vacuum_freed)} freed")

    # Print summary
    print()
    print(f"[cleanup] Total: {total_files_deleted} items deleted, {format_size(total_bytes_freed)} freed")

    if args.dry_run:
        print("[cleanup] DRY RUN - No changes were made")


if __name__ == "__main__":
    main()
