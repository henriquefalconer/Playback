import XCTest
import CryptoKit
import SQLite3
@testable import Playback

private let SQLITE_TRANSIENT_T = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Covers the compact OCR index: the delta-varint posting codec, the
/// compress-then-encrypt text path, and the end-to-end legacy→compact migration.
final class OCRCompactionTests: XCTestCase {

    // MARK: - PostingCodec

    func testVarintRoundtripRandomAscending() {
        var rng = SplitMix64(seed: 0xC0FFEE)
        for _ in 0..<500 {
            let count = Int(rng.next() % 400)
            var fids: [Int64] = []
            var acc: Int64 = Int64(rng.next() % 5) // may start at 0 or a small id
            for _ in 0..<count {
                acc += Int64(1 + rng.next() % 2_000) // strictly ascending
                fids.append(acc)
            }
            XCTAssertEqual(PostingCodec.decode(PostingCodec.encode(fids)), fids)
        }
    }

    func testEncodeIsCompact() {
        // 1000 postings spread over a plausible id range must pack to ~1 byte each,
        // i.e. far below the 8 bytes/posting the old flat table cost.
        let fids = (1...1000).map { Int64($0 * 70) } // avg gap 70 → 1-byte varints
        let encoded = PostingCodec.encode(fids)
        XCTAssertLessThan(encoded.count, 1600)
    }

    func testAppendEqualsRebuild() {
        let existing: [Int64] = [1, 5, 9, 100]
        let added: [Int64] = [101, 250, 999]
        let appended = PostingCodec.appending(PostingCodec.encode(existing), fids: added)
        XCTAssertEqual(PostingCodec.decode(appended), existing + added)
    }

    func testAppendDedupesAndSorts() {
        let appended = PostingCodec.appending(PostingCodec.encode([1, 4]), fids: [4, 2, 9])
        XCTAssertEqual(PostingCodec.decode(appended), [1, 2, 4, 9])
    }

    func testAppendToEmpty() {
        XCTAssertEqual(PostingCodec.decode(PostingCodec.appending(nil, fids: [3, 7])), [3, 7])
    }

    func testIntersectMatchesBruteForce() {
        var rng = SplitMix64(seed: 42)
        for _ in 0..<300 {
            let lists = (0..<Int(2 + rng.next() % 4)).map { _ -> [Int64] in
                Set((0..<Int(rng.next() % 60)).map { _ in Int64(rng.next() % 100) }).sorted()
            }
            let expected = lists.dropFirst().reduce(Set(lists[0])) { $0.intersection($1) }.sorted()
            XCTAssertEqual(PostingCodec.intersect(lists), expected)
        }
    }

    func testIntersectWithEmptyListIsEmpty() {
        XCTAssertEqual(PostingCodec.intersect([[1, 2, 3], []]), [])
    }

    // MARK: - SearchCompression

    func testCompressionRoundtripText() {
        let samples = [
            "", "a", "the quick brown fox jumps over the lazy dog",
            String(repeating: "func compress(_ data: Data) -> Data { return data }\n", count: 40),
            "/Users/vm/Playback/src/Playback/Playback/Search/OCRIndexer.swift"
        ]
        for s in samples {
            let data = Data(s.utf8)
            let out = SearchCompression.decompress(SearchCompression.compress(data))
            XCTAssertEqual(out, data, "roundtrip failed for \(s.prefix(20))")
        }
    }

    func testCompressionRoundtripIncompressible() {
        var rng = SplitMix64(seed: 7)
        var data = Data()
        for _ in 0..<4096 { data.append(UInt8(rng.next() & 0xFF)) }
        XCTAssertEqual(SearchCompression.decompress(SearchCompression.compress(data)), data)
    }

    func testCompressionShrinksRedundantText() {
        let data = Data(String(repeating: "playback ", count: 500).utf8)
        XCTAssertLessThan(SearchCompression.compress(data).count, data.count / 2)
    }

    // MARK: - Migration (legacy → compact)

    func testMigrationConvertsLegacyIndex() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dir.appendingPathComponent("meta.sqlite3").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let handle = db!

        // Build a legacy-format index: flat trigram table + stored thumb/boxes.
        exec(handle, """
            CREATE TABLE ocr_frames (id TEXT PRIMARY KEY, segment_id TEXT NOT NULL, ts REAL NOT NULL,
                app_id TEXT, text_cipher BLOB NOT NULL, thumb_cipher BLOB, boxes_cipher BLOB);
            CREATE TABLE ocr_trigrams (tok BLOB NOT NULL, fid INTEGER NOT NULL);
            CREATE INDEX idx_ocr_trigrams_tok ON ocr_trigrams(tok, fid);
        """)

        let key = SymmetricKey(size: .bits256)
        let tokenKey = SearchCrypto.deriveTokenKey(key)
        let texts = ["the quick brown fox", "lazy sleeping hound", "the brown table"]

