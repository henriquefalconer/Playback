"""FFmpeg wrappers for video processing operations.

This module provides clean, reusable wrappers around FFmpeg and FFprobe
for video encoding and image processing operations used throughout Playback.
"""

import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import List, Optional, Tuple


class FFmpegError(Exception):
    """Raised when FFmpeg operations fail."""
    pass


class FFprobeError(Exception):
    """Raised when FFprobe operations fail."""
    pass


def _get_ffmpeg_path() -> str:
    """Get FFmpeg executable path from environment or common locations.

    Checks in order:
    1. FFMPEG_PATH environment variable (set by LaunchAgent)
    2. Common Homebrew and system locations
    3. System PATH search via shutil.which

    Returns:
        Absolute path to ffmpeg executable, or "ffmpeg" as fallback.
    """
    if "FFMPEG_PATH" in os.environ:
        ffmpeg_path = os.environ["FFMPEG_PATH"]
        if os.path.exists(ffmpeg_path):
            return ffmpeg_path

    for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]:
        if os.path.exists(path):
            return path

    found = shutil.which("ffmpeg")
    return found if found else "ffmpeg"


def _get_ffprobe_path() -> str:
    """Get FFprobe executable path from environment or common locations.

    Checks in order:
    1. FFPROBE_PATH environment variable
    2. Common Homebrew and system locations
    3. System PATH search via shutil.which

    Returns:
        Absolute path to ffprobe executable, or "ffprobe" as fallback.
    """
    if "FFPROBE_PATH" in os.environ:
        ffprobe_path = os.environ["FFPROBE_PATH"]
        if os.path.exists(ffprobe_path):
            return ffprobe_path

    for path in ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"]:
        if os.path.exists(path):
            return path

    found = shutil.which("ffprobe")
    return found if found else "ffprobe"


def check_ffmpeg_available() -> bool:
    """Check if FFmpeg is available in the system.

    Returns:
        True if FFmpeg is available, False otherwise.
    """
    ffmpeg_path = _get_ffmpeg_path()
    return os.path.exists(ffmpeg_path) if os.path.isabs(ffmpeg_path) else shutil.which(ffmpeg_path) is not None


def check_ffprobe_available() -> bool:
    """Check if FFprobe is available in the system.

    Returns:
        True if FFprobe is available, False otherwise.
    """
    ffprobe_path = _get_ffprobe_path()
    return os.path.exists(ffprobe_path) if os.path.isabs(ffprobe_path) else shutil.which(ffprobe_path) is not None


def get_image_size(path: Path) -> Tuple[Optional[int], Optional[int]]:
    """Get the dimensions of an image file using FFprobe.

    Args:
        path: Path to the image file (PNG, JPEG, etc.)

    Returns:
        Tuple of (width, height) in pixels, or (None, None) if detection fails.

    Raises:
        FFprobeError: If FFprobe is not available or the file cannot be read.
    """
    if not check_ffprobe_available():
        raise FFprobeError("FFprobe is not available in PATH")

    try:
        cmd = [
            _get_ffprobe_path(),
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=p=0:s=x",
            str(path),
        ]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )

        output = result.stdout.strip()
        if not output:
            return None, None

        parts = output.split("x")
        if len(parts) != 2:
            return None, None

        width = int(parts[0])
        height = int(parts[1])
        return width, height

    except subprocess.TimeoutExpired:
        raise FFprobeError(f"FFprobe timed out while reading {path}")
    except subprocess.CalledProcessError as e:
        # Return None instead of raising for invalid/corrupt files
        return None, None
    except (ValueError, IndexError):
        return None, None


def get_video_dimensions(path: Path) -> Tuple[Optional[int], Optional[int]]:
    """Get the dimensions of a video file using FFprobe.

    Args:
        path: Path to the video file.

    Returns:
        Tuple of (width, height) in pixels, or (None, None) if detection fails.

    Raises:
        FFprobeError: If FFprobe is not available or the file cannot be read.
    """
    if not check_ffprobe_available():
        raise FFprobeError("FFprobe is not available in PATH")

    try:
        cmd = [
            _get_ffprobe_path(),
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "default=noprint_wrappers=1:nokey=1",
            str(path),
        ]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )

        lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        if len(lines) < 2:
            return None, None

        width = int(lines[0])
        height = int(lines[1])
        return width, height

    except subprocess.TimeoutExpired:
        raise FFprobeError(f"FFprobe timed out while reading {path}")
    except subprocess.CalledProcessError as e:
        raise FFprobeError(f"FFprobe failed: {e.stderr}")
    except (ValueError, IndexError):
        return None, None


