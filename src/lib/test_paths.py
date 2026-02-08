"""
Unit tests for the paths module.

Tests environment-aware path resolution, directory creation, and secure file handling.
"""

import os
import pytest
import tempfile
from pathlib import Path
from unittest.mock import patch

# Import the module under test
import lib.paths as paths


class TestProjectRootDetection:
    """Test _detect_project_root function."""

    def test_detect_project_root_from_lib(self):
        """Test that project root is detected from lib/ directory."""
        root = paths._detect_project_root()
        assert root.is_dir()
        assert (root / "src").is_dir()
        assert (root / "src" / "lib").is_dir()

    def test_project_root_constant_set(self):
        """Test that PROJECT_ROOT constant is set correctly."""
        if paths.PROJECT_ROOT is not None:
            assert paths.PROJECT_ROOT.is_dir()
            assert (paths.PROJECT_ROOT / "src").is_dir()


class TestDevelopmentModeDetection:
    """Test is_development_mode function."""

    def test_development_mode_enabled(self):
        """Test development mode detection when PLAYBACK_DEV_MODE=1."""
        with patch.dict(os.environ, {"PLAYBACK_DEV_MODE": "1"}):
            assert paths.is_development_mode() is True

    def test_development_mode_disabled(self):
        """Test development mode detection when PLAYBACK_DEV_MODE is not set."""
        with patch.dict(os.environ, {}, clear=True):
            assert paths.is_development_mode() is False

    def test_development_mode_wrong_value(self):
        """Test development mode detection when PLAYBACK_DEV_MODE has wrong value."""
        with patch.dict(os.environ, {"PLAYBACK_DEV_MODE": "0"}):
            assert paths.is_development_mode() is False

        with patch.dict(os.environ, {"PLAYBACK_DEV_MODE": "true"}):
            assert paths.is_development_mode() is False


class TestBaseDataDirectory:
    """Test get_base_data_directory function."""

    def test_dev_mode_uses_dev_data(self):
        """Test that development mode uses dev_data/ directory."""
        with patch.dict(os.environ, {"PLAYBACK_DEV_MODE": "1"}):
            base_dir = paths.get_base_data_directory()
            assert "dev_data" in str(base_dir)
            assert base_dir.is_absolute()

    def test_prod_mode_uses_library(self):
        """Test that production mode uses Library/Application Support."""
        with patch.dict(os.environ, {}, clear=True):
            base_dir = paths.get_base_data_directory()
            assert "Library/Application Support/Playback/data" in str(base_dir)
            assert base_dir.is_absolute()


class TestTempDirectory:
    """Test get_temp_directory function."""

    def test_temp_directory_under_base(self):
        """Test that temp directory is under base data directory."""
        base_dir = paths.get_base_data_directory()
        temp_dir = paths.get_temp_directory()
        assert temp_dir.parent == base_dir
        assert temp_dir.name == "temp"


class TestChunksDirectory:
    """Test get_chunks_directory function."""

    def test_chunks_directory_under_base(self):
        """Test that chunks directory is under base data directory."""
        base_dir = paths.get_base_data_directory()
        chunks_dir = paths.get_chunks_directory()
        assert chunks_dir.parent == base_dir
        assert chunks_dir.name == "chunks"


class TestDatabasePath:
    """Test get_database_path function."""

    def test_database_path_under_base(self):
        """Test that database file is under base data directory."""
        base_dir = paths.get_base_data_directory()
        db_path = paths.get_database_path()
        assert db_path.parent == base_dir
        assert db_path.name == "meta.sqlite3"

    def test_database_path_consistent(self):
        """Test that database path is consistent across calls."""
        path1 = paths.get_database_path()
        path2 = paths.get_database_path()
        assert path1 == path2


class TestConfigPath:
    """Test get_config_path function."""

    def test_dev_mode_uses_dev_config(self):
        """Test that development mode uses dev_config.json."""
        with patch.dict(os.environ, {"PLAYBACK_DEV_MODE": "1"}):
            config_path = paths.get_config_path()
            assert config_path.name == "dev_config.json"
            assert config_path.is_absolute()

    def test_prod_mode_uses_library_config(self):
        """Test that production mode uses Library/Application Support config."""
        with patch.dict(os.environ, {}, clear=True):
            config_path = paths.get_config_path()
            assert config_path.name == "config.json"
            assert "Library/Application Support/Playback" in str(config_path)


