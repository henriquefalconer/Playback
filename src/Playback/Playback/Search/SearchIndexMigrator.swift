// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import CryptoKit
import SQLite3
import os

private let SQLITE_TRANSIENT_MIG = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// One-time, in-place upgrade of a pre-compaction OCR index to the compact format:
///
/// * `text_cipher` is re-sealed as `AES-GCM(DEFLATE(text))` instead of `AES-GCM(text)`.
/// * the flat `ocr_trigrams(tok, fid)` table (a token repeated once per posting,
///   plus a duplicate covering index) is folded into `ocr_postings(tok, fids)`,
///   where each token stores its ascending frame ids once as delta varints.
/// * the `thumb_cipher` / `boxes_cipher` columns are dropped — previews and word
///   boxes are now re-derived from the video on demand.
/// * `VACUUM` reclaims the freed pages so the file actually shrinks.
///
/// It runs inside a single transaction, so it is atomic: a crash leaves the old
/// format fully intact and the upgrade simply retries. Re-encoded rows are produced
/// by the exact same pipeline as freshly-indexed frames, so migrated data is
/// indistinguishable from natively-written data.
enum SearchIndexMigrator {
    /// True when the OCR index is still below the current version AND holds legacy
    /// data that must be converted. Opens its own read-only connection and needs no
    /// key, so a launcher can call it before deciding whether to show any UI.
    static func isPending(dbPath: String) -> Bool {
        guard FileManager.default.fileExists(atPath: dbPath) else { return false }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return false
        }
        defer { sqlite3_close(db) }
        guard SchemaVersions.tableExists(db, "ocr_frames") else { return false } // no index yet
        guard SchemaVersions.version(.ocr, db: db) < SchemaComponent.ocr.current else { return false }
        return SchemaVersions.ocrIsLegacy(db: db)
    }

    static func migrateIfNeeded(db: OpaquePointer, key: SymmetricKey, progress: ((MigrationProgress) -> Void)? = nil) {
        let target = SchemaComponent.ocr.current
        guard SchemaVersions.version(.ocr, db: db) < target else { return }
        // Be self-contained: on an old database the compact tables may not exist yet.
        exec(db, "CREATE TABLE IF NOT EXISTS ocr_postings (tok BLOB PRIMARY KEY, fids BLOB NOT NULL) WITHOUT ROWID;")

        let hasOldTrigrams = SchemaVersions.tableExists(db, "ocr_trigrams")
        let hasThumbColumn = SchemaVersions.columnExists(db, table: "ocr_frames", column: "thumb_cipher")
        guard hasOldTrigrams || hasThumbColumn else {
            // Fresh database created directly in the compact format — just stamp it.
            SchemaVersions.set(.ocr, to: target, db: db)
            return
        }

        Log.search.notice("OCR index migration → v\(target, privacy: .public): starting")
        let sizeBefore = fileSize()

        guard exec(db, "BEGIN IMMEDIATE TRANSACTION;") else { return }

        // Phase 1 (0–50%): re-seal text as compressed. Phase 2 (50–85%): build
        // posting lists. Phase 3 (85–100%, indeterminate): VACUUM.
        let migrating = "Migrating your data…"
        if !reencodeText(db, key: key, progress: { progress?(MigrationProgress(fraction: $0 * 0.5, label: migrating)) }) {
            exec(db, "ROLLBACK;")
            Log.search.error("OCR index migration aborted during text re-encode — left unchanged for retry")
            return
        }
        if hasOldTrigrams {
            guard buildPostings(db, progress: { progress?(MigrationProgress(fraction: 0.5 + $0 * 0.35, label: migrating)) }) else {
                exec(db, "ROLLBACK;")
                Log.search.error("OCR index migration aborted during posting build — left unchanged for retry")
                return
            }
            exec(db, "DROP TABLE ocr_trigrams;")
        }
        // These fail harmlessly if the column is already gone; ignore the result.
        exec(db, "ALTER TABLE ocr_frames DROP COLUMN thumb_cipher;")
        exec(db, "ALTER TABLE ocr_frames DROP COLUMN boxes_cipher;")
        SchemaVersions.set(.ocr, to: target, db: db)

        guard exec(db, "COMMIT;") else {
            Log.search.error("OCR index migration commit failed")
            return
        }
        // VACUUM cannot run inside a transaction; do it after committing.
        progress?(MigrationProgress(fraction: nil, label: migrating))
        exec(db, "VACUUM;")
        progress?(MigrationProgress(fraction: 1.0, label: migrating))

        let sizeAfter = fileSize()
        Log.search.notice("OCR index migration → v\(target, privacy: .public): done — \(sizeBefore / 1_048_576, privacy: .public) MB → \(sizeAfter / 1_048_576, privacy: .public) MB")
    }

    // MARK: - Text re-encode

    private static func reencodeText(_ db: OpaquePointer, key: SymmetricKey, progress: (Double) -> Void) -> Bool {
        // Collect (rowid, new cipher) first so the read cursor is closed before we
        // write. New ciphers are compressed, so this holds only ~the compressed text.
        var updates: [(rowid: Int64, cipher: Data)] = []
        var dead: [Int64] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT rowid, text_cipher FROM ocr_frames;", -1, &stmt, nil) == SQLITE_OK, let stmt else { return false }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowid = sqlite3_column_int64(stmt, 0)
            guard let ptr = sqlite3_column_blob(stmt, 1) else { continue }
            let cipher = Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 1)))
            if let plain = SearchCrypto.open(cipher, key: key),
               let resealed = SearchCrypto.seal(SearchCompression.compress(plain), key: key) {
                updates.append((rowid, resealed))
            } else {
                // Undecryptable: encrypted under a key that no longer exists (an old
                // dev-era key rotation), so it can never be searched or shown. Drop
                // it — it's pure dead weight, and re-indexing rebuilds what it can.
                dead.append(rowid)
            }
        }
        sqlite3_finalize(stmt)
        Log.search.notice("OCR migration reencode — keep=\(updates.count, privacy: .public), drop-undecryptable=\(dead.count, privacy: .public)")

        // Safety: if NOTHING decrypted yet rows exist, the key is wrong or momentarily
        // unavailable (not that every row is genuinely orphaned). Abort so the caller
        // rolls back and retries later — never drop the whole index on a bad key.
        if updates.isEmpty && !dead.isEmpty {
            Log.search.fault("OCR migration: 0 of \(dead.count, privacy: .public) rows decrypted — key wrong/unavailable; aborting to preserve data")
            return false
        }

        var up: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE ocr_frames SET text_cipher = ? WHERE rowid = ?;", -1, &up, nil) == SQLITE_OK, let up else { return false }
        let total = max(1, updates.count)
        for (i, update) in updates.enumerated() {
            sqlite3_reset(up)
            update.cipher.withUnsafeBytes { raw in
                sqlite3_bind_blob(up, 1, raw.baseAddress, Int32(update.cipher.count), SQLITE_TRANSIENT_MIG)
            }
            sqlite3_bind_int64(up, 2, update.rowid)
            guard sqlite3_step(up) == SQLITE_DONE else { sqlite3_finalize(up); return false }
            if i % 256 == 0 { progress(Double(i) / Double(total)) }
        }
        sqlite3_finalize(up)

        // Delete dead frames by rowid (the PK — fast). Their trigrams are excluded
        // later by the live-frame join in buildPostings, so no per-fid scan needed.
        if !dead.isEmpty {
            var del: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM ocr_frames WHERE rowid = ?;", -1, &del, nil) == SQLITE_OK, let del else { return false }
            defer { sqlite3_finalize(del) }
            for rowid in dead {
                sqlite3_reset(del)
                sqlite3_bind_int64(del, 1, rowid)
                guard sqlite3_step(del) == SQLITE_DONE else { return false }
            }
        }
        progress(1.0)
        return true
    }

    // MARK: - Posting build

    private static func buildPostings(_ db: OpaquePointer, progress: (Double) -> Void) -> Bool {
        let totalToks = max(1, scalarInt(db, "SELECT COUNT(DISTINCT tok) FROM ocr_trigrams;"))

        // Join to ocr_frames so trigrams of dropped (undecryptable) frames are
        // excluded — postings only ever reference live, decryptable frames.
        var read: OpaquePointer?
        guard sqlite3_prepare_v2(db, """
            SELECT DISTINCT t.tok, t.fid FROM ocr_trigrams t
            JOIN ocr_frames f ON f.rowid = t.fid
            ORDER BY t.tok, t.fid;
            """, -1, &read, nil) == SQLITE_OK, let read else { return false }
        defer { sqlite3_finalize(read) }

        var write: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO ocr_postings (tok, fids) VALUES (?, ?);", -1, &write, nil) == SQLITE_OK, let write else { return false }
        defer { sqlite3_finalize(write) }

        var currentTok: Data?
        var fids: [Int64] = []
        var flushed = 0

        func flush() -> Bool {
            guard let tok = currentTok, !fids.isEmpty else { return true }
            let blob = PostingCodec.encode(fids)
            sqlite3_reset(write)
            tok.withUnsafeBytes { raw in
                sqlite3_bind_blob(write, 1, raw.baseAddress, Int32(tok.count), SQLITE_TRANSIENT_MIG)
            }
            blob.withUnsafeBytes { raw in
                sqlite3_bind_blob(write, 2, raw.baseAddress, Int32(blob.count), SQLITE_TRANSIENT_MIG)
            }
            guard sqlite3_step(write) == SQLITE_DONE else { return false }
            flushed += 1
            if flushed % 512 == 0 { progress(Double(flushed) / Double(totalToks)) }
            return true
        }

        while sqlite3_step(read) == SQLITE_ROW {
            guard let ptr = sqlite3_column_blob(read, 0) else { continue }
            let tok = Data(bytes: ptr, count: Int(sqlite3_column_bytes(read, 0)))
            let fid = sqlite3_column_int64(read, 1)
            if tok != currentTok {
                if !flush() { return false }
                currentTok = tok
                fids = []
            }
            fids.append(fid)
        }
        let ok = flush()
        progress(1.0)
        return ok
    }

    private static func scalarInt(_ db: OpaquePointer, _ sql: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    // MARK: - Helpers

    @discardableResult
    private static func exec(_ db: OpaquePointer, _ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private static func fileSize() -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: Paths.databasePath.path)[.size] as? Int64) ?? 0
    }
}
