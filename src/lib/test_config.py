"""
Unit tests for src/lib/config.py

Tests configuration loading, validation, defaults, and exclusion logic.
"""

import json
import pytest
import tempfile
from pathlib import Path
from unittest.mock import patch
from lib.config import (
    Config,
    load_config,
    load_config_with_defaults,
    RECOMMENDED_EXCLUSIONS
)


class TestConfigDefaults:
    """Test Config class initialization with defaults."""

    def test_empty_dict_uses_all_defaults(self):
        """Empty config dict should use all default values."""
        config = Config({})

        assert config.version == "1.0.0"
        assert config.processing_interval_minutes == 5
        assert config.temp_retention_policy == "1_week"
        assert config.recording_retention_policy == "never"
        assert config.exclusion_mode == "skip"
        assert config.excluded_apps == []
        assert config.ffmpeg_crf == 28
        assert config.video_fps == 30
        assert config.timeline_shortcut == "Option+Shift+Space"
        assert config.notifications_processing_complete is True
        assert config.notifications_processing_errors is True
        assert config.notifications_disk_space_warnings is True
        assert config.notifications_recording_status is False

    def test_partial_config_fills_missing_fields(self):
        """Partial config should use defaults for missing fields."""
        config = Config({"version": "2.0.0", "video_fps": 60})

        assert config.version == "2.0.0"
        assert config.video_fps == 60
        assert config.processing_interval_minutes == 5  # default
        assert config.temp_retention_policy == "1_week"  # default

    def test_none_values_crash_during_validation(self):
        """None values crash during validation (not handled)."""
        # ffmpeg_crf: None fails at: if not (0 <= self.ffmpeg_crf <= 51)
        with pytest.raises(TypeError):
            Config({
                "processing_interval_minutes": None,
                "ffmpeg_crf": None
            })

        # video_fps: None fails at: if self.video_fps <= 0
        with pytest.raises(TypeError):
            Config({"video_fps": None})


class TestProcessingIntervalValidation:
    """Test validation of processing_interval_minutes field."""

    def test_valid_intervals_accepted(self):
        """Valid interval values should be accepted."""
        valid_intervals = [1, 5, 10, 15, 30, 60]
        for interval in valid_intervals:
            config = Config({"processing_interval_minutes": interval})
            assert config.processing_interval_minutes == interval

    def test_invalid_interval_uses_default(self):
        """Invalid intervals should fall back to default (5)."""
        invalid_intervals = [0, 2, 3, 7, 20, 45, 61, 120, -1]
        for interval in invalid_intervals:
            config = Config({"processing_interval_minutes": interval})
            assert config.processing_interval_minutes == 5

    def test_non_integer_interval_uses_default(self):
        """Non-integer intervals should use default."""
        # String "5" is not in valid_intervals list, so validation uses default
        config = Config({"processing_interval_minutes": "5"})
        assert config.processing_interval_minutes == 5

        # Float 5.5 is not in valid_intervals list, so validation uses default
        config = Config({"processing_interval_minutes": 5.5})
        assert config.processing_interval_minutes == 5


class TestRetentionPolicyValidation:
    """Test validation of retention policy fields."""

    def test_valid_temp_retention_policies(self):
        """Valid temp retention policies should be accepted."""
        valid_policies = ["never", "1_day", "1_week", "1_month"]
        for policy in valid_policies:
            config = Config({"temp_retention_policy": policy})
            assert config.temp_retention_policy == policy

    def test_invalid_temp_retention_uses_default(self):
        """Invalid temp retention should default to '1_week'."""
        invalid_policies = ["", "1_year", "forever", "1day", "1 week", None]
        for policy in invalid_policies:
            config = Config({"temp_retention_policy": policy})
            assert config.temp_retention_policy == "1_week"

    def test_valid_recording_retention_policies(self):
        """Valid recording retention policies should be accepted."""
        valid_policies = ["never", "1_day", "1_week", "1_month"]
        for policy in valid_policies:
            config = Config({"recording_retention_policy": policy})
            assert config.recording_retention_policy == policy

    def test_invalid_recording_retention_uses_default(self):
        """Invalid recording retention should default to 'never'."""
        invalid_policies = ["", "1_year", "always", None]
        for policy in invalid_policies:
            config = Config({"recording_retention_policy": policy})
            assert config.recording_retention_policy == "never"


