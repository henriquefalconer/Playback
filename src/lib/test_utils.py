"""
Unit tests for the utils module.

Tests shared utility functions used across Playback scripts and services.
"""

# Import the module under test
import lib.utils as utils


class TestFormatSize:
    """Test format_size function."""

    def test_bytes(self):
        """Test formatting byte counts less than 1 KB."""
        assert utils.format_size(0) == "0 B"
        assert utils.format_size(1) == "1 B"
        assert utils.format_size(512) == "512 B"
        assert utils.format_size(1023) == "1023 B"

    def test_kilobytes(self):
        """Test formatting byte counts in KB range."""
        assert utils.format_size(1024) == "1.0 KB"
        assert utils.format_size(2048) == "2.0 KB"
        assert utils.format_size(1536) == "1.5 KB"
        assert utils.format_size(102400) == "100.0 KB"

    def test_megabytes(self):
        """Test formatting byte counts in MB range."""
        assert utils.format_size(1024 ** 2) == "1.0 MB"
        assert utils.format_size(1024 ** 2 * 2) == "2.0 MB"
        assert utils.format_size(1024 ** 2 + 1024 ** 2 // 2) == "1.5 MB"
        assert utils.format_size(1024 ** 2 * 100) == "100.0 MB"

    def test_gigabytes(self):
        """Test formatting byte counts in GB range."""
        assert utils.format_size(1024 ** 3) == "1.00 GB"
        assert utils.format_size(1024 ** 3 * 2) == "2.00 GB"
        assert utils.format_size(int(1024 ** 3 * 1.5)) == "1.50 GB"
        assert utils.format_size(1024 ** 3 * 100) == "100.00 GB"

    def test_edge_cases(self):
        """Test edge cases and boundary values."""
        # Boundary between B and KB
        assert utils.format_size(1023) == "1023 B"
        assert utils.format_size(1024) == "1.0 KB"

        # Boundary between KB and MB
        assert utils.format_size(1024 ** 2 - 1) == "1024.0 KB"
        assert utils.format_size(1024 ** 2) == "1.0 MB"

        # Boundary between MB and GB
        assert utils.format_size(1024 ** 3 - 1) == "1024.0 MB"
        assert utils.format_size(1024 ** 3) == "1.00 GB"

    def test_precision(self):
        """Test decimal precision for different units."""
        # KB and MB use 1 decimal place
        assert utils.format_size(1536) == "1.5 KB"
        assert utils.format_size(1024 ** 2 + 512 * 1024) == "1.5 MB"

        # GB uses 2 decimal places
        assert utils.format_size(int(1024 ** 3 * 1.234)) == "1.23 GB"
        assert utils.format_size(int(1024 ** 3 * 1.999)) == "2.00 GB"

    def test_large_values(self):
        """Test very large byte counts."""
        # 1 TB
        assert utils.format_size(1024 ** 4) == "1024.00 GB"

        # 10 TB
        assert utils.format_size(1024 ** 4 * 10) == "10240.00 GB"
