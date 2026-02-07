# Text Search and OCR Specification

**Component:** Text Search and OCR
**Version:** 1.0
**Last Updated:** 2026-02-07

## Overview

Playback includes powerful text search capabilities powered by OCR (Optical Character Recognition). Users can search for any text that appeared on their screen, making it easy to find specific moments in their recording history.

## Design Philosophy

**Inspiration:** Arc browser's Command Bar and search experience

**Key Principles:**
- Fast, responsive search
- Search-as-you-type with instant results
- Minimal, non-intrusive UI
- Keyboard-first navigation
- Visual feedback for matches

## OCR Processing

### When to Perform OCR

**Strategy:** Process screenshots during video generation (processing service)

**Rationale:**
- Amortize OCR cost across batch processing
- Don't block recording or playback
- Once-per-screenshot (not on-demand)

### OCR Engine

**Primary:** Apple's Vision framework (built into macOS)

**Advantages:**
- Free, built-in (no external dependencies)
- Hardware-accelerated (Neural Engine on Apple Silicon)
- Optimized for macOS
- Privacy-preserving (on-device processing)
- Supports multiple languages

**Alternative:** Tesseract (open source)
- Only if Vision framework unavailable
- Requires separate installation
- Slower but more configurable

### Implementation

**Using Vision Framework:**

```python
# Python wrapper using pyobjc
from Foundation import NSData, NSURL
from Vision import VNRecognizeTextRequest, VNImageRequestHandler
import Quartz

def perform_ocr(image_path: str) -> str:
    """Extract text from image using Vision framework."""
    # Load image
    url = NSURL.fileURLWithPath_(image_path)
    image = Quartz.CIImage.imageWithContentsOfURL_(url)

    if image is None:
        return ""

    # Create OCR request
    request = VNRecognizeTextRequest.alloc().init()
    request.setRecognitionLevel_(1)  # Accurate (vs. Fast)
    request.setUsesLanguageCorrection_(True)

    # Perform OCR
    handler = VNImageRequestHandler.alloc().initWithCIImage_options_(image, None)
    success = handler.performRequests_error_([request], None)

    if not success:
        return ""

    # Extract text
    observations = request.results()
    if not observations:
        return ""

    text_lines = []
    for observation in observations:
        top_candidate = observation.topCandidates_(1)[0]
        text_lines.append(top_candidate.string())

    return "\n".join(text_lines)
```

**Using Swift (alternative for menu bar app or Playback):**

```swift
import Vision

func performOCR(on image: NSImage) -> String {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return ""
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

    do {
        try handler.perform([request])
    } catch {
        print("OCR failed: \(error)")
        return ""
    }

    guard let observations = request.results else { return "" }

    let text = observations.compactMap { observation in
        observation.topCandidates(1).first?.string
    }.joined(separator: "\n")

    return text
}
```

### OCR During Processing

**Integration Point:** `build_chunks_from_temp.py`

**Process:**
1. Load frames for day (as usual)
2. For each frame:
   - Perform OCR to extract text
   - Store text in database (new table: `ocr_text`)
3. Generate video segments (as usual)
4. Build search index from OCR text

**Performance:**
- OCR adds ~100-200ms per frame
- Batch processing mitigates impact (non-blocking)
- Can be parallelized (process multiple frames simultaneously)

**Optional:** Background OCR service
- Separate process that OCRs screenshots asynchronously
- Doesn't block video generation
- Useful for large backlogs

## Database Schema

### ocr_text Table

**Purpose:** Store extracted text for each screenshot

**Schema:**
```sql
CREATE TABLE IF NOT EXISTS ocr_text (
    id TEXT PRIMARY KEY,           -- Unique ID
    frame_path TEXT NOT NULL,       -- Path to screenshot
    segment_id TEXT,                -- Associated video segment (nullable during processing)
    timestamp REAL NOT NULL,        -- Frame timestamp (epoch seconds)
    text_content TEXT NOT NULL,     -- Extracted text
    confidence REAL,                -- OCR confidence score (0.0-1.0)
    language TEXT,                  -- Detected language (en, es, etc.)
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ocr_text_timestamp ON ocr_text(timestamp);
CREATE INDEX IF NOT EXISTS idx_ocr_text_segment ON ocr_text(segment_id);
```

