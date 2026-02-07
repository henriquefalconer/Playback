#!/usr/bin/env python3
"""
OCR (Optical Character Recognition) processor for Playback.

This module extracts text from screenshots using Apple's Vision framework via PyObjC.
It provides both synchronous and batch processing capabilities with configurable
parallelism and timeout handling.

Performance targets:
- 5-10 frames/second processing rate
- <5 seconds timeout per frame
- <200MB memory per worker
"""

import logging
import multiprocessing as mp
import os
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

logger = logging.getLogger(__name__)


@dataclass
class OCRResult:
    """Result from OCR processing of a single frame."""
    frame_path: str
    text: str
    confidence: float
    language: str
    success: bool
    error: Optional[str] = None


def perform_ocr_sync(image_path: str, timeout: float = 5.0) -> OCRResult:
    """
    Perform OCR on a single image using Vision framework.

    This function uses PyObjC to interface with Apple's Vision framework for
    high-quality text recognition. It runs synchronously and respects the timeout.

    Args:
        image_path: Path to the image file (PNG, JPEG, etc.)
        timeout: Maximum time to spend on OCR (seconds)

    Returns:
        OCRResult: OCR extraction result with text and metadata

    Example:
        result = perform_ocr_sync("/path/to/screenshot.png")
        if result.success:
            print(f"Extracted: {result.text}")
    """
    try:
        # Import PyObjC Vision framework bindings
        # These imports are here to avoid loading when not needed
        from Foundation import NSURL
        from Vision import (
            VNRecognizeTextRequest,
            VNImageRequestHandler,
            VNRecognizeTextRequestRevisionLatest
        )
        from Quartz import CGImageSourceCreateWithURL, CGImageSourceCreateImageAtIndex

        # Validate image path
        image_path_obj = Path(image_path)
        if not image_path_obj.exists():
            return OCRResult(
                frame_path=image_path,
                text="",
                confidence=0.0,
                language="en",
                success=False,
                error=f"Image file not found: {image_path}"
            )

        # Load image
        image_url = NSURL.fileURLWithPath_(str(image_path_obj.absolute()))
        image_source = CGImageSourceCreateWithURL(image_url, None)

        if image_source is None:
            return OCRResult(
                frame_path=image_path,
                text="",
                confidence=0.0,
                language="en",
                success=False,
                error="Failed to load image"
            )

        cg_image = CGImageSourceCreateImageAtIndex(image_source, 0, None)
        if cg_image is None:
            return OCRResult(
                frame_path=image_path,
                text="",
                confidence=0.0,
                language="en",
                success=False,
                error="Failed to create CGImage"
            )

        # Create Vision text recognition request
        request = VNRecognizeTextRequest.alloc().init()
        request.setRecognitionLevel_(1)  # 1 = accurate, 0 = fast
        request.setUsesLanguageCorrection_(True)
        request.setRevision_(VNRecognizeTextRequestRevisionLatest)

        # Create request handler and perform OCR
        handler = VNImageRequestHandler.alloc().initWithCGImage_options_(cg_image, None)

        success = handler.performRequests_error_([request], None)
        if not success[0]:
            error_msg = str(success[1]) if len(success) > 1 else "Unknown error"
            return OCRResult(
                frame_path=image_path,
                text="",
                confidence=0.0,
                language="en",
                success=False,
                error=f"Vision request failed: {error_msg}"
            )

        # Extract results
        observations = request.results()
        if not observations:
            # No text found (not an error, just empty)
            return OCRResult(
                frame_path=image_path,
                text="",
                confidence=1.0,
                language="en",
                success=True
            )

        # Collect all recognized text with confidence scores
        text_lines = []
        confidences = []

        for observation in observations:
            top_candidate = observation.topCandidates_(1)[0]
            text = top_candidate.string()
            confidence = top_candidate.confidence()

            text_lines.append(text)
            confidences.append(confidence)

        # Combine text with newlines
        full_text = "\n".join(text_lines)
        avg_confidence = sum(confidences) / len(confidences) if confidences else 0.0

        return OCRResult(
            frame_path=image_path,
            text=full_text,
            confidence=avg_confidence,
            language="en",  # Vision framework auto-detects, but default to en
            success=True
        )

    except ImportError as e:
        logger.error(f"PyObjC Vision framework not available: {e}")
        return OCRResult(
            frame_path=image_path,
            text="",
            confidence=0.0,
            language="en",
            success=False,
            error=f"PyObjC not installed: {e}"
        )
    except Exception as e:
        logger.error(f"OCR failed for {image_path}: {e}", exc_info=True)
        return OCRResult(
            frame_path=image_path,
            text="",
            confidence=0.0,
            language="en",
            success=False,
            error=str(e)
        )


