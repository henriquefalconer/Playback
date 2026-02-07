# Text Search & OCR Implementation Plan

**Component:** Text Search and OCR
**Version:** 1.0
**Last Updated:** 2026-02-07

## Implementation Checklist

### Vision Framework Integration
- [ ] Add Vision framework import to project
  - Source: `Playback/Playback/Services/OCRService.swift` (new)
  - Framework: `import Vision`
  - Minimum macOS: 12.0+

- [ ] Implement OCR service in Swift
  - Source: `Playback/Playback/Services/OCRService.swift`
  - Method: `performOCR(on image: NSImage) -> OCRResult`
  - Recognition level: `.accurate`
  - Language correction: enabled

- [ ] Add Python OCR wrapper for processing service
  - Source: `scripts/ocr_processor.py` (new)
  - Dependencies: `pyobjc-framework-Vision`, `pyobjc-framework-Quartz`
  - Method: `perform_ocr(image_path: str) -> OCRResult`

- [ ] Handle OCR errors gracefully
  - Invalid images: Return empty string, log warning
  - Vision framework unavailable: Fallback to empty text
  - Performance: Add timeout (5s max per frame)

### OCR Processing Pipeline
- [ ] Integrate OCR into build_chunks_from_temp.py
  - Source: `scripts/build_chunks_from_temp.py`
  - Location: During frame processing loop
  - Store results in ocr_text table

- [ ] Add batch OCR processing
  - Process frames in parallel (4-8 workers)
  - Progress tracking and logging
  - Graceful handling of failures (skip frame, continue)
  - Performance target: 5-10 frames/second

- [ ] Implement OCR result storage
  - Store text, confidence, language per frame
  - Link to segment_id after video generation
  - Update FTS5 index after batch completion

- [ ] Add OCR performance monitoring
  - Track processing time per frame
  - Log average OCR latency
  - Alert if processing falls behind (>200ms/frame)

### Database Schema for Search (FTS5)
- [ ] Create ocr_text table
  - Source: `scripts/build_chunks_from_temp.py` (schema)
  - Columns: id, frame_path, segment_id, timestamp, text_content, confidence, language
  - Indexes: timestamp, segment_id

- [ ] Create FTS5 full-text search index
  - Table: `ocr_search` (virtual table)
  - Tokenizer: porter unicode61 (stemming + Unicode)
  - Indexed column: text_content
  - Unindexed: segment_id, timestamp (for filtering)

- [ ] Implement index population
  - Initial: Populate from existing ocr_text rows
  - Incremental: Insert during OCR processing
  - Rebuild: Support full re-index if needed

- [ ] Add index maintenance
  - Auto-vacuum FTS5 index periodically
  - Clean up orphaned entries when segments deleted
  - Monitor index size (target: ~1% of video size)

### Search UI (Command+F)
- [ ] Create search bar component
  - Source: `Playback/Playback/Search/SearchBar.swift` (new)
  - Design: Frosted glass overlay, top-right corner
  - Dimensions: 400x44px, 20px margins
  - Animation: Slide down with spring animation

- [ ] Implement keyboard shortcut handling
  - Shortcut: Command+F (toggle search)
  - ESC: Close search, return to current position
  - Enter: Jump to selected result, close search
  - Shift+Enter: Jump to previous result
  - Up/Down: Navigate results list

- [ ] Add search input handling
  - Debounced input: 300ms delay after last keystroke
  - Clear button when text present
  - Result counter: "1 of 15" display

- [ ] Create search results list
  - Source: `Playback/Playback/Search/SearchResultsList.swift` (new)
  - Display: Max 10 visible results, scrollable
  - Row design: App icon, timestamp, highlighted snippet
  - Selection: Highlight selected row

- [ ] Implement result item component
  - Source: `Playback/Playback/Search/SearchResultRow.swift` (new)
  - Display: App icon (20x20), app name, timestamp, snippet
  - Snippet: 2 lines max, match highlighted
  - Click handler: Jump to timestamp

### Search Indexing (Batch vs Realtime)
- [ ] Implement batch indexing during processing
  - Location: `scripts/build_chunks_from_temp.py`
  - Strategy: Process all frames for day, then bulk insert to FTS5
  - Performance: Optimize with transactions (BEGIN/COMMIT)

- [ ] Add incremental indexing for new recordings
  - Update FTS5 index as new segments processed
  - No need for full re-index
  - Monitor index lag (should stay <1 hour behind)

