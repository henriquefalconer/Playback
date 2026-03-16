# Timeline Graphical Interface Specification

**Component:** Timeline Viewer

## Overview

The timeline viewer is a fullscreen window for browsing recorded screen history. It provides video playback, scrubbing, pinch zoom, and date/time navigation.

## Window Behavior

- Fullscreen, no title bar, no window chrome
- Auto-hides menu bar and Dock
- **Open triggers:** Menu bar "Open Timeline", Option+Shift+Space, app icon
- **Close triggers:** ESC, Cmd+Q (closes window only, not app)
- **On open:** Creates `.timeline_open` signal file → recording pauses
- **On close:** Removes signal file → recording resumes

## Video Playback

### AVPlayer Integration

- Uses `AVPlayer` with `AVPlayerLayer` (no Control Center integration)
- Hardware-accelerated decode via VideoToolbox
- `automaticallyWaitsToMinimizeStalling = false` for immediate playback
- Periodic time observer (0.2s) syncs `currentTime` with player

### Segment Preloading

- At 80% of current segment duration, preload next segment
- Separate `AVPlayer` instance for preloading
- Swap when ready for seamless transitions

### Frozen Frame System

- Capture last frame via `AVAssetImageGenerator` before segment transition
- Display as overlay image during loading
- Smooth crossfade (200ms) from frozen to live video
- Also shown when scrubbing through gaps between segments

### Segment Selection

`TimelineStore.segment(for:time:direction:)`:

- Time within segment → return segment + video offset
- Time in gap, direction forward → jump to next segment start
- Time in gap, direction backward → jump to previous segment end
- Before first segment → return nil
- After last segment → return nil

### Consecutive Failure Tracking

After 3 consecutive segment loading failures, show `ErrorStateView` with retry button.

## Timeline Rendering

### Layout

- Position: Bottom of screen, 80px height, 28px margin
- Gradient overlay for visibility against video

### Segment Bar

- Horizontal bar with rounded rectangles per app segment
- Colors derived from app icons (CIAreaAverage filter)
- Fallback: hash bundle ID to HSL color
- Height: 12px
- Gaps show transparent background

### Playhead

- White vertical line (3px wide, 70px tall) at center
- Fixed position — timeline scrolls behind it

### Time Ticks

Adaptive intervals based on zoom level:

| Visible window | Tick interval |
|---|---|
| 60-180s | 10s |
| 180-600s | 30s |
| 600-1200s | 60s |
| 1200-2400s | 5m |
| 2400-3600s | 10m |

### Time Bubble

- Shows current timestamp (clickable)
- Displays relative time ("5 minutes ago") or absolute ("1:23:45 PM")
- Click opens DateTimePicker

## Gestures

### Horizontal Scroll (Scrubbing)

- Natural scrolling inverted (right = future, left = past)
- Speed: `secondsPerPoint = visibleWindowSeconds / 1000.0`
- Video pauses during scrub, resumes after 500ms of no scroll
- NSEvent local monitor for scroll events

### Pinch Zoom

- Pinch out = zoom in (less time visible)
- Pinch in = zoom out (more time visible)
- Exponential sensitivity: `pow(magnification, 3.0)`
- Range: 60 seconds (min) to 3600 seconds (max)
- Anchor: timestamp under cursor stays stationary
- Spring animation: response 0.35s, damping 0.8

### Click to Seek

- Click on timeline bar jumps to that timestamp
- Expanded hit test area for usability

## Keyboard Shortcuts

| Key | Action |
|---|---|
| ESC | Close timeline window |
| Space | Play/pause |
| Left/Right arrows | Seek backward/forward |

## Date/Time Picker

Triggered by clicking the time bubble.

### Layout

- Modal overlay, centered, ~600x400px
- Frosted glass background

### Calendar (Left Panel)

- Month/year header with navigation arrows
- "Today" button
- 7x6 grid of date cells
- Dates with recordings: bold, clickable
- Dates without recordings: grayed out

### Time List (Right Panel)

- Scrollable list of 15-minute intervals
- Times with recordings: normal, clickable
- Times without recordings: grayed out

### Actions

- **Cancel / ESC:** Close without navigating
- **Jump:** Navigate to selected date/time, close picker

### Data Loading

```sql
-- Available dates
SELECT DISTINCT date FROM segments ORDER BY date;

-- Available times for a date
SELECT start_ts FROM segments WHERE date = ? ORDER BY start_ts;
```

Times rounded to nearest 15-minute interval for display.

## State Views

### EmptyStateView

- Shown when no segments exist in database
- `video.slash` icon, message, "Open Menu Bar" button

### LoadingStateView

- Shown during initial timeline load
- Circular progress indicator

### ErrorStateView

- Shown after 3 consecutive segment loading failures
- Error description, retry button (posts `RetryLoadingTimeline` notification)
- Permission denied: "Open System Settings" button

## Auto-Refresh

TimelineStore polls database every 5 seconds for new segments.

## Source Files

- `ContentView.swift` — Main view composition, gesture handling
- `TimelineView.swift` — Segment bars, playhead, ticks, app colors
- `TimelineStore.swift` — SQLite queries, segment/appsegment models
- `PlaybackController.swift` — AVPlayer, scrubbing, preload, frozen frames
- `VideoBackgroundView.swift` — AVPlayerLayer rendering
- `DateTimePickerView.swift` — Calendar + time picker modal
- `ErrorStateView.swift`, `EmptyStateView.swift`, `LoadingStateView.swift` — State views
