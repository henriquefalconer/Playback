# Timeline Graphical Interface Specification

**Component:** Playback (Swift/SwiftUI)
**Version:** 1.0
**Last Updated:** 2026-02-07

## Overview

The Timeline Graphical Interface is a fullscreen timeline viewer that allows users to browse their screen recording history. Designed with simplicity and polish inspired by Arc browser, it provides intuitive navigation through date/time selection and text search. It provides smooth video playback synchronized with an interactive timeline, supporting scrubbing via trackpad/mouse gestures and timeline zoom via pinch gestures.

## Responsibilities

1. Register and respond to global keyboard shortcut (Option+Shift+Space)
2. Launch directly when app icon is clicked
3. Load video segments and metadata from database
4. Display fullscreen timeline interface with video playback
5. Provide smooth scrubbing via trackpad/mouse scroll
6. Support pinch-to-zoom for timeline scale adjustment
7. Show loading screen while processing is in progress
8. Provide date/time navigation with calendar picker
9. Support text search via OCR (search recorded screen content)
10. Pause recording service while visible
11. Auto-refresh to show newly processed segments
12. Disable three-finger swipe between desktops while active

## Design Philosophy

**Inspiration:** Arc browser by The Browser Company

**Key Principles:**
- Minimal, clean interface (no clutter)
- Smooth, polished animations
- Intuitive gestures and interactions
- Focus on content (chrome fades into background)
- Delightful micro-interactions
- Fast, responsive performance

## User Interface

### App Icon

**Design:** Play button inspired by Arc's icon style

**Characteristics:**
- Simple, geometric shape
- Rounded triangle (play symbol)
- Gradient or solid color (vibrant but not overwhelming)
- Clean, modern aesthetic
- Recognizable at small sizes

**Colors:**
- Primary: Vibrant blue/purple gradient (similar to Arc)
- Alternative: Single accent color (user preference in future)

**Reference Style:**
- Arc's icon: Simple, bold, geometric
- Minimal detail, maximum recognition
- Works well in both light and dark menu bar

### Launch Behavior

**Trigger 1:** Global keyboard shortcut `Option+Shift+Space`
**Trigger 2:** Click Playback.app icon in Applications or Dock

**Process:**
1. Check if `build_chunks_from_temp.py` is currently running
2. If running: Show loading screen, wait for completion
3. Load database and segments
4. Enter fullscreen mode
5. Position timeline at most recent timestamp
6. Begin video playback
7. Signal recording service to pause

### Loading Screen

**Displayed when:** Processing service is running at launch time

**Design:**
```
┌────────────────────────────────────────────┐
│                                            │
│                                            │
│              Playback                  │
│                                            │
│           ⏳ Processing...                │
│                                            │
│    Preparing your screen recordings        │
│                                            │
│        [Animated spinner]                  │
│                                            │
│                                            │
└────────────────────────────────────────────┘
```

**Elements:**
- App name/logo
- Status text: "Processing..." or "Loading segments..."
- Animated spinner (macOS standard)
- Semi-transparent black background
- Centered on screen

**Behavior:**
- Polls for process completion every 500ms
- Shows estimated time remaining (if available from logs)
- Dismisses automatically when processing completes
- User can cancel with ESC key (closes app)

### Main Interface

**Fullscreen Mode:**
- No title bar, no window chrome
- Black letterboxing for non-matching aspect ratios
- Video fills screen (scaled to fit)
- Timeline overlaid at bottom
- Gradient overlay for timeline visibility

### Video Playback Area

**Layout:**
- Full screen (ignoring safe area)
- AVPlayer with VideoBackgroundView
- Letterboxed if video aspect ratio doesn't match screen
- Smooth transitions between segments

**Frozen Frame:**
- Shown when navigating between segments or to gaps
- Last known frame displayed as static image
- Black background behind image
- Prevents jarring "black screen" transitions

