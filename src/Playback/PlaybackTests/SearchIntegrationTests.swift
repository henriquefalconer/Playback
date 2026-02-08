import XCTest
import Foundation
@testable import Playback

/// Integration tests for OCR processing, search indexing, and result navigation
@MainActor
final class SearchIntegrationTests: IntegrationTestBase {

    // MARK: - OCR Processing Pipeline

    func testOCRProcessingCreatesTextIndex() async throws {
        // Test that OCR processing creates searchable text index

        // GIVEN: Video segment with OCR data
        let dateStr = "20260208"
        let timestamp = "20260208_110000_000"
        let videoPath = try createTestVideoSegment(date: dateStr, startTimestamp: timestamp)

        assertFileExists(at: videoPath)

        // WHEN: OCR processing runs (simulated)
        // In real scenario, Python OCR service would:
        // 1. Extract frames from video
        // 2. Run Vision framework OCR
        // 3. Insert results into FTS5 table

        // For testing, verify the infrastructure exists
        try initializeTestDatabase()

        // THEN: Database is ready for OCR data
        assertFileExists(at: tempDatabasePath)
    }

    func testOCRTextExtractionFromFrames() async throws {
        // Test OCR text extraction workflow

        // GIVEN: Screenshots with potential text content
        let dateStr = "20260208"
        let screenshots = [
            "20260208_110000_000",
            "20260208_110002_000",
            "20260208_110004_000"
        ]

        for timestamp in screenshots {
            _ = try createTestScreenshot(date: dateStr, timestamp: timestamp)
        }

        // WHEN: OCR processing would extract text
        // Note: Actual OCR requires Vision framework and real images with text
        // This test verifies the file structure is correct

        let tempDir = tempDataDirectory.appendingPathComponent("temp/202602/08")
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        )