class TestLogsDirectory:
    """Test get_logs_directory function."""

    def test_dev_mode_uses_dev_logs(self):
        """Test that development mode uses dev_logs/ directory."""
        with patch.dict(os.environ, {"PLAYBACK_DEV_MODE": "1"}):
            logs_dir = paths.get_logs_directory()
            assert "dev_logs" in str(logs_dir)
            assert logs_dir.is_absolute()

    def test_prod_mode_uses_library_logs(self):
        """Test that production mode uses Library/Logs/Playback."""
        with patch.dict(os.environ, {}, clear=True):
            logs_dir = paths.get_logs_directory()
            assert "Library/Logs/Playback" in str(logs_dir)


class TestTimelineOpenSignalPath:
    """Test get_timeline_open_signal_path function."""

    def test_signal_path_under_base(self):
        """Test that signal file is under base data directory."""
        base_dir = paths.get_base_data_directory()
        signal_path = paths.get_timeline_open_signal_path()
        assert signal_path.parent == base_dir
        assert signal_path.name == ".timeline_open"


class TestEnsureDirectoryExists:
    """Test ensure_directory_exists function."""

    def test_create_new_directory(self):
        """Test creating a new directory."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir) / "test_dir"
            assert not test_dir.exists()

            paths.ensure_directory_exists(test_dir)
            assert test_dir.exists()
            assert test_dir.is_dir()

    def test_create_nested_directories(self):
        """Test creating nested directories."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir) / "parent" / "child" / "grandchild"
            assert not test_dir.exists()

            paths.ensure_directory_exists(test_dir)
            assert test_dir.exists()
            assert test_dir.is_dir()
            assert test_dir.parent.is_dir()
            assert test_dir.parent.parent.is_dir()

    def test_directory_already_exists(self):
        """Test that existing directory is not recreated."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir)
            # Should not raise error
            paths.ensure_directory_exists(test_dir)
            assert test_dir.exists()

    def test_custom_permissions(self):
        """Test creating directory with custom permissions."""
        with tempfile.TemporaryDirectory() as tmpdir:
            test_dir = Path(tmpdir) / "test_perms"
            paths.ensure_directory_exists(test_dir, mode=0o700)

            assert test_dir.exists()
            # Check that permissions were set (may vary by OS umask)
            stat_info = os.stat(test_dir)
            # At least owner should have rwx
            assert stat_info.st_mode & 0o700 == 0o700


class TestEnsureDataDirectories:
    """Test ensure_data_directories function."""

    @patch('lib.paths.ensure_directory_exists')
    def test_creates_all_required_directories(self, mock_ensure):
        """Test that all required directories are created."""
        paths.ensure_data_directories()

        # Should create base, temp, chunks with 0o700, and logs with 0o755
        assert mock_ensure.call_count == 4

        # Check that directories are created with correct permissions
        calls = mock_ensure.call_args_list

        # Verify data directories have mode 0o700
        for call in calls[:3]:
            assert call[1]['mode'] == 0o700

        # Verify logs directory has mode 0o755
        assert calls[3][1]['mode'] == 0o755


class TestSecureFileCreation:
    """Test create_secure_file function."""

    def test_create_secure_file_with_path(self):
        """Test creating a secure file with Path object."""
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "secure_file.bin"
            content = b"sensitive data"

            paths.create_secure_file(file_path, content)

            assert file_path.exists()
            assert file_path.read_bytes() == content

            # Check permissions (0o600 = rw-------)
            stat_info = os.stat(file_path)
            mode = stat_info.st_mode & 0o777
            assert mode == 0o600

    def test_create_secure_file_with_string(self):
        """Test creating a secure file with string path."""
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = str(Path(tmpdir) / "secure_file.bin")
            content = b"sensitive data"

            paths.create_secure_file(file_path, content)

            path_obj = Path(file_path)
            assert path_obj.exists()
            assert path_obj.read_bytes() == content

    def test_secure_file_rejects_non_bytes(self):
        """Test that create_secure_file rejects non-bytes content."""
        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "test.txt"

            with pytest.raises(TypeError, match="content must be bytes"):
                paths.create_secure_file(file_path, "string content")

            with pytest.raises(TypeError, match="content must be bytes"):
                paths.create_secure_file(file_path, 12345)

    def test_secure_file_umask_restored(self):
        """Test that umask is restored after file creation."""
        original_umask = os.umask(0o022)
        os.umask(original_umask)  # Restore it

        with tempfile.TemporaryDirectory() as tmpdir:
            file_path = Path(tmpdir) / "test.bin"
            paths.create_secure_file(file_path, b"test")

            # Umask should be restored
            current_umask = os.umask(0o022)
            os.umask(current_umask)  # Restore again
            assert current_umask == original_umask


class TestGetDayDirectory:
    """Test get_day_directory function."""

    def test_temp_day_directory(self):
        """Test getting temp day directory."""
        day_dir = paths.get_day_directory("20251222", "temp")
        assert "202512" in str(day_dir)
        assert day_dir.name == "22"
        assert day_dir.parent.name == "202512"
        assert "temp" in str(day_dir)

    def test_chunks_day_directory(self):
        """Test getting chunks day directory."""
        day_dir = paths.get_day_directory("20260101", "chunks")
        assert "202601" in str(day_dir)
        assert day_dir.name == "01"
        assert day_dir.parent.name == "202601"
        assert "chunks" in str(day_dir)

    def test_invalid_date_format(self):
        """Test that invalid date format raises ValueError."""
        with pytest.raises(ValueError, match="must be YYYYMMDD format"):
            paths.get_day_directory("2025-12-22", "temp")

        with pytest.raises(ValueError, match="must be YYYYMMDD format"):
            paths.get_day_directory("20251", "temp")

        with pytest.raises(ValueError, match="must be YYYYMMDD format"):
            paths.get_day_directory("202512221", "temp")

    def test_invalid_subdirectory(self):
        """Test that invalid subdirectory raises ValueError."""
        with pytest.raises(ValueError, match="must be 'temp' or 'chunks'"):
            paths.get_day_directory("20251222", "invalid")

        with pytest.raises(ValueError, match="must be 'temp' or 'chunks'"):
            paths.get_day_directory("20251222", "videos")


class TestConstants:
    """Test module constants."""

    def test_constants_are_paths(self):
        """Test that constants are Path objects or None."""
        if paths.PROJECT_ROOT is not None:
            assert isinstance(paths.PROJECT_ROOT, Path)

        if paths.TEMP_ROOT is not None:
            assert isinstance(paths.TEMP_ROOT, Path)

        if paths.CHUNKS_ROOT is not None:
            assert isinstance(paths.CHUNKS_ROOT, Path)

        if paths.META_DB_PATH is not None:
            assert isinstance(paths.META_DB_PATH, Path)


class TestPathConsistency:
    """Test that path functions return consistent results."""

    def test_multiple_calls_same_result(self):
        """Test that multiple calls return the same path."""
        paths_to_test = [
            paths.get_base_data_directory,
            paths.get_temp_directory,
            paths.get_chunks_directory,
            paths.get_database_path,
            paths.get_config_path,
            paths.get_logs_directory,
            paths.get_timeline_open_signal_path,
        ]

        for path_func in paths_to_test:
            path1 = path_func()
            path2 = path_func()
            assert path1 == path2

    def test_all_paths_absolute(self):
        """Test that all returned paths are absolute."""
        assert paths.get_base_data_directory().is_absolute()
        assert paths.get_temp_directory().is_absolute()
        assert paths.get_chunks_directory().is_absolute()
        assert paths.get_database_path().is_absolute()
        assert paths.get_config_path().is_absolute()
        assert paths.get_logs_directory().is_absolute()
        assert paths.get_timeline_open_signal_path().is_absolute()
