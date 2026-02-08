"""
Unit tests for the timestamps module.

Tests filename parsing, generation, and sanitization functions.
"""

from datetime import datetime
from unittest.mock import patch

# Import the module under test
import lib.timestamps as timestamps


class TestParseTimestampFromName:
    """Test parse_timestamp_from_name function."""

    def test_valid_timestamp_parsing(self):
        """Test parsing valid timestamp from filename."""
        # Known timestamp: 2025-02-07 14:30:22
        name = "20250207-143022-abc123-com.example.app"
        result = timestamps.parse_timestamp_from_name(name)

        assert result is not None
        # Verify it's a reasonable timestamp (2025-02-07)
        dt = datetime.fromtimestamp(result)
        assert dt.year == 2025
        assert dt.month == 2
        assert dt.day == 7
        assert dt.hour == 14
        assert dt.minute == 30
        assert dt.second == 22

    def test_timestamp_with_file_extension(self):
        """Test parsing timestamp from filename with extension."""
        name = "20250207-143022-abc123-com.example.app.png"
        result = timestamps.parse_timestamp_from_name(name)

        assert result is not None
        dt = datetime.fromtimestamp(result)
        assert dt.year == 2025
        assert dt.month == 2
        assert dt.day == 7

    def test_timestamp_without_app_id(self):
        """Test parsing timestamp from filename without app ID."""
        name = "20250207-143022-abc123"
        result = timestamps.parse_timestamp_from_name(name)

        assert result is not None
        dt = datetime.fromtimestamp(result)
        assert dt.year == 2025

    def test_invalid_format_returns_none(self):
        """Test that invalid formats return None."""
        invalid_names = [
            "invalid-filename",
            "2025-02-07-14:30:22",  # Wrong separators
            "20250207",  # Missing time
            "143022",  # Missing date
            "",  # Empty string
            "abcdefgh-ijklmn-uuid",  # No valid date
        ]

        for name in invalid_names:
            result = timestamps.parse_timestamp_from_name(name)
            assert result is None, f"Expected None for '{name}', got {result}"

    def test_invalid_date_values(self):
        """Test that invalid date values return None."""
        invalid_names = [
            "20251332-143022-abc123",  # Month 13, day 32
            "20250230-143022-abc123",  # Feb 30 doesn't exist
            "20250101-256070-abc123",  # Hour 25, minute 60, second 70
        ]

        for name in invalid_names:
            result = timestamps.parse_timestamp_from_name(name)
            assert result is None, f"Expected None for '{name}', got {result}"

    def test_edge_case_dates(self):
        """Test edge case dates like leap years, year boundaries."""
        # Leap year Feb 29
        name = "20240229-120000-abc123-app"
        result = timestamps.parse_timestamp_from_name(name)
        assert result is not None

        # New Year's Eve
        name = "20251231-235959-abc123-app"
        result = timestamps.parse_timestamp_from_name(name)
        assert result is not None

        # Jan 1
        name = "20250101-000000-abc123-app"
        result = timestamps.parse_timestamp_from_name(name)
        assert result is not None


class TestParseAppFromName:
    """Test parse_app_from_name function."""

    def test_valid_app_id_extraction(self):
        """Test extracting valid app ID from filename."""
        name = "20250207-143022-abc123-com.example.app"
        result = timestamps.parse_app_from_name(name)
        assert result == "com.example.app"

    def test_app_id_with_extension(self):
        """Test extracting app ID from filename with extension."""
        name = "20250207-143022-abc123-com.example.app.png"
        result = timestamps.parse_app_from_name(name)
        assert result == "com.example.app"

    def test_app_id_with_mp4_extension(self):
        """Test extracting app ID from video filename."""
        name = "20250207-143022-abc123-com.example.app.mp4"
        result = timestamps.parse_app_from_name(name)
        assert result == "com.example.app"

    def test_complex_app_id(self):
        """Test extracting complex app ID with multiple dots."""
        name = "20250207-143022-abc123-com.company.product.app"
        result = timestamps.parse_app_from_name(name)
        assert result == "com.company.product.app"

    def test_no_app_id_returns_none(self):
        """Test that filename without app ID returns None."""
        name = "20250207-143022-abc123"
        result = timestamps.parse_app_from_name(name)
        assert result is None

    def test_empty_app_id_returns_none(self):
        """Test that filename with empty app ID returns None."""
        name = "20250207-143022-abc123-"
        result = timestamps.parse_app_from_name(name)
        assert result is None

    def test_invalid_format_returns_none(self):
        """Test that invalid formats return None."""
        invalid_names = [
            "invalid-filename",
            "20250207-143022",  # No UUID separator
            "20250207143022-abc123-app",  # No time separator
            "",
        ]

        for name in invalid_names:
            result = timestamps.parse_app_from_name(name)
            assert result is None, f"Expected None for '{name}', got {result}"

    def test_app_id_with_numbers(self):
        """Test extracting app ID containing numbers."""
        name = "20250207-143022-abc123-com.1password.1password"
        result = timestamps.parse_app_from_name(name)
        assert result == "com.1password.1password"


