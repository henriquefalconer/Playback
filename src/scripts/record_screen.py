#!/usr/bin/env python3
"""
Screen recording service for Playback.

Continuously captures screenshots at configured intervals using macOS's native
`screencapture` utility. Implements pause detection, app exclusion, and resource
monitoring with structured JSON logging.

Requirements:
- macOS with screencapture utility
- Python 3.12+
- Screen Recording permission granted in System Settings
"""

import subprocess
import time
import sys
from datetime import datetime
from pathlib import Path

# Add parent directory to path to import lib modules
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from lib.paths import (
    get_temp_directory,
    ensure_directory_exists,
    get_timeline_open_signal_path,
)
from lib.macos import (
    is_screen_unavailable,
    get_active_display_index,
    get_frontmost_app_bundle_id,
)
from lib.timestamps import generate_chunk_name
from lib.config import load_config_with_defaults
from lib.logging_config import (
    setup_logger,
    log_info,
    log_warning,
    log_error,
    log_critical,
    log_debug,
    log_resource_metrics,
    log_error_with_context,
)

# Try to import psutil for resource monitoring
try:
    import psutil

    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False


def _has_screen_recording_permission() -> bool:
    """
    Verify Screen Recording permission by attempting a test screenshot.

    Returns:
        True if permission granted, False otherwise
    """
    import tempfile

    try:
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as temp_file:
            temp_path = Path(temp_file.name)

        try:
            cmd = ["screencapture", "-x", "-t", "png", str(temp_path)]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)

            if (
                result.returncode == 0
                and temp_path.exists()
                and temp_path.stat().st_size > 0
            ):
                return True
            else:
                return False

        finally:
            if temp_path.exists():
                temp_path.unlink()

    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, Exception):
        return False


def ensure_chunk_dir(now: datetime) -> Path:
    """
    Ensure temp/YYYYMM/DD directory exists.

    Args:
        now: Current datetime

    Returns:
        Path to day directory
    """
    year_month = now.strftime("%Y%m")
    day = now.strftime("%d")

    day_dir = get_temp_directory() / year_month / day
    ensure_directory_exists(day_dir, mode=0o700)
    return day_dir


def capture_screen(output_path: Path, logger) -> None:
    """
    Capture screenshot using macOS screencapture utility.

    Args:
        output_path: Path where screenshot should be saved
        logger: Logger instance for structured logging

    Raises:
        subprocess.CalledProcessError: If screencapture command fails
    """
    temp_path = output_path.with_suffix(".png")

    # Try to detect active display
    display_index = get_active_display_index()

    cmd = ["screencapture", "-x", "-t", "png"]

    if display_index is not None:
        log_debug(logger, "Using active display", display_index=display_index)
        cmd.extend(["-D", str(display_index)])

    cmd.append(str(temp_path))

    subprocess.run(cmd, check=True)

    # Set secure permissions (0o600 = user read/write only)
    import os

    os.chmod(temp_path, 0o600)

    # Rename to remove .png extension
    temp_path.rename(output_path)

    # Ensure final file has secure permissions
    os.chmod(output_path, 0o600)


def is_timeline_viewer_open() -> bool:
    """
    Check if timeline viewer is open by checking signal file.

    Returns:
        True if signal file exists, False otherwise
    """
    signal_path = get_timeline_open_signal_path()
    return signal_path.exists()


def collect_metrics(start_time: float, total_captures: int) -> dict:
    """
    Collect resource usage metrics if psutil is available.

    Args:
        start_time: Service start time (from time.time())
        total_captures: Total number of captures since start

    Returns:
        Dictionary of metrics
    """
    if not PSUTIL_AVAILABLE:
        return {}

    try:
        process = psutil.Process()
        cpu_percent = process.cpu_percent(interval=0.1)
        memory_info = process.memory_info()
        memory_mb = memory_info.rss / (1024 * 1024)

        # Get disk usage for temp directory
        temp_dir = get_temp_directory()
        disk_usage = psutil.disk_usage(str(temp_dir))
        disk_free_gb = disk_usage.free / (1024 * 1024 * 1024)

        uptime_hours = (time.time() - start_time) / 3600

        return {
            "cpu_percent": cpu_percent,
            "memory_mb": memory_mb,
            "disk_free_gb": disk_free_gb,
            "uptime_hours": uptime_hours,
            "captures_total": total_captures,
        }
    except Exception:
        return {}


