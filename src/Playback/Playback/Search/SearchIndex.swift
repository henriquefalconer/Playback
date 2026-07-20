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

/// One page of results plus a cursor for fetching the next (older) page.
struct OCRSearchPage: Sendable {
    let results: [SearchResult]
    /// Timestamp of the last candidate row scanned — the exclusive upper bound for
    /// the next page. Nil when the page scanned no rows.
    let lastTS: TimeInterval?
    /// True when fewer than a full page of candidates remained, i.e. no older
    /// matches exist beyond this page.
    let reachedEnd: Bool
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

    /// Fetch one page of matches, newest-first, bounded to moments at or before
    /// `upperTS` (the timeline position when search opened). `beforeTS`, when set,
    /// pages further back: only rows strictly older than it are returned. Each
    /// candidate is decrypted and exact-substring verified before inclusion.
    func search(_ rawQuery: String, maxResults: Int, upperTS: TimeInterval, beforeTS: TimeInterval?) -> OCRSearchPage {
        let normalizedQuery = Trigrams.normalize(rawQuery)
        let shingles = Trigrams.shingles(normalizedQuery)
        guard !shingles.isEmpty, let db = openIfNeeded() else {
            return OCRSearchPage(results: [], lastTS: nil, reachedEnd: true)
        }

        let (key, tokenKey) = keys()
        // Cap the number of trigram filters so a very long query can't blow past
        // SQLite's bound-parameter limit. Any subset is a valid pre-filter — the
        // exact-substring verify below still guarantees correctness.
        let tokens = shingles.prefix(64).map { SearchCrypto.token(for: $0, tokenKey: tokenKey) }
        let needle = normalizedQuery.lowercased()

        // First page bounds inclusively at the open moment (`<= upperTS`); later
        // pages page strictly past the previous page's last row (`< beforeTS`).
        let tsClause = beforeTS == nil ? "AND f.ts <= ?" : "AND f.ts < ?"
        let tsBound = beforeTS ?? upperTS

        // Frames whose trigram set contains ALL query tokens, newest first.
        let placeholders = Array(repeating: "?", count: tokens.count).joined(separator: ",")
        let sql = """
            SELECT f.id, f.ts, f.app_id, f.text_cipher
            FROM ocr_frames f
            WHERE f.rowid IN (
                SELECT fid FROM ocr_trigrams WHERE tok IN (\(placeholders))
                GROUP BY fid HAVING COUNT(DISTINCT tok) = ?
            )
            \(tsClause)
            ORDER BY f.ts DESC
            LIMIT ?;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return OCRSearchPage(results: [], lastTS: nil, reachedEnd: true)
        }
        defer { sqlite3_finalize(stmt) }

        var bindIndex: Int32 = 1
        for token in tokens {
            token.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, bindIndex, raw.baseAddress, Int32(token.count), SQLITE_TRANSIENT)
            }
            bindIndex += 1
        }
        sqlite3_bind_int(stmt, bindIndex, Int32(tokens.count)); bindIndex += 1
        sqlite3_bind_double(stmt, bindIndex, tsBound); bindIndex += 1
        sqlite3_bind_int(stmt, bindIndex, Int32(maxResults))

        var results: [SearchResult] = []
        var lastTS: TimeInterval?
        var candidateCount = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            candidateCount += 1
            let ts = sqlite3_column_double(stmt, 1)
            lastTS = ts // cursor advances over every scanned row, matched or not
            guard let idC = sqlite3_column_text(stmt, 0),
                  let blobPtr = sqlite3_column_blob(stmt, 3) else { continue }
            let id = String(cString: idC)
            let appId = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let cipher = Data(bytes: blobPtr, count: Int(sqlite3_column_bytes(stmt, 3)))
            guard let plain = SearchCrypto.open(cipher, key: key),
                  let text = String(data: plain, encoding: .utf8) else { continue }
            // Exact-substring verify to drop trigram false positives.
            guard text.lowercased().contains(needle) else { continue }
            results.append(SearchResult(
                id: id, ts: ts, appId: appId,
                snippet: SnippetBuilder.make(text, query: normalizedQuery)
            ))
        }
        // A short page means the candidate stream is exhausted — nothing older left.
        return OCRSearchPage(results: results, lastTS: lastTS, reachedEnd: candidateCount < maxResults)
    }

    /// Fetch and decrypt the word boxes for one observation.
    func wordBoxes(for id: String) -> [WordBox] {
        guard let db = openIfNeeded() else { return [] }
        let sql = "SELECT boxes_cipher FROM ocr_frames WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW, let blobPtr = sqlite3_column_blob(stmt, 0) else { return [] }
        let cipher = Data(bytes: blobPtr, count: Int(sqlite3_column_bytes(stmt, 0)))
        let (key, _) = keys()
        guard let plain = SearchCrypto.open(cipher, key: key),
              let boxes = try? JSONDecoder().decode([WordBox].self, from: plain) else { return [] }
        return boxes
    }

    /// Fetch and decrypt the preview thumbnail (JPEG data) for one observation.
    func thumbnailData(for id: String) -> Data? {
        guard let db = openIfNeeded() else { return nil }
        let sql = "SELECT thumb_cipher FROM ocr_frames WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW, let blobPtr = sqlite3_column_blob(stmt, 0) else { return nil }
        let cipher = Data(bytes: blobPtr, count: Int(sqlite3_column_bytes(stmt, 0)))
        let (key, _) = keys()
        return SearchCrypto.open(cipher, key: key)
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
    /// True when the result set was clamped to `resultCap` (older matches exist
    /// beyond what the ruler/list cover).
    @Published private(set) var didHitCap = false

    private let store: OCRStore
    private let thumbCache = NSCache<NSString, NSImage>()
    /// The whole match set is loaded in one pass so the ruler can span every date
    /// and clicking it can scroll to any result. Capped to bound memory/time; the
    /// most recent `resultCap` matches (within the date limit) are kept.
    private let resultCap = 2000
    private var searchTask: Task<Void, Never>?

    private var currentQuery = ""

    init() {
        self.store = OCRStore(path: Paths.databasePath.path)
        thumbCache.countLimit = 300
    }

    /// Open the search session; nothing to preload.
    func activate() {}

    func deactivate() {
        searchTask?.cancel()
        searchTask = nil
        results = []
        hasQuery = false
        isSearching = false
        didHitCap = false
        currentQuery = ""
        thumbCache.removeAllObjects()
        Task { await store.close() }
    }

    func search(_ rawQuery: String) {
        currentQuery = rawQuery
        hasQuery = !rawQuery.trimmingCharacters(in: .whitespaces).isEmpty
        searchTask?.cancel()
        guard hasQuery else {
            results = []
            isSearching = false
            didHitCap = false
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
            // One indexed scan pulls the entire match set (newest-first, capped),
            // so the ruler covers every date and any result can be scrolled to.
            let page = await store.search(rawQuery, maxResults: resultCap, upperTS: .greatestFiniteMagnitude, beforeTS: nil)
            if Task.isCancelled || rawQuery != self.currentQuery { return }
            self.results = page.results
            self.didHitCap = !page.reachedEnd
            self.isSearching = false
        }
    }

    /// Normalized bounding boxes (Vision coords) of the words the query matched
    /// within a given frame — used to highlight the exact spot on the video.
    func highlightRects(for id: String, query: String) async -> [CGRect] {
        let needle = Trigrams.normalize(query).lowercased()
        guard needle.count >= Trigrams.minLength else { return [] }
        let words = await store.wordBoxes(for: id)
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

    /// Decrypt (or return cached) the preview thumbnail for a result.
    func thumbnail(for id: String, completion: @escaping (NSImage?) -> Void) {
        if let cached = thumbCache.object(forKey: id as NSString) {
            completion(cached)
            return
        }
        Task { [weak self] in
            guard let self else { completion(nil); return }
            let data = await store.thumbnailData(for: id)
            guard let data, let image = NSImage(data: data) else {
                completion(nil)
                return
            }
            self.thumbCache.setObject(image, forKey: id as NSString)
            completion(image)
        }
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
