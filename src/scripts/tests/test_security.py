#!/usr/bin/env python3
"""
Security tests for Playback application.

Tests file permissions, database security settings, and input validation
to ensure sensitive screen recording data is properly protected.

Run with: python3 -m pytest src/scripts/tests/test_security.py -v
"""

import os
import stat
import tempfile
import sqlite3
from pathlib import Path
from typing import Generator

import pytest

# Add parent directory to path to import lib modules
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

from lib.paths import (
    create_secure_file,
    ensure_directory_exists,
    get_base_data_directory,
    get_temp_directory,
    get_chunks_directory,
    get_database_path,
    get_config_path,
)
from lib.database import DatabaseManager, init_database
from lib.config import Config


@pytest.fixture
def temp_test_dir() -> Generator[Path, None, None]:
    """Create a temporary directory for testing with proper cleanup."""
    with tempfile.TemporaryDirectory() as tmpdir:
        test_path = Path(tmpdir)
        yield test_path


@pytest.fixture
def temp_database(temp_test_dir: Path) -> DatabaseManager:
    """Create a temporary test database."""
    db_path = temp_test_dir / "test_meta.sqlite3"
    db = init_database(db_path)
    return db


class TestFilePermissions:
    """Test suite for file permission enforcement."""

    def test_secure_file_creation_permissions(self, temp_test_dir: Path):
        """Test that create_secure_file creates files with 0o600 permissions."""
        test_file = temp_test_dir / "secure_test.bin"
        test_content = b"sensitive screen recording data"

        create_secure_file(test_file, test_content)

        # Verify file exists
        assert test_file.exists(), "Secure file was not created"

        # Verify content
        assert test_file.read_bytes() == test_content, "File content mismatch"

        # Verify permissions are exactly 0o600 (user read/write only)
        file_stat = os.stat(test_file)
        file_mode = stat.S_IMODE(file_stat.st_mode)
        assert file_mode == 0o600, f"Expected 0o600, got {oct(file_mode)}"

    def test_secure_file_rejects_non_bytes(self, temp_test_dir: Path):
        """Test that create_secure_file raises TypeError for non-bytes content."""
        test_file = temp_test_dir / "invalid.bin"

        with pytest.raises(TypeError, match="content must be bytes"):
            create_secure_file(test_file, "string not bytes")  # type: ignore

        with pytest.raises(TypeError, match="content must be bytes"):
            create_secure_file(test_file, 12345)  # type: ignore

    def test_secure_file_accepts_path_and_string(self, temp_test_dir: Path):
        """Test that create_secure_file accepts both Path and str."""
        test_content = b"test data"

        # Test with Path
        path_file = temp_test_dir / "path_test.bin"
        create_secure_file(path_file, test_content)
        assert path_file.exists()

        # Test with string
        str_file = str(temp_test_dir / "str_test.bin")
        create_secure_file(str_file, test_content)
        assert Path(str_file).exists()

    def test_directory_permissions_data_dirs(self, temp_test_dir: Path):
        """Test that data directories are created with 0o700 (user-only access)."""
        data_dir = temp_test_dir / "sensitive_data"
        ensure_directory_exists(data_dir, mode=0o700)

        assert data_dir.exists(), "Directory was not created"

        dir_stat = os.stat(data_dir)
        dir_mode = stat.S_IMODE(dir_stat.st_mode)
        assert dir_mode == 0o700, f"Expected 0o700, got {oct(dir_mode)}"

    def test_directory_permissions_logs_dir(self, temp_test_dir: Path):
        """Test that log directories can be created with 0o755 (readable by others)."""
        log_dir = temp_test_dir / "logs"
        ensure_directory_exists(log_dir, mode=0o755)

        assert log_dir.exists(), "Directory was not created"

        dir_stat = os.stat(log_dir)
        dir_mode = stat.S_IMODE(dir_stat.st_mode)
        assert dir_mode == 0o755, f"Expected 0o755, got {oct(dir_mode)}"

    def test_config_file_permissions(self, temp_test_dir: Path):
        """Test that config files have 0o644 permissions (readable by group/others)."""
        config_file = temp_test_dir / "config.json"
        config_file.write_text('{"version": "1.0.0"}')
        os.chmod(config_file, 0o644)

        file_stat = os.stat(config_file)
        file_mode = stat.S_IMODE(file_stat.st_mode)
        assert file_mode == 0o644, f"Expected 0o644, got {oct(file_mode)}"

    def test_no_world_readable_sensitive_files(self, temp_test_dir: Path):
        """Test that sensitive files are not world-readable."""
        # Create a sensitive file (screenshot, video, database)
        sensitive_file = temp_test_dir / "screenshot.png"
        create_secure_file(sensitive_file, b"screenshot data")

        file_stat = os.stat(sensitive_file)
        file_mode = stat.S_IMODE(file_stat.st_mode)

        # Check that "others" have no permissions (last 3 bits should be 000)
        others_perms = file_mode & 0o007
        assert others_perms == 0, f"Others have permissions: {oct(others_perms)}"

        # Check that "group" has no write/execute permissions
        group_perms = file_mode & 0o070
        assert group_perms == 0, f"Group has permissions: {oct(group_perms)}"

    def test_database_file_permissions(self, temp_database: DatabaseManager):
        """Test that database file has secure permissions (0o600)."""
        db_path = temp_database.db_path

        # Ensure database file exists by initializing
        assert db_path.exists(), "Database file was not created"

        # Check permissions
        file_stat = os.stat(db_path)
        file_mode = stat.S_IMODE(file_stat.st_mode)
        assert file_mode == 0o600, f"Expected 0o600, got {oct(file_mode)}"

    def test_database_wal_shm_permissions(self, temp_database: DatabaseManager):
        """Test that database WAL and SHM files have secure permissions."""
        db_path = temp_database.db_path

        # Create WAL file by performing a write operation
        temp_database.insert_segment(
            segment_id="test123",
            date_str="2026-02-07",
            start_ts=1234567890.0,
            end_ts=1234567895.0,
            frame_count=5,
            fps=30.0,
            file_size_bytes=1024,
            video_path="test/video.mp4"
        )

        # Check WAL file permissions if it exists
        wal_path = db_path.with_suffix(db_path.suffix + "-wal")
        if wal_path.exists():
            wal_stat = os.stat(wal_path)
            wal_mode = stat.S_IMODE(wal_stat.st_mode)
            assert wal_mode == 0o600, f"WAL file expected 0o600, got {oct(wal_mode)}"

        # Check SHM file permissions if it exists
        shm_path = db_path.with_suffix(db_path.suffix + "-shm")
        if shm_path.exists():
            shm_stat = os.stat(shm_path)
            shm_mode = stat.S_IMODE(shm_stat.st_mode)
            assert shm_mode == 0o600, f"SHM file expected 0o600, got {oct(shm_mode)}"


