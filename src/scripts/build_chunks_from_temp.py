#!/usr/bin/env python3
"""
Converte screenshots em `com.playback.Playback/temp/YYYYMM/DD` em vídeos
segmentados em `com.playback.Playback/chunks/YYYYMM/DD/<id>` (sem extensão),
inspirado no comportamento observado em `com.memoryvault.MemoryVault/chunks`.

Características principais deste script:
- Assume que os frames são PNGs salvos sem extensão pelo `record_screen.py`.
- Agrupa frames em segmentos de duração fixa (ex.: 5 segundos).
- Gera vídeos usando `ffmpeg` com codec HEVC (libx265), 30 fps, mantendo
  resolução original das imagens.
- Registra metadados básicos dos segmentos em um pequeno banco SQLite
  (`meta.sqlite3`) na raiz de `com.playback.Playback`.

Requisitos:
- ffmpeg instalado e disponível no PATH.
- Python 3.8+.
"""

import argparse
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Optional, Tuple

# Add parent directory to path for lib imports
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib.database import init_database, generate_segment_id
from lib.paths import get_temp_directory, get_chunks_directory, get_database_path
from lib.timestamps import parse_timestamp_from_name, parse_app_from_name
from lib.video import get_image_size, create_video_from_images
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
import os
import time

# Import psutil for resource metrics (optional)
try:
    import psutil
    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False

# Import OCR processor for text extraction (Phase 4.1)
try:
    from ocr_processor import perform_ocr_batch, test_ocr_availability
    OCR_AVAILABLE = test_ocr_availability()
except ImportError:
    OCR_AVAILABLE = False


@dataclass
class FrameInfo:
    """
    Representa informações sobre um frame de screenshot individual.

    Attributes:
        path: Full path to the frame image file
        ts: Timestamp in epoch seconds when the frame was captured
        app_id: Bundle ID of the active application when the frame was captured (None if unknown)
        width: Image width in pixels (None if not determined)
        height: Image height in pixels (None if not determined)
    """
    path: Path
    ts: float  # epoch seconds
    app_id: Optional[str]
    width: Optional[int] = None
    height: Optional[int] = None


def load_frames_for_day(day: str, logger) -> List[FrameInfo]:
    """
    Loads all frames from temp/YYYYMM/DD for the day provided
    as a YYYYMMDD string.
    """
    year_month = day[:6]
    day_only = day[6:]
    day_dir = get_temp_directory() / year_month / day_only

    if not day_dir.is_dir():
        raise FileNotFoundError(f"Frames directory not found: {day_dir}")

    frames: List[FrameInfo] = []
    invalid_files = 0

    for entry in sorted(day_dir.iterdir()):
        if not entry.is_file():
            continue
        # Ignore hidden/metadata files (e.g., .DS_Store)
        if entry.name.startswith("."):
            continue

        # For the timeline, we always trust the file's "Date Created"
        # (st_birthtime on macOS). If it doesn't exist, we use mtime as fallback.
        st = entry.stat()
        ts = getattr(st, "st_birthtime", None) or st.st_mtime
        app_id = parse_app_from_name(entry.name)
        width, height = get_image_size(entry)

        # If we can't determine width/height via ffprobe, this file
        # is probably not a valid PNG; better to ignore than break ffmpeg.
        if width is None or height is None:
            log_warning(
                logger,
                "Invalid frame file skipped",
                file_path=str(entry),
                reason="Could not determine dimensions"
            )
            invalid_files += 1
            continue

        frames.append(
            FrameInfo(
                path=entry,
                ts=ts,
                app_id=app_id,
                width=width,
                height=height,
            )
        )

    frames.sort(key=lambda f: f.ts)

    log_info(
        logger,
        "Frames loaded for day",
        day=day,
        total_frames=len(frames),
        invalid_files=invalid_files,
        day_dir=str(day_dir)
    )

    return frames


def group_frames_by_count(
    frames: List[FrameInfo],
    max_frames_per_segment: int,
) -> List[List[FrameInfo]]:
    """
    Groups frames into segments containing at most `max_frames_per_segment`
    consecutive frames **and** ensuring each segment has only one
    frame format (same width/height).

    This "compresses" an arbitrarily long sequence of screenshots into
    short N-frame videos (e.g., 150 frames = 5s at 30fps), without repeating
    frames.
    """
    if max_frames_per_segment <= 0:
        return [frames] if frames else []

    segments: List[List[FrameInfo]] = []
    current_segment: List[FrameInfo] = []
    current_size: Optional[Tuple[Optional[int], Optional[int]]] = None

    for frame in frames:
        frame_size = (frame.width, frame.height)

        if not current_segment:
            current_segment = [frame]
            current_size = frame_size
            continue

        reached_max = len(current_segment) >= max_frames_per_segment
        # If resolution (width/height) changes, always start a new segment,
        # even if one of the dimensions is None. This ensures we don't mix
        # different monitors in the same video.
        size_changed = current_size is not None and frame_size != current_size

        if reached_max or size_changed:
            segments.append(current_segment)
            current_segment = [frame]
            current_size = frame_size
        else:
            current_segment.append(frame)

    if current_segment:
        segments.append(current_segment)

    return segments