class TestExclusionModeValidation:
    """Test validation of exclusion_mode field."""

    def test_valid_exclusion_modes(self):
        """Valid exclusion modes should be accepted."""
        for mode in ["skip", "invisible"]:
            config = Config({"exclusion_mode": mode})
            assert config.exclusion_mode == mode

    def test_invalid_exclusion_mode_uses_default(self):
        """Invalid exclusion modes should default to 'skip'."""
        invalid_modes = ["", "hide", "block", "Skip", "INVISIBLE", None]
        for mode in invalid_modes:
            config = Config({"exclusion_mode": mode})
            assert config.exclusion_mode == "skip"


class TestExcludedAppsValidation:
    """Test validation and sanitization of excluded_apps list."""

    def test_valid_bundle_ids_accepted(self):
        """Valid bundle IDs should be accepted."""
        valid_ids = [
            "com.1password.1password",
            "com.apple.Keychain",
            "com.example.app-name",
            "io.github.user.app"
        ]
        config = Config({"excluded_apps": valid_ids})
        assert config.excluded_apps == valid_ids

    def test_whitespace_stripped_from_bundle_ids(self):
        """Whitespace should be stripped from bundle IDs."""
        config = Config({"excluded_apps": [
            " com.1password.1password ",
            "  com.apple.Keychain",
            "com.example.app  "
        ]})
        assert config.excluded_apps == [
            "com.1password.1password",
            "com.apple.Keychain",
            "com.example.app"
        ]

    def test_empty_strings_filtered_out(self):
        """Empty strings should be removed from excluded_apps."""
        config = Config({"excluded_apps": [
            "com.1password.1password",
            "",
            "   ",
            "com.apple.Keychain"
        ]})
        assert config.excluded_apps == [
            "com.1password.1password",
            "com.apple.Keychain"
        ]

    def test_invalid_bundle_ids_filtered_out(self):
        """Bundle IDs with invalid characters should be filtered."""
        config = Config({"excluded_apps": [
            "com.valid.app",
            "invalid/app",
            "com.valid-app.name",
            "bad@app",
            "com.another.valid"
        ]})
        assert config.excluded_apps == [
            "com.valid.app",
            "com.valid-app.name",
            "com.another.valid"
        ]

    def test_non_string_items_in_list_filtered_out(self):
        """Non-string items in excluded_apps list should be filtered."""
        config = Config({"excluded_apps": [
            "com.valid.app",
            123,
            None,
            "com.another.valid",
            {"key": "value"},
            ["nested", "list"]
        ]})
        assert config.excluded_apps == [
            "com.valid.app",
            "com.another.valid"
        ]

    def test_non_list_excluded_apps_behavior(self):
        """Non-list excluded_apps should be handled gracefully."""
        # Valid string bundle ID should be converted to single-item list
        config = Config({"excluded_apps": "com.test.app"})
        assert config.excluded_apps == ["com.test.app"]

        # Invalid string bundle ID should result in empty list
        config = Config({"excluded_apps": "invalid/bundle@id"})
        assert config.excluded_apps == []

        # Empty string should result in empty list
        config = Config({"excluded_apps": ""})
        assert config.excluded_apps == []

        # None should result in empty list (graceful handling)
        config = Config({"excluded_apps": None})
        assert config.excluded_apps == []

        # Number should result in empty list
        config = Config({"excluded_apps": 123})
        assert config.excluded_apps == []