def create_video_from_images(
    image_paths: List[Path],
    output_path: Path,
    fps: float = 30.0,
    codec: str = "libx264",
    crf: int = 28,
    preset: str = "veryfast",
    pix_fmt: str = "yuv420p",
) -> Tuple[int, Optional[int], Optional[int]]:
    """Create a video file from a sequence of image files using FFmpeg.

    This function copies the images to a temporary directory with sequential
    naming (frame_00001.png, frame_00002.png, etc.) and then uses FFmpeg
    to encode them into a video file.

    Args:
        image_paths: List of paths to image files, in display order.
        output_path: Path where the output video should be saved.
            If the path has no extension, .mp4 will be added.
        fps: Frames per second for the output video. Default: 30.0.
        codec: Video codec to use. Default: "libx264" (H.264).
            Other options: "libx265" (HEVC/H.265), "libvpx-vp9" (VP9).
        crf: Constant Rate Factor for quality control (0-51).
            Lower values = higher quality/larger files.
            Default: 28 (good balance for screen recordings).
        preset: Encoding speed preset. Default: "veryfast".
            Options: ultrafast, superfast, veryfast, faster, fast,
                     medium, slow, slower, veryslow.
        pix_fmt: Pixel format. Default: "yuv420p" (best compatibility).

    Returns:
        Tuple of (file_size_bytes, width, height).
        width and height may be None if they cannot be determined.

    Raises:
        FFmpegError: If FFmpeg is not available or encoding fails.
        ValueError: If image_paths is empty or output_path is invalid.
    """
    if not image_paths:
        raise ValueError("image_paths cannot be empty")

    if not check_ffmpeg_available():
        raise FFmpegError("FFmpeg is not available in PATH")

    # Ensure output path has .mp4 extension for compatibility
    if not output_path.suffix:
        output_path = output_path.with_suffix(".mp4")

    # Create parent directory if needed
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmpdir_str:
        tmpdir = Path(tmpdir_str)

        # Copy images to temporary directory with sequential naming
        for idx, image_path in enumerate(image_paths, start=1):
            target = tmpdir / f"frame_{idx:05d}.png"
            shutil.copy2(image_path, target)

        # Build FFmpeg command
        cmd = [
            _get_ffmpeg_path(),
            "-y",  # Overwrite output file if it exists
            "-framerate", str(fps),
            "-i", str(tmpdir / "frame_%05d.png"),
            "-c:v", codec,
            "-preset", preset,
            "-crf", str(crf),
            "-pix_fmt", pix_fmt,
            str(output_path),
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True,
                timeout=300,  # 5 minute timeout for encoding
            )
        except subprocess.TimeoutExpired:
            raise FFmpegError("FFmpeg encoding timed out after 5 minutes")
        except subprocess.CalledProcessError as e:
            raise FFmpegError(f"FFmpeg encoding failed: {e.stderr}")

    # Get file size
    if not output_path.exists():
        raise FFmpegError(f"FFmpeg completed but output file not found: {output_path}")

    file_size_bytes = output_path.stat().st_size

    # Get video dimensions using FFprobe
    try:
        width, height = get_video_dimensions(output_path)
    except FFprobeError:
        width, height = None, None

    return file_size_bytes, width, height


def get_video_duration(path: Path) -> Optional[float]:
    """Get the duration of a video file in seconds using FFprobe.

    Args:
        path: Path to the video file.

    Returns:
        Duration in seconds, or None if it cannot be determined.

    Raises:
        FFprobeError: If FFprobe is not available or the file cannot be read.
    """
    if not check_ffprobe_available():
        raise FFprobeError("FFprobe is not available in PATH")

    try:
        cmd = [
            _get_ffprobe_path(),
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            str(path),
        ]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )

        output = result.stdout.strip()
        if not output:
            return None

        return float(output)

    except subprocess.TimeoutExpired:
        raise FFprobeError(f"FFprobe timed out while reading {path}")
    except subprocess.CalledProcessError as e:
        raise FFprobeError(f"FFprobe failed: {e.stderr}")
    except ValueError:
        return None


def get_video_frame_count(path: Path) -> Optional[int]:
    """Get the number of frames in a video file using FFprobe.

    Args:
        path: Path to the video file.

    Returns:
        Number of frames, or None if it cannot be determined.

    Raises:
        FFprobeError: If FFprobe is not available or the file cannot be read.
    """
    if not check_ffprobe_available():
        raise FFprobeError("FFprobe is not available in PATH")

    try:
        cmd = [
            _get_ffprobe_path(),
            "-v", "error",
            "-select_streams", "v:0",
            "-count_frames",
            "-show_entries", "stream=nb_read_frames",
            "-of", "default=noprint_wrappers=1:nokey=1",
            str(path),
        ]
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True,
            timeout=30,  # Frame counting can be slow
        )

        output = result.stdout.strip()
        if not output:
            return None

        return int(output)

    except subprocess.TimeoutExpired:
        raise FFprobeError(f"FFprobe timed out while counting frames in {path}")
    except subprocess.CalledProcessError as e:
        raise FFprobeError(f"FFprobe failed: {e.stderr}")
    except ValueError:
        return None
