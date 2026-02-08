#!/usr/bin/env python3
"""
Data export utility for Playback application.

This script exports all recordings and database to a timestamped ZIP archive
for backup, migration, or uninstallation purposes. The export includes video
segments, database, and a manifest file describing the export contents.

Features:
- Export all video segments from chunks/ directory
- Export metadata database (meta.sqlite3)
- Generate manifest.json with export metadata
- Create timestamped ZIP file: playback-export-YYYYMMDD-HHMMSS.zip
- Progress indication during export
- Support for both dev and production data directories
- Configurable output path and compression level

Usage:
    # Basic export to default location (current directory)
    python3 export_data.py

    # Export to custom location
    python3 export_data.py --output /path/to/exports/

    # Custom compression level (0-9, higher=better compression, slower)
    python3 export_data.py --compression 9

    # Dry-run mode to preview export contents
    python3 export_data.py --dry-run
"""

import argparse
import json
import os
import sys
import zipfile
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple

# Add parent directory to path for lib imports
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib.paths import (
    get_base_data_directory,
    get_chunks_directory,
    get_database_path,
    is_development_mode,
)
from lib.logging_config import (
    setup_logger,
    log_info,
    log_warning,
    log_error,
    log_debug,
    log_resource_metrics,
    log_error_with_context,
)
from lib.utils import format_size
import time

# Import psutil for resource metrics (optional)
try:
    import psutil
    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False


def collect_files_to_export(logger) -> Tuple[List[Tuple[Path, str]], Dict[str, int]]:
    """
    Collect all files that will be exported.

    Args:
        logger: Logger instance

    Returns:
        Tuple of:
        - List of (source_path, archive_path) tuples
        - Dictionary with statistics (total_files, total_bytes, etc.)
    """
    files_to_export: List[Tuple[Path, str]] = []
    stats = {
        "video_files": 0,
        "video_bytes": 0,
        "database_bytes": 0,
        "total_files": 0,
        "total_bytes": 0,
    }

    chunks_dir = get_chunks_directory()
    db_path = get_database_path()
    data_dir = get_base_data_directory()

    log_debug(
        logger,
        "Starting file collection",
        chunks_dir=str(chunks_dir),
        db_path=str(db_path),
        data_dir=str(data_dir)
    )

    # Collect video segments
    if chunks_dir.exists():
        for root, dirs, files in os.walk(chunks_dir):
            for file in files:
                if not file.endswith('.mp4'):
                    continue

                source_path = Path(root) / file

                try:
                    file_size = source_path.stat().st_size

                    # Create archive path relative to data directory
                    rel_path = source_path.relative_to(data_dir)
                    archive_path = str(rel_path)

                    files_to_export.append((source_path, archive_path))

                    stats["video_files"] += 1
                    stats["video_bytes"] += file_size
                    stats["total_files"] += 1
                    stats["total_bytes"] += file_size

                except (OSError, FileNotFoundError) as e:
                    log_warning(
                        logger,
                        "Cannot access video file",
                        source_path=str(source_path),
                        error=str(e)
                    )

    # Include database if it exists
    if db_path.exists():
        try:
            db_size = db_path.stat().st_size
            files_to_export.append((db_path, "meta.sqlite3"))

            stats["database_bytes"] = db_size
            stats["total_files"] += 1
            stats["total_bytes"] += db_size

        except (OSError, FileNotFoundError) as e:
            log_warning(
                logger,
                "Cannot access database",
                db_path=str(db_path),
                error=str(e)
            )

    log_info(
        logger,
        "File collection completed",
        video_files=stats["video_files"],
        video_bytes=stats["video_bytes"],
        database_bytes=stats["database_bytes"],
        total_files=stats["total_files"],
        total_bytes=stats["total_bytes"]
    )

    return files_to_export, stats


