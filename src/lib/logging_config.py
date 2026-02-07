"""
Centralized logging configuration for Playback.

Provides structured JSON logging with rotation for all Playback services.
"""

import json
import logging
import logging.handlers
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

from lib import paths


class JSONFormatter(logging.Formatter):
    """Custom formatter that outputs newline-delimited JSON."""

    def __init__(self, component: str):
        """Initialize JSON formatter.

        Args:
            component: Component name (recording, processing, cleanup, export)
        """
        super().__init__()
        self.component = component

    def format(self, record: logging.LogRecord) -> str:
        """Format log record as JSON.

        Args:
            record: Log record to format

        Returns:
            JSON string representation of log record
        """
        log_entry: Dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "level": record.levelname,
            "component": self.component,
            "message": record.getMessage(),
        }

        # Add metadata from extra fields
        if hasattr(record, "metadata") and isinstance(record.metadata, dict):
            log_entry["metadata"] = record.metadata

        # Add exception info if present
        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)

        return json.dumps(log_entry, ensure_ascii=False)


def setup_logger(
    component: str,
    log_level: str = "INFO",
    max_bytes: int = 10 * 1024 * 1024,  # 10 MB
    backup_count: int = 5,
    console_output: bool = True,
) -> logging.Logger:
    """Setup logger with JSON formatting and file rotation.

    Args:
        component: Component name (recording, processing, cleanup, export)
        log_level: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        max_bytes: Maximum size per log file in bytes (default: 10 MB)
        backup_count: Number of backup files to keep (default: 5)
        console_output: Whether to also output logs to console (default: True)

    Returns:
        Configured logger instance
    """
    logger = logging.getLogger(f"playback.{component}")
    logger.setLevel(getattr(logging, log_level.upper()))
    logger.handlers.clear()  # Remove any existing handlers

    # Determine log directory based on environment
    if paths.is_development_mode():
        log_dir = paths.PROJECT_ROOT / "dev_logs"
    else:
        log_dir = Path.home() / "Library" / "Logs" / "Playback"

    # Ensure log directory exists
    log_dir.mkdir(parents=True, exist_ok=True)

    # Create rotating file handler
    log_file = log_dir / f"{component}.log"
    file_handler = logging.handlers.RotatingFileHandler(
        log_file,
        maxBytes=max_bytes,
        backupCount=backup_count,
        encoding="utf-8",
    )
    file_handler.setFormatter(JSONFormatter(component))
    logger.addHandler(file_handler)

    # Add console handler if requested
    if console_output:
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(JSONFormatter(component))
        logger.addHandler(console_handler)

    return logger


def log_with_metadata(logger: logging.Logger, level: str, message: str, **metadata: Any) -> None:
    """Log message with structured metadata.

    Args:
        logger: Logger instance
        level: Log level (debug, info, warning, error, critical)
        message: Log message
        **metadata: Additional key-value pairs to include in metadata field
    """
    log_method = getattr(logger, level.lower())
    log_method(message, extra={"metadata": metadata})


def log_resource_metrics(
    logger: logging.Logger,
    cpu_percent: float,
    memory_mb: float,
    disk_free_gb: float,
    uptime_hours: float,
    **additional_metrics: Any,
) -> None:
    """Log resource usage metrics.

    Args:
        logger: Logger instance
        cpu_percent: CPU usage percentage
        memory_mb: Memory usage in megabytes (RSS)
        disk_free_gb: Free disk space in gigabytes
        uptime_hours: Service uptime in hours
        **additional_metrics: Additional metrics to log
    """
    metadata = {
        "cpu_percent": round(cpu_percent, 1),
        "memory_mb": round(memory_mb, 1),
        "disk_free_gb": round(disk_free_gb, 1),
        "uptime_hours": round(uptime_hours, 2),
        **additional_metrics,
    }
    log_with_metadata(logger, "info", "Resource metrics", **metadata)


def log_error_with_context(
    logger: logging.Logger,
    message: str,
    exception: Optional[Exception] = None,
    **context: Any,
) -> None:
    """Log error with exception and context metadata.

    Args:
        logger: Logger instance
        message: Error message
        exception: Exception instance (optional)
        **context: Additional context key-value pairs
    """
    if exception:
        logger.error(message, exc_info=exception, extra={"metadata": context})
    else:
        log_with_metadata(logger, "error", message, **context)


def log_processing_completion(
    logger: logging.Logger,
    date: str,
    duration_s: float,
    segments_created: int,
    cpu_avg_pct: float,
    memory_peak_mb: float,
    **additional_stats: Any,
) -> None:
    """Log processing completion metrics.

    Args:
        logger: Logger instance
        date: Date processed (YYYY-MM-DD or YYYYMMDD)
        duration_s: Processing duration in seconds
        segments_created: Number of segments created
        cpu_avg_pct: Average CPU usage percentage
        memory_peak_mb: Peak memory usage in megabytes
        **additional_stats: Additional statistics to log
    """
    metadata = {
        "date": date,
        "duration_s": round(duration_s, 1),
        "segments_created": segments_created,
        "cpu_avg_pct": round(cpu_avg_pct, 1),
        "memory_peak_mb": round(memory_peak_mb, 1),
        **additional_stats,
    }
    log_with_metadata(logger, "info", "Day processing completed", **metadata)


# Convenience functions for common log levels

def log_info(logger: logging.Logger, message: str, **metadata: Any) -> None:
    """Log INFO level message with metadata."""
    log_with_metadata(logger, "info", message, **metadata)


def log_warning(logger: logging.Logger, message: str, **metadata: Any) -> None:
    """Log WARNING level message with metadata."""
    log_with_metadata(logger, "warning", message, **metadata)


def log_error(logger: logging.Logger, message: str, **metadata: Any) -> None:
    """Log ERROR level message with metadata."""
    log_with_metadata(logger, "error", message, **metadata)


def log_critical(logger: logging.Logger, message: str, **metadata: Any) -> None:
    """Log CRITICAL level message with metadata."""
    log_with_metadata(logger, "critical", message, **metadata)


def log_debug(logger: logging.Logger, message: str, **metadata: Any) -> None:
    """Log DEBUG level message with metadata."""
    log_with_metadata(logger, "debug", message, **metadata)