- [ ] Optional: Background OCR service
  - Source: `scripts/background_ocr.py` (future)
  - Separate process for large backlogs
  - Doesn't block video generation

### Query Parsing and Matching
- [ ] Implement search controller
  - Source: `Playback/Playback/Search/SearchController.swift` (new)
  - Method: `search(query: String) -> [SearchResult]`
  - Database: Query FTS5 index with prepared statements

- [ ] Add query tokenization
  - Split into words, remove stop words
  - Apply stemming (built into FTS5 porter tokenizer)
  - Support phrase search: "exact phrase"
  - Support prefix search: screen*

- [ ] Implement FTS5 query building
  - Simple search: word AND word (all must match)
  - Phrase search: "exact phrase" with quotes
  - Prefix search: word* for autocomplete
  - Ranking: Use BM25 (built into FTS5)

- [ ] Add result limiting and pagination
  - Limit: 100 results max initially
  - Pagination: Load more on scroll (future)
  - Cache recent queries (5 min TTL)

### Result Highlighting in Timeline
- [ ] Implement timeline match markers
  - Source: `Playback/Playback/Timeline/TimelineWithHighlights.swift` (new)
  - Design: Yellow vertical lines at match timestamps
  - Dimensions: 2px wide, 30px tall
  - Z-index: Above timeline, below scrubber

- [ ] Add segment highlighting
  - Make segments with matches slightly brighter
  - Show match count badge on hover
  - Update on search query change

- [ ] Integrate with existing timeline view
  - Source: `Playback/Playback/TimelineView.swift`
  - Pass match timestamps from SearchController
  - Render markers in ZStack overlay

### Navigation Between Matches
- [ ] Implement result navigation
  - Source: `Playback/Playback/Search/SearchController.swift`
  - Methods: `jumpToNext()`, `jumpToPrevious()`
  - Wrap around: Last result → first result
  - Update selected index in UI

- [ ] Add timeline jump functionality
  - Method: `jumpToTimestamp(_ timestamp: TimeInterval)`
  - Integration: Call PlaybackController.seek(to:)
  - Close search after navigation (optional)

- [ ] Implement search history tracking
  - Track current position in results
  - Remember last search query (session only)
  - Restore position when reopening search

### Performance Optimization
- [ ] Optimize OCR processing
  - Target: 5-10 frames/second
  - Parallelization: 4-8 worker threads
  - CPU limit: <50% average usage

- [ ] Optimize search query performance
  - Target latency: <50ms typical, <200ms max
  - Index optimization: VACUUM FTS5 periodically
  - Query caching: Cache last 10 queries (5 min TTL)

- [ ] Monitor memory usage
  - OCR service: <200MB per worker
  - Search index: <100MB in memory
  - Results cache: <10MB
  - Total: <500MB for search features

- [ ] Add performance metrics
  - Log OCR processing time per frame
  - Log search query latency
  - Track cache hit rate
  - Alert on performance degradation

## Search & OCR Implementation Details

### Vision Framework Usage

The implementation uses Apple's Vision framework for OCR, which provides excellent accuracy and performance on macOS 12.0+.

**Swift OCR Service Example:**

```swift
import Vision
import AppKit

struct OCRResult {
    let text: String
    let confidence: Float
    let language: String
}

class OCRService {
    func performOCR(on image: NSImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            return OCRResult(text: "", confidence: 0.0, language: "en")
        }

        let recognizedText = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }.joined(separator: " ")

        let avgConfidence = observations.compactMap { observation in
            observation.topCandidates(1).first?.confidence
        }.reduce(0.0, +) / Float(max(observations.count, 1))

        return OCRResult(
            text: recognizedText,
            confidence: avgConfidence,
            language: "en"
        )
    }
}
```

**Python OCR Wrapper Example:**