def build_appsegments_for_day(frames: List[FrameInfo]) -> List[Tuple[Optional[str], float, float]]:
    """
    From all frames of a day (already sorted by timestamp),
    groups continuous intervals by app_id.

    - Each app_id change starts a new appsegment.
    - app_id can be None; in these cases we still create an appsegment to
      represent periods "without known app", which can be displayed
      with a generic color on the timeline.
    """
    if not frames:
        return []

    segments: List[Tuple[Optional[str], float, float]] = []

    current_app: Optional[str] = frames[0].app_id
    current_start: float = frames[0].ts
    last_ts: float = frames[0].ts

    for frame in frames[1:]:
        if frame.app_id == current_app:
            # Continue same app; just advance the end of the interval.
            last_ts = frame.ts
            continue

        # App switched: close current interval at last_ts
        segments.append((current_app, current_start, last_ts))

        # Start a new interval for the new app.
        current_app = frame.app_id
        current_start = frame.ts
        last_ts = frame.ts

    # Close the last interval using the last frame's timestamp.
    segments.append((current_app, current_start, last_ts))

    return segments


def process_ocr_for_frames(
    frames: List[FrameInfo],
    segment_id: str,
    db,
    logger,
    num_workers: int = 4
) -> int:
    """
    Extrai texto via OCR dos frames e insere no banco de dados.

    Args:
        frames: Lista de frames a processar
        segment_id: ID do segmento de vídeo associado
        db: DatabaseManager instance
        logger: Logger instance
        num_workers: Número de workers paralelos para OCR

    Returns:
        int: Número de registros OCR inseridos com sucesso
    """
    if not OCR_AVAILABLE:
        return 0

    if not frames:
        return 0

    ocr_start_time = time.time()
    log_info(
        logger,
        "Starting OCR batch processing",
        segment_id=segment_id,
        frame_count=len(frames),
        num_workers=num_workers
    )

    # Batch OCR processing with parallel workers
    frame_paths = [str(f.path) for f in frames]

    try:
        from ocr_processor import perform_ocr_batch
        ocr_results = perform_ocr_batch(frame_paths, num_workers=num_workers, timeout=5.0)
    except Exception as e:
        log_error_with_context(
            logger,
            "OCR batch processing failed",
            exception=e,
            segment_id=segment_id,
            frame_count=len(frames),
            num_workers=num_workers
        )
        return 0

    # Prepare batch insert records
    ocr_records = []
    success_count = 0
    empty_count = 0
    failed_count = 0

    for frame, result in zip(frames, ocr_results):
        if not result.success:
            failed_count += 1
            continue

        # Skip empty results (no text found)
        if not result.text.strip():
            empty_count += 1
            continue

        # Build tuple for batch insert: (frame_path, timestamp, text_content, confidence, segment_id, language)
        ocr_records.append((
            str(frame.path),
            frame.ts,
            result.text,
            result.confidence,
            segment_id,
            result.language
        ))
        success_count += 1

    # Batch insert into database
    if ocr_records:
        try:
            inserted = db.insert_ocr_batch(ocr_records)
            ocr_duration = time.time() - ocr_start_time

            log_info(
                logger,
                "OCR batch processing completed",
                segment_id=segment_id,
                total_frames=len(frames),
                frames_with_text=success_count,
                frames_empty=empty_count,
                frames_failed=failed_count,
                records_inserted=inserted,
                duration_s=round(ocr_duration, 2)
            )
            return inserted
        except Exception as e:
            log_error_with_context(
                logger,
                "OCR database insertion failed",
                exception=e,
                segment_id=segment_id,
                ocr_records_count=len(ocr_records)
            )
            return 0
    else:
        log_info(
            logger,
            "OCR processing found no text",
            segment_id=segment_id,
            total_frames=len(frames),
            frames_empty=empty_count,
            frames_failed=failed_count
        )
        return 0