**Example Row:**
```sql
INSERT INTO ocr_text (
    id, frame_path, segment_id, timestamp, text_content, confidence, language
) VALUES (
    'ocr_1234567890abcdef',
    'temp/202512/22/20251222-143050-a1b2c3d4-com.apple.Safari',
    'a3f8b29c4d1e5f67890a',
    1703258450.0,
    'Welcome to Playback\nYour screen recording assistant\nhttps://falconer.com/playback',
    0.92,
    'en'
);
```

### Full-Text Search Index

**Purpose:** Enable fast text search across all OCR'd content

**Schema (SQLite FTS5):**
```sql
CREATE VIRTUAL TABLE IF NOT EXISTS ocr_search USING fts5(
    segment_id UNINDEXED,
    timestamp UNINDEXED,
    text_content,
    tokenize='porter unicode61'  -- Porter stemming + Unicode support
);
```

**Populating Index:**
```sql
INSERT INTO ocr_search (segment_id, timestamp, text_content)
SELECT segment_id, timestamp, text_content FROM ocr_text;
```

**Search Query:**
```sql
SELECT segment_id, timestamp, snippet(ocr_search, 2, '**', '**', '...', 32) AS snippet
FROM ocr_search
WHERE ocr_search MATCH ?
ORDER BY rank
LIMIT 100;
```

## Search UI

### Search Bar

**Location:** Top-right corner of Playback app (overlaid on video)

**Design:**
```
┌──────────────────────────────────────┐
│  🔍  Search screen content...        │
└──────────────────────────────────────┘
```

**Dimensions:**
- Width: 400px
- Height: 44px
- Positioned: 20px from top, 20px from right
- Background: Blurred backdrop (frosted glass effect)
- Border: Subtle rounded corners (22px radius)
- Shadow: Soft drop shadow

**States:**

1. **Hidden (default)**
   - Not visible on screen
   - Activated by Command+F

2. **Empty**
   - Search icon + placeholder text
   - No results shown

3. **Active (typing)**
   - User typing query
   - Results appear below in real-time
   - Debounced (300ms delay after last keystroke)

4. **Results**
   - Results list shown below search bar
   - Match count displayed in search bar
   - Navigate with Enter/Shift+Enter

**Implementation:**
```swift
struct SearchBar: View {
    @Binding var query: String
    @Binding var isVisible: Bool
    @State private var results: [SearchResult] = []
    @State private var selectedIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Search input
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search screen content...", text: $query)
                    .textFieldStyle(PlainTextFieldStyle())
                    .onChange(of: query) { _, newValue in
                        performSearch(query: newValue)
                    }

                if !query.isEmpty {
                    Text("\(selectedIndex + 1) of \(results.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: clearSearch) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(22)

            // Results list (if any)
            if !results.isEmpty {
                SearchResultsList(results: results, selectedIndex: $selectedIndex)
            }
        }
        .frame(width: 400)
        .shadow(radius: 10)
        .offset(y: isVisible ? 0 : -100)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
    }

    func performSearch(query: String) {
        guard !query.isEmpty else {
            results = []
            return
        }

        // Debounce: Only search after 300ms of no typing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            results = searchDatabase(query: query)
            selectedIndex = 0
        }
    }
}
```

### Search Results

**Display:**
- Dropdown list below search bar
- Max 10 results visible (scrollable)
- Each result shows:
  - Timestamp (date + time)
  - Text snippet with match highlighted
  - App icon/name

**Result Item Design:**
```
┌──────────────────────────────────────┐
│  📱 Safari - 2:30 PM                │
│  ...Welcome to **Playback**...   │
└──────────────────────────────────────┘
```

**Navigation:**
- Click result: Jump to that timestamp
- Enter: Jump to selected result (closes search)
- Shift+Enter: Jump to previous result
- Up/Down arrows: Navigate results
- ESC: Close search (return to current position)

**Implementation:**
```swift
struct SearchResultsList: View {
    let results: [SearchResult]
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results.indices, id: \.self) { index in
                    SearchResultRow(
                        result: results[index],
                        isSelected: index == selectedIndex
                    )
                    .onTapGesture {
                        jumpToResult(results[index])
                    }
                }
            }
        }
        .frame(maxHeight: 400)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.top, 4)
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool

    var body: some View {
        HStack {
            // App icon
            if let icon = result.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Timestamp + app name
                Text("\(result.appName) - \(formatTime(result.timestamp))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Text snippet with match highlighted
                Text(result.snippet)
                    .font(.body)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}
```

