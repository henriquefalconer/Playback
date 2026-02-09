# Timeline Graphical Interface Implementation Plan

**Component:** Timeline Viewer (Playback.app - standalone app in Applications folder)
**Last Updated:** 2026-02-07

**Architecture Note:** The timeline viewer is a fullscreen window within the menu bar app:
- Lives in `/Applications/Playback.app` (only user-visible Playback app)
- Can be launched from menu bar, global hotkey (Option+Shift+Space), or app icon
- **Quit behavior:** Cmd+Q or quitting from Dock closes ONLY the timeline window, not the app
  - Menu bar icon remains visible
  - Recording and processing services continue running
  - Only "Quit Playback" from menu bar stops all services and quits the app completely
- ESC key closes the timeline window (same as Cmd+Q)
- Signals recording service to pause while open, resume when closed
- Read-only access to database and configuration

## Implementation Checklist

### Global Hotkey Registration
- [ ] Implement Carbon-based global hotkey manager
  - Source: `src/Playback/Playback/Services/GlobalHotkeyManager.swift`
  - Shortcut: Option+Shift+Space (key code 49)
  - Handler: Activates app and shows timeline window

- [ ] Request and verify Accessibility permissions
  - Show permission prompt on first launch
  - Graceful fallback if permission denied
  - Provide "Open System Preferences" button

- [ ] Register hotkey on app launch
  - Initialize in `PlaybackApp.swift` applicationDidFinishLaunching
  - Unregister on app termination
  - Handle hotkey conflicts gracefully

### App Icon and Launch Behavior
- [ ] Design and implement app icon
  - Style: Play button (rounded triangle)
  - Colors: Vibrant blue/purple gradient
  - Sizes: Multiple resolutions for Dock and Finder
  - Location: `/Applications/Playback.app` (only user-visible app)

- [ ] Implement launch triggers
  - Trigger 1: Global hotkey (Option+Shift+Space) - handled by menu bar agent
  - Trigger 2: Menu bar "Open Timeline" - launched by menu bar agent via NSWorkspace
  - Trigger 3: Click app icon in Applications/Dock - standard macOS launch
  - All triggers: Open timeline immediately, no blocking screens

- [ ] Implement launch sequence
  - Create signal file: `~/Library/Application Support/Playback/data/.timeline_open`
  - Load database and segments (read-only)
  - Enter fullscreen mode
  - Position timeline at most recent timestamp
  - Begin video playback
  - Recording service detects signal file and pauses automatically
  - Processing continues in background if running (non-blocking)

### Loading Screen
- [x] **REMOVED:** No blocking loading screen
  - Users can navigate timeline freely even while processing is running
  - Video segments appear as they're processed
  - No modal overlay or blocking UI
  - Processing happens in background without interrupting user navigation

### Fullscreen Timeline Window
- [ ] Implement fullscreen window configuration
  - Source: `src/Playback/Playback/Timeline/TimelineWindow.swift`
  - No title bar, no window chrome
  - Black letterboxing for non-matching aspect ratios
  - Disable three-finger swipe gestures

- [ ] Configure presentation options
  - Disable Mission Control gestures
  - Auto-hide menu bar and Dock
  - Disable process switching (Cmd+Tab)
  - Restore normal behavior on exit

- [ ] Implement ESC and Cmd+Q handlers
  - Exit fullscreen mode
  - Delete signal file: `~/Library/Application Support/Playback/data/.timeline_open`
  - Close timeline window (window only, not app)
  - Recording service detects missing file and resumes automatically
  - Menu bar icon remains visible
  - App continues running with services active
  - Note: To quit the entire app, use "Quit Playback" from menu bar

### Video Playback System
- [ ] Implement video player integration (AVPlayer)
  - Source: `src/Playback/Playback/Timeline/VideoPlayer.swift` (EXISTING)
  - Use AVPlayerLayer for discrete playback (no Control Center integration)
  - Hardware-accelerated decode via VideoToolbox
  - Smooth segment transitions
  - Configuration: Preload next segment in background for seamless transitions
  - Use KVO on AVPlayer.status and AVPlayerItem.status for state management