def cleanup_temp_files(frames: List[FrameInfo], day: str, logger) -> None:
    """
    Remove os arquivos temporários (screenshots) após processamento bem-sucedido.

    Args:
        frames: Lista de frames que foram processados com sucesso
        day: String YYYYMMDD representando o dia processado
        logger: Logger instance
    """
    log_info(
        logger,
        "Starting temp file cleanup",
        day=day,
        file_count=len(frames)
    )

    deleted_count = 0
    error_count = 0
    total_size = 0

    for frame in frames:
        try:
            if frame.path.exists():
                file_size = frame.path.stat().st_size
                frame.path.unlink()
                deleted_count += 1
                total_size += file_size
        except Exception as e:
            log_warning(
                logger,
                "Failed to delete temp file",
                file_path=str(frame.path),
                error=str(e)
            )
            error_count += 1

    log_info(
        logger,
        "Temp file cleanup completed",
        day=day,
        files_deleted=deleted_count,
        files_failed=error_count,
        bytes_freed=total_size,
        mb_freed=round(total_size / (1024 * 1024), 2)
    )

    # Tenta remover o diretório do dia se estiver vazio
    try:
        year_month = day[:6]
        day_only = day[6:]
        day_dir = get_temp_directory() / year_month / day_only

        # Verifica se o diretório está vazio (ignora .DS_Store e outros arquivos ocultos)
        remaining_files = [f for f in day_dir.iterdir() if not f.name.startswith('.')]

        if not remaining_files:
            day_dir.rmdir()
            log_info(logger, "Empty day directory removed", day_dir=str(day_dir))

            # Tenta remover o diretório do mês se também estiver vazio
            month_dir = day_dir.parent
            if not any(month_dir.iterdir()):
                month_dir.rmdir()
                log_info(logger, "Empty month directory removed", month_dir=str(month_dir))
    except Exception as e:
        log_warning(
            logger,
            "Failed to remove empty directories",
            day=day,
            error=str(e)
        )


def collect_metrics(start_time: float = None) -> dict:
    """
    Collect current resource metrics using psutil.

    Args:
        start_time: Optional service start time (from time.time()) for uptime calculation

    Returns:
        Dictionary of metrics including cpu_percent, memory_mb, disk_free_gb, and optionally uptime_hours
    """
    metrics = {}
    if PSUTIL_AVAILABLE:
        try:
            process = psutil.Process()
            metrics["cpu_percent"] = process.cpu_percent(interval=0.1)
            metrics["memory_mb"] = round(process.memory_info().rss / (1024 * 1024), 2)
            metrics["disk_free_gb"] = round(psutil.disk_usage('/').free / (1024 * 1024 * 1024), 2)

            # Add uptime if start_time is provided
            if start_time is not None:
                metrics["uptime_hours"] = (time.time() - start_time) / 3600
        except Exception:
            pass
    return metrics