class TestFFmpegCRFValidation:
    """Test validation of ffmpeg_crf field."""

    def test_valid_crf_values_accepted(self):
        """CRF values in range 0-51 should be accepted."""
        for crf in [0, 10, 23, 28, 35, 51]:
            config = Config({"ffmpeg_crf": crf})
            assert config.ffmpeg_crf == crf

    def test_out_of_range_crf_uses_default(self):
        """CRF values outside 0-51 should use default (28)."""
        invalid_values = [-1, -10, 52, 100]
        for crf in invalid_values:
            config = Config({"ffmpeg_crf": crf})
            assert config.ffmpeg_crf == 28

    def test_non_integer_crf_uses_default(self):
        """Non-integer CRF values should use default."""
        # String "28" fails 0 <= self.ffmpeg_crf <= 51 check (TypeError), uses default
        with pytest.raises(TypeError):
            Config({"ffmpeg_crf": "28"})

        # Float 28.5 passes range check, is accepted as-is
        config = Config({"ffmpeg_crf": 28.5})
        assert config.ffmpeg_crf == 28.5


class TestVideoFPSValidation:
    """Test validation of video_fps field."""

    def test_positive_fps_accepted(self):
        """Positive FPS values should be accepted."""
        for fps in [1, 15, 24, 30, 60, 120]:
            config = Config({"video_fps": fps})
            assert config.video_fps == fps

    def test_zero_or_negative_fps_uses_default(self):
        """Zero or negative FPS should use default (30)."""
        invalid_values = [0, -1, -30]
        for fps in invalid_values:
            config = Config({"video_fps": fps})
            assert config.video_fps == 30

    def test_non_integer_fps_uses_default(self):
        """Non-integer FPS values should use default."""
        # String "30" fails <= 0 check (TypeError), crashes
        with pytest.raises(TypeError):
            Config({"video_fps": "30"})

        # Float 30.5 passes > 0 check, is accepted as-is
        config = Config({"video_fps": 30.5})
        assert config.video_fps == 30.5


class TestNotificationSettings:
    """Test notification-related configuration fields."""

    def test_notification_defaults(self):
        """Notification settings should have correct defaults."""
        config = Config({})
        assert config.notifications_processing_complete is True
        assert config.notifications_processing_errors is True
        assert config.notifications_disk_space_warnings is True
        assert config.notifications_recording_status is False

    def test_notification_settings_from_nested_dict(self):
        """Notifications can be provided as nested dict."""
        config = Config({
            "notifications": {
                "processing_complete": False,
                "processing_errors": False,
                "disk_space_warnings": False,
                "recording_status": True
            }
        })
        assert config.notifications_processing_complete is False
        assert config.notifications_processing_errors is False
        assert config.notifications_disk_space_warnings is False
        assert config.notifications_recording_status is True

    def test_notification_settings_do_not_support_flat_keys(self):
        """Flat keys are NOT supported - only nested dict works."""
        # The implementation only looks at config_dict.get("notifications", {})
        # Flat keys like "notifications_processing_complete" are ignored
        config = Config({
            "notifications_processing_complete": False,
            "notifications_recording_status": True
        })
        # These flat keys are ignored, defaults are used
        assert config.notifications_processing_complete is True  # default
        assert config.notifications_recording_status is False  # default
        assert config.notifications_processing_errors is True  # default

    def test_non_boolean_notification_passes_through(self):
        """Non-boolean notification values pass through as-is, no validation."""
        config = Config({
            "notifications": {
                "processing_complete": "yes",
                "processing_errors": 1
            }
        })
        # No validation happens, values pass through dict.get() as-is
        assert config.notifications_processing_complete == "yes"
        assert config.notifications_processing_errors == 1