**Implementation:**
```swift
ZStack {
    // Video player (background)
    VideoBackgroundView(player: playbackController.player)
        .ignoresSafeArea()

    // Frozen frame (overlay when needed)
    if playbackController.showFrozenFrame, let image = playbackController.frozenFrame {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea()
        }
    }

    // Timeline UI (overlay at bottom)
    // ...
}
```

### Timeline View

**Position:** Bottom of screen, 120px height, 40px margin from bottom edge

**Design:**
```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│                                                          │
│                                                          │
│  [Video content fills this area]                        │
│                                                          │
│                                                          │
│                                                          │
│  ┌─────────────────────────────────────────────────┐   │
│  │ Subtle gradient overlay                          │   │
│  │                                                   │   │
│  │  [Timeline with app segments]                    │   │
│  │             ▼ Playhead                           │   │
│  │  ─────█████─────██████████─────█████─────        │   │
│  │  10:00 AM         12:00 PM         2:00 PM      │   │
│  │                                                   │   │
│  │  Time bubble: 1:23:45 PM                         │   │
│  └─────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

**Components:**

1. **Gradient Overlay**
   - Linear gradient from transparent (top) to translucent blue-gray (bottom)
   - Height: 140px
   - Ensures timeline visibility over any video content

2. **Segments Bar**
   - Horizontal bar showing all video segments
   - Each segment: Rounded rectangle with app-specific color
   - Gaps between segments: Transparent (shows background)
   - Height: 20px

3. **Playhead**
   - Vertical line indicating current time
   - Red color (#FF0000)
   - Extends 30px above and below timeline bar
   - Capped with small circle (5px radius)

4. **Time Labels**
   - Major ticks every N hours (depends on zoom level)
   - Minor ticks every N/5 hours
   - Label format: "10:00 AM" or "2:30 PM"
   - Color: White with slight shadow for readability

5. **Time Bubble (clickable)**
   - Follows playhead position
   - Shows current timestamp in larger text
   - Format: "1:23:45 PM" (with seconds)
   - Background: Semi-transparent rounded rectangle
   - Positioned above playhead
   - **Clickable:** Opens date/time picker popup

**App Segment Colors:**

Generated deterministically from bundle ID hash:
```swift
func colorForApp(_ bundleId: String?) -> Color {
    guard let bundleId = bundleId else {
        return Color.gray.opacity(0.5)
    }

    let hash = bundleId.hashValue
    let hue = Double(abs(hash) % 360) / 360.0
    return Color(hue: hue, saturation: 0.6, brightness: 0.8)
}
```

### Date/Time Picker

**Trigger:** Click on time bubble at bottom of screen

**Design Philosophy:**
- Inspired by Arc's Command Bar and date pickers
- Clean, minimal design with smooth animations
- Keyboard-navigable
- Responsive and fast

**Popup Design:**

```
┌────────────────────────────────────────────────────┐
│                                                    │
│   ┌─────────────────────┐  ┌──────────────────┐  │
│   │   December 2025     │  │   Times          │  │
│   │  S  M  T  W  T  F  S│  │                  │  │
│   │           1  2  3  4│  │  ▸ 09:00 AM      │  │
│   │  5  6  7  8  9 10 11│  │    10:15 AM      │  │
│   │ 12 13 14 15 16 17 18│  │    11:30 AM      │  │
│   │ 19 20 21 22 23 24 25│  │    12:45 PM      │  │
│   │ 26 27 28 29 30 31   │  │    02:00 PM      │  │
│   │                      │  │  ▸ 03:15 PM      │  │
│   │  ◀  Today    ▶      │  │    04:30 PM      │  │
│   └─────────────────────┘  │    05:45 PM      │  │
│                            │    ...           │  │
│                            └──────────────────┘  │
│                                                    │
│   [Jump to Date/Time]                [Cancel]     │
└────────────────────────────────────────────────────┘
```

**Dimensions:**
- Width: 600px
- Height: 400px
- Positioned: Center of screen
- Background: Blurred backdrop (Arc-style frosted glass effect)
- Border: Subtle rounded corners (12px radius)

**Calendar View (Left Panel):**

**Month Header:**
- Month and year displayed prominently
- Previous/Next month arrows
- "Today" button to jump to current date

**Calendar Grid:**
- 7 columns (Sun-Sat)
- 5-6 rows (dates)
- Date styling:
  - **Normal:** White text, no background
  - **Today:** Accent color border
  - **Selected:** Accent color background
  - **Has recordings:** Bold text
  - **No recordings:** Greyed out (50% opacity), not clickable
  - **Hover:** Subtle highlight (if has recordings)

**Implementation:**
```swift
struct CalendarDayView: View {
    let date: Date
    let hasRecordings: Bool
    let isSelected: Bool
    let isToday: Bool
    @Binding var selectedDate: Date