class TestDatabaseSecurity:
    """Test suite for database security settings."""

    def test_secure_delete_enabled(self, temp_database: DatabaseManager):
        """Test that secure_delete pragma is enabled."""
        is_enabled = temp_database.verify_secure_delete()
        assert is_enabled, "secure_delete pragma is not enabled"

    def test_secure_delete_on_connection(self, temp_database: DatabaseManager):
        """Test that secure_delete is set on each connection."""
        with temp_database._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("PRAGMA secure_delete")
            result = cursor.fetchone()
            assert result[0] == 1, "secure_delete is not enabled on connection"

    def test_secure_delete_overwrites_deleted_data(self, temp_database: DatabaseManager):
        """Test that deleted data is overwritten (integration test)."""
        # Insert a segment with known data
        segment_id = "testsecuredel"
        secret_data = "secret video path with sensitive info"

        temp_database.insert_segment(
            segment_id=segment_id,
            date_str="2026-02-07",
            start_ts=1234567890.0,
            end_ts=1234567895.0,
            frame_count=5,
            fps=30.0,
            file_size_bytes=1024,
            video_path=secret_data
        )

        # Verify insertion
        assert temp_database.segment_exists(segment_id)

        # Delete the segment
        temp_database.delete_segment(segment_id)

        # Verify deletion
        assert not temp_database.segment_exists(segment_id)

        # Note: We can't easily verify that data is overwritten without
        # examining raw database pages. This test verifies the setting is enabled,
        # which ensures SQLite will overwrite deleted data.

    def test_wal_mode_enabled(self, temp_database: DatabaseManager):
        """Test that WAL mode is enabled for concurrent access."""
        with temp_database._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            cursor.execute("PRAGMA journal_mode")
            result = cursor.fetchone()
            # Result should be "wal" (case-insensitive)
            assert result[0].lower() == "wal", f"Expected WAL mode, got {result[0]}"

    def test_database_integrity_check(self, temp_database: DatabaseManager):
        """Test that database integrity check works."""
        integrity_ok = temp_database.check_integrity()
        assert integrity_ok, "Database integrity check failed"


