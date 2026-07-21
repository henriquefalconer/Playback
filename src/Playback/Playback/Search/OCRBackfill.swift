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

    // MARK: - Persistent worker entry point

    /// Persistent OCR worker protocol (over stdin/stdout, line-delimited):
    ///   • line 1        — the AES key, base64.
    ///   • lines 2…N     — one `Manifest` JSON per line (a batch to OCR); for each,
    ///                     the worker writes the rows to `manifest.ocrOutputPath`
    ///                     and replies with a single `OK`/`ERR` line on stdout.
    ///   • stdin EOF     — exit.
    ///
    /// The Vision text model loads on the first request and is reused for every one
    /// after — that reuse is the whole point of a persistent worker: no per-segment
    /// model reload, so a pool of workers keeps the CPU busy continuously instead of
    /// pulsing (cold-start stall → burst → exit → repeat) once per segment.
    static func runWorker() -> Int32 {
        let reader = PipeLineReader(FileHandle.standardInput)
        let out = FileHandle.standardOutput
        guard let keyLine = reader.readLine(), let key = SearchCrypto.key(fromBase64: keyLine) else {
            Log.processing.error("OCR worker: missing key on stdin")
            return 1
        }
        let tokenKey = SearchCrypto.deriveTokenKey(key)

        while let line = reader.readLine() {
            if line.isEmpty { continue }
            var ack = "ERR"
            if let data = line.data(using: .utf8),
               let manifest = try? JSONDecoder().decode(Manifest.self, from: data) {
                do {
                    let rows = try ocrSegment(manifest: manifest, key: key, tokenKey: tokenKey)
                    let encoded = try JSONEncoder().encode(rows)
                    try encoded.write(to: URL(fileURLWithPath: manifest.ocrOutputPath))
                    ack = "OK"
                } catch {
                    Log.processing.error("OCR worker request failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            // Reply so the parent knows the output file is ready (or the batch failed).
            try? out.write(contentsOf: Data("\(ack)\n".utf8))
        }
        return 0
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

/// Reads newline-delimited lines from a `FileHandle` (a pipe), buffering across
/// reads. Backs the persistent OCR worker's request/reply protocol on both ends —
/// the worker reads requests from stdin, the parent reads replies from the worker's
/// stdout. `readLine()` blocks until a full line arrives and returns nil at EOF
/// (e.g. the other end was closed or the process was killed).
final class PipeLineReader {
    private let handle: FileHandle
    private var buffer = Data()

    init(_ handle: FileHandle) { self.handle = handle }

    func readLine() -> String? {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                return String(data: line, encoding: .utf8) ?? ""
            }
            let chunk = handle.availableData
            if chunk.isEmpty {
                guard !buffer.isEmpty else { return nil }
                let line = buffer
                buffer.removeAll()
                return String(data: line, encoding: .utf8) ?? ""
            }
            buffer.append(chunk)
        }
    }
}