### Timeline Highlighting

**Visual Feedback:** Highlight segments in timeline that contain matches

**Implementation:**
- Add yellow markers at match timestamps
- Make segments with matches slightly brighter
- Show match count in timeline UI

```swift
struct TimelineWithHighlights: View {
    let matchTimestamps: [TimeInterval]

    var body: some View {
        ZStack {
            // Normal timeline
            TimelineView(...)

            // Match markers
            ForEach(matchTimestamps, id: \.self) { timestamp in
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 2, height: 30)
                    .position(x: xPosition(for: timestamp), y: timelineCenter)
            }
        }
    }
}
```

## Search Algorithm

### Query Processing

**Tokenization:**
- Split query into words
- Remove stop words (the, a, an, etc.)
- Apply stemming (running → run)

**Example:**
- Query: "Welcome to Playback"
- Tokens: ["welcome", "screenseek"]

### Database Search

**FTS5 Query:**
```sql
-- Simple search (all words must appear)
SELECT * FROM ocr_search WHERE ocr_search MATCH 'welcome AND screenseek';

-- Phrase search (exact order)
SELECT * FROM ocr_search WHERE ocr_search MATCH '"Welcome to Playback"';

-- Prefix search (autocomplete)
SELECT * FROM ocr_search WHERE ocr_search MATCH 'screen*';
```

**Ranking:**
- BM25 algorithm (built into FTS5)
- Results sorted by relevance
- Exact phrase matches ranked higher

### Performance

**Optimization:**
- Index pre-built during processing
- Search executes in < 50ms (typical)
- Results limited to 100 (pagination if needed)

**Caching:**
- Cache recent search results
- Invalidate on new recordings

## Privacy Considerations

### OCR Text Storage

**Sensitivity:**
- OCR text may contain passwords, personal info, sensitive data
- Same privacy considerations as video recordings

**Storage:**
- Stored locally only (no cloud sync)
- Same file permissions as videos (0600)
- Deleted when parent segment deleted

**User Control:**
- OCR can be disabled in settings (future feature)
- Search still works on existing OCR'd content

## Testing

### Unit Tests

- OCR accuracy (test images with known text)
- Search query parsing
- FTS5 index correctness
- Result ranking

### Integration Tests

- End-to-end OCR during processing
- Search across multiple days
- Search with special characters
- Performance with large datasets (1M+ frames)

### Manual Tests

- Search for known text in recordings
- Verify result relevance
- Test keyboard navigation
- Verify timeline highlighting

## Future Enhancements

### Potential Features

1. **Advanced Search Operators**
   - Boolean operators (AND, OR, NOT)
   - Date range filters
   - App filters

2. **Search History**
   - Remember recent searches
   - Quick access to past queries

3. **Search Suggestions**
   - Autocomplete based on OCR'd text
   - Common queries

4. **Multi-Language Support**
   - Better handling of non-English text
   - Language detection per frame

5. **Semantic Search**
   - ML-based similarity search
   - "Find screenshots similar to this"

6. **Export Search Results**
   - Export matching frames as images
   - Generate report of matches

7. **Real-Time OCR**
   - OCR during recording (not just processing)
   - Enables immediate searchability

## Performance Targets

### OCR Processing

- Process rate: 5-10 frames/second
- Latency per frame: 100-200ms
- CPU usage: < 50% (parallelizable)

### Search

- Query latency: < 50ms (typical)
- Max latency: < 200ms (worst case)
- Index size: ~1% of video size
- Memory usage: < 100MB for index

## Dependencies

### System

- macOS 12.0+ (Vision framework)
- SQLite 3.35+ (FTS5 support)

### Python Packages

- `pyobjc-framework-Vision` (Vision framework bindings)
- `pyobjc-framework-Quartz` (Image loading)

**Installation:**
```bash
pip3 install pyobjc-framework-Vision pyobjc-framework-Quartz
```

### Swift Frameworks

- Vision (built-in)
- CoreImage (built-in)
- AppKit (built-in)