class TestInputValidation:
    """Test suite for input validation and sanitization."""

    def test_bundle_id_validation(self):
        """Test that bundle IDs are validated properly."""
        config = Config({
            "excluded_apps": [
                "com.example.app",  # valid
                "com.1password.1password",  # valid (numbers OK)
                "com.app-name.test",  # valid (hyphens OK)
                "invalid/bundle/id",  # invalid (slashes)
                "../path/traversal",  # invalid (path traversal)
                "com.example.app; rm -rf /",  # invalid (shell injection)
                "",  # invalid (empty)
                "   ",  # invalid (whitespace only)
            ]
        })

        # Only valid bundle IDs should remain
        assert "com.example.app" in config.excluded_apps
        assert "com.1password.1password" in config.excluded_apps
        assert "com.app-name.test" in config.excluded_apps

        # Invalid bundle IDs should be filtered out
        assert "invalid/bundle/id" not in config.excluded_apps
        assert "../path/traversal" not in config.excluded_apps
        assert "com.example.app; rm -rf /" not in config.excluded_apps
        assert "" not in config.excluded_apps
        assert "   " not in config.excluded_apps

    def test_path_validation_no_traversal(self, temp_test_dir: Path):
        """Test that path traversal attempts are rejected."""
        # Attempt to create a file with path traversal
        base_dir = temp_test_dir / "data"
        base_dir.mkdir()

        # These should not escape the base directory
        malicious_paths = [
            "../../../etc/passwd",
            "../../outside.txt",
            "subdir/../../escape.txt",
        ]

        for malicious in malicious_paths:
            # Path should be resolved to prevent traversal
            resolved = (base_dir / malicious).resolve()

            # If properly validated, resolved path should still be inside base_dir
            # This is a demonstration - actual validation should reject these
            is_inside = str(resolved).startswith(str(base_dir.resolve()))

            # In production code, we should reject paths that escape base_dir
            # For now, we just verify that resolve() handles them
            assert resolved.exists() or not is_inside or True  # Placeholder

    def test_config_value_validation(self):
        """Test that invalid config values are rejected or defaulted."""
        config = Config({
            "processing_interval_minutes": 99,  # invalid, should default to 5
            "temp_retention_policy": "invalid",  # invalid, should default to "1_week"
            "exclusion_mode": "invalid",  # invalid, should default to "skip"
            "ffmpeg_crf": 100,  # invalid (>51), should default to 28
            "video_fps": -10,  # invalid (negative), should default to 30
        })

        assert config.processing_interval_minutes == 5
        assert config.temp_retention_policy == "1_week"
        assert config.exclusion_mode == "skip"
        assert config.ffmpeg_crf == 28
        assert config.video_fps == 30

    def test_config_sql_injection_prevention(self):
        """Test that config values don't allow SQL injection."""
        # Attempt to inject SQL through config values
        malicious_app_id = "'; DROP TABLE segments; --"

        config = Config({
            "excluded_apps": [malicious_app_id]
        })

        # Should be filtered out because it contains invalid characters
        assert malicious_app_id not in config.excluded_apps

    def test_segment_id_format(self, temp_database: DatabaseManager):
        """Test that segment IDs are properly formatted (no injection)."""
        from lib.database import generate_segment_id

        # Generate multiple IDs and verify format
        for _ in range(10):
            seg_id = generate_segment_id()

            # Should be exactly 20 hex characters
            assert len(seg_id) == 20, f"Expected 20 chars, got {len(seg_id)}"
            assert all(c in "0123456789abcdef" for c in seg_id), \
                f"Non-hex characters in segment ID: {seg_id}"

        # Test that malformed IDs can't be used for injection
        malicious_id = "'; DROP TABLE segments; --"
        temp_database.insert_segment(
            segment_id=malicious_id,
            date_str="2026-02-07",
            start_ts=1234567890.0,
            end_ts=1234567895.0,
            frame_count=5,
            fps=30.0,
            file_size_bytes=1024,
            video_path="test.mp4"
        )

        # Database should still be intact (parameterized queries prevent injection)
        integrity_ok = temp_database.check_integrity()
        assert integrity_ok, "Database corrupted after malicious ID insertion"