def create_manifest(stats: Dict[str, int]) -> str:
    """
    Create manifest.json content with export metadata.

    Args:
        stats: Statistics dictionary from collect_files_to_export()

    Returns:
        JSON string for manifest.json
    """
    manifest = {
        "export_version": "1.0",
        "export_timestamp": datetime.now().isoformat(),
        "environment": "development" if is_development_mode() else "production",
        "statistics": {
            "total_files": stats["total_files"],
            "total_size_bytes": stats["total_bytes"],
            "total_size_formatted": format_size(stats["total_bytes"]),
            "video_files": stats["video_files"],
            "video_size_bytes": stats["video_bytes"],
            "video_size_formatted": format_size(stats["video_bytes"]),
            "database_size_bytes": stats["database_bytes"],
            "database_size_formatted": format_size(stats["database_bytes"]),
        },
        "contents": {
            "chunks/": "Video segments organized by date (YYYYMM/DD/)",
            "meta.sqlite3": "Metadata database containing segment information",
            "manifest.json": "This file - export metadata and contents description",
        },
        "notes": [
            "This export contains all video recordings and metadata from Playback.",
            "To restore: Extract the ZIP file and place contents in the appropriate data directory.",
            "Production data directory: ~/Library/Application Support/Playback/data/",
            "Development data directory: project_root/dev_data/",
            "Database format: SQLite 3.x with Write-Ahead Logging (WAL) mode",
            "Video format: MP4 (H.264 codec, AAC audio if present)",
        ]
    }

    return json.dumps(manifest, indent=2, sort_keys=False)