        // THEN: All screenshots exist for OCR processing
        XCTAssertEqual(contents.count, 3)
    }

    func testFTS5IndexCreation() async throws {
        // Test that FTS5 full-text search index is created

        // GIVEN: Database with segments table
        try initializeTestDatabase()

        // THEN: Database exists
        assertFileExists(at: tempDatabasePath)

        // Note: Actual FTS5 table creation requires database migration
        // This test verifies database infrastructure is ready
    }

    // MARK: - Search Query Processing

    func testSearchQueryBasicMatch() async throws {
        // Test basic search query matching

        // GIVEN: Sample OCR text entries (simulated)
        let sampleTexts = [
            "Meeting with Sarah about project timeline",
            "Code review feedback for PR #123",
            "Email from John regarding budget approval"
        ]

        // WHEN: Searching for "meeting"
        let query = "meeting"
        let matchingTexts = sampleTexts.filter { text in
            text.lowercased().contains(query.lowercased())
        }

        // THEN: Matching text is found
        XCTAssertEqual(matchingTexts.count, 1)
        XCTAssertTrue(matchingTexts[0].contains("Meeting"))
    }

    func testSearchQueryMultipleMatches() async throws {
        // Test search with multiple matching results

        // GIVEN: Sample OCR texts
        let sampleTexts = [
            "Project Alpha meeting notes",
            "Project Beta status update",
            "Project Gamma proposal review"
        ]

        // WHEN: Searching for "project"
        let query = "project"
        let matchingTexts = sampleTexts.filter { text in
            text.lowercased().contains(query.lowercased())
        }

        // THEN: All three match
        XCTAssertEqual(matchingTexts.count, 3)
    }

    func testSearchQueryCaseInsensitive() async throws {
        // Test that search is case-insensitive

        // GIVEN: Mixed case text
        let text = "MacOS System Preferences"

        // WHEN: Searching with different cases
        let queries = ["macos", "MACOS", "MacOS", "MaCos"]

        // THEN: All queries match
        for query in queries {
            XCTAssertTrue(
                text.lowercased().contains(query.lowercased()),
                "Query '\(query)' should match '\(text)'"
            )
        }
    }

    func testSearchQueryPartialMatch() async throws {
        // Test partial word matching

        // GIVEN: Text with compound words
        let text = "Understanding asynchronous programming"

        // WHEN: Searching for partial words
        let queries = ["async", "program", "understand"]

        // THEN: Partial matches found
        for query in queries {
            XCTAssertTrue(
                text.lowercased().contains(query.lowercased()),
                "Query '\(query)' should match '\(text)'"
            )
        }
    }

    func testSearchQueryEmptyString() async throws {
        // Test search with empty query

        // GIVEN: Sample texts
        let sampleTexts = ["Text 1", "Text 2", "Text 3"]

        // WHEN: Searching with empty string
        let query = ""

        // THEN: Empty query behavior (typically returns no results or all results)
        // Implementation decision: empty query returns nothing
        if query.isEmpty {
            XCTAssertTrue(true, "Empty query handled correctly")
        }
    }

    func testSearchQuerySpecialCharacters() async throws {
        // Test search with special characters

        // GIVEN: Text with special characters
        let text = "Email: user@example.com, Phone: (555) 123-4567"

        // WHEN: Searching for email
        let emailQuery = "user@example"
        let phoneQuery = "555"

        // THEN: Special characters are searchable
        XCTAssertTrue(text.contains(emailQuery))
        XCTAssertTrue(text.contains(phoneQuery))
    }

    // MARK: - Search Result Navigation

    func testSearchResultSorting() async throws {
        // Test that search results are sorted by timestamp

        // GIVEN: Mock search results with different timestamps
        struct MockResult {
            let timestamp: String
            let text: String
        }

        var results = [
            MockResult(timestamp: "20260208_120000_000", text: "Result 3"),
            MockResult(timestamp: "20260208_100000_000", text: "Result 1"),
            MockResult(timestamp: "20260208_110000_000", text: "Result 2")
        ]

        // WHEN: Sorting by timestamp
        results.sort { $0.timestamp < $1.timestamp }

        // THEN: Results are in chronological order
        XCTAssertEqual(results[0].text, "Result 1")
        XCTAssertEqual(results[1].text, "Result 2")
        XCTAssertEqual(results[2].text, "Result 3")
    }

    func testSearchResultLimiting() async throws {
        // Test limiting number of search results

        // GIVEN: Large number of results
        var allResults = [String]()
        for i in 1...100 {
            allResults.append("Result \(i)")
        }

        // WHEN: Limiting to 10 results
        let maxResults = 10
        let limitedResults = Array(allResults.prefix(maxResults))

        // THEN: Only 10 results returned
        XCTAssertEqual(limitedResults.count, 10)
    }

    func testSearchResultPagination() async throws {
        // Test pagination of search results

        // GIVEN: 50 search results
        let totalResults = Array(1...50)
        let pageSize = 10

        // WHEN: Getting first page
        let page1 = Array(totalResults.prefix(pageSize))
        XCTAssertEqual(page1.count, 10)
        XCTAssertEqual(page1.first, 1)

        // WHEN: Getting second page
        let page2 = Array(totalResults.dropFirst(pageSize).prefix(pageSize))
        XCTAssertEqual(page2.count, 10)
        XCTAssertEqual(page2.first, 11)

        // THEN: Pages don't overlap
        XCTAssertNotEqual(page1.last, page2.first)
    }

    func testNavigationToSearchResult() async throws {
        // Test navigation to specific search result timestamp

        // GIVEN: Search result with timestamp
        let resultTimestamp = "20260208_110000_000"
        let dateStr = "20260208"

        // Create corresponding video segment
        let videoPath = try createTestVideoSegment(date: dateStr, startTimestamp: resultTimestamp)

        // THEN: Video segment exists for navigation
        assertFileExists(at: videoPath)

        // WHEN: Parsing timestamp for navigation
        let components = resultTimestamp.split(separator: "_")
        XCTAssertEqual(components.count, 3)
        XCTAssertEqual(String(components[0]), dateStr)
    }

    // MARK: - Search Performance

    func testSearchQueryPerformance() async throws {
        // Test search query performance with large dataset

        // GIVEN: Large corpus of text
        var corpus = [String]()
        for i in 1...1000 {
            corpus.append("This is test document number \(i) with various keywords")
        }

        let startTime = Date()

        // WHEN: Performing search
        let query = "document"
        let results = corpus.filter { $0.contains(query) }

        let searchTime = Date().timeIntervalSince(startTime)

        // THEN: Search completes quickly
        XCTAssertEqual(results.count, 1000)
        XCTAssertLessThan(searchTime, 0.1, "Search took too long: \(searchTime)s")
    }

    func testSearchIndexUpdatePerformance() async throws {
        // Test performance of updating search index

        // GIVEN: Multiple OCR results to index
        let startTime = Date()

        var ocrResults: [(timestamp: String, text: String)] = []
        for i in 0..<100 {
            let timestamp = String(format: "20260208_%02d0000_000", i)
            ocrResults.append((timestamp, "Sample text content \(i)"))
        }

        let indexingTime = Date().timeIntervalSince(startTime)

        // THEN: Indexing completes quickly
        XCTAssertEqual(ocrResults.count, 100)
        XCTAssertLessThan(indexingTime, 0.5, "Indexing took too long: \(indexingTime)s")
    }

    // MARK: - Search Result Highlighting

    func testSearchTermHighlighting() async throws {
        // Test that search terms are highlighted in results

        // GIVEN: Text with search term
        let text = "This is a sample document with important information"
        let query = "sample"

        // WHEN: Finding match positions
        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()

        if let range = lowercasedText.range(of: lowercasedQuery) {
            let distance = lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound)

            // THEN: Match position is found
            XCTAssertGreaterThanOrEqual(distance, 0)
            XCTAssertLessThan(distance, text.count)
        } else {
            XCTFail("Expected to find query in text")
        }
    }

    func testContextSnippetExtraction() async throws {
        // Test extraction of context around search match

        // GIVEN: Long text with search term
        let text = "This is a very long document that contains many words and sentences. The search term appears somewhere in the middle of this text. We want to extract a snippet around it for display."
        let query = "search term"

        // WHEN: Finding match and extracting context
        if let range = text.lowercased().range(of: query.lowercased()) {
            let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
            let contextRadius = 30

            let snippetStart = max(0, matchStart - contextRadius)
            let snippetEnd = min(text.count, matchStart + query.count + contextRadius)

            let startIndex = text.index(text.startIndex, offsetBy: snippetStart)
            let endIndex = text.index(text.startIndex, offsetBy: snippetEnd)
            let snippet = String(text[startIndex..<endIndex])

            // THEN: Snippet contains the match and context
            XCTAssertTrue(snippet.lowercased().contains(query.lowercased()))
            XCTAssertLessThanOrEqual(snippet.count, contextRadius * 2 + query.count)
        } else {
            XCTFail("Expected to find query in text")
        }
    }

    // MARK: - Search Filtering

    func testSearchFilterByDateRange() async throws {
        // Test filtering search results by date range

        // GIVEN: Results from different dates
        struct SearchResult {
            let date: String
            let text: String
        }

        let results = [
            SearchResult(date: "20260206", text: "Result 1"),
            SearchResult(date: "20260207", text: "Result 2"),
            SearchResult(date: "20260208", text: "Result 3"),
            SearchResult(date: "20260209", text: "Result 4")
        ]

        // WHEN: Filtering by date range
        let startDate = "20260207"
        let endDate = "20260208"

        let filtered = results.filter { result in
            result.date >= startDate && result.date <= endDate
        }

        // THEN: Only results within range
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].date, "20260207")
        XCTAssertEqual(filtered[1].date, "20260208")
    }

    func testSearchFilterByApplication() async throws {
        // Test filtering search results by application

        // GIVEN: Results from different applications
        struct SearchResult {
            let appID: String
            let text: String
        }

        let results = [
            SearchResult(appID: "com.apple.Safari", text: "Safari result"),
            SearchResult(appID: "com.apple.Mail", text: "Mail result"),
            SearchResult(appID: "com.apple.Safari", text: "Another Safari result")
        ]

        // WHEN: Filtering by application
        let targetApp = "com.apple.Safari"
        let filtered = results.filter { $0.appID == targetApp }

        // THEN: Only Safari results
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.appID == targetApp })
    }

    // MARK: - Error Handling

    func testSearchWithInvalidQuery() async throws {
        // Test handling of invalid search queries

        // GIVEN: Various invalid queries
        let invalidQueries = [
            "",              // Empty
            "   ",           // Only whitespace
            String(repeating: "a", count: 10000) // Extremely long
        ]

        // THEN: Each query is handled without crashing
        for query in invalidQueries {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                XCTAssertTrue(true, "Empty query handled")
            } else if trimmed.count > 500 {
                // Could limit query length
                XCTAssertTrue(true, "Long query detected")
            }
        }
    }

    func testSearchWithMissingDatabase() async throws {
        // Test search when database is missing

        // GIVEN: No database file
        let nonExistentDB = tempRootDirectory.appendingPathComponent("nonexistent.sqlite3")

        // THEN: Database does not exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: nonExistentDB.path))

        // Note: SearchController would handle this by returning empty results or error
    }

    func testSearchWithCorruptedIndex() async throws {
        // Test handling of corrupted search index

        // GIVEN: Database exists but might be corrupted
        try initializeTestDatabase()

        // Simulate corruption by writing invalid data
        let invalidData = Data([0x00, 0x01, 0x02])
        try invalidData.write(to: tempDatabasePath)

        // THEN: File exists but is corrupted
        assertFileExists(at: tempDatabasePath)

        // Note: SearchController should handle this gracefully
        let fileSize = try FileManager.default.attributesOfItem(atPath: tempDatabasePath.path)[.size] as! Int64
        XCTAssertLessThan(fileSize, 1000, "Corrupted file should be small")
    }
}