class TestSanitizeAppId:
    """Test sanitize_app_id function."""

    def test_valid_app_id_unchanged(self):
        """Test that valid app IDs pass through unchanged."""
        valid_ids = [
            "com.example.app",
            "com.company.product",
            "com.1password.1password",
            "org.mozilla.firefox",
        ]

        for app_id in valid_ids:
            result = timestamps.sanitize_app_id(app_id)
            assert result == app_id

    def test_special_characters_replaced(self):
        """Test that special characters are replaced with underscores."""
        assert timestamps.sanitize_app_id("My App!@#") == "My_App_"  # Consecutive special chars become single _
        assert timestamps.sanitize_app_id("app name") == "app_name"
        assert timestamps.sanitize_app_id("app-name") == "app_name"
        assert timestamps.sanitize_app_id("app/name") == "app_name"

    def test_empty_string_becomes_unknown(self):
        """Test that empty string becomes 'unknown'."""
        assert timestamps.sanitize_app_id("") == "unknown"

    def test_whitespace_replaced(self):
        """Test that whitespace is replaced with underscores."""
        assert timestamps.sanitize_app_id("app name") == "app_name"
        assert timestamps.sanitize_app_id("app\tname") == "app_name"
        assert timestamps.sanitize_app_id("app\nname") == "app_name"

    def test_consecutive_special_chars(self):
        """Test that consecutive special characters become single underscore."""
        assert timestamps.sanitize_app_id("app!!!name") == "app_name"
        assert timestamps.sanitize_app_id("app   name") == "app_name"

    def test_unicode_characters(self):
        """Test handling of unicode characters."""
        result = timestamps.sanitize_app_id("app™®©")
        assert "_" in result
        # Unicode characters should be replaced

    def test_numbers_preserved(self):
        """Test that numbers are preserved."""
        assert timestamps.sanitize_app_id("app123") == "app123"
        assert timestamps.sanitize_app_id("com.1password.2fa") == "com.1password.2fa"