def create_export(
    output_path: Path,
    logger,
    compression: int = zipfile.ZIP_DEFLATED,
    compress_level: int = 6,
    dry_run: bool = False,
    verbose: bool = True
) -> None:
    """
    Create export archive with all recordings and database.

    Args:
        output_path: Path for the output ZIP file
        logger: Logger instance
        compression: ZIP compression method (ZIP_DEFLATED, ZIP_STORED, etc.)
        compress_level: Compression level (0-9, higher=better compression)
        dry_run: If True, preview export without creating file
        verbose: If True, print progress information
    """
    export_start_time = time.time()

    # Collect files
    if verbose:
        print("[export] Scanning data directory...")

    log_info(
        logger,
        "Starting export",
        output_path=str(output_path),
        compression_level=compress_level,
        dry_run=dry_run
    )

    files_to_export, stats = collect_files_to_export(logger)

    if stats["total_files"] == 0:
        log_error(
            logger,
            "No data found to export",
            data_dir=str(get_base_data_directory())
        )
        print("[export] No data found to export")
        print(f"[export] Data directory: {get_base_data_directory()}")
        sys.exit(1)

    # Log summary (structured)
    log_info(
        logger,
        "Export summary",
        environment="development" if is_development_mode() else "production",
        video_files=stats['video_files'],
        video_bytes=stats['video_bytes'],
        video_formatted=format_size(stats['video_bytes']),
        database_bytes=stats['database_bytes'],
        database_formatted=format_size(stats['database_bytes']),
        total_files=stats['total_files'],
        total_bytes=stats['total_bytes'],
        total_formatted=format_size(stats['total_bytes'])
    )

    # Print summary (user-facing)
    print(f"\n[export] Export Summary:")
    print(f"  Environment:    {'Development' if is_development_mode() else 'Production'}")
    print(f"  Video segments: {stats['video_files']} files ({format_size(stats['video_bytes'])})")
    print(f"  Database:       {format_size(stats['database_bytes'])}")
    print(f"  Total:          {stats['total_files']} files ({format_size(stats['total_bytes'])})")
    print()

    if dry_run:
        log_info(
            logger,
            "Dry run mode - no archive created",
            would_create=str(output_path),
            estimated_size_bytes=stats['total_bytes']
        )
        print("[export] DRY RUN MODE - No archive will be created")
        print(f"[export] Would create: {output_path}")
        print(f"[export] Estimated size: {format_size(stats['total_bytes'])}")
        print()

        if verbose:
            print("[export] Files to export:")
            for source_path, archive_path in files_to_export:
                file_size = source_path.stat().st_size
                print(f"  {archive_path} ({format_size(file_size)})")

        return

    # Collect metrics before ZIP creation
    if PSUTIL_AVAILABLE:
        metrics = collect_metrics(export_start_time)
        if metrics:
            log_resource_metrics(logger, **metrics, operation="before_zip_creation")

    # Create ZIP archive
    if verbose:
        print(f"[export] Creating archive: {output_path}")
        print(f"[export] Compression level: {compress_level}")
        print()

    log_info(
        logger,
        "Creating ZIP archive",
        output_path=str(output_path),
        compression_level=compress_level,
        total_files=stats['total_files']
    )

    try:
        with zipfile.ZipFile(
            output_path,
            mode='w',
            compression=compression,
            compresslevel=compress_level
        ) as zipf:
            # Add all collected files with progress
            for idx, (source_path, archive_path) in enumerate(files_to_export, 1):
                if verbose:
                    file_size = source_path.stat().st_size
                    progress = f"[{idx}/{stats['total_files']}]"
                    print(f"{progress} Adding: {archive_path} ({format_size(file_size)})")

                try:
                    zipf.write(source_path, archive_path)

                    if idx % 50 == 0 and PSUTIL_AVAILABLE:
                        metrics = collect_metrics(export_start_time)
                        if metrics:
                            log_resource_metrics(
                                logger,
                                **metrics,
                                operation="zip_creation_progress",
                                files_processed=idx,
                                total_files=stats['total_files']
                            )

                except Exception as e:
                    log_warning(
                        logger,
                        "Failed to add file to archive",
                        archive_path=archive_path,
                        error=str(e)
                    )
                    print(f"[export] Error adding {archive_path}: {e}")

            # Add manifest
            if verbose:
                print(f"[{stats['total_files'] + 1}/{stats['total_files'] + 1}] Adding: manifest.json")

            log_debug(logger, "Adding manifest to archive")
            manifest_content = create_manifest(stats)
            zipf.writestr("manifest.json", manifest_content)

        # Verify archive was created and get final size
        if output_path.exists():
            archive_size = output_path.stat().st_size
            compression_ratio = (1 - archive_size / stats['total_bytes']) * 100 if stats['total_bytes'] > 0 else 0
            export_duration = time.time() - export_start_time

            log_info(
                logger,
                "Export completed successfully",
                archive_path=str(output_path),
                archive_size_bytes=archive_size,
                archive_size_formatted=format_size(archive_size),
                compression_ratio=round(compression_ratio, 1),
                total_files=stats['total_files'] + 1,
                duration_s=round(export_duration, 2)
            )

            print()
            print("[export] Export completed successfully!")
            print(f"[export] Archive:         {output_path}")
            print(f"[export] Archive size:    {format_size(archive_size)}")
            print(f"[export] Compression:     {compression_ratio:.1f}%")
            print(f"[export] Total files:     {stats['total_files'] + 1} (including manifest)")

            if PSUTIL_AVAILABLE:
                metrics = collect_metrics(export_start_time)
                if metrics:
                    log_resource_metrics(logger, **metrics, operation="export_complete")
        else:
            log_error(logger, "Archive file was not created", expected_path=str(output_path))
            print("[export] Error: Archive file was not created")
            sys.exit(1)

    except Exception as e:
        log_error_with_context(
            logger,
            "Failed to create archive",
            exception=e,
            output_path=str(output_path)
        )
        print(f"[export] Error creating archive: {e}")

        # Clean up partial archive
        if output_path.exists():
            try:
                output_path.unlink()
                log_info(logger, "Removed incomplete archive", path=str(output_path))
                print(f"[export] Removed incomplete archive: {output_path}")
            except Exception:
                pass

        sys.exit(1)


def generate_output_filename() -> str:
    """
    Generate timestamped filename for export.

    Returns:
        Filename in format: playback-export-YYYYMMDD-HHMMSS.zip
    """
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return f"playback-export-{timestamp}.zip"


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Export all Playback recordings and database to ZIP archive",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Export to current directory with default settings
  python3 export_data.py

  # Export to custom location
  python3 export_data.py --output ~/Desktop/backups/

  # Maximum compression (slower but smaller file)
  python3 export_data.py --compression 9

  # Preview export without creating file
  python3 export_data.py --dry-run --verbose