- [ ] Implement frozen frame system
  - Source: `src/Playback/Playback/Timeline/PlaybackController.swift` (EXISTING)
  - Capture last frame before segment transition using AVAssetImageGenerator
  - Display frozen frame as overlay image during loading
  - Hide when new segment ready and playing
  - Freeze frame also used when scrubbing through gaps
  - Smooth crossfade transition (200ms) from frozen to live video

- [ ] Enhance PlaybackController
  - Source: `src/Playback/Playback/Timeline/PlaybackController.swift` (EXISTING)
  - Methods: `update(for:store:)`, `scrub(to:store:)`, `scheduleUpdate(for:store:)`
  - State: currentSegment, currentTime, frozenFrame, showFrozenFrame
  - Time observer for synchronization

- [ ] Implement segment selection logic
  - Source: `src/Playback/Playback/Timeline/TimelineStore.swift`
  - Function: `segment(for:direction:) -> (Segment, TimeInterval)?`
  - Algorithm: Binary search for efficient lookup in sorted segments array
  - Handle gaps between segments (use direction: forward = next segment, backward = previous segment)
  - Handle before first segment: return nil or first segment depending on direction
  - Handle after last segment: return nil or last segment depending on direction
  - Return tuple: (segment, video offset) for immediate playback positioning

### Timeline Rendering
- [ ] Implement timeline view component
  - Source: `src/Playback/Playback/Timeline/TimelineView.swift` (EXISTING)
  - Position: Bottom of screen, 120px height, 40px margin
  - Gradient overlay for visibility

- [ ] Implement segments bar rendering
  - Horizontal bar with all video segments
  - Rounded rectangles with app-specific colors
  - Gaps show transparent background
  - Height: 20px

