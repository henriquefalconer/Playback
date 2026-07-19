// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import CoreGraphics
import ImageIO
import CryptoKit
import UniformTypeIdentifiers
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

/// One encrypted OCR observation, as written to the sidecar file by the encoder
/// helper and read back by `ProcessingService`. Only ciphertext ever hits disk.
struct OCRSidecarRow: Codable {
    let ts: Double
    let appId: String?
    let textCipherB64: String
    let thumbCipherB64: String?
    /// Concatenated blind-index tokens (each `SearchCrypto.tokenLength` bytes),
    /// base64-encoded. Keyed HMACs of the frame's trigrams — irreversible.
    let trigramTokensB64: String
    /// Encrypted JSON of the frame's `WordBox` list (for match highlighting).
    let boxesCipherB64: String?
}

/// Native, on-device OCR (Vision) plus preview-thumbnail generation, run inside
/// the short-lived encoder subprocess so the recognizer's working set dies with
/// the process (the same reason video encoding runs there).
enum OCRIndexer {
    /// Max dimension (px) of the stored preview thumbnail. Retina-crisp for the
    /// ~52pt squircle shown in search results.
    private static let thumbMaxDimension = 400

    /// The OCR text + thumbnail of a processed frame, carried forward so a
    /// pixel-identical next frame can reuse it without re-running Vision.
    struct FramePrint {
        let fingerprint: UInt64
        /// Whitespace-normalized recognized text (empty when the frame had none).
        let text: String
        let thumb: Data?
        let words: [WordBox]
    }

    /// Run OCR + thumbnail on a single decoded frame and return an encrypted
    /// sidecar row (nil when the frame has no text) plus the `FramePrint` to
    /// pass in as `previous` on the next call. When the frame is pixel-identical
    /// to `previous`, OCR and thumbnail generation are skipped entirely.
    nonisolated static func makeRow(
        cgImage: CGImage,
        timestamp: Double,
        appId: String?,
        key: SymmetricKey,
        tokenKey: SymmetricKey,
        previous: FramePrint?
    ) -> (row: OCRSidecarRow?, print: FramePrint) {
        let fingerprint = pixelFingerprint(cgImage)

        let text: String
        let thumb: Data?
        let words: [WordBox]
        if let previous, previous.fingerprint == fingerprint {
            // Identical frame — reuse the prior result, skipping Vision entirely.
            text = previous.text
            thumb = previous.thumb
            words = previous.words
        } else {
            words = recognizeWords(in: cgImage)
            // The search text is exactly the words single-spaced, so a match's
            // character offset maps back to the same words for highlighting.
            text = words.map { $0.t }.joined(separator: " ")
            thumb = text.isEmpty ? nil : thumbnailJPEG(from: cgImage)
        }

        let print = FramePrint(fingerprint: fingerprint, text: text, thumb: thumb, words: words)

        guard !text.isEmpty,
              let textData = text.data(using: .utf8),
              let textCipher = SearchCrypto.seal(textData, key: key) else {
            return (nil, print)
        }

        var thumbCipherB64: String?
        if let thumb, let thumbCipher = SearchCrypto.seal(thumb, key: key) {
            thumbCipherB64 = thumbCipher.base64EncodedString()
        }

        var boxesCipherB64: String?
        if let boxesData = try? JSONEncoder().encode(words),
           let boxesCipher = SearchCrypto.seal(boxesData, key: key) {
            boxesCipherB64 = boxesCipher.base64EncodedString()
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
            thumbCipherB64: thumbCipherB64,
            trigramTokensB64: tokenBlob.base64EncodedString(),
            boxesCipherB64: boxesCipherB64
        )
        return (row, print)
    }

    // MARK: - Frame fingerprint

    /// Exact FNV-1a hash over the frame's decoded pixels. Any pixel difference
    /// yields a different fingerprint, so dedup never reuses text across frames
    /// that actually changed (even a small text edit on an otherwise static
    /// screen).
    private static func pixelFingerprint(_ cgImage: CGImage) -> UInt64 {
        guard let data = cgImage.dataProvider?.data else {
            // No accessible pixels — return a unique-ish value so this frame is
            // never treated as a duplicate (it will always be OCR'd).
            return UInt64(cgImage.width) &* 0x9E3779B97F4A7C15 &+ UInt64(cgImage.height) &+ 1
        }
        let length = CFDataGetLength(data)
        guard let ptr = CFDataGetBytePtr(data), length > 0 else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let buffer = UnsafeBufferPointer(start: ptr, count: length)
        for byte in buffer {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    // MARK: - OCR

    /// Recognize text and return each whitespace-delimited word with its
    /// bounding box. Splitting on whitespace (not Vision's word tokenizer) keeps
    /// the reconstructed text identical to what the trigram index and snippets
    /// use, so match offsets line up with these boxes.
    nonisolated private static func recognizeWords(in cgImage: CGImage) -> [WordBox] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
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

    // MARK: - Thumbnail

    nonisolated private static func thumbnailJPEG(from cgImage: CGImage) -> Data? {
        let srcW = cgImage.width
        let srcH = cgImage.height
        guard srcW > 0, srcH > 0 else { return nil }

        let scale = min(1.0, Double(thumbMaxDimension) / Double(max(srcW, srcH)))
        let dstW = max(1, Int((Double(srcW) * scale).rounded()))
        let dstH = max(1, Int((Double(srcH) * scale).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: nil,
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))
        guard let scaled = context.makeImage() else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, scaled, [
            kCGImageDestinationLossyCompressionQuality: 0.6
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