```python
from Quartz import CGImageSourceCreateWithURL, CGImageSourceCreateImageAtIndex
from Vision import VNRecognizeTextRequest, VNImageRequestHandler
from Foundation import NSURL
import objc

def perform_ocr(image_path: str) -> dict:
    """Perform OCR on an image using Vision framework."""
    url = NSURL.fileURLWithPath_(image_path)
    image_source = CGImageSourceCreateWithURL(url, None)

    if not image_source:
        return {"text": "", "confidence": 0.0, "language": "en"}

    image = CGImageSourceCreateImageAtIndex(image_source, 0, None)

    request = VNRecognizeTextRequest.alloc().init()
    request.setRecognitionLevel_(1)  # 1 = accurate
    request.setUsesLanguageCorrection_(True)
    request.setRecognitionLanguages_(["en-US"])

    handler = VNImageRequestHandler.alloc().initWithCGImage_options_(image, {})
    success = handler.performRequests_error_([request], None)

    if not success:
        return {"text": "", "confidence": 0.0, "language": "en"}

    results = request.results()
    if not results:
        return {"text": "", "confidence": 0.0, "language": "en"}

    text_parts = []
    confidences = []

    for observation in results:
        candidate = observation.topCandidates_(1)[0]
        text_parts.append(candidate.string())
        confidences.append(candidate.confidence())

    avg_confidence = sum(confidences) / max(len(confidences), 1)

    return {
        "text": " ".join(text_parts),
        "confidence": avg_confidence,
        "language": "en"
    }
```

### Database Schema Details

**ocr_text Table:**

```sql
CREATE TABLE ocr_text (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    frame_path TEXT NOT NULL,
    segment_id INTEGER,
    timestamp REAL NOT NULL,
    text_content TEXT NOT NULL,
    confidence REAL,
    language TEXT DEFAULT 'en',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (segment_id) REFERENCES segments(id) ON DELETE CASCADE
);

CREATE INDEX idx_ocr_timestamp ON ocr_text(timestamp);
CREATE INDEX idx_ocr_segment ON ocr_text(segment_id);
```

**FTS5 Virtual Table:**

```sql
CREATE VIRTUAL TABLE ocr_search USING fts5(
    text_content,
    segment_id UNINDEXED,
    timestamp UNINDEXED,
    tokenize = 'porter unicode61'
);

-- Populate from ocr_text
INSERT INTO ocr_search (rowid, text_content, segment_id, timestamp)
SELECT id, text_content, segment_id, timestamp FROM ocr_text;
```

### FTS5 Query Syntax Examples

**Simple Search (AND logic):**
```sql
-- Finds frames containing both "hello" and "world"
SELECT segment_id, timestamp, text_content
FROM ocr_search
WHERE ocr_search MATCH 'hello world'
ORDER BY rank;
```

**Phrase Search:**
```sql
-- Finds exact phrase "hello world"
SELECT segment_id, timestamp, text_content
FROM ocr_search
WHERE ocr_search MATCH '"hello world"'
ORDER BY rank;
```

**Prefix Search (autocomplete):**
```sql
-- Finds words starting with "scre" (screen, screenshot, etc.)
SELECT segment_id, timestamp, text_content
FROM ocr_search
WHERE ocr_search MATCH 'scre*'
ORDER BY rank;
```

**Boolean Operators:**
```sql
-- OR: either word matches
WHERE ocr_search MATCH 'hello OR world'

-- NOT: exclude results
WHERE ocr_search MATCH 'hello NOT goodbye'

-- Combined
WHERE ocr_search MATCH 'hello (world OR universe) NOT goodbye'
```

**Snippet Generation:**
```sql
-- Get highlighted snippets with context
SELECT
    segment_id,
    timestamp,
    snippet(ocr_search, 0, '[', ']', '...', 15) as snippet
FROM ocr_search
WHERE ocr_search MATCH 'search_term'
ORDER BY rank;
```

### UI Component Structure

**SearchBar Component (SwiftUI):**

```swift
struct SearchBar: View {
    @Binding var searchText: String
    @Binding var isVisible: Bool
    let resultCount: Int
    let currentIndex: Int
    let onSearch: (String) -> Void
    let onClose: () -> Void

    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search in video", text: $searchText)
                .textFieldStyle(.plain)
                .onChange(of: searchText) { newValue in
                    // Debounce: cancel previous task
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                        if !Task.isCancelled {
                            onSearch(newValue)
                        }
                    }
                }

            if !searchText.isEmpty {
                Text("\(currentIndex + 1) of \(resultCount)")
                    .foregroundColor(.secondary)
                    .font(.caption)

                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 400, height: 44)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.1), radius: 10)
        .offset(y: isVisible ? 0 : -64)
        .animation(.spring(), value: isVisible)
    }
}
```

**SearchResultRow Component:**

