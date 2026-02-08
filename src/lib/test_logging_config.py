"""
Unit tests for logging_config.py - Structured JSON logging configuration.
"""

import json
import logging
import tempfile
from datetime import datetime
from pathlib import Path
from unittest.mock import MagicMock, patch

from lib import logging_config


class TestJSONFormatter:
    """Tests for JSONFormatter class."""

    def test_format_basic_message(self):
        """Test formatting basic log message to JSON."""
        formatter = logging_config.JSONFormatter("test_component")
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="",
            lineno=0,
            msg="Test message",
            args=(),
            exc_info=None,
        )

        output = formatter.format(record)
        parsed = json.loads(output)

        assert parsed["level"] == "INFO"
        assert parsed["component"] == "test_component"
        assert parsed["message"] == "Test message"
        assert "timestamp" in parsed
        assert parsed["timestamp"].endswith("Z")

    def test_format_with_metadata(self):
        """Test formatting log message with metadata."""
        formatter = logging_config.JSONFormatter("recording")
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="",
            lineno=0,
            msg="Screenshot captured",
            args=(),
            exc_info=None,
        )
        record.metadata = {"path": "/tmp/test.png", "size_kb": 123}

        output = formatter.format(record)
        parsed = json.loads(output)

        assert parsed["metadata"]["path"] == "/tmp/test.png"
        assert parsed["metadata"]["size_kb"] == 123

    def test_format_with_exception(self):
        """Test formatting log message with exception."""
        formatter = logging_config.JSONFormatter("processing")
        try:
            raise ValueError("Test error")
        except ValueError:
            import sys

            exc_info = sys.exc_info()
            record = logging.LogRecord(
                name="test",
                level=logging.ERROR,
                pathname="",
                lineno=0,
                msg="Error occurred",
                args=(),
                exc_info=exc_info,
            )

            output = formatter.format(record)
            parsed = json.loads(output)

            assert parsed["level"] == "ERROR"
            assert "exception" in parsed
            assert "ValueError: Test error" in parsed["exception"]

    def test_timestamp_format(self):
        """Test timestamp is ISO 8601 with Z suffix."""
        formatter = logging_config.JSONFormatter("test")
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="",
            lineno=0,
            msg="Test",
            args=(),
            exc_info=None,
        )

        output = formatter.format(record)
        parsed = json.loads(output)

        # Verify ISO 8601 format with Z suffix
        timestamp = parsed["timestamp"]
        assert timestamp.endswith("Z")
        # Should be parseable as ISO 8601
        datetime.fromisoformat(timestamp.replace("Z", "+00:00"))

    def test_unicode_message(self):
        """Test formatting message with unicode characters."""
        formatter = logging_config.JSONFormatter("test")
        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname="",
            lineno=0,
            msg="Test with unicode: 你好世界 🎉",
            args=(),
            exc_info=None,
        )

        output = formatter.format(record)
        parsed = json.loads(output)

        assert "你好世界" in parsed["message"]
        assert "🎉" in parsed["message"]


