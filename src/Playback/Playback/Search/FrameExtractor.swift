// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import AVFoundation
import CoreGraphics
import SQLite3
import os

private let SQLITE_TRANSIENT_FE = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Pulls frames out of segment `.mp4`s on demand, given absolute timeline
/// timestamps. Search-result thumbnails and match-highlight boxes are re-derived
/// this way now that neither is stored — the video chunk already holds the pixels.
///
/// Built for throughput: it is a plain class (not an actor), so many thumbnails
/// decode concurrently instead of one at a time; the SQLite lookup is the only
/// serialized part, and the decode runs outside the lock. Thumbnails use a
/// bounded-size generator with a lenient time tolerance (nearest decoded frame),
/// which is far faster than an exact seek; only the highlight path, which OCRs the
/// frame, asks for the exact frame at full resolution.
///
/// It lives behind the search session and is torn down when the timeline closes,
/// so decoders only exist — and only consume CPU/RAM — while the timeline is open.
final class FrameExtractor: @unchecked Sendable {
    private let dbPath: String
    private let maxThumbDimension: CGFloat
    /// Bound the live decoder count so RAM stays low even over long scrolls.
    private let generatorCap = 32

    private let lock = NSLock()
    private var db: OpaquePointer?
    private var thumbGenerators = BoundedGenerators()
    private var exactGenerators = BoundedGenerators()

    init(dbPath: String, maxThumbDimension: CGFloat = 400) {
        self.dbPath = dbPath
        self.maxThumbDimension = maxThumbDimension
    }

    /// A fast, downscaled preview frame near `ts`.
    func thumbnail(at ts: TimeInterval) async -> CGImage? { await image(at: ts, exact: false) }

    /// The exact full-resolution frame at `ts`, for on-demand OCR/highlighting.
    func exactImage(at ts: TimeInterval) async -> CGImage? { await image(at: ts, exact: true) }

    private func image(at ts: TimeInterval, exact: Bool) async -> CGImage? {
        lock.lock()
        guard let seg = segmentLocked(for: ts) else { lock.unlock(); return nil }
        let url = Paths.baseDataDirectory.appendingPathComponent(seg.videoPath)
        guard FileManager.default.fileExists(atPath: url.path) else { lock.unlock(); return nil }
        let generator = generatorLocked(for: seg.videoPath, url: url, exact: exact)
        lock.unlock()

        // The video is compressed to `frameCount/fps` seconds, NOT the wall-clock
        // span it covers — so seek by the fractional position within the segment
        // times the actual video duration. (Seeking by `ts - startTS` lands far past
        // the end and returns nil.)
        let span = max(0.0001, seg.endTS - seg.startTS)
        let ratio = min(1, max(0, (ts - seg.startTS) / span))
        let videoDuration = seg.fps > 0 ? Double(seg.frameCount) / seg.fps : span
        let time = CMTime(seconds: ratio * videoDuration, preferredTimescale: 600)

        let started = Date()
        do {
            let image = try await generator.image(at: time).image
            Log.search.debug("thumb ok ts=\(ts, privacy: .public) exact=\(exact, privacy: .public) in \(Int(Date().timeIntervalSince(started) * 1000), privacy: .public)ms")
            return image
        } catch {
            Log.search.debug("thumb FAIL ts=\(ts, privacy: .public) exact=\(exact, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func close() {
        lock.lock()
        if let db { sqlite3_close(db); self.db = nil }
        thumbGenerators.removeAll()
        exactGenerators.removeAll()
        lock.unlock()
    }

    // MARK: - Generators (lock held)

    private func generatorLocked(for key: String, url: URL, exact: Bool) -> AVAssetImageGenerator {
        if exact {
            if let existing = exactGenerators.get(key) { return existing }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            exactGenerators.put(key, generator, cap: 4)
            return generator
        }
        if let existing = thumbGenerators.get(key) { return existing }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        // A bounded output size decodes far less than a full Retina frame, and an
        // infinite tolerance lets AVFoundation return the nearest keyframe — no
        // decode-to-exact-frame cost. Benchmarked ~2× faster than an exact seek and
        // plenty accurate for a preview. (Highlighting uses the exact generator.)
        generator.maximumSize = CGSize(width: maxThumbDimension, height: maxThumbDimension)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        thumbGenerators.put(key, generator, cap: generatorCap)
        return generator
    }

    // MARK: - Segment lookup (lock held)

    private struct SegmentRef {
        let videoPath: String
        let startTS: Double
        let endTS: Double
        let frameCount: Int
        let fps: Double
    }

    private func segmentLocked(for ts: TimeInterval) -> SegmentRef? {
        guard let db = openDBLocked() else { return nil }
        let sql = """
            SELECT video_path, start_ts, end_ts, frame_count, COALESCE(fps, 1.0) FROM segments
            WHERE start_ts <= ? AND end_ts >= ? ORDER BY start_ts DESC LIMIT 1;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, ts)
        sqlite3_bind_double(stmt, 2, ts)
        guard sqlite3_step(stmt) == SQLITE_ROW, let pathC = sqlite3_column_text(stmt, 0) else { return nil }
        return SegmentRef(
            videoPath: String(cString: pathC),
            startTS: sqlite3_column_double(stmt, 1),
            endTS: sqlite3_column_double(stmt, 2),
            frameCount: Int(sqlite3_column_int(stmt, 3)),
            fps: sqlite3_column_double(stmt, 4)
        )
    }

    private func openDBLocked() -> OpaquePointer? {
        if let db { return db }
        guard FileManager.default.fileExists(atPath: dbPath) else { return nil }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        db = handle
        return handle
    }
}

/// A tiny FIFO-bounded cache of image generators. Eviction just drops the
/// reference (any in-flight decode it still holds finishes, then ARC frees it) —
/// it never cancels work, so a visible thumbnail is never killed by scrolling
/// past the cache bound. Everything is cancelled only when the session closes.
private struct BoundedGenerators {
    private var order: [String] = []
    private var map: [String: AVAssetImageGenerator] = [:]

    func get(_ key: String) -> AVAssetImageGenerator? { map[key] }

    mutating func put(_ key: String, _ generator: AVAssetImageGenerator, cap: Int) {
        map[key] = generator
        order.append(key)
        while order.count > cap {
            map.removeValue(forKey: order.removeFirst())
        }
    }

    mutating func removeAll() {
        for generator in map.values { generator.cancelAllCGImageGeneration() }
        map.removeAll()
        order.removeAll()
    }
}
