"""
Unit tests for the video module.

Tests FFmpeg wrappers for video processing, image size detection, and error handling.
"""

import pytest
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock

# Import the module under test
import lib.video as video


class TestFFmpegAvailability:
    """Test FFmpeg and FFprobe availability checks."""

    def test_ffmpeg_available(self):
        """Test that FFmpeg is detected when available in PATH."""
        with patch('lib.video._get_ffmpeg_path', return_value='/usr/local/bin/ffmpeg'):
            with patch('os.path.exists', return_value=True):
                assert video.check_ffmpeg_available() is True

    def test_ffmpeg_not_available(self):
        """Test that FFmpeg is detected as unavailable when not in PATH."""
        with patch('lib.video._get_ffmpeg_path', return_value='ffmpeg'):
            with patch('shutil.which', return_value=None):
                assert video.check_ffmpeg_available() is False

    def test_ffprobe_available(self):
        """Test that FFprobe is detected when available in PATH."""
        with patch('lib.video._get_ffprobe_path', return_value='/usr/local/bin/ffprobe'):
            with patch('os.path.exists', return_value=True):
                assert video.check_ffprobe_available() is True

    def test_ffprobe_not_available(self):
        """Test that FFprobe is detected as unavailable when not in PATH."""
        with patch('lib.video._get_ffprobe_path', return_value='ffprobe'):
            with patch('shutil.which', return_value=None):
                assert video.check_ffprobe_available() is False


class TestImageSizeDetection:
    """Test get_image_size function."""

    def test_valid_png_image(self):
        """Test getting dimensions of valid PNG image."""
        with patch('lib.video.check_ffprobe_available', return_value=True), \
             patch('subprocess.run') as mock_run:

            mock_run.return_value = MagicMock(
                stdout="1920x1080\n",
                returncode=0
            )

            width, height = video.get_image_size(Path("/test/image.png"))

            assert width == 1920
            assert height == 1080
            mock_run.assert_called_once()
            assert 'ffprobe' in mock_run.call_args[0][0]
            assert '-select_streams' in mock_run.call_args[0][0]
            assert 'v:0' in mock_run.call_args[0][0]

    def test_valid_jpeg_image(self):
        """Test getting dimensions of valid JPEG image."""
        with patch('lib.video.check_ffprobe_available', return_value=True), \
             patch('subprocess.run') as mock_run:

            mock_run.return_value = MagicMock(
                stdout="2560x1440\n",
                returncode=0
            )

            width, height = video.get_image_size(Path("/test/image.jpg"))

            assert width == 2560
            assert height == 1440

    def test_invalid_image_returns_none(self):
        """Test that invalid image returns (None, None)."""
        with patch('lib.video.check_ffprobe_available', return_value=True), \
             patch('subprocess.run') as mock_run:

            mock_run.side_effect = subprocess.CalledProcessError(1, 'ffprobe', stderr='Invalid file')

            width, height = video.get_image_size(Path("/test/invalid.png"))

            assert width is None
            assert height is None

    def test_ffprobe_not_available_raises_error(self):
        """Test that FFprobeError is raised when ffprobe is not available."""
        with patch('lib.video.check_ffprobe_available', return_value=False):
            with pytest.raises(video.FFprobeError, match="FFprobe is not available in PATH"):
                video.get_image_size(Path("/test/image.png"))

    def test_subprocess_timeout(self):
        """Test that timeout raises FFprobeError."""
        with patch('lib.video.check_ffprobe_available', return_value=True), \
             patch('subprocess.run') as mock_run:

            mock_run.side_effect = subprocess.TimeoutExpired('ffprobe', 10)

            with pytest.raises(video.FFprobeError, match="timed out"):
                video.get_image_size(Path("/test/image.png"))

    def test_malformed_output(self):
        """Test that malformed output returns (None, None)."""
        with patch('lib.video.check_ffprobe_available', return_value=True), \
             patch('subprocess.run') as mock_run:

            mock_run.return_value = MagicMock(
                stdout="invalid_format\n",
                returncode=0
            )

            width, height = video.get_image_size(Path("/test/image.png"))

            assert width is None
            assert height is None

    def test_empty_output(self):
        """Test that empty output returns (None, None)."""
        with patch('lib.video.check_ffprobe_available', return_value=True), \
             patch('subprocess.run') as mock_run:

            mock_run.return_value = MagicMock(
                stdout="",
                returncode=0
            )

            width, height = video.get_image_size(Path("/test/image.png"))

            assert width is None
            assert height is None


