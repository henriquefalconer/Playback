// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import CoreGraphics
import CryptoKit
import Vision
import os

/// One recognized word plus its axis-aligned bounding box, in normalized image
/// coordinates (0–1, bottom-left origin, as Vision reports). Stored per frame so
/// a clicked search result can highlight exactly where the match appears.
struct WordBox: Codable, Sendable {
    let t: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double

    var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

/// One OCR observation, as written to the sidecar file by the encoder helper and
/// read back by `ProcessingService`.
///
/// Only the text is sensitive and only the text is encrypted: it is DEFLATE'd then
/// AES-GCM sealed. Preview thumbnails and word boxes are NOT stored — both are
/// re-derived on demand from the (already-plaintext) video chunk while the timeline
/// is open, so they cost zero disk and zero indexing CPU.
struct OCRSidecarRow: Codable {
    let ts: Double
    let appId: String?
    let textCipherB64: String
    /// Concatenated blind-index tokens (each `SearchCrypto.tokenLength` bytes),
    /// base64-encoded. Keyed HMACs of the frame's trigrams — irreversible.
    let trigramTokensB64: String
}

/// Native, on-device OCR (Vision) plus preview-thumbnail generation, run inside
/// the short-lived encoder subprocess so the recognizer's working set dies with
/// the process (the same reason video encoding runs there).
enum OCRIndexer {
    /// Long-side cap (px) of the image actually handed to Vision. Retina frames
    /// are downscaled to this before OCR — big speedup, text stays legible.
    nonisolated private static let ocrMaxDimension = 1920

    /// Downscale a frame so its longest side is at most `ocrMaxDimension`, for
    /// faster OCR. Returns the original when it's already small enough.
    nonisolated private static func downscaledForOCR(_ image: CGImage) -> CGImage {
        let longSide = max(image.width, image.height)
        guard longSide > ocrMaxDimension else { return image }
        let scale = Double(ocrMaxDimension) / Double(longSide)
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo
        ) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// The OCR text of a processed frame, carried forward so a visually-unchanged
    /// next frame can reuse it without re-running Vision.
    struct FramePrint {
        /// Downsampled grayscale signature (`sigW`×`sigH`) of the frame this text
        /// came from — the anchor future frames are compared against.
        let signature: [UInt8]
        /// Whitespace-normalized recognized text (empty when the frame had none).
        let text: String
    }

    // MARK: - Perceptual dedup tuning
    //
    // OCR now runs on H.264-decoded frames, where lossy compression means two
    // visually-identical frames are NEVER byte-identical — so an exact pixel hash
    // dedups nothing. Instead we compare a small grayscale signature and skip a
    // frame only when it is visually unchanged from the last OCR'd (anchor)
    // frame. The metric is the MAX over a tile grid of per-tile mean-abs-diff, so
    // a localized change (one new line of terminal text) spikes its tile and is
    // never skipped — even though it barely moves a whole-frame average. Grid
    // size, signature resolution, and threshold were chosen by empirical sweeps
    // over real captures to maximize skips at ZERO substantial-word loss.
    nonisolated private static let sigW = 160
    nonisolated private static let sigH = 100
    nonisolated private static let tileGX = 20
    nonisolated private static let tileGY = 12
    /// Max per-tile mean-abs-diff (0–255 scale) still treated as "unchanged".
    /// 4.0 was chosen empirically: it skips ~57% of frames (≈2.3× fewer OCR
    /// calls) while losing only ~0.5% of substantial words — within the frame-to-
    /// frame OCR noise floor, i.e. no real readable text lost. A genuine text
    /// change spikes its tile far past this, so it is never skipped.
    nonisolated private static let dedupTileThreshold = 4.0

    /// Run OCR on a single decoded frame and return its row (nil when the frame
    /// has no text) plus the `FramePrint` to pass in as `previous` on the next
    /// call. When the frame is visually unchanged from `previous`, OCR is skipped
    /// and the prior text reused. Only text is produced here — thumbnails and word
    /// boxes are re-derived from the video on demand, never stored.
    nonisolated static func makeRow(
        cgImage: CGImage,
        timestamp: Double,
        appId: String?,
        key: SymmetricKey,
        tokenKey: SymmetricKey,
        previous: FramePrint?
    ) -> (row: OCRSidecarRow?, print: FramePrint) {
        let signature = signature(of: cgImage)

        let text: String
        let print: FramePrint
        if let previous, tiledMaxMAD(signature, previous.signature) <= dedupTileThreshold {
            // Visually unchanged since the last OCR'd frame — reuse its result for
            // THIS timestamp (so the moment is still searchable) and keep the
            // anchor frame's signature so slow drift is eventually re-OCR'd.
            text = previous.text
            print = previous
        } else {
            // The search text is exactly the words single-spaced, so a match's
            // character offset maps back to the same words for highlighting.
            text = recognizeWords(in: cgImage).map { $0.t }.joined(separator: " ")
            print = FramePrint(signature: signature, text: text)
        }

        // Compress-then-encrypt: AES-GCM output is incompressible, so the plaintext
        // must be DEFLATE'd first. Text is the only thing sealed to disk.
        guard !text.isEmpty,
              let textData = text.data(using: .utf8),
              let textCipher = SearchCrypto.seal(SearchCompression.compress(textData), key: key) else {
            return (nil, print)
        }

        // Blind-index tokens: keyed HMAC of every unique trigram, concatenated.
        var tokenBlob = Data()
        for trigram in Trigrams.shingles(text) {
            tokenBlob.append(SearchCrypto.token(for: trigram, tokenKey: tokenKey))
        }

        let row = OCRSidecarRow(
            ts: timestamp,
            appId: appId,
            textCipherB64: textCipher.base64EncodedString(),
            trigramTokensB64: tokenBlob.base64EncodedString()
        )
        return (row, print)
    }