Note:
  The script automatically detects development vs production mode based on
  the PLAYBACK_DEV_MODE environment variable and exports data from the
  appropriate directory.
        """
    )

    parser.add_argument(
        "--output",
        type=str,
        help="Output directory or file path (default: current directory with timestamped name)"
    )

    parser.add_argument(
        "--compression",
        type=int,
        choices=range(0, 10),
        default=6,
        metavar="LEVEL",
        help="Compression level 0-9 (0=none, 9=maximum, default: 6)"
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview export without creating archive"
    )

    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print detailed progress information"
    )

    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Minimize output (overrides --verbose)"
    )

    return parser.parse_args()


def collect_metrics(start_time: float) -> dict:
    """
    Collect resource usage metrics if psutil is available.

    Args:
        start_time: Service start time (from time.time())

    Returns:
        Dictionary of metrics including cpu_percent, memory_mb, disk_free_gb, uptime_hours
    """
    if not PSUTIL_AVAILABLE:
        return {}

    try:
        process = psutil.Process()
        cpu_percent = process.cpu_percent(interval=0.1)
        memory_mb = process.memory_info().rss / (1024 * 1024)
        disk_free_gb = psutil.disk_usage('/').free / (1024 * 1024 * 1024)
        uptime_hours = (time.time() - start_time) / 3600

        return {
            "cpu_percent": cpu_percent,
            "memory_mb": memory_mb,
            "disk_free_gb": disk_free_gb,
            "uptime_hours": uptime_hours,
        }
    except Exception:
        return {}


def main() -> None:
    """Main entry point for export script."""
    args = parse_args()

    # Setup structured logging
    logger = setup_logger("export_data", log_level="INFO", console_output=False)

    start_time = time.time()

    # Determine verbosity
    verbose = args.verbose and not args.quiet

    log_info(
        logger,
        "Export script started",
        verbose=verbose,
        dry_run=args.dry_run,
        compression_level=args.compression,
        environment="development" if is_development_mode() else "production",
        psutil_available=PSUTIL_AVAILABLE
    )

    # Collect initial resource metrics
    if PSUTIL_AVAILABLE:
        metrics = collect_metrics(start_time)
        if metrics:
            log_resource_metrics(logger, **metrics, operation="start")

    # Determine output path
    if args.output:
        output_path = Path(args.output).expanduser().resolve()

        # If output is a directory, create filename in that directory
        if output_path.is_dir():
            output_path = output_path / generate_output_filename()
        elif output_path.exists() and output_path.is_dir():
            output_path = output_path / generate_output_filename()

        # Ensure parent directory exists
        output_path.parent.mkdir(parents=True, exist_ok=True)
    else:
        # Default to current directory with timestamped filename
        output_path = Path.cwd() / generate_output_filename()

    log_info(logger, "Output path determined", output_path=str(output_path))

    # Confirm if file already exists (unless dry-run)
    if output_path.exists() and not args.dry_run:
        log_warning(logger, "Output file already exists", output_path=str(output_path))
        print(f"[export] Warning: Output file already exists: {output_path}")
        try:
            response = input("[export] Overwrite? (y/N): ")
            if response.lower() != 'y':
                log_info(logger, "Export cancelled by user", reason="declined_overwrite")
                print("[export] Export cancelled")
                sys.exit(0)
            else:
                log_info(logger, "User confirmed overwrite")
        except (KeyboardInterrupt, EOFError):
            log_info(logger, "Export cancelled by user", reason="keyboard_interrupt")
            print("\n[export] Export cancelled")
            sys.exit(0)

    # Determine compression method
    if args.compression == 0:
        compression_method = zipfile.ZIP_STORED
        compress_level = 0
    else:
        compression_method = zipfile.ZIP_DEFLATED
        compress_level = args.compression

    # Create export
    try:
        create_export(
            output_path=output_path,
            logger=logger,
            compression=compression_method,
            compress_level=compress_level,
            dry_run=args.dry_run,
            verbose=verbose or not args.quiet
        )
    except KeyboardInterrupt:
        log_info(logger, "Export interrupted by user", output_path=str(output_path))
        print("\n[export] Export cancelled by user")

        # Clean up partial archive
        if output_path.exists() and not args.dry_run:
            try:
                output_path.unlink()
                log_info(logger, "Removed incomplete archive after interruption", path=str(output_path))
                print(f"[export] Removed incomplete archive: {output_path}")
            except Exception:
                pass

        sys.exit(1)


if __name__ == "__main__":
    main()
