"""
Configuration management for Playback Python services.

Provides functions to load and parse the config.json file with validation
and default fallback values.
"""

import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from .paths import get_config_path


RECOMMENDED_EXCLUSIONS: List[Tuple[str, str]] = [
    ("com.apple.keychainaccess", "Keychain Access"),
    ("com.1password.1password", "1Password 8"),
    ("com.agilebits.onepassword7", "1Password 7"),
    ("com.lastpass.LastPass", "LastPass"),
    ("com.dashlane.Dashlane", "Dashlane"),
    ("com.keepassxc.keepassxc", "KeePassXC"),
    ("com.bitwarden.desktop", "Bitwarden"),
    ("org.keepassx.keepassxc", "KeePassX"),
]
"""
Recommended apps to exclude from recording.

This list contains bundle IDs and display names of password managers and
other sensitive applications that users should consider excluding from
screen recording.

IMPORTANT: These apps are NOT automatically excluded. Users must manually
add them to the excluded_apps list in their config.json. This list is
provided as a convenience for users to make informed privacy decisions.

Each entry is a tuple of (bundle_id, display_name).

Privacy rationale:
- Password managers: Prevent recording of master passwords, stored credentials
- Sensitive apps: Prevent recording of banking, financial, or personal data

To exclude an app, users should add the bundle ID to the "excluded_apps"
array in config.json:
{
  "excluded_apps": ["com.1password.1password", "com.apple.keychainaccess"]
}
"""


class Config:
    """Configuration holder with typed properties."""

    def __init__(self, config_dict: Dict[str, Any]):
        """
        Initialize configuration from dictionary.

        Args:
            config_dict: Configuration dictionary loaded from JSON.
        """
        self.version: str = config_dict.get("version", "1.0.0")
        self.processing_interval_minutes: int = config_dict.get("processing_interval_minutes", 5)
        self.temp_retention_policy: str = config_dict.get("temp_retention_policy", "1_week")
        self.recording_retention_policy: str = config_dict.get("recording_retention_policy", "never")
        self.exclusion_mode: str = config_dict.get("exclusion_mode", "skip")
        self.excluded_apps: List[str] = config_dict.get("excluded_apps", [])
        self.ffmpeg_crf: int = config_dict.get("ffmpeg_crf", 28)
        self.video_fps: int = config_dict.get("video_fps", 30)
        self.timeline_shortcut: str = config_dict.get("timeline_shortcut", "Option+Shift+Space")

        notifications = config_dict.get("notifications", {})
        self.notifications_processing_complete: bool = notifications.get("processing_complete", True)
        self.notifications_processing_errors: bool = notifications.get("processing_errors", True)
        self.notifications_disk_space_warnings: bool = notifications.get("disk_space_warnings", True)
        self.notifications_recording_status: bool = notifications.get("recording_status", False)

        self._validate()

    def _validate(self) -> None:
        """Validate configuration values and apply defaults for invalid values."""
        valid_intervals = [1, 5, 10, 15, 30, 60]
        if self.processing_interval_minutes not in valid_intervals:
            self.processing_interval_minutes = 5

        valid_policies = ["never", "1_day", "1_week", "1_month"]
        if self.temp_retention_policy not in valid_policies:
            self.temp_retention_policy = "1_week"
        if self.recording_retention_policy not in valid_policies:
            self.recording_retention_policy = "never"

        if self.exclusion_mode not in ["invisible", "skip"]:
            self.exclusion_mode = "skip"

        self.excluded_apps = [
            app.strip() for app in self.excluded_apps
            if app.strip() and all(c.isalnum() or c in ".-" for c in app.strip())
        ]

        if not (0 <= self.ffmpeg_crf <= 51):
            self.ffmpeg_crf = 28

        if self.video_fps <= 0:
            self.video_fps = 30

    def is_app_excluded(self, bundle_id: str) -> bool:
        """
        Check if an app should be excluded from recording.

        Args:
            bundle_id: Bundle identifier of the app to check.

        Returns:
            True if the app is in the excluded_apps list, False otherwise.
        """
        return bundle_id in self.excluded_apps

    @staticmethod
    def get_recommended_exclusions() -> List[Tuple[str, str]]:
        """
        Get list of recommended apps to exclude from recording.

        Returns a list of (bundle_id, display_name) tuples for password managers
        and other sensitive applications that users should consider excluding.

        IMPORTANT: These apps are NOT automatically excluded. Users must manually
        add them to their config.json excluded_apps list. This method is provided
        for UI convenience and user education about privacy options.

        Returns:
            List of (bundle_id, display_name) tuples.

        Example:
            >>> recommendations = Config.get_recommended_exclusions()
            >>> for bundle_id, name in recommendations:
            ...     print(f"{name}: {bundle_id}")
            Keychain Access: com.apple.keychainaccess
            1Password 8: com.1password.1password
            ...
        """
        return RECOMMENDED_EXCLUSIONS.copy()


def load_config() -> Config:
    """
    Load configuration from config.json file.

    Automatically uses the correct config file path based on environment
    (development vs production).

    Returns:
        Config object with validated configuration values.

    Raises:
        FileNotFoundError: If config file doesn't exist.
        json.JSONDecodeError: If config file contains invalid JSON.
    """
    config_path = get_config_path()

    if not config_path.exists():
        raise FileNotFoundError(
            f"Config file not found: {config_path}. "
            "Create a config.json file or run the Playback app to generate defaults."
        )

    with open(config_path, "r", encoding="utf-8") as f:
        config_dict = json.load(f)

    return Config(config_dict)


def load_config_with_defaults() -> Config:
    """
    Load configuration with fallback to defaults if file doesn't exist.

    Returns:
        Config object with validated configuration values.
    """
    try:
        return load_config()
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"Warning: Failed to load config ({e}), using defaults")
        return Config({})


__all__ = [
    "Config",
    "load_config",
    "load_config_with_defaults",
    "RECOMMENDED_EXCLUSIONS",
]
