import Foundation
import SQLite3

@MainActor
final class SearchController: ObservableObject {
    @Published var query: String = ""
    @Published var results: [SearchResult] = []
    @Published var isSearching: Bool = false
    @Published var currentResultIndex: Int = 0

    private var dbPath: String
    private var resultCache: [String: [SearchResult]] = [:]
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    struct SearchResult: Identifiable {
        let id: Int
        let text: String
        let timestamp: Double
        let segmentId: String?
        let confidence: Double

        var formattedTime: String {
            let date = Date(timeIntervalSince1970: timestamp)
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm:ss a"
            return formatter.string(from: date)
        }

        var snippet: String {
            let maxLength = 100
            if text.count <= maxLength {
                return text
            }
            return String(text.prefix(maxLength)) + "..."
        }
    }

    init(databasePath: String) {
        self.dbPath = databasePath
    }

    func search(query: String, minConfidence: Double = 0.5) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            await MainActor.run {
                self.results = []
                self.currentResultIndex = 0
            }
            return
        }

        await MainActor.run {
            self.isSearching = true
        }

        // Check cache first
        if let cachedResults = getCachedResults(for: query) {
            await MainActor.run {
                self.results = cachedResults
                self.currentResultIndex = 0
                self.isSearching = false
            }
            return
        }

        // Perform FTS5 search
        let searchResults = await performFTS5Search(query: query, minConfidence: minConfidence)

        // Update cache
        cacheResults(searchResults, for: query)

        await MainActor.run {
            self.results = searchResults
            self.currentResultIndex = 0
            self.isSearching = false
        }
    }

    private func getCachedResults(for query: String) -> [SearchResult]? {
        guard let results = resultCache[query],
              let timestamp = cacheTimestamps[query],
              Date().timeIntervalSince(timestamp) < cacheTTL else {
            return nil
        }
        return results
    }

    private func cacheResults(_ results: [SearchResult], for query: String) {
        resultCache[query] = results
        cacheTimestamps[query] = Date()

        // Keep cache size reasonable (max 10 queries)
        if resultCache.count > 10 {
            let oldestQuery = cacheTimestamps.min { $0.value < $1.value }?.key
            if let key = oldestQuery {
                resultCache.removeValue(forKey: key)
                cacheTimestamps.removeValue(forKey: key)
            }
        }
    }

    private func performFTS5Search(query: String, minConfidence: Double) async -> [SearchResult] {
        return await Task.detached(priority: .userInitiated) {
            var results: [SearchResult] = []
            var db: OpaquePointer?

            // Open database in read-only mode
            let flags = SQLITE_OPEN_READONLY
            guard sqlite3_open_v2(self.dbPath, &db, flags, nil) == SQLITE_OK else {
                print("[SearchController] Failed to open database: \(self.dbPath)")
                return results
            }

            defer {
                sqlite3_close(db)
            }

            // Prepare FTS5 search query
            let sql = """
                SELECT
                    o.id,
                    o.text_content,
                    o.timestamp,
                    o.segment_id,
                    o.confidence,
                    s.rank
                FROM ocr_text o
                JOIN ocr_search s ON o.id = s.rowid
                WHERE s.text_content MATCH ?
                AND o.confidence >= ?
                ORDER BY s.rank
                LIMIT 100
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                let error = String(cString: sqlite3_errmsg(db))
                print("[SearchController] Failed to prepare statement: \(error)")
                return results
            }

            defer {
                sqlite3_finalize(statement)
            }

            // Bind parameters
            sqlite3_bind_text(statement, 1, query, -1, nil)
            sqlite3_bind_double(statement, 2, minConfidence)

            // Execute query and collect results
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int64(statement, 0))
                let text = String(cString: sqlite3_column_text(statement, 1))
                let timestamp = sqlite3_column_double(statement, 2)
                let segmentIdPtr = sqlite3_column_text(statement, 3)
                let segmentId = segmentIdPtr != nil ? String(cString: segmentIdPtr!) : nil
                let confidence = sqlite3_column_double(statement, 4)

                let result = SearchResult(
                    id: id,
                    text: text,
                    timestamp: timestamp,
                    segmentId: segmentId,
                    confidence: confidence
                )
                results.append(result)
            }

            print("[SearchController] Search '\(query)' returned \(results.count) results")
            return results
        }.value
    }

    func jumpToResult(_ result: SearchResult) {
        // This will be called by the UI to jump to a specific timestamp
        // The TimelineStore will handle the actual navigation
        NotificationCenter.default.post(
            name: NSNotification.Name("JumpToTimestamp"),
            object: nil,
            userInfo: ["timestamp": result.timestamp]
        )
    }

    func nextResult() {
        guard !results.isEmpty else { return }
        currentResultIndex = (currentResultIndex + 1) % results.count
        if currentResultIndex < results.count {
            jumpToResult(results[currentResultIndex])
        }
    }

    func previousResult() {
        guard !results.isEmpty else { return }
        currentResultIndex = (currentResultIndex - 1 + results.count) % results.count
        if currentResultIndex < results.count {
            jumpToResult(results[currentResultIndex])
        }
    }

    func clearSearch() {
        query = ""
        results = []
        currentResultIndex = 0
    }

    var resultCountText: String {
        guard !results.isEmpty else { return "No results" }
        return "\(currentResultIndex + 1) of \(results.count)"
    }
}