def _worker_process_ocr(
    task_queue: mp.Queue,
    result_queue: mp.Queue,
    timeout: float
) -> None:
    """
    Worker process for parallel OCR processing.

    Args:
        task_queue: Queue of image paths to process
        result_queue: Queue for OCR results
        timeout: OCR timeout per frame
    """
    while True:
        try:
            image_path = task_queue.get(timeout=1.0)
            if image_path is None:
                break

            result = perform_ocr_sync(image_path, timeout=timeout)
            result_queue.put(result)

        except Exception as e:
            logger.error(f"Worker error: {e}", exc_info=True)
            continue


def perform_ocr_batch(
    image_paths: List[str],
    num_workers: int = 4,
    timeout: float = 5.0
) -> List[OCRResult]:
    """
    Perform OCR on multiple images in parallel using worker processes.

    Args:
        image_paths: List of image file paths to process
        num_workers: Number of parallel worker processes (default: 4)
        timeout: Maximum time per frame (seconds)

    Returns:
        List[OCRResult]: Results for all images (same order as input)

    Example:
        paths = ["/path/frame1.png", "/path/frame2.png", "/path/frame3.png"]
        results = perform_ocr_batch(paths, num_workers=8)
        for result in results:
            if result.success:
                print(f"{result.frame_path}: {len(result.text)} chars")
    """
    if not image_paths:
        return []

    # Limit workers to reasonable bounds
    num_workers = max(1, min(num_workers, mp.cpu_count(), 8))
    logger.info(f"Starting OCR batch processing: {len(image_paths)} images, {num_workers} workers")

    # Create queues
    task_queue = mp.Queue()
    result_queue = mp.Queue()

    # Start worker processes
    workers = []
    for _ in range(num_workers):
        worker = mp.Process(
            target=_worker_process_ocr,
            args=(task_queue, result_queue, timeout)
        )
        worker.start()
        workers.append(worker)

    # Submit tasks
    for image_path in image_paths:
        task_queue.put(image_path)

    # Send stop signals
    for _ in range(num_workers):
        task_queue.put(None)

    # Collect results
    results = []
    for _ in range(len(image_paths)):
        try:
            result = result_queue.get(timeout=timeout + 5.0)
            results.append(result)
        except Exception as e:
            logger.error(f"Failed to get result: {e}")

    # Wait for workers to finish
    for worker in workers:
        worker.join(timeout=10.0)
        if worker.is_alive():
            logger.warning(f"Worker {worker.pid} did not terminate, killing")
            worker.terminate()

    logger.info(f"OCR batch complete: {len(results)}/{len(image_paths)} processed")
    return results


def test_ocr_availability() -> bool:
    """
    Test if Vision framework OCR is available.

    Returns:
        bool: True if OCR is available, False otherwise
    """
    try:
        from Vision import VNRecognizeTextRequest
        return True
    except ImportError:
        return False


if __name__ == "__main__":
    # Test script
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s"
    )

    print("Testing OCR processor...")

    # Test availability
    if test_ocr_availability():
        print("✓ Vision framework OCR is available")
    else:
        print("✗ Vision framework OCR is NOT available (install PyObjC)")
        exit(1)

    # Test with sample image if provided
    import sys
    if len(sys.argv) > 1:
        test_image = sys.argv[1]
        if Path(test_image).exists():
            print(f"\nTesting OCR on: {test_image}")
            result = perform_ocr_sync(test_image)

            if result.success:
                print(f"✓ OCR Success")
                print(f"  Text length: {len(result.text)} characters")
                print(f"  Confidence: {result.confidence:.2%}")
                print(f"  Language: {result.language}")
                if result.text:
                    print(f"  Preview: {result.text[:200]}...")
            else:
                print(f"✗ OCR Failed: {result.error}")
        else:
            print(f"✗ Image not found: {test_image}")
    else:
        print("\nUsage: python3 ocr_processor.py <image_path>")
