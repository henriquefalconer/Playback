// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import SwiftUI
import AppKit
import Combine
import CryptoKit
import SQLite3
import os

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A single search hit surfaced to the UI.
struct SearchResult: Identifiable, Sendable {
    let id: String
    let ts: TimeInterval
    let appId: String?
    /// Snippet with the matched substring styled, plus leading/trailing context.
    let snippet: AttributedString
}


/// Thread-safe reader over the encrypted index. Each query is a single indexed
/// lookup on the on-disk blind (trigram) index that decrypts only the handful of
/// matching frames — nothing is ever bulk-loaded into memory. Implemented as an
/// actor so its SQLite connection stays off the main thread.
actor OCRStore {
    private let path: String
    private var db: OpaquePointer?
    private var cachedKey: SymmetricKey?
    private var cachedTokenKey: SymmetricKey?

    init(path: String) {
        self.path = path
    }

    private func openIfNeeded() -> OpaquePointer? {
        if let db { return db }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            Log.search.error("Search store: failed to open DB at \(self.path, privacy: .public)")
            return nil
        }
        db = handle
        return handle
    }

    private func keys() -> (SymmetricKey, SymmetricKey) {
        if let cachedKey, let cachedTokenKey { return (cachedKey, cachedTokenKey) }
        let key = SearchCrypto.loadOrCreateKey()
        let tokenKey = SearchCrypto.deriveTokenKey(key)
        cachedKey = key
        cachedTokenKey = tokenKey
        return (key, tokenKey)
    }

    /// Fetch *every* match for a query, newest-first, spanning the full history —
    /// no cap. A ubiquitous word ("the") matches many frames across every recorded
    /// day and they all come back, so the list is complete and the ruler (which
    /// thins the view by snapping onto its fixed slot grid) can reach any date.
    /// Each candidate is decrypted and exact-substring verified before inclusion.
    func search(_ rawQuery: String) -> [SearchResult] {
        let normalizedQuery = Trigrams.normalize(rawQuery)
        let shingles = Trigrams.shingles(normalizedQuery)
        guard !shingles.isEmpty, let db = openIfNeeded() else { return [] }

        let (key, tokenKey) = keys()
        // Cap the number of trigram filters so a very long query can't blow past
        // SQLite's bound-parameter limit. Any subset is a valid pre-filter — the
        // exact-substring verify below still guarantees correctness.
        let tokens = shingles.prefix(64).map { SearchCrypto.token(for: $0, tokenKey: tokenKey) }
        let needle = normalizedQuery.lowercased()

        // Intersect the query tokens' posting lists → frames containing ALL of
        // them. Each posting list is a token's ascending frame ids, delta-varint
        // packed; decoding + intersecting happens in memory.
        let lists = tokens.map { postingFids(for: $0, db: db) }
        let candidates = PostingCodec.intersect(lists)
        guard !candidates.isEmpty, loadCandidates(candidates, db: db) else { return [] }

        let sql = """
            SELECT f.id, f.ts, f.app_id, f.text_cipher
            FROM ocr_frames f JOIN _cand c ON f.rowid = c.fid
            ORDER BY f.ts DESC;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        var results: [SearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let ts = sqlite3_column_double(stmt, 1)
            guard let idC = sqlite3_column_text(stmt, 0),
                  let blobPtr = sqlite3_column_blob(stmt, 3) else { continue }
            let id = String(cString: idC)
            let appId = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let cipher = Data(bytes: blobPtr, count: Int(sqlite3_column_bytes(stmt, 3)))
            // Reverse the write path: AES-GCM open, then DEFLATE inflate.
            guard let deflated = SearchCrypto.open(cipher, key: key),
                  let plain = SearchCompression.decompress(deflated),
                  let text = String(data: plain, encoding: .utf8) else { continue }
            // Exact-substring verify to drop trigram false positives.
            guard text.lowercased().contains(needle) else { continue }
            results.append(SearchResult(
                id: id, ts: ts, appId: appId,
                snippet: SnippetBuilder.make(text, query: normalizedQuery)
            ))
        }
        return results
    }

    /// Decode one token's posting list into its ascending frame ids.
    private func postingFids(for tok: Data, db: OpaquePointer) -> [Int64] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT fids FROM ocr_postings WHERE tok = ?;", -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        tok.withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, 1, raw.baseAddress, Int32(tok.count), SQLITE_TRANSIENT)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW, let ptr = sqlite3_column_blob(stmt, 0) else { return [] }
        let blob = Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 0)))
        return PostingCodec.decode(blob)
    }

    /// Load the intersected candidate fids into a temp table for the ordered join.
    /// A read-only main connection can still write to the temp database.
    private func loadCandidates(_ fids: [Int64], db: OpaquePointer) -> Bool {
        sqlite3_exec(db, "CREATE TEMP TABLE IF NOT EXISTS _cand(fid INTEGER PRIMARY KEY);", nil, nil, nil)
        sqlite3_exec(db, "DELETE FROM _cand;", nil, nil, nil)
        guard sqlite3_exec(db, "BEGIN;", nil, nil, nil) == SQLITE_OK else { return false }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO _cand(fid) VALUES (?);", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil); return false
        }
        for fid in fids {
            sqlite3_reset(stmt)
            sqlite3_bind_int64(stmt, 1, fid)
            if sqlite3_step(stmt) != SQLITE_DONE {
                sqlite3_finalize(stmt); sqlite3_exec(db, "ROLLBACK;", nil, nil, nil); return false
            }
        }
        sqlite3_finalize(stmt)
        return sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK
    }

    func close() {
        if let db { sqlite3_close(db) }
        db = nil
    }
}

/// Live search over the encrypted, on-disk blind index. Holds no bulk plaintext:
/// every keystroke issues one fast indexed query that decrypts only its matches.
@MainActor
final class SearchIndex: ObservableObject {
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var hasQuery = false
    /// True while a query is loading — so the UI shows a loading state instead of
    /// prematurely reading empty results as "No matches".
    @Published private(set) var isSearching = false

    private let store: OCRStore
    /// Re-derives result previews and highlight boxes from the video on demand.
    private let extractor: FrameExtractor
    private let thumbCache = NSCache<NSString, NSImage>()
    private var searchTask: Task<Void, Never>?

    private var currentQuery = ""
    /// A refresh timer is pending (waiting out the coalescing window).
    private var refreshScheduled = false
    /// A refresh search is decrypting right now — never run two at once.
    private var refreshInFlight = false
    /// Progress arrived; another refresh is wanted once the current one settles.
    private var refreshPending = false

    init() {
        self.store = OCRStore(path: Paths.databasePath.path)
        self.extractor = FrameExtractor(dbPath: Paths.databasePath.path)
        thumbCache.countLimit = 300
        // As the background indexer finishes more segments, pull the newly-indexed
        // matches into the open result list so results stream in without retyping.
        NotificationCenter.default.addObserver(
            forName: .ocrIndexProgressed, object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleIndexRefresh()
        }
    }

    /// Open the search session; nothing to preload.
    func activate() {}

    /// Re-run the current query a beat after indexing batches finish, so a just-OCR'd
    /// frame's match appears without retyping. Silent: it never clears the visible
    /// rows or flashes the empty-state spinner.
    ///
    /// Since a query with no cap can match thousands of frames — each decrypted every
    /// refresh — this is deliberately frugal: batches are coalesced into one refresh
    /// per second, two refreshes never decrypt at once (a burst just sets a pending
    /// flag that runs one trailing refresh), and the published list is replaced only
    /// when it actually changed, so we don't rebuild a huge row list for nothing.
    private func scheduleIndexRefresh() {
        guard hasQuery else { return }
        refreshPending = true
        guard !refreshScheduled, !refreshInFlight else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.runIndexRefresh()
        }
    }

    private func runIndexRefresh() {
        refreshScheduled = false
        guard hasQuery, refreshPending, !refreshInFlight else { return }
        refreshPending = false
        refreshInFlight = true
        let query = currentQuery
        Task { [weak self] in
            guard let self else { return }
            let fresh = await self.store.search(query)
            self.refreshInFlight = false
            guard query == self.currentQuery else { return }
            // Replacing the @Published array re-diffs the whole row list, so only do
            // it when the match set's size or endpoints actually moved.
            if fresh.count != self.results.count
                || fresh.first?.id != self.results.first?.id
                || fresh.last?.id != self.results.last?.id {
                self.results = fresh
            }
            // More progress landed while we were decrypting — run one more pass.
            if self.refreshPending { self.scheduleIndexRefresh() }
        }
    }

    func deactivate() {
        searchTask?.cancel()
        searchTask = nil
        results = []
        hasQuery = false
        isSearching = false
        currentQuery = ""
        refreshPending = false
        thumbCache.removeAllObjects()
        extractor.close()
        Task { [store] in await store.close() }
    }

    func search(_ rawQuery: String) {
        currentQuery = rawQuery
        hasQuery = !rawQuery.trimmingCharacters(in: .whitespaces).isEmpty
        searchTask?.cancel()
        guard hasQuery else {
            results = []
            isSearching = false
            return
        }
        // Show the loading state immediately (covers the debounce + fetch) so an
        // in-flight search never reads as "No matches" — but only for queries long
        // enough to actually hit the index. A 1–2 char query resolves straight to
        // "Keep typing…" with no spinner flash.
        isSearching = Trigrams.normalize(rawQuery).count >= Trigrams.minLength
        searchTask = Task { [weak self] in
            guard let self else { return }
            // Coalesce fast keystrokes into a single query.
            try? await Task.sleep(nanoseconds: 40_000_000)
            if Task.isCancelled { return }
            // One indexed scan pulls the entire match set, spanning every date, so
            // the list shows them all and the ruler can scroll to any of them.
            let fresh = await store.search(rawQuery)
            if Task.isCancelled || rawQuery != self.currentQuery { return }
            self.results = fresh
            self.isSearching = false
        }
    }

    /// Normalized bounding boxes (Vision coords) of the words the query matched
    /// within the frame at `ts` — used to highlight the exact spot on the video.
    /// The frame is pulled from the chunk and OCR'd on demand (nothing is stored).
    func highlightRects(at ts: TimeInterval, query: String) async -> [CGRect] {
        let needle = Trigrams.normalize(query).lowercased()
        guard needle.count >= Trigrams.minLength,
              let cgImage = await extractor.exactImage(at: ts) else { return [] }
        // Vision text recognition is a heavy synchronous call. Run it on a detached
        // task so it executes on the global executor, never the main thread — this
        // type is `@MainActor`, so doing it inline would freeze the UI for a
        // second-plus after every result click.
        return await Task.detached(priority: .userInitiated) {
            Self.matchRects(in: cgImage, needle: needle)
        }.value
    }

    /// OCR `cgImage`, then collect the bounding boxes of every word overlapping the
    /// `needle` match. Pure and off-actor — safe to run on a background executor.
    private nonisolated static func matchRects(in cgImage: CGImage, needle: String) -> [CGRect] {
        let words = OCRIndexer.recognizeWords(in: cgImage)
        guard !words.isEmpty else { return [] }

        // Reconstruct the exact search text (words single-spaced) and locate the
        // match, then collect every word whose character span overlaps it.
        let text = words.map { $0.t }.joined(separator: " ").lowercased()
        guard let range = text.range(of: needle) else { return [] }
        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let matchEnd = text.distance(from: text.startIndex, to: range.upperBound)

        var rects: [CGRect] = []
        var offset = 0
        for word in words {
            let wordStart = offset
            let wordEnd = offset + word.t.count
            if wordStart < matchEnd, wordEnd > matchStart {
                let rect = word.rect
                if rect.width > 0, rect.height > 0 { rects.append(rect) }
            }
            offset = wordEnd + 1 // +1 for the joining space
        }
        return rects
    }

    /// The preview for a result: the frame at its timestamp, pulled from the video
    /// chunk on demand and downscaled. Cached by result id for the session.
    ///
    /// `async` so the caller's SwiftUI `.task(id:)` owns it — when a row scrolls off
    /// screen the task is cancelled and its decode stops, so effort stays focused on
    /// the rows actually visible. Concurrent calls (one per visible row) decode in
    /// parallel across videos.
    /// The already-decoded preview for a result, if it's in the session cache — a
    /// synchronous peek so a row can show its thumbnail on first render (and across
    /// table-cell reuse) without a flash of empty placeholder.
    func cachedThumbnail(for result: SearchResult) -> NSImage? {
        thumbCache.object(forKey: result.id as NSString)
    }

    func thumbnail(for result: SearchResult) async -> NSImage? {
        if let cached = thumbCache.object(forKey: result.id as NSString) { return cached }
        guard let cgImage = await extractor.thumbnail(at: result.ts), !Task.isCancelled,
              let image = Self.downscaled(cgImage, maxDimension: 400) else { return nil }
        thumbCache.setObject(image, forKey: result.id as NSString)
        return image
    }

    /// Downscale a decoded frame to at most `maxDimension` on its long side — a
    /// retina-crisp preview for the ~52pt squircle without caching full frames.
    private static func downscaled(_ cgImage: CGImage, maxDimension: Int) -> NSImage? {
        let longSide = max(cgImage.width, cgImage.height)
        let scale = longSide > maxDimension ? Double(maxDimension) / Double(longSide) : 1.0
        let w = max(1, Int((Double(cgImage.width) * scale).rounded()))
        let h = max(1, Int((Double(cgImage.height) * scale).rounded()))
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSImage(cgImage: scaled, size: NSSize(width: w, height: h))
    }
}

/// Builds a two-line-friendly, highlighted snippet centered on the first match.
enum SnippetBuilder {
    private static let contextBefore = 40
    private static let contextAfter = 90

    static func make(_ text: String, query: String) -> AttributedString {
        guard let matchRange = text.range(of: query, options: .caseInsensitive) else {
            return AttributedString(String(text.prefix(160)))
        }

        let windowStart = text.index(matchRange.lowerBound, offsetBy: -contextBefore,
                                     limitedBy: text.startIndex) ?? text.startIndex
        let windowEnd = text.index(matchRange.upperBound, offsetBy: contextAfter,
                                   limitedBy: text.endIndex) ?? text.endIndex

        let window = String(text[windowStart..<windowEnd])
        var attr = AttributedString()

        if windowStart > text.startIndex {
            attr += AttributedString("… ")
        }

        if let localMatch = window.range(of: query, options: .caseInsensitive) {
            attr += AttributedString(String(window[window.startIndex..<localMatch.lowerBound]))

            var highlight = AttributedString(String(window[localMatch]))
            highlight.foregroundColor = .black
            highlight.backgroundColor = .yellow
            highlight.font = .system(size: 13, weight: .semibold)
            attr += highlight

            attr += AttributedString(String(window[localMatch.upperBound...]))
        } else {
            attr += AttributedString(window)
        }

        if windowEnd < text.endIndex {
            attr += AttributedString(" …")
        }
        return attr
    }
}