def process_day(
    day: str,
    fps: float,
    segment_duration: float,
    crf: int,
    preset: str,
    logger,
    cleanup: bool = True,
) -> None:
    """
    Generates videos from frames of a day (YYYYMMDD).

    Args:
        day: Day in YYYYMMDD format
        fps: Frames per second of output video
        segment_duration: Duration of each segment in seconds
        crf: Constant Rate Factor for compression
        preset: FFmpeg preset (veryfast, medium, slow, etc.)
        logger: Logger instance
        cleanup: If True, removes temporary files after processing
    """
    day_start_time = time.time()
    start_metrics = collect_metrics()

    log_info(
        logger,
        "Starting day processing",
        day=day,
        fps=fps,
        segment_duration=segment_duration,
        crf=crf,
        preset=preset,
        cleanup_enabled=cleanup,
        **start_metrics
    )

    frames = load_frames_for_day(day, logger)
    if not frames:
        log_info(logger, "No frames found for day", day=day)
        return

    # App ranges (appsegments) for the entire day, independent of how
    # frames will be grouped into videos (segments).
    appsegments = build_appsegments_for_day(frames)

    # Target number of frames per segment: fps * desired duration in seconds.
    max_frames_per_segment = int(fps * segment_duration)
    segments = group_frames_by_count(frames, max_frames_per_segment)

    log_info(
        logger,
        "Day segmentation calculated",
        day=day,
        total_frames=len(frames),
        segments_count=len(segments),
        appsegments_count=len(appsegments),
        frames_per_segment=max_frames_per_segment
    )

    year_month = day[:6]
    day_only = day[6:]
    day_chunks_dir = get_chunks_directory() / year_month / day_only
    day_chunks_dir.mkdir(parents=True, exist_ok=True)

    db = init_database(get_database_path())

    date_str = f"{day[:4]}-{day[4:6]}-{day[6:]}"

    total_video_size = 0
    total_ocr_records = 0

    for idx, seg_frames in enumerate(segments, start=1):
        segment_start_time = time.time()
        segment_id = generate_segment_id()
        dest_without_ext = day_chunks_dir / segment_id

        log_info(
            logger,
            "Processing segment",
            day=day,
            segment_index=idx,
            total_segments=len(segments),
            segment_id=segment_id,
            frame_count=len(seg_frames)
        )

        # Use shared library function for video creation
        frame_paths = [frame.path for frame in seg_frames]
        size, width, height = create_video_from_images(
            image_paths=frame_paths,
            output_path=dest_without_ext,
            fps=fps,
            codec="libx264",
            crf=crf,
            preset=preset,
            pix_fmt="yuv420p",
        )

        total_video_size += size

        # Set secure permissions on generated video file (0o600 = user read/write only)
        video_file = dest_without_ext.with_suffix(".mp4")
        os.chmod(video_file, 0o600)

        # Path relative to base data directory
        base_data_dir = get_database_path().parent
        rel_path = str(video_file.relative_to(base_data_dir))

        # Use DatabaseManager methods instead of direct SQL
        start_ts = seg_frames[0].ts
        end_ts = seg_frames[-1].ts
        db.insert_segment(
            segment_id=segment_id,
            date_str=date_str,
            start_ts=start_ts,
            end_ts=end_ts,
            frame_count=len(seg_frames),
            fps=fps,
            file_size_bytes=size,
            video_path=rel_path,
            width=width,
            height=height,
        )

        segment_duration_actual = time.time() - segment_start_time

        log_info(
            logger,
            "Segment created",
            day=day,
            segment_index=idx,
            segment_id=segment_id,
            video_path=rel_path,
            file_size_bytes=size,
            file_size_mb=round(size / (1024 * 1024), 2),
            width=width,
            height=height,
            duration_s=round(segment_duration_actual, 2)
        )

        # Phase 4.1: Extract text via OCR from frames (if available)
        if OCR_AVAILABLE:
            ocr_records = process_ocr_for_frames(seg_frames, segment_id, db, logger, num_workers=4)
            total_ocr_records += ocr_records

        # Collect metrics every 10 segments to avoid overhead
        if idx % 10 == 0 and PSUTIL_AVAILABLE:
            metrics = collect_metrics(day_start_time)
            if metrics:
                log_resource_metrics(
                    logger,
                    **metrics,
                    segments_processed=idx,
                    total_segments=len(segments)
                )

    # Persist all calculated appsegments for the day.
    log_info(
        logger,
        "Inserting app segments",
        day=day,
        appsegments_count=len(appsegments)
    )

    for app_id, start_ts, end_ts in appsegments:
        appsegment_id = generate_segment_id()
        db.insert_appsegment(
            appsegment_id=appsegment_id,
            date_str=date_str,
            start_ts=start_ts,
            end_ts=end_ts,
            app_id=app_id,
        )

    # Remove temporary files after successful processing
    if cleanup:
        cleanup_temp_files(frames, day, logger)

    # Final metrics
    day_duration = time.time() - day_start_time
    end_metrics = collect_metrics()

    log_info(
        logger,
        "Day processing completed",
        day=day,
        total_frames=len(frames),
        segments_created=len(segments),
        appsegments_created=len(appsegments),
        ocr_records_created=total_ocr_records,
        total_video_size_bytes=total_video_size,
        total_video_size_mb=round(total_video_size / (1024 * 1024), 2),
        duration_s=round(day_duration, 2),
        **end_metrics
    )


def parse_args() -> argparse.Namespace:
    """
    Parses command line arguments for the processing script.

    Returns:
        argparse.Namespace containing parsed arguments:
            - day: Specific day to process (YYYYMMDD)
            - auto: Flag for automatic mode (last 7 pending days)
            - no_cleanup: Flag to keep temporary files
            - fps: Frame rate per second for output video
            - segment_duration: Target duration of each segment in seconds
            - crf: Constant Rate Factor for compression
            - preset: FFmpeg preset for speed/quality
    """
    parser = argparse.ArgumentParser(
        description="Converte screenshots em temp/YYYYMM/DD em vídeos em chunks/YYYYMM/DD"
    )
    parser.add_argument(
        "--day",
        type=str,
        help="Dia no formato YYYYMMDD (ex.: 20251222)",
    )
    parser.add_argument(
        "--auto",
        action="store_true",
        help="Automatically processes all pending days (last 7 days)",
    )
    parser.add_argument(
        "--no-cleanup",
        action="store_true",
        help="Does not remove temporary files after processing",
    )
    parser.add_argument(
        "--fps",
        type=float,
        default=None,
        help="Output video FPS (default: loads from config)",
    )
    parser.add_argument(
        "--segment-duration",
        type=float,
        default=5.0,
        help="Target duration of each segment in seconds (default: 5.0)",
    )
    parser.add_argument(
        "--crf",
        type=int,
        default=None,
        help="libx265 CRF (default: loads from config)",
    )
    parser.add_argument(
        "--preset",
        type=str,
        default="veryfast",
        help="Preset do libx265 (default: veryfast)",
    )
    return parser.parse_args()


