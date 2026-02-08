"""
Environment-aware path resolution for Playback.

Provides centralized path resolution that automatically switches between
development and production environments based on the PLAYBACK_DEV_MODE
environment variable.

Development mode:
    - Data directory: project_root/dev_data/
    - Config file: project_root/dev_config.json
    - Logs directory: project_root/dev_logs/

Production mode:
    - Data directory: ~/Library/Application Support/Playback/data/
    - Config file: ~/Library/Application Support/Playback/config.json
    - Logs directory: ~/Library/Logs/Playback/

All paths are Path objects from pathlib for consistent cross-platform handling.
"""

import os
from pathlib import Path
from typing import Optional, Union


def _detect_project_root() -> Path:
    """
    Detect the project root directory by walking up from this file's location.

    The project root is identified by the presence of src/ directory.

    Returns:
        Path to the project root directory.

    Raises:
        RuntimeError: If project root cannot be determined.
    """
    current = Path(__file__).resolve()

    # Walk up the directory tree looking for src/ directory
    for parent in [current, *current.parents]:
        if (parent / "src").is_dir():
            return parent

    raise RuntimeError(
        f"Cannot determine project root from {current}. "
        "Expected to find src/ directory in parent hierarchy."
    )


def is_development_mode() -> bool:
    """
    Check if running in development mode.

    Development mode is enabled when PLAYBACK_DEV_MODE environment variable
    is set to "1".

    Returns:
        True if in development mode, False otherwise.
    """
    return os.environ.get("PLAYBACK_DEV_MODE") == "1"


def get_base_data_directory() -> Path:
    """
    Get the base data directory for the current environment.

    Development: project_root/dev_data/
    Production: ~/Library/Application Support/Playback/data/

    Returns:
        Path to the base data directory.
    """
    if is_development_mode():
        return _detect_project_root() / "dev_data"
    else:
        home = Path.home()
        return home / "Library" / "Application Support" / "Playback" / "data"


def get_temp_directory() -> Path:
    """
    Get the temporary screenshots directory.

    Development: dev_data/temp/
    Production: ~/Library/Application Support/Playback/data/temp/

    Returns:
        Path to the temp directory.
    """
    return get_base_data_directory() / "temp"


def get_chunks_directory() -> Path:
    """
    Get the video segments directory.

    Development: dev_data/chunks/
    Production: ~/Library/Application Support/Playback/data/chunks/

    Returns:
        Path to the chunks directory.
    """
    return get_base_data_directory() / "chunks"


def get_database_path() -> Path:
    """
    Get the metadata database file path.

    Development: dev_data/meta.sqlite3
    Production: ~/Library/Application Support/Playback/data/meta.sqlite3

    Returns:
        Path to the meta.sqlite3 database file.
    """
    return get_base_data_directory() / "meta.sqlite3"


def get_config_path() -> Path:
    """
    Get the configuration file path.

    Development: project_root/dev_config.json
    Production: ~/Library/Application Support/Playback/config.json

    Returns:
        Path to the config.json file.
    """
    if is_development_mode():
        return _detect_project_root() / "dev_config.json"
    else:
        home = Path.home()
        return home / "Library" / "Application Support" / "Playback" / "config.json"


def get_logs_directory() -> Path:
    """
    Get the logs directory.

    Development: project_root/dev_logs/
    Production: ~/Library/Logs/Playback/

    Returns:
        Path to the logs directory.
    """
    if is_development_mode():
        return _detect_project_root() / "dev_logs"
    else:
        home = Path.home()
        return home / "Library" / "Logs" / "Playback"


def get_timeline_open_signal_path() -> Path:
    """
    Get the timeline open signal file path.

    This file is created when the timeline viewer is open and deleted when
    it closes. The recording service checks for this file to pause recording.

    Development: dev_data/.timeline_open
    Production: ~/Library/Application Support/Playback/data/.timeline_open

    Returns:
        Path to the .timeline_open signal file.
    """
    return get_base_data_directory() / ".timeline_open"


def ensure_directory_exists(path: Path, mode: int = 0o755) -> None:
    """
    Ensure a directory exists, creating it with proper permissions if needed.

    Creates parent directories as needed. If the directory already exists,
    this is a no-op.

    Args:
        path: Directory path to create.
        mode: Unix permissions mode (default: 0o755 = drwxr-xr-x).

    Raises:
        OSError: If directory creation fails.
    """
    if not path.exists():
        path.mkdir(parents=True, mode=mode, exist_ok=True)