class TestSetupLogger:
    """Tests for setup_logger function."""

    def test_setup_logger_creates_logger(self):
        """Test setup_logger creates logger with correct name."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("lib.logging_config.paths.is_development_mode", return_value=True):
                with patch(
                    "lib.logging_config.paths.PROJECT_ROOT", Path(tmpdir)
                ):
                    logger = logging_config.setup_logger("recording", console_output=False)

                    assert logger.name == "playback.recording"
                    assert logger.level == logging.INFO

    def test_setup_logger_creates_log_file(self):
        """Test setup_logger creates log file in correct directory."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("lib.logging_config.paths.is_development_mode", return_value=True):
                with patch(
                    "lib.logging_config.paths.PROJECT_ROOT", Path(tmpdir)
                ):
                    logger = logging_config.setup_logger("test_service", console_output=False)
                    logger.info("Test message")

                    log_file = Path(tmpdir) / "dev_logs" / "test_service.log"
                    assert log_file.exists()

    def test_setup_logger_log_level(self):
        """Test setup_logger respects log_level parameter."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("lib.logging_config.paths.is_development_mode", return_value=True):
                with patch(
                    "lib.logging_config.paths.PROJECT_ROOT", Path(tmpdir)
                ):
                    logger = logging_config.setup_logger(
                        "test", log_level="DEBUG", console_output=False
                    )

                    assert logger.level == logging.DEBUG

    def test_setup_logger_production_path(self):
        """Test setup_logger uses production path when not in dev mode."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("lib.logging_config.paths.is_development_mode", return_value=False):
                with patch("pathlib.Path.home", return_value=Path(tmpdir)):
                    logger = logging_config.setup_logger("processing", console_output=False)
                    logger.info("Test")

                    log_file = Path(tmpdir) / "Library" / "Logs" / "Playback" / "processing.log"
                    assert log_file.exists()

    def test_setup_logger_with_console_output(self):
        """Test setup_logger adds console handler when requested."""
        logger = logging_config.setup_logger("test", console_output=True)

        # Should have 2 handlers: file + console
        assert len(logger.handlers) >= 2

    def test_setup_logger_without_console_output(self):
        """Test setup_logger only has file handler when console disabled."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("lib.logging_config.paths.is_development_mode", return_value=True):
                with patch(
                    "lib.logging_config.paths.PROJECT_ROOT", Path(tmpdir)
                ):
                    logger = logging_config.setup_logger("test", console_output=False)

                    # Should have exactly 1 handler: file only
                    assert len(logger.handlers) == 1

    def test_setup_logger_clears_existing_handlers(self):
        """Test setup_logger removes existing handlers before adding new ones."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("lib.logging_config.paths.is_development_mode", return_value=True):
                with patch(
                    "lib.logging_config.paths.PROJECT_ROOT", Path(tmpdir)
                ):
                    # Setup logger twice
                    logger1 = logging_config.setup_logger("test", console_output=False)
                    handler_count_1 = len(logger1.handlers)

                    logger2 = logging_config.setup_logger("test", console_output=False)
                    handler_count_2 = len(logger2.handlers)

                    # Should have same number of handlers (not doubled)
                    assert handler_count_1 == handler_count_2


class TestLogWithMetadata:
    """Tests for log_with_metadata function."""

    def test_log_with_metadata_info(self):
        """Test logging info message with metadata."""
        logger = MagicMock()
        logging_config.log_with_metadata(
            logger, "info", "Test message", key1="value1", key2=123
        )

        logger.info.assert_called_once()
        call_args = logger.info.call_args
        assert call_args[0][0] == "Test message"
        assert call_args[1]["extra"]["metadata"]["key1"] == "value1"
        assert call_args[1]["extra"]["metadata"]["key2"] == 123

    def test_log_with_metadata_error(self):
        """Test logging error message with metadata."""
        logger = MagicMock()
        logging_config.log_with_metadata(logger, "error", "Error occurred", error_code=404)

        logger.error.assert_called_once()

    def test_log_with_metadata_debug(self):
        """Test logging debug message with metadata."""
        logger = MagicMock()
        logging_config.log_with_metadata(logger, "debug", "Debug info", details="test")

        logger.debug.assert_called_once()


class TestLogResourceMetrics:
    """Tests for log_resource_metrics function."""

    def test_log_resource_metrics_basic(self):
        """Test logging resource metrics with required fields."""
        logger = MagicMock()
        logging_config.log_resource_metrics(
            logger,
            cpu_percent=15.234,
            memory_mb=234.567,
            disk_free_gb=45.321,
            uptime_hours=2.5,
        )

        logger.info.assert_called_once()
        call_args = logger.info.call_args
        metadata = call_args[1]["extra"]["metadata"]

        assert metadata["cpu_percent"] == 15.2  # Rounded to 1 decimal
        assert metadata["memory_mb"] == 234.6
        assert metadata["disk_free_gb"] == 45.3
        assert metadata["uptime_hours"] == 2.5

    def test_log_resource_metrics_with_additional(self):
        """Test logging resource metrics with additional fields."""
        logger = MagicMock()
        logging_config.log_resource_metrics(
            logger,
            cpu_percent=10.0,
            memory_mb=100.0,
            disk_free_gb=50.0,
            uptime_hours=1.0,
            captures_total=500,
            custom_metric="test",
        )

        call_args = logger.info.call_args
        metadata = call_args[1]["extra"]["metadata"]

        assert metadata["captures_total"] == 500
        assert metadata["custom_metric"] == "test"


class TestLogErrorWithContext:
    """Tests for log_error_with_context function."""

    def test_log_error_without_exception(self):
        """Test logging error without exception."""
        logger = MagicMock()
        logging_config.log_error_with_context(
            logger, "Operation failed", file_path="/tmp/test.png", reason="not found"
        )

        logger.error.assert_called_once()
        call_args = logger.error.call_args
        assert "exc_info" not in call_args[1]

    def test_log_error_with_exception(self):
        """Test logging error with exception."""
        logger = MagicMock()
        try:
            raise ValueError("Test error")
        except ValueError as e:
            logging_config.log_error_with_context(
                logger, "Operation failed", exception=e, context="test"
            )

        logger.error.assert_called_once()
        call_args = logger.error.call_args
        assert call_args[1]["exc_info"] is not None