- [ ] Implement playhead indicator
  - Vertical line at current time position
  - Red color (#FF0000)
  - Extends above and below timeline
  - Capped with small circle (5px radius)

- [ ] Implement time labels and ticks
  - Major ticks every N hours (zoom-dependent)
  - Minor ticks every N/5 hours
  - Format: "10:00 AM" or "2:30 PM"
  - White text with shadow for readability

- [ ] Implement time bubble
  - Shows current timestamp
  - Format: "1:23:45 PM" (with seconds) or relative ("5 minutes ago")
  - Semi-transparent rounded rectangle background
  - Positioned above playhead
  - Clickable: Opens date/time picker

- [ ] Implement app color generation
  - Deterministic colors from app bundle ID using hash function
  - Algorithm: Hash bundle ID string → convert to HSL → map to color space
  - Extract average color from app icon using NSWorkspace.icon(forFile:)
  - Boost saturation (+20%) and brightness (+15%) for vibrancy
  - Fallback: Use bundle ID hash if icon extraction fails
  - Cache colors in dictionary for performance (key: bundle ID, value: NSColor)
  - Pre-warm cache on app launch with active app bundle IDs

### Trackpad/Mouse Gestures
- [ ] Implement horizontal scroll for scrubbing
  - Source: `src/Playback/Playback/Timeline/ContentView.swift`
  - Natural scrolling inverted (right = future, left = past)
  - Dynamic speed based on visible window size
  - Formula: `secondsPerPoint = visibleWindowSeconds / 1000.0`
  - Physics: Apply velocity multiplier for fling-style gestures
  - Deceleration curve: Natural logarithmic decay for smooth stop
  - Video paused during scrubbing, resumes after 500ms of no scroll events
  - Update playhead position in real-time during scrub

- [ ] Implement pinch gesture for zoom
  - Pinch OUT = zoom IN (less time visible)
  - Pinch IN = zoom OUT (more time visible)
  - Exponential sensitivity: `pow(magnification, 3.0)` for natural feel
  - Limits: 60s (min) to 3600s (max) visible window
  - Spring animation: response 0.35s, damping 0.8 for smooth zoom transitions
  - Anchor point: Keep timestamp under cursor stationary during zoom
  - Update time labels and tick spacing dynamically based on zoom level

- [ ] Implement click-to-seek on timeline
  - Click on timeline bar to jump to timestamp
  - Calculate position based on visible window
  - Update playhead and video immediately

- [ ] Implement scroll event monitoring
  - Source: `src/Playback/Playback/Timeline/VideoBackgroundView.swift` (EXISTING)
  - Use NSEvent.addLocalMonitorForEvents for scroll events
  - Consume events to prevent system handling
  - Pass to PlaybackController for scrubbing

### Date/Time Picker
- [ ] Implement date/time picker popup
  - Source: `src/Playback/Playback/Timeline/DateTimePicker.swift`
  - Trigger: Click on time bubble
  - Arc-inspired design (frosted glass, minimal)
  - Centered on screen, 600x400px

- [ ] Implement calendar view
  - Source: `src/Playback/Playback/Timeline/DateTimePicker.swift`
  - Left panel: Calendar grid
  - Month/year header with navigation arrows
  - "Today" button
  - Dates with recordings: Bold, clickable
  - Dates without recordings: Greyed out, disabled

- [ ] Implement time list view
  - Source: `src/Playback/Playback/Timeline/DateTimePicker.swift`
  - Right panel: Scrollable time list
  - 15-minute intervals (09:00, 09:15, 09:30, ...)
  - Times with recordings: Normal, clickable
  - Times without recordings: Greyed out, disabled
  - Currently playing time: Marked with play indicator

- [ ] Implement date/time data loading
  - Query database for available dates: `loadAvailableDates() -> Set<Date>`
  - SQL: `SELECT DISTINCT DATE(start_ts, 'unixepoch', 'localtime') FROM segments ORDER BY start_ts`
  - Query database for available times on date: `loadAvailableTimes(for:) -> [TimeInterval]`
  - SQL: `SELECT start_ts FROM segments WHERE DATE(start_ts, 'unixepoch', 'localtime') = ? ORDER BY start_ts`
  - Round times to nearest 15-minute interval for UI display
  - Cache queries for performance (in-memory dictionary)
  - Invalidate cache on new recordings (watch segments count)
  - Background loading: Run queries on background dispatch queue

- [ ] Implement date/time picker behavior
  - Fade in/out animations (Arc-style)
  - Calendar updates time list on date selection
  - "Jump to Date/Time" button: Navigate and close
  - "Cancel" or ESC: Close without navigation
  - Click outside: Close without navigation
  - Instant jump (no scroll animation)
### Text Search (OCR)
- [ ] Implement search UI
  - Source: `src/Playback/Playback/Timeline/SearchView.swift`
  - Trigger: Command+F
  - Floating search bar (top-right corner)
  - Arc-style minimal design
- [ ] Implement OCR search integration
  - Defer to separate OCR Search specification (search-ocr.md)
  - Highlight matching segments in timeline
  - Jump to next/previous match (Enter/Shift+Enter)
  - Show match count ("3 of 15 matches")
  - Real-time search results (debounced)
### - [ ] Implement database connection
  - Source: `src/Playback/Playback/Database/DatabaseManager.swift`
  - File: `~/Library/Application Support/Playback/data/meta.sqlite3`
  - Query segments: `SELECT id, start_ts, end_ts, frame_count, fps, video_path FROM segments ORDER BY start_ts ASC`
  - Query app segments: `SELECT id, app_id, start_ts, end_ts FROM appsegments ORDER BY start_ts ASC`
- [ ] Implement Segment model
  - Source: `src/Playback/Playback/Models/Segment.swift`
  - Properties: id, startTS, endTS, frameCount, fps, videoURL
  - Computed: duration, videoDuration
  - Methods: `videoOffset(forAbsoluteTime:)`, `absoluteTime(forVideoOffset:)`
- [ ] Implement AppSegment model
  - Source: `src/Playback/Playback/Models/AppSegment.swift`
  - Properties: id, startTS, endTS, appId
  - Computed: duration
- [ ] Implement auto-refresh mechanism
  - Poll database every 5 seconds for new segments
  - Use `.onChange(of: segments.count)` to detect changes
  - Automatically reposition to latest timestamp on new segments
### - [ ] Implement recording service pause detection
  - Mechanism: Recording service checks for Playback app process
  - Use `pgrep -f "Playback.app"` to check if app running
  - Recording service auto-pauses when app visible
  - Recording service auto-resumes when app exits
- [ ] Document recording service changes
  - Update recording service code to check for Playback app
  - Add process detection to recording loop
  - Ensure clean pause/resume without data loss
### Error Handling
- [ ] Handle database not found
  - Show empty state screen
  - Message: "No recordings yet. Start recording from the menu bar."
  - Button: "Open Menu Bar Settings"
  - ESC to close
- [ ] Handle video file missing
  - Log warning
  - Show frozen frame (last known good frame)
  - Continue timeline playback
  - Skip to next available segment
- [ ] Handle segment loading failure
  - Log error with details
  - Show frozen frame
  - Attempt to load next segment
  - Show error message if multiple consecutive failures
- [ ] Handle permission denied
  - Show error dialog: "Playback needs Screen Recording permission"
  - Button: "Open System Preferences"
  - Cannot display videos without permission
## Timeline Implementation Details

### AVPlayer Integration and Segment Selection

**AVPlayer Configuration:**
- Use `AVPlayer` with `AVPlayerLayer` for hardware-accelerated video playback
- Set `automaticallyWaitsToMinimizeStalling = false` for immediate playback
- Configure `preferredForwardBufferDuration = 5.0` for smooth segment transitions
- Use `AVAssetImageGenerator` for frozen frame capture with `requestedTimeToleranceAfter = .zero`

**Segment Selection Algorithm:**
```swift
func segment(for timestamp: TimeInterval, direction: Direction) -> (Segment, TimeInterval)? {
    // Binary search in sorted segments array
    let index = segments.binarySearch { $0.startTS <= timestamp && timestamp < $0.endTS }

    if let idx = index {
        // Time is within a segment
        let segment = segments[idx]
        let videoOffset = timestamp - segment.startTS
        return (segment, videoOffset)
    }

    // Time is in a gap between segments
    switch direction {
    case .forward:
        // Find next segment after timestamp
        let nextIdx = segments.firstIndex { $0.startTS > timestamp }
        return nextIdx.map { (segments[$0], 0.0) }
    case .backward:
        // Find previous segment before timestamp
        let prevIdx = segments.lastIndex { $0.endTS < timestamp }
        return prevIdx.map { (segments[$0], segments[$0].duration) }
    }
}
```

**Segment Preloading:**
- Monitor `currentTime` via `addPeriodicTimeObserver(forInterval:queue:using:)`
- When 80% through current segment, preload next segment in background
- Use separate `AVPlayer` instance for preloading, swap when ready

### Scroll Gesture Physics

**Natural Scrolling Implementation:**
```swift
func handleScroll(_ event: NSEvent) {
    // Invert scrolling: right = future, left = past
    let delta = -event.scrollingDeltaX

    // Calculate speed based on visible window
    let secondsPerPoint = visibleWindowSeconds / 1000.0
    let timeDelta = delta * secondsPerPoint

    // Apply velocity multiplier for momentum scrolling
    let velocity = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaX : event.scrollingDeltaX
    let momentumMultiplier = abs(velocity) > 10 ? 1.5 : 1.0

    // Update timeline position
    currentTimestamp += timeDelta * momentumMultiplier

    // Pause video during scrubbing
    pauseVideoForScrubbing()

    // Schedule resume after 500ms of no scroll events
    scheduleScrubResumeTimer()
}
```

**Deceleration Curve:**
- Use `CADisplayLink` for 60fps scroll animation
- Apply logarithmic decay: `velocity *= 0.95` per frame
- Stop when velocity < 0.1 seconds/frame

### Pinch Zoom Sensitivity and Limits

**Zoom Implementation:**
```swift
func handlePinch(_ gesture: NSMagnificationGestureRecognizer) {
    let magnification = gesture.magnification

    // Exponential sensitivity for natural feel
    let zoomFactor = pow(1.0 + magnification, 3.0)

    // Update visible window size
    let newWindow = visibleWindowSeconds / zoomFactor

    // Clamp to limits
    visibleWindowSeconds = max(60.0, min(3600.0, newWindow))

    // Keep timestamp under cursor stationary (anchor point)
    let cursorX = gesture.location(in: timelineView).x
    let cursorTimestamp = timestampAtX(cursorX)

    // Adjust timeline center to maintain anchor
    centerTimestamp = cursorTimestamp + (centerTimestamp - cursorTimestamp) / zoomFactor

    // Animate with spring
    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
        updateTimelineLayout()
    }
}
```

**Dynamic Tick Spacing:**
- 60-300s visible: Major ticks every 1 hour, minor every 15 min
- 300-900s visible: Major ticks every 3 hours, minor every 1 hour
- 900-1800s visible: Major ticks every 6 hours, minor every 2 hours
- 1800-3600s visible: Major ticks every 12 hours, minor every 4 hours

### Date/Time Picker UI Structure

**Component Hierarchy:**
```
DateTimePicker (Modal)
├── Background (frosted glass, blur(radius: 20))
├── Container (600x400px, rounded corners)
│   ├── Header ("Jump to Date/Time", close button)
│   ├── ContentSplit (HStack)
│   │   ├── CalendarView (300px wide)
│   │   │   ├── MonthYearHeader (nav arrows, "Today" button)
│   │   │   └── CalendarGrid (7x6 grid of date cells)
│   │   └── TimeListView (300px wide)
│   │       └── ScrollView (15-min interval list)
│   └── Footer (HStack)
│       ├── CancelButton
│       └── JumpButton (primary action)
```

**Data Loading Strategy:**
```swift
class DateTimePickerViewModel: ObservableObject {
    @Published var availableDates: Set<Date> = []
    @Published var availableTimes: [TimeInterval] = []

    func loadAvailableDates() async {
        let dates = await database.query("""
            SELECT DISTINCT DATE(start_ts, 'unixepoch', 'localtime')
            FROM segments
            ORDER BY start_ts
        """)

        await MainActor.run {
            self.availableDates = Set(dates)
        }
    }

    func loadAvailableTimes(for date: Date) async {
        let times = await database.query("""
            SELECT start_ts
            FROM segments
            WHERE DATE(start_ts, 'unixepoch', 'localtime') = ?
            ORDER BY start_ts
        """, [date])

        // Round to 15-minute intervals
        let roundedTimes = times.map { roundTo15Minutes($0) }

        await MainActor.run {
            self.availableTimes = Array(Set(roundedTimes)).sorted()
        }
    }
}
```

### Timeline Rendering with App Colors

**Hash-Based Color Generation:**
```swift
func colorForApp(bundleID: String) -> NSColor {
    // Check cache first
    if let cached = colorCache[bundleID] {
        return cached
    }

    // Try to extract from app icon
    if let appPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
       let icon = NSWorkspace.shared.icon(forFile: appPath.path) {
        if let averageColor = extractAverageColor(from: icon) {
            let vibrant = boostSaturationAndBrightness(averageColor)
            colorCache[bundleID] = vibrant
            return vibrant
        }
    }

    // Fallback: Hash bundle ID to HSL color
    let hash = bundleID.hashValue
    let hue = Double(abs(hash) % 360) / 360.0
    let saturation = 0.7 + (Double(abs(hash >> 8) % 20) / 100.0)  // 0.7-0.9
    let brightness = 0.6 + (Double(abs(hash >> 16) % 20) / 100.0)  // 0.6-0.8

    let color = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
    colorCache[bundleID] = color
    return color
}

func boostSaturationAndBrightness(_ color: NSColor) -> NSColor {
    guard let hsbColor = color.usingColorSpace(.deviceRGB) else { return color }

    let newSaturation = min(1.0, hsbColor.saturationComponent * 1.2)  // +20%
    let newBrightness = min(1.0, hsbColor.brightnessComponent * 1.15)  // +15%

    return NSColor(hue: hsbColor.hueComponent,
                   saturation: newSaturation,
                   brightness: newBrightness,
                   alpha: 1.0)
}
```

**Timeline Rendering Loop:**
```swift
func drawTimeline(in context: CGContext, rect: CGRect) {
    // Draw segments bar
    for appSegment in visibleAppSegments {
        let x = xPosition(for: appSegment.startTS)
        let width = (xPosition(for: appSegment.endTS) - x)
        let rect = CGRect(x: x, y: rect.height - 60, width: width, height: 20)

        context.setFillColor(colorForApp(bundleID: appSegment.appId).cgColor)
        context.fillPath(in: rect, cornerRadius: 4)
    }

    // Draw playhead
    let playheadX = xPosition(for: currentTimestamp)
    context.setStrokeColor(NSColor.red.cgColor)
    context.setLineWidth(2)
    context.move(to: CGPoint(x: playheadX, y: 0))
    context.addLine(to: CGPoint(x: playheadX, y: rect.height))
    context.strokePath()

    // Draw playhead circle
    context.setFillColor(NSColor.red.cgColor)
    context.fillEllipse(in: CGRect(x: playheadX - 5, y: rect.height - 70, width: 10, height: 10))

    // Draw time labels and ticks
    drawTimeLabelsAndTicks(in: context, rect: rect)
}
```

### Frozen Frame Handling During Transitions

**Frozen Frame Capture:**
```swift
func captureCurrentFrame() async -> NSImage? {
    guard let currentItem = player.currentItem,
          let asset = currentItem.asset as? AVURLAsset else {
        return nil
    }

    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true
    imageGenerator.requestedTimeToleranceAfter = .zero
    imageGenerator.requestedTimeToleranceBefore = .zero

    let time = currentItem.currentTime()

    do {
        let (cgImage, _) = try await imageGenerator.image(at: time)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    } catch {
        print("Failed to capture frame: \(error)")
        return nil
    }
}
```

**Transition State Machine:**
```swift
enum PlaybackState {
    case playing(segment: Segment)
    case frozen(frame: NSImage, targetTimestamp: TimeInterval)
    case loading(targetSegment: Segment, targetOffset: TimeInterval)
}

func transitionToSegment(_ segment: Segment, offset: TimeInterval) async {
    // 1. Capture current frame
    if let frame = await captureCurrentFrame() {
        state = .frozen(frame: frame, targetTimestamp: segment.startTS + offset)
    }

    // 2. Load new segment
    state = .loading(targetSegment: segment, targetOffset: offset)

    let playerItem = AVPlayerItem(url: segment.videoURL)
    player.replaceCurrentItem(with: playerItem)

    // 3. Wait for ready to play
    await playerItem.waitUntilReadyToPlay()

    // 4. Seek to offset
    await player.seek(to: CMTime(seconds: offset, preferredTimescale: 600))

    // 5. Start playback with crossfade
    state = .playing(segment: segment)
    withAnimation(.easeInOut(duration: 0.2)) {
        frozenFrameOpacity = 0.0
    }

    player.play()
}
```

**Frozen Frame View:**
```swift
struct FrozenFrameOverlay: View {
    let image: NSImage?
    let opacity: Double

    var body: some View {
        if let image = image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .opacity(opacity)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }
}
```

### Referenced Source Files

- `src/Playback/Playback/Timeline/TimelineView.swift` - Timeline rendering and gestures
- `src/Playback/Playback/Timeline/VideoBackgroundView.swift` - Video player view with scroll capture
- `src/Playback/Playback/Timeline/PlaybackController.swift` - Video playback and scrubbing logic
- `src/Playback/Playback/Timeline/TimelineStore.swift` - Segment data management
- `src/Playback/Playback/Timeline/ContentView.swift` - Main timeline view composition
- `src/Playback/Playback/Services/GlobalHotkeyManager.swift` - Global hotkey registration
- `src/Playback/Playback/Timeline/DateTimePicker.swift` - Date/time picker modal
- `src/Playback/Playback/Timeline/LoadingScreenView.swift` - Processing loading screen
- `src/Playback/Playback/Database/DatabaseManager.swift` - SQLite database interface
- `src/Playback/Playback/Models/Segment.swift` - Video segment model
- `src/Playback/Playback/Models/AppSegment.swift` - App usage segment model

### Related Specifications

- `architecture.md` - System architecture and component communication
- `search-ocr.md` - OCR-based text search implementation
- `build-process.md` - Build configuration and code signing
- `installation-deployment.md` - Deployment and installation procedures

## Testing Checklist

### Unit Tests
- [ ] Test segment selection logic
  - Test time within segment
  - Test time in gap between segments (forward/backward direction)
  - Test before first segment
  - Test after last segment
- [ ] Test time mapping functions
  - Test `videoOffset(forAbsoluteTime:)` for various times
  - Test `absoluteTime(forVideoOffset:)` for various offsets
  - Test edge cases (start, end, boundaries)
- [ ] Test app color generation
  - Test deterministic colors from bundle ID
  - Test color caching
  - Test fallback for unknown apps
### Integration Tests
- [ ] Test database loading
  - Test loading segments from database
  - Test loading app segments from database
  - Test empty database handling
  - Test corrupted database handling
- [ ] Test video playback
  - Test initial video load
  - Test segment transitions
  - Test frozen frame display during transitions
  - Test video seek accuracy
- [ ] Test segment transitions
  - Test smooth transition between consecutive segments
  - Test transition across gaps
  - Test transition with frozen frame
  - Test transition failure recovery
- [ ] Test scrubbing accuracy
  - Test horizontal scroll scrubbing
  - Test click-to-seek on timeline
  - Test scrubbing through gaps
  - Test scrubbing at timeline boundaries
### UI Tests
- [ ] Test global hotkey activation
  - Test Option+Shift+Space triggers app
  - Test hotkey works from any app
  - Test hotkey requires Accessibility permission
  - Test graceful fallback if permission denied
- [ ] Test fullscreen mode
  - Test app enters fullscreen on launch
  - Test no title bar or window chrome
  - Test letterboxing for non-matching aspect ratios
  - Test three-finger swipe disabled
- [ ] Test scroll/pinch gestures
  - Test horizontal scroll for scrubbing
  - Test pinch for timeline zoom
  - Test gesture speed and sensitivity
  - Test zoom limits (60s min, 3600s max)
- [ ] Test ESC key handling
  - Test ESC exits fullscreen
  - Test ESC closes app
  - Test ESC signals recording service to resume
  - Test ESC works from loading screen
- [ ] Test date/time picker
  - Test click on time bubble opens picker
  - Test calendar shows dates with recordings
  - Test time list shows times with recordings
  - Test "Jump to Date/Time" navigates correctly
  - Test "Cancel" and ESC close picker
  - Test click outside closes picker
### Manual Tests
- [ ] Test long recording session (24+ hours)
  - Test timeline rendering with large dataset
  - Test scrubbing performance
  - Test memory usage stays within limits
  - Test auto-refresh with new segments
- [ ] Test multiple segment transitions
  - Test playback across many segments
  - Test frozen frame stability
  - Test no visual glitches or flashes
  - Test audio/video sync maintained
- [ ] Test scrubbing through gaps
  - Test scrubbing forwards into gap
  - Test scrubbing backwards into gap
  - Test frozen frame shown in gaps
  - Test video resumes after gap
- [ ] Test zoom limits (min/max)
  - Test minimum zoom (60 seconds visible)
  - Test maximum zoom (3600 seconds visible)
  - Test pinch gesture doesn't exceed limits
  - Test timeline rendering at extreme zooms
- [ ] Test three-finger swipe disabled
  - Test three-finger swipe doesn't switch desktops
  - Test behavior restored after app exit
  - Test on multiple macOS versions
- [ ] Test recording pauses when visible
  - Test recording service detects Playback app
  - Test recording pauses when app opens
  - Test recording resumes when app closes
  - Test no data loss during pause/resume
- [ ] Test loading screen behavior
  - Test loading screen shows when processing running
  - Test estimated time remaining (if available)
  - Test ESC cancels and closes app
  - Test automatic dismissal when processing completes
- [ ] Test app icon launch
  - Test clicking icon in Applications folder launches app
  - Test clicking icon in Dock launches app
  - Test icon visible in menu bar (if applicable)
  - Test icon design matches specification
### Performance Tests
- [ ] Verify startup time
  - Target: Cold launch < 2 seconds
  - Target: Database load < 500ms (30 days data)
  - Target: First video load < 500ms
  - Target: Fullscreen transition immediate
- [ ] Verify memory usage
  - Target: Baseline ~100MB (app overhead)
  - Target: Video buffers ~100-200MB (AVPlayer managed)
  - Target: Timeline rendering ~50MB (cached layers)
  - Target: Peak ~300-500MB
- [ ] Verify CPU usage
  - Target: Idle (video paused) < 5%
  - Target: Video playback 15-30% (hardware decode)
  - Target: Scrubbing 20-40% (rapid seeks)
  - Target: Timeline rendering 10-20% (during zoom/pan)
- [ ] Verify GPU usage
  - Video decode: Hardware accelerated (VideoToolbox)
  - UI rendering: Metal backend
  - Target: Smooth 60fps on older Macs
- [ ] Test with 30+ days of data
  - Test database query performance
  - Test timeline rendering performance
  - Test memory usage with large dataset
  - Test scrubbing responsiveness