    var body: some View {
        Text("\(Calendar.current.component(.day, from: date))")
            .fontWeight(hasRecordings ? .bold : .regular)
            .foregroundColor(hasRecordings ? .primary : .secondary)
            .opacity(hasRecordings ? 1.0 : 0.3)
            .frame(width: 40, height: 40)
            .background(isSelected ? Color.accentColor : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .onTapGesture {
                if hasRecordings {
                    selectedDate = date
                }
            }
            .disabled(!hasRecordings)
    }
}
```

**Time List (Right Panel):**

**Header:**
- "Times" label
- Scrollable list of available times

**Time Entries:**
- Format: "HH:MM AM/PM"
- 15-minute intervals shown (09:00, 09:15, 09:30, ...)
- Styling:
  - **Has recordings:** Normal text, white
  - **No recordings:** Greyed out (50% opacity), not clickable
  - **Currently playing:** Marked with ▸ indicator
  - **Selected:** Accent color background
  - **Hover:** Subtle highlight (if has recordings)

**Scrolling:**
- Smooth scroll to selected time on open
- Keyboard navigation (arrow keys)
- Mouse wheel/trackpad scrolling

**Implementation:**
```swift
struct TimeListView: View {
    let date: Date
    let availableTimes: [TimeInterval]
    let currentTime: TimeInterval
    @Binding var selectedTime: TimeInterval

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(generateTimeSlots(), id: \.self) { time in
                        let hasRecording = availableTimes.contains(time)
                        let isCurrent = abs(time - currentTime) < 60 // Within 1 minute

                        HStack {
                            if isCurrent {
                                Image(systemName: "play.fill")
                                    .font(.caption)
                            }
                            Text(formatTime(time))
                                .foregroundColor(hasRecording ? .primary : .secondary)
                                .opacity(hasRecording ? 1.0 : 0.3)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedTime == time ? Color.accentColor : Color.clear)
                        .cornerRadius(6)
                        .onTapGesture {
                            if hasRecording {
                                selectedTime = time
                            }
                        }
                        .disabled(!hasRecording)
                        .id(time)
                    }
                }
                .padding()
            }
            .onAppear {
                proxy.scrollTo(currentTime, anchor: .center)
            }
        }
    }

    func generateTimeSlots() -> [TimeInterval] {
        // Generate 15-minute intervals for selected day
        // ...
    }
}
```

**Behavior:**

1. **Opening:**
   - Fade in animation (0.2s)
   - Subtle scale effect (Arc-style)
   - Calendar shows current month
   - Time list scrolls to current time
   - Selected date/time match current playback position

2. **Navigation:**
   - Click date: Updates time list with available times for that day
   - Click time: Jumps to that timestamp in video (closes popup)
   - Previous/Next month: Animates calendar transition
   - "Today" button: Jumps to current date

3. **Closing:**
   - Click "Jump to Date/Time" button: Navigates to selected date/time, closes popup
   - Click "Cancel" or ESC: Closes popup without navigation
   - Click outside popup: Closes popup (same as Cancel)
   - Fade out animation (0.15s)

4. **Background Change:**
   - When date/time selected and confirmed: Video INSTANTLY changes (no scroll animation)
   - Playback controller updates video segment
   - Timeline updates to show new position
   - No smooth scroll transition (instant jump)

**Data Loading:**

```swift
func loadAvailableDates() -> Set<Date> {
    // Query database for all dates with recordings
    let segments = timelineStore.segments
    return Set(segments.map { segment in
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: segment.startTS))
    })
}