```swift
struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // App icon
                if let icon = result.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "app")
                        .frame(width: 20, height: 20)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // App name and timestamp
                    HStack {
                        Text(result.appName)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(result.formattedTimestamp)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Highlighted snippet
                    Text(result.attributedSnippet)
                        .lineLimit(2)
                        .font(.body)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}
```

### Performance Optimization Techniques

**Parallel OCR Processing:**

```python
from concurrent.futures import ProcessPoolExecutor, as_completed
import multiprocessing

def process_frames_parallel(frame_paths: list[str], num_workers: int = 4):
    """Process multiple frames in parallel using multiprocessing."""
    results = []

    with ProcessPoolExecutor(max_workers=num_workers) as executor:
        # Submit all tasks
        future_to_frame = {
            executor.submit(perform_ocr, path): path
            for path in frame_paths
        }

        # Process results as they complete
        for future in as_completed(future_to_frame):
            frame_path = future_to_frame[future]
            try:
                result = future.result(timeout=5.0)
                results.append({
                    "frame_path": frame_path,
                    "text": result["text"],
                    "confidence": result["confidence"],
                    "language": result["language"]
                })
            except Exception as e:
                print(f"OCR failed for {frame_path}: {e}")
                results.append({
                    "frame_path": frame_path,
                    "text": "",
                    "confidence": 0.0,
                    "language": "en"
                })

    return results

# Optimal worker count: 4-8 for typical workloads
optimal_workers = min(8, multiprocessing.cpu_count())
results = process_frames_parallel(frames, num_workers=optimal_workers)
```

**Batch Database Insertion:**

```python
def bulk_insert_ocr_results(conn, results: list[dict]):
    """Insert OCR results in a single transaction for performance."""
    cursor = conn.cursor()

    cursor.execute("BEGIN TRANSACTION")

    try:
        # Batch insert into ocr_text
        cursor.executemany("""
            INSERT INTO ocr_text
            (frame_path, timestamp, text_content, confidence, language)
            VALUES (?, ?, ?, ?, ?)
        """, [
            (r["frame_path"], r["timestamp"], r["text"], r["confidence"], r["language"])
            for r in results
        ])

        # Batch insert into FTS5 index
        cursor.executemany("""
            INSERT INTO ocr_search (text_content, segment_id, timestamp)
            VALUES (?, ?, ?)
        """, [
            (r["text"], r.get("segment_id"), r["timestamp"])
            for r in results
            if r["text"]  # Only index non-empty text
        ])

        cursor.execute("COMMIT")
        print(f"Inserted {len(results)} OCR results")

    except Exception as e:
        cursor.execute("ROLLBACK")
        raise e
```

**Search Query Caching:**

```swift
class SearchController {
    private var queryCache: [String: [SearchResult]] = [:]
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 300 // 5 minutes

    func search(query: String) async -> [SearchResult] {
        // Check cache
        if let cached = queryCache[query],
           let timestamp = cacheTimestamps[query],
           Date().timeIntervalSince(timestamp) < cacheTTL {
            return cached
        }

        // Perform search
        let results = await performDatabaseSearch(query)

        // Update cache
        queryCache[query] = results
        cacheTimestamps[query] = Date()

        // Limit cache size
        if queryCache.count > 10 {
            let oldestKey = cacheTimestamps.min(by: { $0.value < $1.value })?.key
            if let key = oldestKey {
                queryCache.removeValue(forKey: key)
                cacheTimestamps.removeValue(forKey: key)
            }
        }

        return results
    }
}
```

### Privacy Considerations

**Local-Only Storage:**
- All OCR text is stored exclusively in the local SQLite database
- No network requests are made during OCR processing
- No cloud synchronization of OCR text
- Database file permissions set to 0600 (user read/write only)

**Data Retention:**
- OCR text is automatically deleted when parent segments are deleted
- Foreign key constraint with ON DELETE CASCADE ensures cleanup
- No orphaned OCR data remains after segment deletion

**Sensitive Content Handling:**
- OCR captures all visible text, including potentially sensitive information
- Users should be aware that passwords, credit cards, personal data may be indexed
- Consider adding UI warning on first search usage
- Future enhancement: Regex-based filtering for common sensitive patterns (credit cards, SSNs)