def main(interval_seconds: int = 2) -> None:
    """
    Main recording loop.

    Captures screenshots at regular intervals, pausing when timeline viewer is open
    and skipping excluded apps as configured.

    Args:
        interval_seconds: Seconds between captures (default: 2)
    """
    # Setup structured logging
    logger = setup_logger("recording", log_level="INFO", console_output=False)

    log_info(logger, "Recording service starting", interval_seconds=interval_seconds)

    # Verify Screen Recording permission
    if not _has_screen_recording_permission():
        log_critical(
            logger,
            "Screen Recording permission denied",
            resolution="Grant permission in System Settings > Privacy & Security > Screen Recording",
        )

        # Also print to stderr for immediate visibility
        error_message = """
[Playback] CRITICAL: Screen Recording permission denied.

To grant permission:
1. Open System Settings (Preferences)
2. Go to Privacy & Security > Screen Recording
3. Enable permission for the app running this script
4. Restart this service after granting permission

Service exiting now.
"""
        print(error_message, file=sys.stderr)
        sys.exit(1)

    log_info(logger, "Screen Recording permission verified")

    temp_root = get_temp_directory()
    signal_path = get_timeline_open_signal_path()
    config = load_config_with_defaults()

    log_info(
        logger,
        "Recording service initialized",
        temp_directory=str(temp_root),
        signal_path=str(signal_path),
        excluded_apps=config.excluded_apps or [],
        exclusion_mode=config.exclusion_mode,
    )

    timeline_was_open = False
    last_config_check = time.time()
    start_time = time.time()
    total_captures = 0
    last_metrics_log = 0

    while True:
        now = datetime.now()
        cycle_start = time.time()

        # Reload config every 30 seconds
        if time.time() - last_config_check > 30:
            config = load_config_with_defaults()
            last_config_check = time.time()
            log_debug(logger, "Configuration reloaded")

        # Check if timeline viewer is open
        timeline_open = is_timeline_viewer_open()

        # Log timeline viewer state changes
        if timeline_open and not timeline_was_open:
            log_info(logger, "Timeline viewer opened - pausing recording")
            timeline_was_open = True
        elif not timeline_open and timeline_was_open:
            log_info(logger, "Timeline viewer closed - resuming recording")
            timeline_was_open = False

        # Skip capture if timeline viewer is open
        if timeline_open:
            log_debug(logger, "Skipping capture - timeline viewer open")
            time.sleep(interval_seconds)
            continue

        # Check if screen is unavailable (screensaver, locked, off)
        screen_unavailable = is_screen_unavailable()

        if screen_unavailable:
            log_debug(logger, "Skipping capture - screen unavailable")
            time.sleep(interval_seconds)
            continue

        # Get frontmost app bundle ID
        app_id = get_frontmost_app_bundle_id()

        # Check if app is excluded
        if config.is_app_excluded(app_id):
            if config.exclusion_mode == "skip":
                log_debug(
                    logger, "Skipping capture - app excluded", app_id=app_id or "unknown"
                )
                time.sleep(interval_seconds)
                continue
            # If exclusion_mode is "invisible", still capture
            # (future: implement blurring/redaction)

        # Prepare capture directory
        day_dir = ensure_chunk_dir(now)

        # Generate chunk name with timestamp and app ID
        chunk_name = generate_chunk_name(now, app_id)
        chunk_path = day_dir / chunk_name

        try:
            capture_screen(chunk_path, logger)
            total_captures += 1

            file_size_kb = chunk_path.stat().st_size / 1024

            log_info(
                logger,
                "Screenshot captured",
                path=str(chunk_path),
                size_kb=round(file_size_kb, 1),
                app_id=app_id or "unknown",
            )

        except subprocess.CalledProcessError as e:
            log_error_with_context(
                logger,
                "Screenshot capture failed",
                exception=e,
                path=str(chunk_path),
                return_code=e.returncode,
            )

        except Exception as e:
            log_error_with_context(
                logger,
                "Unexpected error during capture",
                exception=e,
                path=str(chunk_path),
            )

        # Log resource metrics every 100 captures (~200 seconds at 2s interval)
        if PSUTIL_AVAILABLE and total_captures > 0 and total_captures % 100 == 0:
            if time.time() - last_metrics_log > 30:  # At most once per 30 seconds
                metrics = collect_metrics(start_time, total_captures)
                if metrics:
                    log_resource_metrics(logger, **metrics)
                    last_metrics_log = time.time()

        # Sleep for remainder of interval
        elapsed = time.time() - cycle_start
        sleep_time = max(0, interval_seconds - elapsed)
        if sleep_time > 0:
            time.sleep(sleep_time)


if __name__ == "__main__":
    main(interval_seconds=2)