func loadAvailableTimes(for date: Date) -> [TimeInterval] {
    // Query database for all timestamps on given date
    let dayStart = Calendar.current.startOfDay(for: date)
    let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

    return timelineStore.segments
        .filter { $0.startTS >= dayStart.timeIntervalSince1970 && $0.startTS < dayEnd.timeIntervalSince1970 }
        .map { $0.startTS }
        .sorted()
}
```

**Performance:**
- Calendar rendered on-demand (not all months preloaded)
- Time list uses LazyVStack for efficiency
- Date queries cached (invalidated on new recordings)

### Text Search

**Trigger:** Command+F (standard search shortcut)

**Design:**
- Floating search bar (top-right corner)
- Arc-style minimal design
- Search as you type (debounced)

**Search Bar:**
```
┌─────────────────────────────────┐
│  🔍  Search screen content...   │
└─────────────────────────────────┘
```

**Features:**
- OCR-based text search across all recordings
- Highlights matching segments in timeline
- Jump to next/previous match (Enter/Shift+Enter)
- Shows match count ("3 of 15 matches")
- Real-time search results

**Implementation:** See separate OCR Search specification (13-search-ocr.md)

### Keyboard Shortcuts

**ESC** - Close playback app
- Exits fullscreen
- Closes window
- Signals recording service to resume
- Preserves: Last viewed timestamp (not persisted)

**Command+F** - Open text search
- Shows search bar
- Focuses input field
- Initiates OCR search

**All other shortcuts from prototype:**
- Scroll: Scrub timeline
- Pinch: Zoom timeline

### Trackpad/Mouse Interactions

**Horizontal Scroll (Two-Finger Swipe)**
- Direction: Natural scrolling inverted
  - Swipe RIGHT → Move forward in time (future)
  - Swipe LEFT → Move backward in time (past)
- Speed: Dynamic based on visible window size
  - Formula: `secondsPerPoint = visibleWindowSeconds / 1000.0`
  - Example: 1-hour window → ~3.6s per scroll point
- Behavior:
  - Immediate scrubbing (no debounce)
  - Video remains PAUSED during scrubbing
  - Updates timeline position in real-time
  - Clamps to timeline bounds (earliest/latest timestamp)

**Implementation:**
```swift
scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
    let fingerDelta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaX : event.scrollingDeltaX
    let secondsPerPoint = visibleWindowSeconds / 1000.0
    let secondsDelta = Double(fingerDelta) * secondsPerPoint

    var newTime = playbackController.currentTime + secondsDelta
    newTime = clamp(newTime, timelineStart, timelineEnd)

    playbackController.scrub(to: newTime, store: timelineStore)
    centerTime = playbackController.currentTime

    return nil  // Consume event
}
```

**Pinch Gesture (Zoom)**
- Direction:
  - Pinch OUT → Zoom IN (show less time, more detail)
  - Pinch IN → Zoom OUT (show more time, less detail)
- Sensitivity: Exponential (`pow(value, 3.0)` for aggressive zoom)
- Limits:
  - Minimum: 60 seconds (1 minute visible)
  - Maximum: 3600 seconds (60 minutes visible)
- Behavior:
  - Applies to entire window (not just over timeline)
  - Spring animation for smooth feel
  - Response: 0.35s, Damping: 0.8

**Implementation:**
```swift
.simultaneousGesture(
    MagnificationGesture()
        .onChanged { value in
            guard let base = pinchBaseVisibleWindowSeconds else { return }
            let factor = pow(Double(value), 3.0)
            var newWindow = base / factor
            newWindow = clamp(newWindow, minVisibleWindowSeconds, maxVisibleWindowSeconds)
            visibleWindowSeconds = newWindow
        }
        .onEnded { _ in
            pinchBaseVisibleWindowSeconds = nil
        }
)
```

**Click on Timeline**
- Action: Seek to clicked timestamp
- Visual feedback: Playhead jumps to position
- Video updates immediately

### Three-Finger Swipe Behavior

**Requirement:** Disable three-finger swipe between desktops while playback app is active

**Implementation:**
```swift
// On appear
NSApplication.shared.presentationOptions.insert(.disableForceQuit)