**Database Security:**
```python
import os
import sqlite3

def initialize_database(db_path: str):
    """Initialize database with appropriate security settings."""
    # Set restrictive file permissions before creating
    os.umask(0o077)  # Creates files with 0600 permissions

    conn = sqlite3.connect(db_path)

    # Verify permissions
    st = os.stat(db_path)
    if st.st_mode & 0o077:  # Check if group/others have any permissions
        os.chmod(db_path, 0o600)
        print(f"Fixed database permissions: {db_path}")

    return conn
```

### Key Source Files

- `Playback/Playback/Services/OCRService.swift` - Vision framework OCR implementation
- `Playback/Playback/Search/SearchController.swift` - Search logic and database queries
- `Playback/Playback/Search/SearchBar.swift` - Search input UI component
- `Playback/Playback/Search/SearchResultsList.swift` - Search results display
- `Playback/Playback/Search/SearchResultRow.swift` - Individual result row component
- `Playback/Playback/Timeline/TimelineWithHighlights.swift` - Timeline match markers
- `scripts/ocr_processor.py` - Python OCR wrapper for processing service
- `scripts/build_chunks_from_temp.py` - Integration point for batch OCR processing

## Testing Checklist

### Unit Tests
- [ ] Test OCR accuracy with sample images
  - Test images with known text (various fonts, sizes)
  - Test with low-quality/blurry screenshots
  - Verify confidence scores are reasonable

- [ ] Test search query parsing
  - Simple queries: single word, multiple words
  - Phrase queries: "exact match"
  - Prefix queries: prefix*
  - Special characters: quotes, apostrophes, unicode

- [ ] Test FTS5 index correctness
  - Insert sample text, verify searchable
  - Test ranking: exact match > partial match
  - Test stemming: "running" matches "run"
  - Test case-insensitivity

- [ ] Test result limiting and pagination
  - Verify 100 result limit enforced
  - Test result ordering (by rank)
  - Test empty query handling

### Integration Tests
- [ ] Test end-to-end OCR during processing
  - Process test screenshots through build_chunks_from_temp.py
  - Verify OCR text stored in database
  - Verify FTS5 index populated
  - Verify searchable after processing

- [ ] Test search across multiple days
  - Create recordings spanning multiple days
  - Search for text appearing on different days
  - Verify all matches returned
  - Verify chronological ordering

- [ ] Test search with special characters
  - Test unicode text (emoji, accents, CJK)
  - Test punctuation (quotes, periods, hyphens)
  - Test URLs and email addresses
  - Verify no parsing errors

- [ ] Test performance with large datasets
  - Generate 1000+ screenshots with OCR text
  - Measure search query latency (<200ms)
  - Measure OCR processing rate (5-10 fps)
  - Verify memory usage within limits

### Manual Tests
- [ ] Test Command+F keyboard shortcut
  - Verify search bar appears/disappears
  - Test ESC to close
  - Test focus management

- [ ] Test search-as-you-type
  - Verify 300ms debounce
  - Verify results update in real-time
  - Verify result counter updates

- [ ] Test keyboard navigation
  - Enter: Jump to selected result
  - Shift+Enter: Jump to previous result
  - Up/Down: Navigate results list
  - Verify wrap-around behavior

- [ ] Test timeline highlighting
  - Verify yellow markers at match timestamps
  - Verify markers positioned correctly
  - Verify markers disappear when search closed

- [ ] Test result jumping
  - Click result: Verify video jumps to timestamp
  - Verify playback starts at correct moment
  - Verify search closes after jump (if configured)

### Performance Tests
- [ ] Measure OCR processing performance
  - Process 1000 frames, measure time
  - Verify average 100-200ms per frame
  - Verify parallelization works (4-8 workers)
  - Monitor CPU usage (<50% average)

- [ ] Measure search query performance
  - Run 100 queries, measure latency
  - Verify <50ms typical, <200ms max
  - Test with cold cache vs warm cache
  - Verify cache hit rate >50%

- [ ] Measure memory usage
  - Monitor during OCR processing
  - Monitor during search operations
  - Verify <500MB total for search features
  - Test for memory leaks (24-hour run)

### Privacy & Security Tests
- [ ] Verify OCR text stored locally only
  - Check no network requests during OCR
  - Verify no cloud sync
  - Verify file permissions (0600)

- [ ] Test OCR text deletion
  - Delete segment, verify OCR text deleted
  - Verify FTS5 index entries removed
  - Test cascade delete behavior

- [ ] Test with sensitive content
  - OCR passwords, credit cards, etc.
  - Verify stored locally only
  - Verify deleted when parent segment deleted