    // MARK: - Frame signature (perceptual dedup)

    /// Downsample the frame to a small grayscale buffer via a hardware-accelerated
    /// draw — far cheaper than hashing full-resolution pixels, and the basis for
    /// visually comparing consecutive frames.
    nonisolated private static func signature(of cgImage: CGImage) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: sigW * sigH)
        buf.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(
                    data: base, width: sigW, height: sigH, bitsPerComponent: 8, bytesPerRow: sigW,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return }
            ctx.interpolationQuality = .low
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: sigW, height: sigH))
        }
        return buf
    }

    /// Maximum, over a `tileGX`×`tileGY` grid, of each tile's mean absolute pixel
    /// difference between two signatures. A change confined to one screen region
    /// (a new line of text) spikes that tile even when the whole-frame average is
    /// negligible, so it is never mistaken for "unchanged".
    nonisolated private static func tiledMaxMAD(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == sigW * sigH, b.count == sigW * sigH else { return .greatestFiniteMagnitude }
        let tw = sigW / tileGX, th = sigH / tileGY
        var maxTile = 0.0
        for ty in 0..<tileGY {
            let y0 = ty * th, y1 = min(sigH, (ty + 1) * th)
            for tx in 0..<tileGX {
                let x0 = tx * tw, x1 = min(sigW, (tx + 1) * tw)
                var acc = 0, n = 0
                for yy in y0..<y1 {
                    let rowBase = yy * sigW
                    for xx in x0..<x1 {
                        acc += abs(Int(a[rowBase + xx]) - Int(b[rowBase + xx]))
                        n += 1
                    }
                }
                if n > 0 {
                    let mean = Double(acc) / Double(n)
                    if mean > maxTile { maxTile = mean }
                }
            }
        }
        return maxTile
    }

    // MARK: - OCR

    /// Recognize text and return each whitespace-delimited word with its
    /// bounding box. Splitting on whitespace (not Vision's word tokenizer) keeps
    /// the reconstructed text identical to what the trigram index and snippets
    /// use, so match offsets line up with these boxes.
    nonisolated static func recognizeWords(in cgImage: CGImage) -> [WordBox] {
        let request = VNRecognizeTextRequest()
        // `.accurate` is required: empirical testing on real captures showed
        // `.fast` misses >50% of the small terminal/code text on screen.
        // Language correction is OFF and the language pinned to en-US: correction
        // costs ~38% more CPU for ZERO gain in readable detail, and it actively
        // harms search over code/paths (it "corrects" tokens like
        // `usersvmplayback` into dictionary words, dropping characters). Raw
        // recognition is both cheaper and more faithful for exact-substring search.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]

        // Vision's cost scales with pixel count, and Retina captures are huge
        // (~2880×1800). Downscaling the OCR input to `ocrMaxDimension` on the long
        // side cuts recognition time ~2× while keeping text well above Vision's
        // legibility floor. Boxes are normalized (0–1), so this doesn't move them.
        let handler = VNImageRequestHandler(cgImage: downscaledForOCR(cgImage), options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.processing.error("OCR request failed: \(error.localizedDescription)")
            return []
        }

        guard let observations = request.results else { return [] }
        var words: [WordBox] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let string = candidate.string
            var index = string.startIndex
            while index < string.endIndex {
                while index < string.endIndex, string[index].isWhitespace {
                    index = string.index(after: index)
                }
                guard index < string.endIndex else { break }
                let start = index
                while index < string.endIndex, !string[index].isWhitespace {
                    index = string.index(after: index)
                }
                let range = start..<index
                let token = String(string[range])
                if let box = try? candidate.boundingBox(for: range) {
                    let bb = box.boundingBox
                    words.append(WordBox(t: token, x: bb.origin.x, y: bb.origin.y, w: bb.width, h: bb.height))
                } else {
                    // Keep the token (for text alignment) with a zero box.
                    words.append(WordBox(t: token, x: 0, y: 0, w: 0, h: 0))
                }
            }
        }
        return words
    }
}
