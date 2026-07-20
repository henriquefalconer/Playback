// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import CryptoKit
import SQLite3
import os

/// Registers the OCR search-index upgrade as a `DataMigration` so it runs through
/// the shared migration coordinator + dialog. All the actual work lives in
/// `SearchIndexMigrator`; this is just the adapter.
struct SearchIndexMigration: DataMigration {
    let id = "ocr-compact-v2"

    func isPending(dbPath: String) -> Bool {
        SearchIndexMigrator.isPending(dbPath: dbPath)
    }

    func run(dbPath: String, key: SymmetricKey, progress: @escaping (MigrationProgress) -> Void) {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            Log.search.error("SearchIndexMigration: could not open database")
            return
        }
        defer { sqlite3_close(db) }
        // The upgrade takes a write lock and VACUUMs; wait out any writer.
        sqlite3_busy_timeout(db, 30_000)
        SearchIndexMigrator.migrateIfNeeded(db: db, key: key, progress: progress)
    }
}