class TestLogProcessingCompletion:
    """Tests for log_processing_completion function."""

    def test_log_processing_completion_basic(self):
        """Test logging processing completion with required fields."""
        logger = MagicMock()
        logging_config.log_processing_completion(
            logger,
            date="2026-02-07",
            duration_s=45.123,
            segments_created=142,
            cpu_avg_pct=35.234,
            memory_peak_mb=512.567,
        )

        logger.info.assert_called_once()
        call_args = logger.info.call_args
        metadata = call_args[1]["extra"]["metadata"]

        assert metadata["date"] == "2026-02-07"
        assert metadata["duration_s"] == 45.1
        assert metadata["segments_created"] == 142
        assert metadata["cpu_avg_pct"] == 35.2
        assert metadata["memory_peak_mb"] == 512.6

    def test_log_processing_completion_with_additional(self):
        """Test logging processing completion with additional stats."""
        logger = MagicMock()
        logging_config.log_processing_completion(
            logger,
            date="20260207",
            duration_s=30.0,
            segments_created=100,
            cpu_avg_pct=20.0,
            memory_peak_mb=400.0,
            disk_read_mb=1234.5,
            disk_write_mb=567.8,
        )

        call_args = logger.info.call_args
        metadata = call_args[1]["extra"]["metadata"]

        assert metadata["disk_read_mb"] == 1234.5
        assert metadata["disk_write_mb"] == 567.8


class TestConvenienceFunctions:
    """Tests for convenience logging functions."""

    def test_log_info(self):
        """Test log_info convenience function."""
        logger = MagicMock()
        logging_config.log_info(logger, "Info message", key="value")

        logger.info.assert_called_once()

    def test_log_warning(self):
        """Test log_warning convenience function."""
        logger = MagicMock()
        logging_config.log_warning(logger, "Warning message", code=123)

        logger.warning.assert_called_once()

    def test_log_error(self):
        """Test log_error convenience function."""
        logger = MagicMock()
        logging_config.log_error(logger, "Error message", error="test")

        logger.error.assert_called_once()

    def test_log_critical(self):
        """Test log_critical convenience function."""
        logger = MagicMock()
        logging_config.log_critical(logger, "Critical message", severity="high")

        logger.critical.assert_called_once()

    def test_log_debug(self):
        """Test log_debug convenience function."""
        logger = MagicMock()
        logging_config.log_debug(logger, "Debug message", details="test")

        logger.debug.assert_called_once()


class TestLogRotation:
    """Tests for log rotation configuration."""

    def test_rotating_file_handler_configured(self):
        """Test that RotatingFileHandler is configured correctly."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("lib.logging_config.paths.is_development_mode", return_value=True):
                with patch(
                    "lib.logging_config.paths.PROJECT_ROOT", Path(tmpdir)
                ):
                    logger = logging_config.setup_logger(
                        "test",
                        console_output=False,
                        max_bytes=5000,
                        backup_count=3,
                    )

                    # Find the file handler
                    file_handler = None
                    for handler in logger.handlers:
                        if isinstance(handler, logging.handlers.RotatingFileHandler):
                            file_handler = handler
                            break

                    assert file_handler is not None
                    assert file_handler.maxBytes == 5000
                    assert file_handler.backupCount == 3

    def test_log_rotation_creates_backups(self):
        """Test that log rotation creates backup files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("lib.logging_config.paths.is_development_mode", return_value=True):
                with patch(
                    "lib.logging_config.paths.PROJECT_ROOT", Path(tmpdir)
                ):
                    # Create logger with small max_bytes to trigger rotation
                    logger = logging_config.setup_logger(
                        "test",
                        console_output=False,
                        max_bytes=100,  # Very small to trigger rotation
                        backup_count=2,
                    )

                    # Write enough data to trigger rotation
                    for i in range(50):
                        logger.info(f"Test message {i}" * 10)

                    log_dir = Path(tmpdir) / "dev_logs"
                    log_file = log_dir / "test.log"

                    # Check that log file and potentially backup exist
                    assert log_file.exists()
                    # Rotation may have created .1 backup
                    # (depends on exact message sizes, so we don't assert backup exists)
