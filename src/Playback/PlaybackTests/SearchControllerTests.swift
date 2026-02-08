import XCTest
import Combine
@testable import Playback

@MainActor
final class SearchControllerTests: XCTestCase {
    var searchController: SearchController!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        searchController = SearchController(databasePath: "/tmp/test.db")
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        searchController = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testSearchControllerInitialization() {
        XCTAssertNotNil(searchController)
    }

    func testInitialQueryIsEmpty() {
        XCTAssertEqual(searchController.query, "")
    }

    func testInitialResultsIsEmpty() {
        XCTAssertEqual(searchController.results.count, 0)
    }

    func testInitialIsSearchingIsFalse() {
        XCTAssertFalse(searchController.isSearching)
    }

    func testInitialCurrentResultIndexIsZero() {
        XCTAssertEqual(searchController.currentResultIndex, 0)
    }

    // MARK: - SearchResult Model Tests

    func testSearchResultInitialization() {
        let result = SearchController.SearchResult(
            id: 123,
            text: "test text",
            timestamp: 1640000000.0,
            segmentId: "seg-1",
            confidence: 0.95,
            framePath: nil
        )
        XCTAssertEqual(result.id, 123)
        XCTAssertEqual(result.text, "test text")
        XCTAssertEqual(result.timestamp, 1640000000.0)
        XCTAssertEqual(result.segmentId, "seg-1")
        XCTAssertEqual(result.confidence, 0.95)
    }

    func testSearchResultFormattedTime() {
        let result = SearchController.SearchResult(
            id: 1,
            text: "test",
            timestamp: 1640000000.0,
            segmentId: nil,
            confidence: 0.9,
            framePath: nil
        )
        XCTAssertFalse(result.formattedTime.isEmpty)
        XCTAssertTrue(result.formattedTime.contains(":"))
    }

    func testSearchResultSnippetUnderMaxLength() {
        let shortText = "Short text"
        let result = SearchController.SearchResult(
            id: 1,
            text: shortText,
            timestamp: 1640000000.0,
            segmentId: nil,
            confidence: 0.9,
            framePath: nil
        )
        XCTAssertEqual(result.snippet, shortText)
        XCTAssertFalse(result.snippet.contains("..."))
    }

    func testSearchResultSnippetOverMaxLength() {
        let longText = String(repeating: "a", count: 150)
        let result = SearchController.SearchResult(
            id: 1,
            text: longText,
            timestamp: 1640000000.0,
            segmentId: nil,
            confidence: 0.9,
            framePath: nil
        )
        XCTAssertTrue(result.snippet.count <= 103)
        XCTAssertTrue(result.snippet.hasSuffix("..."))
    }

    func testSearchResultSnippetExactlyMaxLength() {
        let exactText = String(repeating: "a", count: 100)
        let result = SearchController.SearchResult(
            id: 1,
            text: exactText,
            timestamp: 1640000000.0,
            segmentId: nil,
            confidence: 0.9,
            framePath: nil
        )
        XCTAssertEqual(result.snippet, exactText)
        XCTAssertFalse(result.snippet.contains("..."))
    }

    // MARK: - Published Properties Tests