// Disable Mission Control gestures
let options = NSApplication.PresentationOptions.fullScreen
    .union(.autoHideMenuBar)
    .union(.autoHideDock)
    .union(.disableProcessSwitching)
    .union(.disableForceQuit)
    .union(.disableSessionTermination)
    .union(.disableHideApplication)

NSApp.presentationOptions = options

// On disappear (restore normal behavior)
NSApp.presentationOptions = []
```

**Alternative approach (if above doesn't work):**
Monitor three-finger swipe events and consume them:
```swift
NSEvent.addLocalMonitorForEvents(matching: .gesture) { event in
    // Detect three-finger swipe
    if event.type == .swipe && event.phase == .began {
        return nil  // Consume event
    }
    return event
}
```

## Data Loading

### Database Connection

**File:** `~/Library/Application Support/Playback/data/meta.sqlite3`

**Query:**
```sql
SELECT id, start_ts, end_ts, frame_count, fps, video_path
FROM segments
ORDER BY start_ts ASC;
```

**Segment Model:**
```swift
struct Segment: Identifiable {
    let id: String
    let startTS: TimeInterval
    let endTS: TimeInterval
    let frameCount: Int
    let fps: Double?
    let videoURL: URL

    var duration: TimeInterval {
        max(0, endTS - startTS)
    }

    var videoDuration: TimeInterval? {
        guard let fps, fps > 0, frameCount > 0 else { return nil }
        return TimeInterval(Double(frameCount) / fps)
    }

    func videoOffset(forAbsoluteTime time: TimeInterval) -> TimeInterval {
        let clampedTime = min(max(time, startTS), endTS)
        let timelineOffset = max(0, min(clampedTime - startTS, duration))

        guard let videoDuration, duration > 0 else {
            return timelineOffset
        }

        let ratio = timelineOffset / duration
        return videoDuration * min(1.0, ratio)
    }

    func absoluteTime(forVideoOffset offset: TimeInterval) -> TimeInterval {
        guard let videoDuration, videoDuration > 0, duration > 0 else {
            return startTS + min(offset, duration)
        }

        let ratio = min(max(offset / videoDuration, 0), 1)
        let timelineOffset = ratio * duration
        return startTS + timelineOffset
    }
}
```

**App Segments Query:**
```sql
SELECT id, app_id, start_ts, end_ts
FROM appsegments
ORDER BY start_ts ASC;
```

**App Segment Model:**
```swift
struct AppSegment: Identifiable {
    let id: String
    let startTS: TimeInterval
    let endTS: TimeInterval
    let appId: String?

    var duration: TimeInterval {
        max(0, endTS - startTS)
    }
}
```

### Auto-Refresh

**Trigger:** New segments added to database (processing completed)

**Implementation:**
```swift
.onChange(of: timelineStore.segments.count) { _, newCount in
    guard newCount > 0, let latest = timelineStore.latestTS else { return }
    print("[ContentView] segments.count changed to \(newCount); repositioning to latest")
    centerTime = latest
    playbackController.update(for: latest, store: timelineStore)
}
```

**Polling (fallback if onChange not reliable):**
```swift
Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
    timelineStore.reload()
}
```

## Video Playback Control

### Playback Controller

**Responsibilities:**
- Manage AVPlayer instance
- Load appropriate video segment for current time
- Handle segment transitions
- Maintain frozen frame during transitions
- Track current playback time
- Support scrubbing

**State:**
```swift
class PlaybackController: ObservableObject {
    @Published var player: AVPlayer
    @Published var currentTime: TimeInterval = 0
    @Published var showFrozenFrame: Bool = false
    @Published var frozenFrame: NSImage?

