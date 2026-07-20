// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import CryptoKit
import os

/// Backfills the OCR index for a video segment that was recorded before OCR
/// existed (or whose index was lost) by decoding its frames straight from the
/// `.mp4` and running the same OCR + blind-index pipeline used at encode time.
///
/// Runs in a short-lived helper subprocess (`--ocr-segment`) so the video
/// decoder's and recognizer's working sets die with the process. The AES key
/// arrives on stdin, never on disk.
enum OCRBackfill {
    /// Instructions written by the parent, read by the helper. The helper OCRs only
    /// the frame range `[loFrame, hiFrame)` so a large segment is processed — and
    /// its matches surfaced — a batch at a time, newest frames first.
    struct Manifest: Codable {
        let videoPath: String
        let startTS: Double
        let endTS: Double
        let frameCount: Int
        let fps: Double
        let loFrame: Int
        let hiFrame: Int
        let ocrOutputPath: String
    }

    // MARK: - Helper entry point

    static func runHelper(manifestPath: String) -> Int32 {
        guard let data = FileManager.default.contents(atPath: manifestPath),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            Log.processing.error("Backfill helper: unreadable manifest at \(manifestPath, privacy: .public)")
            return 1
        }
        guard let keyB64 = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8),
              let key = SearchCrypto.key(fromBase64: keyB64) else {
            Log.processing.error("Backfill helper: no key on stdin")
            return 1
        }
        let tokenKey = SearchCrypto.deriveTokenKey(key)

        do {
            let rows = try ocrSegment(manifest: manifest, key: key, tokenKey: tokenKey)
            let out = try JSONEncoder().encode(rows)
            try out.write(to: URL(fileURLWithPath: manifest.ocrOutputPath))
            Log.processing.info("Backfill helper: wrote \(rows.count, privacy: .public) rows")
            return 0
        } catch {
            Log.processing.error("Backfill helper failed: \(error.localizedDescription, privacy: .public)")
            return 1
        }
    }

    // MARK: - Decode + OCR

    private enum BackfillError: Error { case noVideoTrack, readerFailed }

    private static func ocrSegment(manifest: Manifest, key: SymmetricKey, tokenKey: SymmetricKey) throws -> [OCRSidecarRow] {
        let asset = AVURLAsset(url: URL(fileURLWithPath: manifest.videoPath))
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw BackfillError.noVideoTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw BackfillError.readerFailed }
        reader.add(output)

        let span = manifest.endTS - manifest.startTS
        let frameCount = max(1, manifest.frameCount)
        let fps = manifest.fps > 0 ? manifest.fps : Double(frameCount) / max(0.001, span)
        let lo = max(0, manifest.loFrame)
        let hi = min(frameCount, manifest.hiFrame)

        // Seek straight to the batch instead of decoding from the start — as cheap
        // as a segment decode for this range. A little slack on each side absorbs
        // keyframe snapping; frames outside [lo, hi) are dropped by their index.
        let slack = 2.0 / fps
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: max(0, Double(lo) / fps - slack), preferredTimescale: 600),
            duration: CMTime(seconds: Double(hi - lo) / fps + 2 * slack, preferredTimescale: 600)
        )
        guard reader.startReading() else { throw reader.error ?? BackfillError.readerFailed }

        var rows: [OCRSidecarRow] = []
        var lastPrint: OCRIndexer.FramePrint?

        while let sample = output.copyNextSampleBuffer() {
            autoreleasepool {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample),
                      let cgImage = Self.cgImage(from: pixelBuffer) else { return }
                // Index the frame by its presentation time — robust to keyframe
                // snapping — and keep only those inside the requested batch.
                let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                let index = Int((pts * fps).rounded())
                guard index >= lo, index < hi else { return }

                // Absolute timeline timestamp (linear over the segment, matching
                // how playback maps offsets).
                let ts = manifest.startTS + (Double(index) / Double(frameCount)) * span
                let result = OCRIndexer.makeRow(
                    cgImage: cgImage, timestamp: ts, appId: nil,
                    key: key, tokenKey: tokenKey, previous: lastPrint
                )
                lastPrint = result.print
                if let row = result.row { rows.append(row) }
            }
        }

        if reader.status == .failed { throw reader.error ?? BackfillError.readerFailed }
        return rows
    }

    /// Copy a BGRA CVPixelBuffer into a standalone CGImage via CoreGraphics.
    private static func cgImage(from buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: base, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo
        ) else { return nil }
        return context.makeImage()
    }
}
