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

        // Map the absolute timestamp to the frame index the OCR indexer recorded — it
        // decodes frames sequentially, so its index is exact — then seek to the CENTER
        // of that frame's presentation interval. Seeking to the frame's start edge
        // (index/fps) lets a zero-tolerance decode round *down* into the previous frame
        // at the boundary; at an app switch that renders a different app entirely, with
        // none of the matched text and no highlight box. The +0.5 lands squarely inside
        // the intended frame. (Seeking by `ts - startTS` instead would land far past the
        // end, since the video is compressed to frameCount/fps seconds, not wall-clock.)
        let span = max(0.0001, seg.endTS - seg.startTS)
        let ratio = min(1, max(0, (ts - seg.startTS) / span))
        let fps = seg.fps > 0 ? seg.fps : max(1, Double(seg.frameCount)) / span
        let lastIndex = Double(max(0, seg.frameCount - 1))
        let index = min(lastIndex, (ratio * Double(seg.frameCount)).rounded())
        let time = CMTime(seconds: (index + 0.5) / fps, preferredTimescale: 600)

        lock.unlock()
        return await Self.rawDecode(generator, at: time)
    }

    private static func rawDecode(_ generator: AVAssetImageGenerator, at time: CMTime) async -> CGImage? {
        do {
            return try await generator.image(at: time).image
        } catch {
            Log.search.debug("thumb decode failed: \(error.localizedDescription, privacy: .public)")
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
        // The bounded output size is where the thumbnail's speed comes from — it decodes
        // far less than a full Retina frame. The tolerance must stay zero, though: with
        // an infinite tolerance AVFoundation returns whatever frame is cheapest to
        // produce (in practice a single frame for a whole region), ignoring the
        // requested time — so the preview shows a *different* frame than the one that
        // matched. Every frame is intra-coded, so an exact seek still decodes just one
        // frame. (Highlighting uses the full-resolution exact generator.)
        generator.maximumSize = CGSize(width: maxThumbDimension, height: maxThumbDimension)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
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