        for (i, text) in texts.enumerated() {
            // Legacy text_cipher: sealed WITHOUT compression.
            let cipher = SearchCrypto.seal(Data(text.utf8), key: key)!
            let ins = prepare(handle, "INSERT INTO ocr_frames (id, segment_id, ts, app_id, text_cipher, thumb_cipher) VALUES (?,?,?,?,?,?);")
            sqlite3_bind_text(ins, 1, "id\(i)", -1, SQLITE_TRANSIENT_T)
            sqlite3_bind_text(ins, 2, "seg", -1, SQLITE_TRANSIENT_T)
            sqlite3_bind_double(ins, 3, Double(i))
            sqlite3_bind_null(ins, 4)
            cipher.withUnsafeBytes { sqlite3_bind_blob(ins, 5, $0.baseAddress, Int32(cipher.count), SQLITE_TRANSIENT_T) }
            let fakeThumb = Data([0xFF, 0xD8, 0xFF]) // pretend JPEG, must be dropped
            fakeThumb.withUnsafeBytes { sqlite3_bind_blob(ins, 6, $0.baseAddress, Int32(fakeThumb.count), SQLITE_TRANSIENT_T) }
            XCTAssertEqual(sqlite3_step(ins), SQLITE_DONE)
            sqlite3_finalize(ins)
            let fid = sqlite3_last_insert_rowid(handle)
            for tri in Trigrams.shingles(text) {
                let tok = SearchCrypto.token(for: tri, tokenKey: tokenKey)
                let t = prepare(handle, "INSERT INTO ocr_trigrams (tok, fid) VALUES (?, ?);")
                tok.withUnsafeBytes { sqlite3_bind_blob(t, 1, $0.baseAddress, Int32(tok.count), SQLITE_TRANSIENT_T) }
                sqlite3_bind_int64(t, 2, fid)
                XCTAssertEqual(sqlite3_step(t), SQLITE_DONE)
                sqlite3_finalize(t)
            }
        }

        XCTAssertTrue(SchemaVersions.ocrIsLegacy(db: handle))
        SearchIndexMigrator.migrateIfNeeded(db: handle, key: key)

        // Schema is now compact.
        XCTAssertFalse(SchemaVersions.tableExists(handle, "ocr_trigrams"))
        XCTAssertTrue(SchemaVersions.tableExists(handle, "ocr_postings"))
        XCTAssertFalse(SchemaVersions.columnExists(handle, table: "ocr_frames", column: "thumb_cipher"))
        XCTAssertFalse(SchemaVersions.columnExists(handle, table: "ocr_frames", column: "boxes_cipher"))
        XCTAssertEqual(SchemaVersions.version(.ocr, db: handle), SchemaComponent.ocr.current)
        XCTAssertFalse(SchemaVersions.ocrIsLegacy(db: handle))

        // Text is now compress-then-encrypt and decrypts back to the original.
        for (i, text) in texts.enumerated() {
            let sel = prepare(handle, "SELECT text_cipher FROM ocr_frames WHERE ts = ?;")
            sqlite3_bind_double(sel, 1, Double(i))
            XCTAssertEqual(sqlite3_step(sel), SQLITE_ROW)
            let cipher = Data(bytes: sqlite3_column_blob(sel, 0), count: Int(sqlite3_column_bytes(sel, 0)))
            sqlite3_finalize(sel)
            let plain = SearchCompression.decompress(SearchCrypto.open(cipher, key: key)!)!
            XCTAssertEqual(String(data: plain, encoding: .utf8), text)
        }

        // Posting lists reproduce the trigram membership: "the" occurs in frames
        // 0 and 2 (ts 0 and 2), so intersecting its trigrams yields exactly {1, 3}.
        let theTokens = Trigrams.shingles("the").map { SearchCrypto.token(for: $0, tokenKey: tokenKey) }
        let lists = theTokens.map { readPosting(handle, tok: $0) }
        XCTAssertEqual(PostingCodec.intersect(lists), [1, 3])
    }

    // MARK: - Helpers

    private func exec(_ db: OpaquePointer, _ sql: String) {
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, "exec failed: \(String(cString: sqlite3_errmsg(db)))")
    }

    private func prepare(_ db: OpaquePointer, _ sql: String) -> OpaquePointer {
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK, "prepare failed: \(String(cString: sqlite3_errmsg(db)))")
        return stmt!
    }

    private func readPosting(_ db: OpaquePointer, tok: Data) -> [Int64] {
        let stmt = prepare(db, "SELECT fids FROM ocr_postings WHERE tok = ?;")
        defer { sqlite3_finalize(stmt) }
        tok.withUnsafeBytes { sqlite3_bind_blob(stmt, 1, $0.baseAddress, Int32(tok.count), SQLITE_TRANSIENT_T) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let ptr = sqlite3_column_blob(stmt, 0) else { return [] }
        return PostingCodec.decode(Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 0))))
    }
}

/// Deterministic PRNG so property tests are reproducible across runs.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