class TestVideoDimensionDetection:
    """Test get_video_dimensions function."""

    def test_valid_video_dimensions(self):
        """Test getting dimensions of valid video file."""
        with patch('lib.video.check_ffprobe_available', return_value=True), \
             patch('subprocess.run') as mock_run:

            mock_run.return_value = MagicMock(
                stdout="1920\n1080\n",
                returncode=0
            )

            width, height = video.get_video_dimensions(Path("/test/video.mp4"))

            assert width == 1920
            assert height == 1080

    def test_video_dimensions_error_handling(self):
        """Test error handling for video dimension detection."""
        with patch('lib.video.check_ffprobe_available', return_value=True), \
             patch('subprocess.run') as mock_run:

            mock_run.side_effect = subprocess.CalledProcessError(1, 'ffprobe', stderr='Error')

            with pytest.raises(video.FFprobeError, match="FFprobe failed"):
                video.get_video_dimensions(Path("/test/video.mp4"))


class TestVideoCreation:
    """Test create_video_from_images function."""

    def test_empty_image_list_raises_error(self):
        """Test that empty image list raises ValueError."""
        with pytest.raises(ValueError, match="image_paths cannot be empty"):
            video.create_video_from_images([], Path("/test/output.mp4"))

    def test_ffmpeg_not_available_raises_error(self):
        """Test that FFmpegError is raised when ffmpeg is not available."""
        with patch('lib.video.check_ffmpeg_available', return_value=False):
            with pytest.raises(video.FFmpegError, match="FFmpeg is not available in PATH"):
                video.create_video_from_images([Path("/test/img.png")], Path("/test/output.mp4"))

    def test_basic_video_creation(self):
        """Test basic video creation from images."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create test images
            img1 = Path(tmpdir) / "img1.png"
            img2 = Path(tmpdir) / "img2.png"
            img1.write_bytes(b"fake_png_data")
            img2.write_bytes(b"fake_png_data")

            output_path = Path(tmpdir) / "output.mp4"

            with patch('lib.video.check_ffmpeg_available', return_value=True), \
                 patch('subprocess.run') as mock_run, \
                 patch('lib.video.get_video_dimensions', return_value=(1920, 1080)):

                mock_run.return_value = MagicMock(returncode=0)

                # Create fake output file
                output_path.write_bytes(b"fake_video_data_" * 1000)

                file_size, width, height = video.create_video_from_images(
                    [img1, img2],
                    output_path,
                    fps=30.0,
                    codec='libx264',
                    crf=28,
                    preset='veryfast'
                )

                assert file_size > 0
                assert width == 1920
                assert height == 1080
                mock_run.assert_called_once()

    def test_ffmpeg_command_construction(self):
        """Test that FFmpeg command is constructed correctly."""
        with tempfile.TemporaryDirectory() as tmpdir:
            img = Path(tmpdir) / "img.png"
            img.write_bytes(b"fake_png")

            output_path = Path(tmpdir) / "output.mp4"

            with patch('lib.video.check_ffmpeg_available', return_value=True), \
                 patch('subprocess.run') as mock_run, \
                 patch('lib.video.get_video_dimensions', return_value=(1920, 1080)):

                mock_run.return_value = MagicMock(returncode=0)
                output_path.write_bytes(b"fake_video")

                video.create_video_from_images(
                    [img],
                    output_path,
                    fps=60.0,
                    codec='libx265',
                    crf=23,
                    preset='medium',
                    pix_fmt='yuv444p'
                )

                call_args = mock_run.call_args[0][0]
                assert 'ffmpeg' in call_args
                assert '-framerate' in call_args
                assert '60.0' in call_args
                assert '-c:v' in call_args
                assert 'libx265' in call_args
                assert '-crf' in call_args
                assert '23' in call_args
                assert '-preset' in call_args
                assert 'medium' in call_args
                assert '-pix_fmt' in call_args
                assert 'yuv444p' in call_args

    def test_frame_rate_parameter(self):
        """Test that fps parameter is correctly passed to FFmpeg."""
        with tempfile.TemporaryDirectory() as tmpdir:
            img = Path(tmpdir) / "img.png"
            img.write_bytes(b"fake_png")
            output_path = Path(tmpdir) / "output.mp4"

            with patch('lib.video.check_ffmpeg_available', return_value=True), \
                 patch('subprocess.run') as mock_run, \
                 patch('lib.video.get_video_dimensions', return_value=(1920, 1080)):

                mock_run.return_value = MagicMock(returncode=0)
                output_path.write_bytes(b"fake_video")

                video.create_video_from_images([img], output_path, fps=15.0)

                call_args = mock_run.call_args[0][0]
                framerate_idx = call_args.index('-framerate')
                assert call_args[framerate_idx + 1] == '15.0'

    def test_codec_selection(self):
        """Test that codec parameter is correctly passed to FFmpeg."""
        with tempfile.TemporaryDirectory() as tmpdir:
            img = Path(tmpdir) / "img.png"
            img.write_bytes(b"fake_png")
            output_path = Path(tmpdir) / "output.mp4"

            with patch('lib.video.check_ffmpeg_available', return_value=True), \
                 patch('subprocess.run') as mock_run, \
                 patch('lib.video.get_video_dimensions', return_value=(1920, 1080)):

                mock_run.return_value = MagicMock(returncode=0)
                output_path.write_bytes(b"fake_video")

                video.create_video_from_images([img], output_path, codec='libvpx-vp9')

                call_args = mock_run.call_args[0][0]
                codec_idx = call_args.index('-c:v')
                assert call_args[codec_idx + 1] == 'libvpx-vp9'

    def test_crf_quality_setting(self):
        """Test that CRF quality parameter is correctly passed to FFmpeg."""
        with tempfile.TemporaryDirectory() as tmpdir:
            img = Path(tmpdir) / "img.png"
            img.write_bytes(b"fake_png")
            output_path = Path(tmpdir) / "output.mp4"

            with patch('lib.video.check_ffmpeg_available', return_value=True), \
                 patch('subprocess.run') as mock_run, \
                 patch('lib.video.get_video_dimensions', return_value=(1920, 1080)):

                mock_run.return_value = MagicMock(returncode=0)
                output_path.write_bytes(b"fake_video")

                video.create_video_from_images([img], output_path, crf=18)

                call_args = mock_run.call_args[0][0]
                crf_idx = call_args.index('-crf')
                assert call_args[crf_idx + 1] == '18'

    def test_preset_parameter(self):
        """Test that preset parameter is correctly passed to FFmpeg."""
        with tempfile.TemporaryDirectory() as tmpdir:
            img = Path(tmpdir) / "img.png"
            img.write_bytes(b"fake_png")
            output_path = Path(tmpdir) / "output.mp4"

            with patch('lib.video.check_ffmpeg_available', return_value=True), \
                 patch('subprocess.run') as mock_run, \
                 patch('lib.video.get_video_dimensions', return_value=(1920, 1080)):

                mock_run.return_value = MagicMock(returncode=0)
                output_path.write_bytes(b"fake_video")

                video.create_video_from_images([img], output_path, preset='slow')

                call_args = mock_run.call_args[0][0]
                preset_idx = call_args.index('-preset')
                assert call_args[preset_idx + 1] == 'slow'

    def test_pixel_format_parameter(self):
        """Test that pixel format parameter is correctly passed to FFmpeg."""
        with tempfile.TemporaryDirectory() as tmpdir:
            img = Path(tmpdir) / "img.png"
            img.write_bytes(b"fake_png")
            output_path = Path(tmpdir) / "output.mp4"

            with patch('lib.video.check_ffmpeg_available', return_value=True), \
                 patch('subprocess.run') as mock_run, \
                 patch('lib.video.get_video_dimensions', return_value=(1920, 1080)):

                mock_run.return_value = MagicMock(returncode=0)
                output_path.write_bytes(b"fake_video")

                video.create_video_from_images([img], output_path, pix_fmt='yuv422p')

                call_args = mock_run.call_args[0][0]
                pix_fmt_idx = call_args.index('-pix_fmt')
                assert call_args[pix_fmt_idx + 1] == 'yuv422p'

    def test_output_path_mp4_extension_added(self):
        """Test that .mp4 extension is added when output path has no extension."""
        with tempfile.TemporaryDirectory() as tmpdir:
            img = Path(tmpdir) / "img.png"
            img.write_bytes(b"fake_png")
            output_path = Path(tmpdir) / "output"

            with patch('lib.video.check_ffmpeg_available', return_value=True), \
                 patch('subprocess.run') as mock_run, \
                 patch('lib.video.get_video_dimensions', return_value=(1920, 1080)):

                mock_run.return_value = MagicMock(returncode=0)
                expected_path = Path(tmpdir) / "output.mp4"
                expected_path.write_bytes(b"fake_video")

                file_size, _, _ = video.create_video_from_images([img], output_path)

                assert expected_path.exists()
                assert file_size > 0

    def test_file_size_calculation(self):
        """Test that file size is correctly calculated after encoding."""
        with tempfile.TemporaryDirectory() as tmpdir:
            img = Path(tmpdir) / "img.png"
            img.write_bytes(b"fake_png")
            output_path = Path(tmpdir) / "output.mp4"

            with patch('lib.video.check_ffmpeg_available', return_value=True), \
                 patch('subprocess.run') as mock_run, \
                 patch('lib.video.get_video_dimensions', return_value=(1920, 1080)):

                mock_run.return_value = MagicMock(returncode=0)
                fake_video_data = b"x" * 12345
                output_path.write_bytes(fake_video_data)

                file_size, _, _ = video.create_video_from_images([img], output_path)

                assert file_size == 12345

    def test_ffmpeg_subprocess_failure(self):
        """Test that FFmpegError is raised when FFmpeg subprocess fails."""
        with tempfile.TemporaryDirectory() as tmpdir:
            img = Path(tmpdir) / "img.png"
            img.write_bytes(b"fake_png")
            output_path = Path(tmpdir) / "output.mp4"

            with patch('lib.video.check_ffmpeg_available', return_value=True), \
                 patch('subprocess.run') as mock_run:

                mock_run.side_effect = subprocess.CalledProcessError(
                    1, 'ffmpeg', stderr='Encoding failed'
                )

                with pytest.raises(video.FFmpegError, match="FFmpeg encoding failed"):
                    video.create_video_from_images([img], output_path)

    def test_ffmpeg_timeout(self):
        """Test that FFmpegError is raised when FFmpeg times out."""
        with tempfile.TemporaryDirectory() as tmpdir:
            img = Path(tmpdir) / "img.png"
            img.write_bytes(b"fake_png")
            output_path = Path(tmpdir) / "output.mp4"

            with patch('lib.video.check_ffmpeg_available', return_value=True), \
                 patch('subprocess.run') as mock_run:

                mock_run.side_effect = subprocess.TimeoutExpired('ffmpeg', 300)

                with pytest.raises(video.FFmpegError, match="timed out"):
                    video.create_video_from_images([img], output_path)

    def test_output_file_not_created(self):
        """Test that FFmpegError is raised when output file is not created."""
        with tempfile.TemporaryDirectory() as tmpdir:
            img = Path(tmpdir) / "img.png"
            img.write_bytes(b"fake_png")
            output_path = Path(tmpdir) / "output.mp4"

            with patch('lib.video.check_ffmpeg_available', return_value=True), \
                 patch('subprocess.run') as mock_run:

                mock_run.return_value = MagicMock(returncode=0)

                with pytest.raises(video.FFmpegError, match="output file not found"):
                    video.create_video_from_images([img], output_path)

    def test_dimensions_fallback_on_error(self):
        """Test that dimensions are None when get_video_dimensions fails."""
        with tempfile.TemporaryDirectory() as tmpdir:
            img = Path(tmpdir) / "img.png"
            img.write_bytes(b"fake_png")
            output_path = Path(tmpdir) / "output.mp4"

            with patch('lib.video.check_ffmpeg_available', return_value=True), \
                 patch('subprocess.run') as mock_run, \
                 patch('lib.video.get_video_dimensions', side_effect=video.FFprobeError("Error")):

                mock_run.return_value = MagicMock(returncode=0)
                output_path.write_bytes(b"fake_video")

                file_size, width, height = video.create_video_from_images([img], output_path)

                assert file_size > 0
                assert width is None
                assert height is None


class TestVideoDuration:
    """Test get_video_duration function."""

    def test_valid_video_duration(self):
        """Test getting duration of valid video file."""
        with patch('lib.video.check_ffprobe_available', return_value=True), \
             patch('subprocess.run') as mock_run:

            mock_run.return_value = MagicMock(
                stdout="123.456\n",
                returncode=0
            )

            duration = video.get_video_duration(Path("/test/video.mp4"))

            assert duration == 123.456

    def test_duration_error_handling(self):
        """Test error handling for video duration detection."""
        with patch('lib.video.check_ffprobe_available', return_value=True), \
             patch('subprocess.run') as mock_run:

            mock_run.side_effect = subprocess.CalledProcessError(1, 'ffprobe', stderr='Error')

            with pytest.raises(video.FFprobeError, match="FFprobe failed"):
                video.get_video_duration(Path("/test/video.mp4"))


class TestVideoFrameCount:
    """Test get_video_frame_count function."""

    def test_valid_frame_count(self):
        """Test getting frame count of valid video file."""
        with patch('lib.video.check_ffprobe_available', return_value=True), \
             patch('subprocess.run') as mock_run:

            mock_run.return_value = MagicMock(
                stdout="1500\n",
                returncode=0
            )

            frame_count = video.get_video_frame_count(Path("/test/video.mp4"))

            assert frame_count == 1500

    def test_frame_count_error_handling(self):
        """Test error handling for video frame count detection."""
        with patch('lib.video.check_ffprobe_available', return_value=True), \
             patch('subprocess.run') as mock_run:

            mock_run.side_effect = subprocess.CalledProcessError(1, 'ffprobe', stderr='Error')

            with pytest.raises(video.FFprobeError, match="FFprobe failed"):
                video.get_video_frame_count(Path("/test/video.mp4"))


class TestErrorClasses:
    """Test custom error classes."""

    def test_ffmpeg_error_inheritance(self):
        """Test that FFmpegError inherits from Exception."""
        error = video.FFmpegError("Test error")
        assert isinstance(error, Exception)
        assert str(error) == "Test error"

    def test_ffprobe_error_inheritance(self):
        """Test that FFprobeError inherits from Exception."""
        error = video.FFprobeError("Test error")
        assert isinstance(error, Exception)
        assert str(error) == "Test error"
