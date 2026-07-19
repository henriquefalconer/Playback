// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import CryptoKit
import ImageIO
import os

/// Encodes a sequence of PNG frames into an H.264 MP4.
///
/// This runs in a short-lived helper subprocess (see `main.swift`), NOT in the
/// main app. VideoToolbox/AVFoundation retain their compression session and its
/// large working set in-process for reuse, and `malloc_zone_pressure_relief`
/// cannot reclaim it — so encoding in-process permanently inflates the app's
/// footprint by hundreds of MB. Doing it in a subprocess means the kernel
/// reclaims every byte the instant the process exits, keeping the app lean.
enum VideoEncoder {
    enum EncodeError: Error {
        case manifestUnreadable
        case setupFailed
        case encodingFailed
    }

    /// Manifest written by the parent and read by the helper.
    struct Manifest: Codable {
        let outputPath: String
        let width: Int
        let height: Int
        let framePaths: [String]
        // OCR indexing (optional). When present, the helper runs on-device OCR
        // over each frame and writes an encrypted sidecar to `ocrOutputPath`.
        // The arrays are parallel to `framePaths`.
        var frameTimestamps: [Double]?
        var frameAppIds: [String?]?
        var ocrOutputPath: String?
    }

    // MARK: - Helper entry point

    /// Runs the encode described by the manifest file and returns a process exit
    /// code (0 = success). Called from `main.swift` in the helper subprocess.
    ///
    /// The AES index key is read from stdin (a kernel pipe), never from disk, so
    /// the plaintext key is never persisted anywhere.
    static func runHelper(manifestPath: String) -> Int32 {
        guard let data = FileManager.default.contents(atPath: manifestPath),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            Log.processing.error("Encoder helper: could not read manifest at \(manifestPath, privacy: .public)")
            return 1
        }
        let keyB64 = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)
        do {
            try encode(
                framePaths: manifest.framePaths,
                outputPath: manifest.outputPath,
                width: manifest.width,
                height: manifest.height,
                ocr: OCRPass(manifest: manifest, keyB64: keyB64)
            )
            return 0
        } catch {
            Log.processing.error("Encoder helper: encode failed — \(error.localizedDescription, privacy: .public)")
            return 1
        }
    }

    // MARK: - OCR pass configuration

    /// Resolved OCR configuration for an encode run, or nil when the manifest
    /// carried no OCR request (or no key arrived on stdin).
    struct OCRPass {
        let timestamps: [Double]
        let appIds: [String?]
        let key: SymmetricKey
        let tokenKey: SymmetricKey
        let outputPath: String

        init?(manifest: Manifest, keyB64: String?) {
            guard let timestamps = manifest.frameTimestamps,
                  let appIds = manifest.frameAppIds,
                  let outputPath = manifest.ocrOutputPath,
                  let keyB64,
                  let key = SearchCrypto.key(fromBase64: keyB64),
                  timestamps.count == manifest.framePaths.count,
                  appIds.count == manifest.framePaths.count else {
                return nil
            }
            self.timestamps = timestamps
            self.appIds = appIds
            self.key = key
            self.tokenKey = SearchCrypto.deriveTokenKey(key)
            self.outputPath = outputPath
        }
    }

    // MARK: - Encode

    static func encode(framePaths: [String], outputPath: String, width: Int, height: Int, ocr: OCRPass? = nil) throws {  // swiftlint:disable:this function_body_length cyclomatic_complexity
        let outputURL = URL(fileURLWithPath: outputPath)
        do {
            try FileManager.default.removeItem(at: outputURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // File doesn't exist yet, that's fine
        } catch {
            Log.processing.debug("Could not remove pre-existing video file: \(error.localizedDescription)")
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(500_000, width * height),
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttribs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttribs
        )

        guard writer.canAdd(input) else {
            throw EncodeError.setupFailed
        }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Cap in-flight pixel buffers. The writer accepts frames far faster
        // than it encodes them, so without a threshold its queue balloons to
        // dozens of full-screen buffers.
        let poolAuxAttributes = [
            kCVPixelBufferPoolAllocationThresholdKey as String: 6
        ] as CFDictionary

        var ocrRows: [OCRSidecarRow] = []
        var lastFramePrint: OCRIndexer.FramePrint?

        let encodeLoopStart = CFAbsoluteTimeGetCurrent()
        for (index, framePath) in framePaths.enumerated() {
            autoreleasepool {
                var waited = 0
                while !input.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.01)
                    waited += 1
                    if waited > 1000 { break }  // Timeout after 10s
                }

                guard let pool = adaptor.pixelBufferPool else {
                    Log.processing.notice("Pixel buffer pool unavailable at frame \(index)")
                    return
                }
                var pixelBuffer: CVPixelBuffer?
                var poolStatus = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                    kCFAllocatorDefault, pool, poolAuxAttributes, &pixelBuffer
                )
                var poolWaited = 0
                while poolStatus == kCVReturnWouldExceedAllocationThreshold, poolWaited < 1000 {
                    Thread.sleep(forTimeInterval: 0.01)
                    poolWaited += 1
                    poolStatus = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                        kCFAllocatorDefault, pool, poolAuxAttributes, &pixelBuffer
                    )
                }
                guard poolStatus == kCVReturnSuccess, let buffer = pixelBuffer else {
                    Log.processing.notice("Failed to get buffer from pool at frame \(index): \(poolStatus)")
                    return
                }

                let frameURL = URL(fileURLWithPath: framePath)
                guard let imageSource = CGImageSourceCreateWithURL(frameURL as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    Log.processing.notice("Skipping unreadable frame: \(frameURL.lastPathComponent)")
                    return
                }

                guard fillPixelBuffer(buffer, from: cgImage, width: width, height: height) else {
                    Log.processing.notice("Skipping frame (render failed): \(frameURL.lastPathComponent)")
                    return
                }

                let presentationTime = CMTime(value: CMTimeValue(index), timescale: 30)
                adaptor.append(buffer, withPresentationTime: presentationTime)

                // On-device OCR + preview thumbnail, indexed for search. Runs
                // here (in the helper subprocess) so the recognizer's working
                // set is reclaimed when the process exits. Pixel-identical
                // consecutive frames (a static screen) reuse the previous
                // frame's OCR + thumbnail instead of re-running Vision.
                if let ocr, index < ocr.timestamps.count {
                    let result = OCRIndexer.makeRow(
                        cgImage: cgImage,
                        timestamp: ocr.timestamps[index],
                        appId: ocr.appIds[index],
                        key: ocr.key,
                        tokenKey: ocr.tokenKey,
                        previous: lastFramePrint
                    )
                    lastFramePrint = result.print
                    if let row = result.row {
                        ocrRows.append(row)
                    }
                }

                if (index + 1) % 100 == 0 {
                    let elapsed = CFAbsoluteTimeGetCurrent() - encodeLoopStart
                    Log.processing.info("Encoding progress — frame \(index + 1, privacy: .public)/\(framePaths.count, privacy: .public), elapsed=\(String(format: "%.1f", elapsed), privacy: .public)s")
                }
            }
        }

        input.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        if writer.status == .failed {
            throw writer.error ?? EncodeError.encodingFailed
        }

        if let ocr {
            writeOCRSidecar(ocrRows, to: ocr.outputPath)
        }
    }

    /// Persist the encrypted OCR rows for the parent process to ingest. Failure
    /// to write the sidecar must never fail the encode — the video is the
    /// primary artifact; the search index is best-effort.
    private static func writeOCRSidecar(_ rows: [OCRSidecarRow], to path: String) {
        do {
            let data = try JSONEncoder().encode(rows)
            try data.write(to: URL(fileURLWithPath: path))
            Log.processing.info("OCR sidecar written — rows=\(rows.count, privacy: .public)")
        } catch {
            Log.processing.error("Failed to write OCR sidecar: \(error.localizedDescription)")
        }
    }

    private static func fillPixelBuffer(_ buffer: CVPixelBuffer, from cgImage: CGImage, width: Int, height: Int) -> Bool {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return false }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return false }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return true
    }
}