    private var currentSegment: Segment?
    private var timeObserver: Any?
}
```

### Segment Selection

**Function:** `segment(for time: TimeInterval, direction: TimeInterval) -> (Segment, TimeInterval)?`

**Logic:**
1. If `time` falls within a segment: Return that segment
2. If `time` is before first segment: Return first segment at start
3. If `time` is after last segment: Return last segment at end
4. If `time` is in a gap between segments:
   - If moving FORWARD: Return next segment at start
   - If moving BACKWARD: Return previous segment at end
   - If no direction: Return closest segment

**Rationale:** Prevents unexpected jumps when scrubbing through gaps

### Video Loading

**Process:**
1. Determine target segment and video offset
2. If segment changed: Load new video file
3. Seek to video offset
4. Show frozen frame during loading
5. Hide frozen frame when new video is ready

**Implementation:**
```swift
func update(for time: TimeInterval, store: TimelineStore) {
    guard let (segment, offset) = store.segment(for: time) else { return }

    if currentSegment?.id != segment.id {
        // Capture frozen frame from current player
        frozenFrame = captureCurrentFrame()
        showFrozenFrame = true

        // Load new segment
        let playerItem = AVPlayerItem(url: segment.videoURL)
        player.replaceCurrentItem(with: playerItem)
        currentSegment = segment

        // Seek to offset
        player.seek(to: CMTime(seconds: offset, preferredTimescale: 600)) { [weak self] _ in
            self?.showFrozenFrame = false
        }
    } else {
        // Same segment, just seek
        player.seek(to: CMTime(seconds: offset, preferredTimescale: 600))
    }

    currentTime = time
}
```

### Time Observer

**Purpose:** Keep `currentTime` synchronized with AVPlayer's actual playback position

**Implementation:**
```swift
func setupTimeObserver() {
    let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
        guard let self = self, let segment = self.currentSegment else { return }

        let videoOffset = time.seconds
        let absoluteTime = segment.absoluteTime(forVideoOffset: videoOffset)

        self.currentTime = absoluteTime
    }
}
```

### Scrubbing

**Function:** `scrub(to time: TimeInterval, store: TimelineStore)`

**Behavior:**
- Pause playback
- Update video position immediately
- Keep video paused (user is actively scrubbing)
- Resume playback only when scrubbing stops (via timer)

**Implementation:**
```swift
func scrub(to time: TimeInterval, store: TimelineStore) {
    player.pause()
    update(for: time, store: store)

    // Debounce: Resume playback after 500ms of no scrubbing
    scrubDebounceTimer?.invalidate()
    scrubDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
        self?.player.play()
    }
}
```

## Recording Service Integration

### Pause Recording When Visible

**Mechanism:** Recording service checks for playback app process

**Recording service code:**
```python
def is_playback_app_visible() -> bool:
    # Check if Playback (playback) app is running and frontmost
    script = '''
    tell application "System Events"
        set frontApp to name of first process whose frontmost is true
        return frontApp
    end tell
    '''
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    return "Playback" in result.stdout
```

**Alternative (simpler):** Check for process existence
```python
def is_playback_app_running() -> bool:
    result = subprocess.run(["pgrep", "-f", "Playback.app"], capture_output=True)
    return result.returncode == 0
```

### Resume Recording When Closed

**Playback app signals recording service on exit:**
- No explicit IPC needed
- Recording service automatically resumes when playback app process ends

## Global Keyboard Shortcut

### Registration

**Framework:** Carbon framework (for system-wide hotkeys)

**Implementation:**
```swift
import Carbon

class GlobalHotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private let signature = UTGetOSTypeFromString("SSEN" as CFString)
    private let hotkeyID = EventHotKeyID(signature: signature, id: 1)

    func register(key: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let handler = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            handler.onHotkey()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        RegisterEventHotKey(key, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func onHotkey() {
        // Launch playback app
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

**Shortcut:** Option+Shift+Space
- Key code: 49 (Space)
- Modifiers: optionKey + shiftKey

**Alternative (using Accessibility):**
```swift
// In app delegate
func applicationDidFinishLaunching(_ notification: Notification) {
    NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 49 && event.modifierFlags.contains([.option, .shift]) {
            self.showPlaybackWindow()
        }
    }
}
```

**Accessibility Permission:** Required for global event monitoring

## Error Handling

### Database Not Found

**Scenario:** meta.sqlite3 doesn't exist (no recordings yet)

**Behavior:**
1. Show empty state screen
2. Message: "No recordings yet. Start recording from the menu bar."
3. Button: "Open Menu Bar Settings"
4. ESC to close

### Video File Missing

**Scenario:** Segment exists in database but video file is missing

**Behavior:**
1. Log warning
2. Show frozen frame (last known good frame)
3. Continue timeline playback
4. Skip to next available segment

### Segment Loading Failure

**Scenario:** AVPlayer fails to load video file

**Behavior:**
1. Log error with details
2. Show frozen frame
3. Attempt to load next segment
4. If multiple consecutive failures: Show error message

### Permission Denied

**Scenario:** Screen Recording permission revoked

**Behavior:**
1. Show error dialog: "Playback needs Screen Recording permission"
2. Button: "Open System Preferences"
3. Cannot display videos without permission

## Performance Characteristics

### Startup Time

- Cold launch: 1-2 seconds
- Database load: < 500ms (for 30 days of data)
- First video load: < 500ms
- Fullscreen transition: Immediate

### Memory Usage

- Baseline: ~100MB (app overhead)
- Video buffers: ~100-200MB (AVPlayer managed)
- Timeline rendering: ~50MB (cached layers)
- Peak: ~300-500MB

### CPU Usage

- Idle (video paused): < 5%
- Video playback: 15-30% (hardware decode)
- Scrubbing: 20-40% (rapid seeks)
- Timeline rendering: 10-20% (during zoom/pan)

### GPU Usage

- Video decode: Hardware accelerated (VideoToolbox)
- UI rendering: Metal backend
- Smooth 60fps even on older Macs

## Testing

### Unit Tests

- Segment selection logic (gaps, boundaries)
- Time mapping (video offset ↔ absolute time)
- App color generation (deterministic)

### Integration Tests

- Database loading
- Video playback
- Segment transitions
- Scrubbing accuracy

### UI Tests

- Global hotkey activation
- Fullscreen mode
- Scroll/pinch gestures
- ESC key handling

### Manual Tests

- Long recording session (24+ hours)
- Multiple segment transitions
- Scrubbing through gaps
- Zoom limits (min/max)
- Three-finger swipe disabled
- Recording pauses when visible

## Dependencies

- macOS 12.0+ (Monterey or later)
- Swift 5.5+
- SwiftUI 3.0+
- AVFoundation (AVPlayer, AVKit)
- SQLite3 (system framework)
- Carbon (global hotkeys)

## Future Enhancements

### Potential Features

1. **Search by App** - Jump to segments from specific app
2. **Date Picker** - Calendar UI to jump to specific date
3. **Bookmarks** - Save interesting moments
4. **Export Range** - Export time range as video file
5. **Annotations** - Add notes to timeline
6. **Thumbnail Scrubbing** - Show frame preview while scrubbing
7. **Multi-Display Timeline** - Separate tracks for each monitor
8. **Speed Control** - Playback speed adjustment (0.5x, 2x, etc.)
9. **Picture-in-Picture** - View timeline while working
10. **Shared Sessions** - View recordings from other devices

### Performance Optimizations

1. **Predictive Loading** - Preload next segment
2. **Thumbnail Cache** - Cache timeline thumbnails
3. **Lazy Segment Loading** - Load only visible segments
4. **Metal Shaders** - Custom video rendering pipeline