class TestGenerateChunkName:
    """Test generate_chunk_name function."""

    def test_basic_generation(self):
        """Test basic chunk name generation."""
        dt = datetime(2025, 2, 7, 14, 30, 22)
        name = timestamps.generate_chunk_name(dt, "com.example.app")

        # Check format
        assert name.startswith("20250207-143022-")
        assert name.endswith("-com.example.app")

        # Check UUID part exists (8 hex chars)
        parts = name.split("-")
        assert len(parts) == 4
        assert len(parts[2]) == 8  # UUID part
        assert all(c in "0123456789abcdef" for c in parts[2])

    def test_generation_without_app_id(self):
        """Test generation without app ID."""
        dt = datetime(2025, 2, 7, 14, 30, 22)
        name = timestamps.generate_chunk_name(dt)

        assert name.startswith("20250207-143022-")
        assert name.endswith("-unknown")

    def test_generation_with_none_app_id(self):
        """Test generation with None app ID."""
        dt = datetime(2025, 2, 7, 14, 30, 22)
        name = timestamps.generate_chunk_name(dt, None)

        assert name.endswith("-unknown")

    def test_generation_with_empty_app_id(self):
        """Test generation with empty app ID."""
        dt = datetime(2025, 2, 7, 14, 30, 22)
        name = timestamps.generate_chunk_name(dt, "")

        assert name.endswith("-unknown")

    def test_unique_generation(self):
        """Test that multiple calls generate unique names."""
        dt = datetime(2025, 2, 7, 14, 30, 22)
        names = set()

        for _ in range(10):
            name = timestamps.generate_chunk_name(dt, "com.example.app")
            names.add(name)

        # All names should be unique due to UUID
        assert len(names) == 10

    def test_app_id_sanitized(self):
        """Test that app ID is sanitized in generated name."""
        dt = datetime(2025, 2, 7, 14, 30, 22)
        name = timestamps.generate_chunk_name(dt, "My App!")

        assert "My_App_" in name
        assert "!" not in name

    def test_different_timestamps(self):
        """Test generation with different timestamps."""
        names = []

        for day in range(1, 4):
            dt = datetime(2025, 2, day, 12, 0, 0)
            name = timestamps.generate_chunk_name(dt, "com.example.app")
            names.append(name)

        # Check that dates differ
        assert names[0].startswith("20250201-")
        assert names[1].startswith("20250202-")
        assert names[2].startswith("20250203-")

    def test_midnight_timestamp(self):
        """Test generation at midnight."""
        dt = datetime(2025, 2, 7, 0, 0, 0)
        name = timestamps.generate_chunk_name(dt, "com.example.app")

        assert "000000" in name  # 00:00:00 time

    def test_end_of_day_timestamp(self):
        """Test generation at end of day."""
        dt = datetime(2025, 2, 7, 23, 59, 59)
        name = timestamps.generate_chunk_name(dt, "com.example.app")

        assert "235959" in name  # 23:59:59 time


class TestRoundTrip:
    """Test round-trip parsing and generation."""

    def test_parse_generated_name(self):
        """Test that generated names can be parsed correctly."""
        dt = datetime(2025, 2, 7, 14, 30, 22)
        app_id = "com.example.app"

        name = timestamps.generate_chunk_name(dt, app_id)

        # Parse timestamp
        parsed_ts = timestamps.parse_timestamp_from_name(name)
        assert parsed_ts is not None

        parsed_dt = datetime.fromtimestamp(parsed_ts)
        assert parsed_dt.year == dt.year
        assert parsed_dt.month == dt.month
        assert parsed_dt.day == dt.day
        assert parsed_dt.hour == dt.hour
        assert parsed_dt.minute == dt.minute
        assert parsed_dt.second == dt.second

        # Parse app ID
        parsed_app = timestamps.parse_app_from_name(name)
        assert parsed_app == app_id

    def test_parse_generated_name_with_extension(self):
        """Test parsing generated name with file extension."""
        dt = datetime(2025, 2, 7, 14, 30, 22)
        app_id = "com.example.app"

        name = timestamps.generate_chunk_name(dt, app_id) + ".png"

        parsed_ts = timestamps.parse_timestamp_from_name(name)
        assert parsed_ts is not None

        parsed_app = timestamps.parse_app_from_name(name)
        assert parsed_app == app_id


class TestDateRegex:
    """Test DATE_RE regex pattern."""

    def test_regex_matches_valid_format(self):
        """Test that regex matches valid date-time format."""
        valid_strings = [
            "20250207-143022",
            "20240101-000000",
            "20251231-235959",
        ]

        for s in valid_strings:
            match = timestamps.DATE_RE.match(s)
            assert match is not None
            assert match.group("date") is not None
            assert match.group("time") is not None

    def test_regex_rejects_invalid_format(self):
        """Test that regex rejects invalid formats."""
        invalid_strings = [
            "2025-02-07-14:30:22",  # Wrong separators
            "20250207",  # Missing time
            "143022",  # Missing date
            "invalid",
        ]

        for s in invalid_strings:
            match = timestamps.DATE_RE.match(s)
            assert match is None

    def test_regex_extracts_correct_groups(self):
        """Test that regex extracts correct date and time groups."""
        s = "20250207-143022-rest-of-string"
        match = timestamps.DATE_RE.match(s)

        assert match.group("date") == "20250207"
        assert match.group("time") == "143022"