def find_pending_days(logger) -> List[str]:
    """
    Finds days with screenshots in the temp folder that have not been processed yet.
    Returns list of strings in YYYYMMDD format for the last 7 days.
    """
    temp_dir = get_temp_directory()
    pending_days = []

    # Check last 7 days
    today = datetime.now()
    for i in range(7):
        check_date = today - timedelta(days=i)
        day_str = check_date.strftime("%Y%m%d")
        year_month = day_str[:6]
        day_only = day_str[6:]

        day_dir = temp_dir / year_month / day_only
        if day_dir.exists():
            # Check if there are any files in this directory
            files = [f for f in day_dir.glob("*") if not f.name.startswith('.')]
            if files:
                pending_days.append(day_str)
                log_debug(
                    logger,
                    "Pending day found",
                    day=day_str,
                    file_count=len(files),
                    day_dir=str(day_dir)
                )

    log_info(
        logger,
        "Pending days scan completed",
        days_checked=7,
        pending_days_found=len(pending_days),
        pending_days=pending_days
    )

    return pending_days


def main() -> None:
    """
    Main entry point of the chunk processing script.

    Loads configurations, initializes structured logging, and processes days in
    automatic mode (last 7 pending days) or manual mode (specific day). Converts
    screenshots in temp/ to video segments in chunks/, runs OCR when
    available, and records metadata in the database.
    """
    args = parse_args()

    # Setup structured logging
    logger = setup_logger("processing", log_level="INFO", console_output=False)

    # Load config for defaults
    config = load_config_with_defaults()

    # Use config values if not specified
    fps = args.fps if args.fps is not None else config.video_fps
    crf = args.crf if args.crf is not None else config.ffmpeg_crf

    # Log service initialization
    log_info(
        logger,
        "Processing service started",
        mode="auto" if args.auto else "manual",
        fps=fps,
        crf=crf,
        preset=args.preset,
        segment_duration=args.segment_duration,
        cleanup_enabled=not args.no_cleanup,
        ocr_available=OCR_AVAILABLE,
        psutil_available=PSUTIL_AVAILABLE,
        temp_directory=str(get_temp_directory()),
        chunks_directory=str(get_chunks_directory()),
        database_path=str(get_database_path())
    )

    if args.auto:
        # Auto mode: process all pending days
        pending_days = find_pending_days(logger)
        if not pending_days:
            log_info(logger, "No pending days to process")
            return

        log_info(
            logger,
            "Auto mode starting",
            pending_days_count=len(pending_days),
            pending_days=pending_days
        )

        successful_days = 0
        failed_days = 0

        for day in pending_days:
            log_info(logger, "Processing day", day=day, mode="auto")
            try:
                process_day(
                    day=day,
                    fps=fps,
                    segment_duration=args.segment_duration,
                    crf=crf,
                    preset=args.preset,
                    logger=logger,
                    cleanup=not args.no_cleanup,
                )
                successful_days += 1
            except Exception as e:
                failed_days += 1
                log_error_with_context(
                    logger,
                    "Failed to process day",
                    exception=e,
                    day=day,
                    mode="auto"
                )
                # Continue with next day even if one fails

        log_info(
            logger,
            "Auto mode completed",
            total_days=len(pending_days),
            successful_days=successful_days,
            failed_days=failed_days
        )

    elif args.day:
        # Manual mode: process specific day
        log_info(logger, "Manual mode processing single day", day=args.day)
        try:
            process_day(
                day=args.day,
                fps=fps,
                segment_duration=args.segment_duration,
                crf=crf,
                preset=args.preset,
                logger=logger,
                cleanup=not args.no_cleanup,
            )
            log_info(logger, "Manual mode completed successfully", day=args.day)
        except Exception as e:
            log_error_with_context(
                logger,
                "Failed to process day in manual mode",
                exception=e,
                day=args.day
            )
            sys.exit(1)
    else:
        log_critical(logger, "Missing required argument: specify --day or --auto")
        sys.exit(1)


if __name__ == "__main__":
    main()