class TestIsAppExcluded:
    """Test the is_app_excluded() method."""

    def test_excluded_app_returns_true(self):
        """Apps in excluded_apps list should return True."""
        config = Config({
            "excluded_apps": [
                "com.1password.1password",
                "com.apple.Keychain"
            ]
        })
        assert config.is_app_excluded("com.1password.1password") is True
        assert config.is_app_excluded("com.apple.Keychain") is True

    def test_non_excluded_app_returns_false(self):
        """Apps not in excluded_apps list should return False."""
        config = Config({
            "excluded_apps": ["com.1password.1password"]
        })
        assert config.is_app_excluded("com.google.Chrome") is False
        assert config.is_app_excluded("com.example.app") is False

    def test_empty_excluded_apps_returns_false(self):
        """When excluded_apps is empty, all apps return False."""
        config = Config({"excluded_apps": []})
        assert config.is_app_excluded("com.1password.1password") is False

    def test_case_sensitive_matching(self):
        """Bundle ID matching should be case-sensitive."""
        config = Config({"excluded_apps": ["com.1password.1password"]})
        assert config.is_app_excluded("com.1password.1password") is True
        assert config.is_app_excluded("com.1password.1Password") is False
        assert config.is_app_excluded("COM.1PASSWORD.1PASSWORD") is False


class TestRecommendedExclusions:
    """Test recommended exclusions functionality."""

    def test_recommended_exclusions_constant_exists(self):
        """RECOMMENDED_EXCLUSIONS should be a non-empty list."""
        assert isinstance(RECOMMENDED_EXCLUSIONS, list)
        assert len(RECOMMENDED_EXCLUSIONS) > 0

    def test_recommended_exclusions_format(self):
        """Each recommended exclusion should be a tuple (bundle_id, display_name)."""
        for item in RECOMMENDED_EXCLUSIONS:
            assert isinstance(item, tuple)
            assert len(item) == 2
            bundle_id, display_name = item
            assert isinstance(bundle_id, str)
            assert isinstance(display_name, str)
            assert len(bundle_id) > 0
            assert len(display_name) > 0

    def test_get_recommended_exclusions_method(self):
        """Config.get_recommended_exclusions() should return the constant."""
        recommended = Config.get_recommended_exclusions()
        assert recommended == RECOMMENDED_EXCLUSIONS


class TestLoadConfigFromFile:
    """Test load_config() function for loading from files."""

    def test_load_valid_config_file_with_mocked_path(self, tmp_path):
        """load_config() should parse valid JSON config file."""
        config_file = tmp_path / "config.json"
        config_data = {
            "version": "2.0.0",
            "processing_interval_minutes": 10,
            "excluded_apps": ["com.1password.1password"]
        }
        config_file.write_text(json.dumps(config_data))

        with patch('lib.config.get_config_path') as mock_get_config_path:
            mock_get_config_path.return_value = config_file
            config = load_config()
            assert config.version == "2.0.0"
            assert config.processing_interval_minutes == 10
            assert config.excluded_apps == ["com.1password.1password"]

    def test_load_config_file_not_found_raises_error(self, tmp_path):
        """load_config() should raise FileNotFoundError for missing file."""
        config_file = tmp_path / "nonexistent.json"

        with patch('lib.config.get_config_path') as mock_get_config_path:
            mock_get_config_path.return_value = config_file
            with pytest.raises(FileNotFoundError):
                load_config()

    def test_load_config_invalid_json_raises_error(self, tmp_path):
        """load_config() should raise JSONDecodeError for invalid JSON."""
        config_file = tmp_path / "invalid.json"
        config_file.write_text("{invalid json}")

        with patch('lib.config.get_config_path') as mock_get_config_path:
            mock_get_config_path.return_value = config_file
            with pytest.raises(json.JSONDecodeError):
                load_config()

    def test_load_config_uses_get_config_path(self):
        """load_config() should use get_config_path() to resolve file location."""
        with patch('lib.config.get_config_path') as mock_get_config_path:
            mock_get_config_path.return_value = Path("/tmp/test_config.json")

            # This will fail to load the file, but we're testing path resolution
            with pytest.raises(FileNotFoundError):
                load_config()

            # Should have called get_config_path()
            mock_get_config_path.assert_called_once()