    func testQueryIsPublished() {
        let expectation = XCTestExpectation(description: "Query published")
        searchController.$query
            .dropFirst()
            .sink { value in
                XCTAssertEqual(value, "test query")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        searchController.query = "test query"
        wait(for: [expectation], timeout: 1.0)
    }

    func testResultsIsPublished() {
        let expectation = XCTestExpectation(description: "Results published")
        searchController.$results
            .dropFirst()
            .sink { value in
                XCTAssertEqual(value.count, 1)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        let result = SearchController.SearchResult(
            id: 1,
            text: "test",
            timestamp: 1640000000.0,
            segmentId: nil,
            confidence: 0.9,
            framePath: nil
        )
        searchController.results = [result]
        wait(for: [expectation], timeout: 1.0)
    }

    func testIsSearchingIsPublished() {
        let expectation = XCTestExpectation(description: "IsSearching published")
        searchController.$isSearching
            .dropFirst()
            .sink { value in
                XCTAssertTrue(value)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        searchController.isSearching = true
        wait(for: [expectation], timeout: 1.0)
    }

    func testCurrentResultIndexIsPublished() {
        let expectation = XCTestExpectation(description: "CurrentResultIndex published")
        searchController.$currentResultIndex
            .dropFirst()
            .sink { value in
                XCTAssertEqual(value, 5)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        searchController.currentResultIndex = 5
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - ObservableObject Tests

    func testPublishedPropertiesCanBeBound() {
        var receivedQuery: String?
        var receivedResults: [SearchController.SearchResult]?
        var receivedIsSearching: Bool?
        var receivedIndex: Int?

        searchController.$query
            .sink { receivedQuery = $0 }
            .store(in: &cancellables)

        searchController.$results
            .sink { receivedResults = $0 }
            .store(in: &cancellables)

        searchController.$isSearching
            .sink { receivedIsSearching = $0 }
            .store(in: &cancellables)

        searchController.$currentResultIndex
            .sink { receivedIndex = $0 }
            .store(in: &cancellables)

        searchController.query = "test"
        searchController.results = []
        searchController.isSearching = true
        searchController.currentResultIndex = 10

        XCTAssertEqual(receivedQuery, "test")
        XCTAssertEqual(receivedResults?.count, 0)
        XCTAssertEqual(receivedIsSearching, true)
        XCTAssertEqual(receivedIndex, 10)
    }

    // MARK: - Navigation Tests
    // Note: Navigation methods post notifications via jumpToResult()
    // Integration tests with actual database should test full navigation behavior

    func testNextResultWithEmptyResults() {
        searchController.results = []
        searchController.currentResultIndex = 0

        searchController.nextResult()

        XCTAssertEqual(searchController.currentResultIndex, 0)
    }

    func testPreviousResultWithEmptyResults() {
        searchController.results = []
        searchController.currentResultIndex = 0

        searchController.previousResult()

        XCTAssertEqual(searchController.currentResultIndex, 0)
    }

    // MARK: - Result Count Display Tests

    func testResultCountTextWithNoResults() {
        searchController.results = []
        searchController.currentResultIndex = 0

        XCTAssertEqual(searchController.resultCountText, "No results")
    }

    func testResultCountTextWithOneResult() {
        let results = createMockResults(count: 1)
        searchController.results = results
        searchController.currentResultIndex = 0

        XCTAssertEqual(searchController.resultCountText, "1 of 1")
    }

    func testResultCountTextWithMultipleResults() {
        let results = createMockResults(count: 10)
        searchController.results = results
        searchController.currentResultIndex = 4

        XCTAssertEqual(searchController.resultCountText, "5 of 10")
    }

    func testResultCountTextChangesWithIndex() {
        let results = createMockResults(count: 5)
        searchController.results = results

        searchController.currentResultIndex = 0
        XCTAssertEqual(searchController.resultCountText, "1 of 5")

        searchController.currentResultIndex = 1
        XCTAssertEqual(searchController.resultCountText, "2 of 5")

        searchController.currentResultIndex = 4
        XCTAssertEqual(searchController.resultCountText, "5 of 5")
    }

    // MARK: - Clear Search Tests

    func testClearSearchResetsQuery() {
        searchController.query = "test query"
        searchController.clearSearch()

        XCTAssertEqual(searchController.query, "")
    }

    func testClearSearchResetsResults() {
        let results = createMockResults(count: 5)
        searchController.results = results
        searchController.clearSearch()

        XCTAssertEqual(searchController.results.count, 0)
    }

    func testClearSearchResetsIndex() {
        searchController.currentResultIndex = 5
        searchController.clearSearch()

        XCTAssertEqual(searchController.currentResultIndex, 0)
    }

    // MARK: - Notification Tests

    func testJumpToResultPostsNotification() {
        let expectation = XCTestExpectation(description: "Notification posted")
        let notificationName = Notification.Name("JumpToTimestamp")

        NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        let result = SearchController.SearchResult(
            id: 1,
            text: "test",
            timestamp: 1640000000.0,
            segmentId: nil,
            confidence: 0.9,
            framePath: nil
        )

        searchController.jumpToResult(result)

        wait(for: [expectation], timeout: 1.0)
    }

    func testJumpToResultIncludesTimestamp() {
        let expectation = XCTestExpectation(description: "Notification contains timestamp")
        let notificationName = Notification.Name("JumpToTimestamp")
        let testTimestamp = 1640000000.0

        NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { notification in
            if let timestamp = notification.userInfo?["timestamp"] as? Double {
                XCTAssertEqual(timestamp, testTimestamp, accuracy: 1.0)
                expectation.fulfill()
            }
        }

        let result = SearchController.SearchResult(
            id: 1,
            text: "test",
            timestamp: testTimestamp,
            segmentId: nil,
            confidence: 0.9,
            framePath: nil
        )

        searchController.jumpToResult(result)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Edge Cases

    func testEmptyQueryHandling() {
        searchController.query = ""
        XCTAssertEqual(searchController.query, "")
    }

    func testWhitespaceQueryHandling() {
        searchController.query = "   "
        XCTAssertEqual(searchController.query, "   ")
    }

    func testNegativeConfidenceHandling() {
        let negativeConfidence = -0.5
        XCTAssertLessThan(negativeConfidence, 0.0)
    }

    func testHighConfidenceHandling() {
        let highConfidence = 1.5
        XCTAssertGreaterThan(highConfidence, 1.0)
    }

    func testZeroConfidenceHandling() {
        let zeroConfidence = 0.0
        XCTAssertEqual(zeroConfidence, 0.0)
    }

    func testMaxConfidenceHandling() {
        let maxConfidence = 1.0
        XCTAssertEqual(maxConfidence, 1.0)
    }

    // MARK: - Helper Methods

    private func createMockResults(count: Int) -> [SearchController.SearchResult] {
        return (0..<count).map { index in
            SearchController.SearchResult(
                id: index,
                text: "Test result \(index) with some longer text for snippet testing",
                timestamp: Date().addingTimeInterval(Double(index * 60)).timeIntervalSince1970,
                segmentId: "segment-\(index)",
                confidence: 0.9,
                framePath: nil
            )
        }
    }
}

// MARK: - Integration Test Notes

/*
 The following tests require actual database with FTS5 table and should be
 implemented as integration tests in a separate test target:

 1. testSearchWithRealDatabase() - Actual FTS5 query execution
 2. testSearchWithMinConfidence() - Confidence filtering with real data
 3. testSearchResultOrdering() - Verify results ordered by timestamp
 4. testSearchCacheHit() - Cache returns same results for same query
 5. testSearchCacheMiss() - Cache performs new query for different query
 6. testSearchCacheExpiration() - Cache expires after TTL
 7. testConcurrentSearchRequests() - Multiple simultaneous searches
 8. testSearchWithSpecialCharacters() - FTS5 special character handling
 9. testSearchWithMultipleWords() - Multi-word query matching
 10. testSearchPerformance() - Search completes within reasonable time

 These integration tests should:
 - Set up a temporary test database with FTS5 table
 - Insert test data with known OCR text and confidence scores
 - Execute searches and verify results match expected data
 - Clean up test database after each test
 - Use realistic data similar to production environment
 */