def ensure_data_directories() -> None:
    """
    Ensure all required data directories exist with proper permissions.

    Creates:
        - Base data directory
        - temp/ subdirectory
        - chunks/ subdirectory
        - logs/ directory

    Uses restrictive permissions (0o700) for data directories containing
    sensitive screen recordings.

    Raises:
        OSError: If directory creation fails.
    """
    # Data directories should be user-only (0o700)
    ensure_directory_exists(get_base_data_directory(), mode=0o700)
    ensure_directory_exists(get_temp_directory(), mode=0o700)
    ensure_directory_exists(get_chunks_directory(), mode=0o700)

    # Logs can be readable by others (0o755)
    ensure_directory_exists(get_logs_directory(), mode=0o755)


def create_secure_file(path: Union[Path, str], content: bytes) -> None:
    """
    Create a file with secure permissions (0o600 = rw-------).

    This function ensures that sensitive files (screenshots, videos, database)
    are created with user-only read/write permissions to prevent other users
    on the system from accessing recorded screen data.

    Implementation:
        1. Set restrictive umask (0o077) to prevent default permissions
        2. Write file content
        3. Explicitly chmod to 0o600 for defense-in-depth
        4. Restore original umask

    Args:
        path: Path to the file to create (Path or str)
        content: Binary content to write to the file

    Raises:
        OSError: If file creation or permission setting fails
        TypeError: If content is not bytes

    Example:
        create_secure_file(Path("/path/to/screenshot.png"), screenshot_data)
        create_secure_file("/path/to/video.mp4", video_data)
    """
    if not isinstance(content, bytes):
        raise TypeError(f"content must be bytes, got {type(content).__name__}")

    # Convert to Path for consistent handling
    file_path = Path(path) if isinstance(path, str) else path

    # Set restrictive umask to prevent readable/writable by group/other
    old_umask = os.umask(0o077)

    try:
        # Write file content
        with open(file_path, 'wb') as f:
            f.write(content)

        # Explicitly set permissions for defense-in-depth
        os.chmod(file_path, 0o600)
    finally:
        # Always restore original umask
        os.umask(old_umask)


def get_day_directory(date_str: str, subdirectory: str) -> Path:
    """
    Get the directory for a specific day within temp/ or chunks/.

    Date-based directory structure: YYYYMM/DD/
    Example: 202512/22/ for December 22, 2025

    Args:
        date_str: Date string in YYYYMMDD format (e.g., "20251222").
        subdirectory: Either "temp" or "chunks".

    Returns:
        Path to the day directory (e.g., chunks/202512/22/).

    Raises:
        ValueError: If date_str is not 8 characters or subdirectory is invalid.
    """
    if len(date_str) != 8:
        raise ValueError(f"date_str must be YYYYMMDD format, got: {date_str}")

    if subdirectory not in ("temp", "chunks"):
        raise ValueError(f"subdirectory must be 'temp' or 'chunks', got: {subdirectory}")

    year_month = date_str[:6]  # YYYYMM
    day = date_str[6:]  # DD

    base = get_base_data_directory()
    return base / subdirectory / year_month / day


# Constants for backward compatibility with existing scripts
PROJECT_ROOT: Optional[Path] = None
TEMP_ROOT: Optional[Path] = None
CHUNKS_ROOT: Optional[Path] = None
META_DB_PATH: Optional[Path] = None

try:
    PROJECT_ROOT = _detect_project_root()
    TEMP_ROOT = get_temp_directory()
    CHUNKS_ROOT = get_chunks_directory()
    META_DB_PATH = get_database_path()
except RuntimeError:
    # If we can't detect project root, constants remain None
    # Functions will still work in production mode
    pass


__all__ = [
    "is_development_mode",
    "get_base_data_directory",
    "get_temp_directory",
    "get_chunks_directory",
    "get_database_path",
    "get_config_path",
    "get_logs_directory",
    "get_timeline_open_signal_path",
    "ensure_directory_exists",
    "ensure_data_directories",
    "get_day_directory",
    "create_secure_file",
    "PROJECT_ROOT",
    "TEMP_ROOT",
    "CHUNKS_ROOT",
    "META_DB_PATH",
]