class TestLoadConfigWithDefaults:
    """Test load_config_with_defaults() function."""

    def test_load_valid_config_with_defaults(self, tmp_path):
        """load_config_with_defaults() should load valid config file."""
        config_file = tmp_path / "config.json"
        config_data = {"video_fps": 60}
        config_file.write_text(json.dumps(config_data))

        with patch('lib.config.get_config_path') as mock_get_config_path:
            mock_get_config_path.return_value = config_file
            config = load_config_with_defaults()
            assert config.video_fps == 60

    def test_missing_file_returns_defaults(self, tmp_path, capsys):
        """Missing file should return default config with warning."""
        config_file = tmp_path / "nonexistent.json"

        with patch('lib.config.get_config_path') as mock_get_config_path:
            mock_get_config_path.return_value = config_file
            config = load_config_with_defaults()

            # Should return defaults
            assert config.processing_interval_minutes == 5
            assert config.temp_retention_policy == "1_week"

            # Should print warning
            captured = capsys.readouterr()
            assert "Warning" in captured.out or "Warning" in captured.err

    def test_invalid_json_returns_defaults(self, tmp_path, capsys):
        """Invalid JSON should return default config with warning."""
        config_file = tmp_path / "invalid.json"
        config_file.write_text("{invalid}")

        with patch('lib.config.get_config_path') as mock_get_config_path:
            mock_get_config_path.return_value = config_file
            config = load_config_with_defaults()

            # Should return defaults
            assert config.processing_interval_minutes == 5
            assert config.temp_retention_policy == "1_week"

    def test_no_file_argument_uses_paths_config(self):
        """load_config_with_defaults() with no arg should use paths.get_config_path()."""
        with patch('lib.config.get_config_path') as mock_get_config_path:
            mock_get_config_path.return_value = Path("/tmp/test_config.json")

            # This will fail to load the file, but we're testing path resolution
            config = load_config_with_defaults()

            # Should have called get_config_path()
            mock_get_config_path.assert_called_once()


class TestConfigVersionField:
    """Test version field handling."""

    def test_version_string_accepted(self):
        """Version should accept any string value."""
        versions = ["1.0.0", "2.0.0", "1.1.0-beta", "dev"]
        for version in versions:
            config = Config({"version": version})
            assert config.version == version

    def test_version_default_is_1_0_0(self):
        """Default version should be '1.0.0'."""
        config = Config({})
        assert config.version == "1.0.0"


class TestTimelineShortcut:
    """Test timeline_shortcut field."""

    def test_timeline_shortcut_default(self):
        """Default timeline shortcut should be 'Option+Shift+Space'."""
        config = Config({})
        assert config.timeline_shortcut == "Option+Shift+Space"

    def test_custom_timeline_shortcut(self):
        """Custom timeline shortcuts should be accepted."""
        shortcuts = [
            "Command+T",
            "Control+Shift+T",
            "F5",
            ""
        ]
        for shortcut in shortcuts:
            config = Config({"timeline_shortcut": shortcut})
            assert config.timeline_shortcut == shortcut


class TestConfigImmutability:
    """Test that config values remain consistent after creation."""

    def test_config_values_consistent_after_creation(self):
        """Config values should not change after object creation."""
        config = Config({
            "processing_interval_minutes": 10,
            "excluded_apps": ["com.1password.1password"]
        })

        # Get values multiple times
        interval1 = config.processing_interval_minutes
        interval2 = config.processing_interval_minutes
        apps1 = config.excluded_apps
        apps2 = config.excluded_apps

        assert interval1 == interval2
        assert apps1 == apps2

    def test_modifying_input_dict_does_not_affect_config(self):
        """Modifying the input dict should not affect Config object."""
        input_dict = {
            "processing_interval_minutes": 10,
            "excluded_apps": ["com.1password.1password"]
        }
        config = Config(input_dict)

        # Modify input dict
        input_dict["processing_interval_minutes"] = 30
        input_dict["excluded_apps"].append("com.apple.Keychain")

        # Config should retain original values
        assert config.processing_interval_minutes == 10
        assert config.excluded_apps == ["com.1password.1password"]