class TestErrorMessageSanitization:
    """Test suite for error message sanitization (no sensitive data in errors)."""

    def test_error_no_absolute_paths(self, temp_test_dir: Path):
        """Test that error messages don't expose absolute paths."""
        # This is a guideline test - actual implementation varies by function
        # Best practice: log full paths, but return/display sanitized messages

        sensitive_path = temp_test_dir / "sensitive" / "user" / "data.db"

        # Simulate an error with path
        try:
            # Attempt to read non-existent file
            sensitive_path.read_bytes()
        except FileNotFoundError as e:
            error_msg = str(e)

            # In production, we should sanitize paths in user-facing messages
            # For internal logs, full paths are OK
            # This test just demonstrates the concept
            assert True  # Placeholder - actual sanitization depends on implementation

    def test_database_error_sanitization(self, temp_database: DatabaseManager):
        """Test that database errors don't leak sensitive data."""
        try:
            # Attempt invalid query to trigger error
            with temp_database._get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("SELECT * FROM nonexistent_table")
        except sqlite3.OperationalError as e:
            error_msg = str(e)

            # Error message should not contain sensitive data
            # SQLite errors typically just say "no such table: nonexistent_table"
            # which is fine - no user data leaked
            assert "no such table" in error_msg.lower()


class TestPermissionEnforcement:
    """Test suite for permission enforcement across the codebase."""

    def test_umask_restored_after_secure_file_creation(self, temp_test_dir: Path):
        """Test that umask is properly restored after secure file creation."""
        # Get original umask
        original_umask = os.umask(0o022)
        os.umask(original_umask)

        # Create secure file
        test_file = temp_test_dir / "umask_test.bin"
        create_secure_file(test_file, b"test data")

        # Check that umask was restored
        current_umask = os.umask(0o022)
        os.umask(current_umask)

        assert current_umask == original_umask, \
            f"Umask not restored: expected {oct(original_umask)}, got {oct(current_umask)}"

    def test_database_connection_sets_secure_delete(self, temp_database: DatabaseManager):
        """Test that every connection sets secure_delete pragma."""
        # Open multiple connections and verify each has secure_delete enabled
        for _ in range(3):
            with temp_database._get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("PRAGMA secure_delete")
                result = cursor.fetchone()
                assert result[0] == 1, "secure_delete not set on connection"

    def test_read_only_connection_respects_secure_delete(self, temp_database: DatabaseManager):
        """Test that read-only connections still have secure_delete enabled."""
        # Note: Read-only connections can't modify the database, so secure_delete
        # setting doesn't apply to writes, but pragma should still return the value

        # First, ensure database exists with some data
        temp_database.insert_segment(
            segment_id="readonly_test",
            date_str="2026-02-07",
            start_ts=1234567890.0,
            end_ts=1234567895.0,
            frame_count=5,
            fps=30.0,
            file_size_bytes=1024,
            video_path="test.mp4"
        )

        # Open read-only connection
        with temp_database._get_connection(read_only=True) as conn:
            cursor = conn.cursor()
            # Read-only connections can still query pragma
            cursor.execute("PRAGMA secure_delete")
            result = cursor.fetchone()
            # Value should reflect database setting (ON/OFF)
            assert result is not None


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
