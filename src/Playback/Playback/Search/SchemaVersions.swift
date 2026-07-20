// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import SQLite3
import os

private let SQLITE_TRANSIENT_SV = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// An independently-evolving part of the database. Each carries its own integer
/// schema version in `component_versions`, so migrations are reasoned about and
/// applied per component instead of with one global number — the OCR search index
/// can rev without touching segments, and vice versa.
enum SchemaComponent: String, CaseIterable {
    case ocr
    case segments
    case appsegments

    /// The version this build writes and expects.
    ///
    /// OCR history:
    ///   1 — flat `ocr_trigrams(tok, fid)` index, stored JPEG thumbnails + word
    ///       boxes, plaintext-then-sealed text.
    ///   2 — compact `ocr_postings(tok, fids)` delta-varint index, no stored
    ///       thumbnails/boxes (re-derived from video), DEFLATE-then-sealed text.
    var current: Int {
        switch self {
        case .ocr:         return 2
        case .segments:    return 1
        case .appsegments: return 1
        }
    }
}

/// Read/write access to `component_versions`, plus the legacy-format detection the
/// OCR migration keys off of.
enum SchemaVersions {
    static func ensureTable(_ db: OpaquePointer) {
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS component_versions (
                component TEXT PRIMARY KEY,
                version INTEGER NOT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            """, nil, nil, nil)
    }

    /// The stored version of a component, or 0 when it has never been stamped
    /// (i.e. a database predating component versioning). Safe on a read-only
    /// connection — it never tries to create the table.
    static func version(_ component: SchemaComponent, db: OpaquePointer) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT version FROM component_versions WHERE component = ?;", -1, &stmt, nil) == SQLITE_OK, let stmt else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, component.rawValue, -1, SQLITE_TRANSIENT_SV)
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    static func set(_ component: SchemaComponent, to version: Int, db: OpaquePointer) {
        ensureTable(db)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO component_versions (component, version, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP);", -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, component.rawValue, -1, SQLITE_TRANSIENT_SV)
        sqlite3_bind_int64(stmt, 2, Int64(version))
        _ = sqlite3_step(stmt)
    }

    /// True when the OCR index is still in the legacy on-disk shape (flat trigram
    /// table or the old stored-thumbnail column). Used both to gate the migration
    /// and to avoid falsely stamping an un-migrated database as current.
    static func ocrIsLegacy(db: OpaquePointer) -> Bool {
        tableExists(db, "ocr_trigrams") || columnExists(db, table: "ocr_frames", column: "thumb_cipher")
    }

    /// Stamp baseline versions for components with no pending migration: segments
    /// and appsegments are stable at v1, and an OCR index with no legacy markers is
    /// stamped at its current version. Legacy OCR data is deliberately left
    /// unstamped so the launch migrator still runs. Requires a writable connection.
    static func reconcile(db: OpaquePointer) {
        ensureTable(db)
        if version(.segments, db: db) == 0 { set(.segments, to: SchemaComponent.segments.current, db: db) }
        if version(.appsegments, db: db) == 0 { set(.appsegments, to: SchemaComponent.appsegments.current, db: db) }
        if version(.ocr, db: db) == 0, !ocrIsLegacy(db: db) {
            set(.ocr, to: SchemaComponent.ocr.current, db: db)
        }
    }

    // MARK: - Introspection

    static func tableExists(_ db: OpaquePointer, _ name: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?;", -1, &stmt, nil) == SQLITE_OK, let stmt else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT_SV)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    static func columnExists(_ db: OpaquePointer, table: String, column: String) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &stmt, nil) == SQLITE_OK, let stmt else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1), String(cString: c) == column { return true }
        }
        return false
    }
}
