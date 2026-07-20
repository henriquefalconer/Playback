import SwiftUI
import AVKit
import AppKit
import os

/// A clicked result's matched-word boxes (normalized Vision coords) tied to the
/// timestamp they belong to, so they can be cleared once the user scrubs away.
struct MatchHighlight: Equatable {
    let ts: TimeInterval
    let rects: [CGRect]
}

struct ContentView: View {
    @EnvironmentObject var timelineStore: TimelineStore
    @EnvironmentObject var playbackController: PlaybackController
    @ObservedObject private var processingService = ProcessingService.shared

    // Initial load: the video area stays black until the pending screenshots
    // are encoded and the player is ready at the latest frame.
    @State private var revealVideo = false
    // True once the store has been reloaded AFTER the opening backlog finished
    // encoding — revealing before this shows a stale "latest" frame, because
    // the store's auto-refresh only picks up new segments every 5 seconds.
    @State private var latestDataLoaded = false

    @StateObject private var searchIndex = SearchIndex()
    @State private var showSearch = false
    // Incremented to ask the open search panel to (re)focus its field.
    @State private var focusSearchTrigger = 0
    // The clicked search result's match location(s), highlighted on the frame.
    @State private var matchHighlight: MatchHighlight?
    // True while the pointer is over the search panel, so scroll wheel events
    // scroll the results list instead of scrubbing the timeline behind it.
    @State private var pointerInSearchPanel = false

    @State private var centerTime: TimeInterval = Date().timeIntervalSince1970
    @State private var showDatePicker = false
    // Visible time window in timeline (in seconds).
    @State private var visibleWindowSeconds: TimeInterval = 60 * 1
    // Zoom limits: prevents zooming in/out beyond these values.
    private let minVisibleWindowSeconds: TimeInterval = 60          // 1 minute
    private let maxVisibleWindowSeconds: TimeInterval = 60 * 60     // 60 minutes
    // Base used for pinch gesture (zoom) applied to entire window.
    @State private var pinchBaseVisibleWindowSeconds: TimeInterval?
    // Anchor timestamp for cursor-anchored zoom (timestamp under cursor when pinch starts)
    @State private var pinchAnchorTimestamp: TimeInterval?
    // Exponent that controls pinch zoom sensitivity.
    private let pinchZoomExponent: Double = 3.0
    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?
    // Momentum scrolling state (for non-trackpad scroll wheels).
    // Trackpad momentum is already handled by OS-generated momentumPhase events.
    @State private var momentumVelocity: Double = 0     // seconds per scroll point
    @State private var momentumTimer: Timer?

    var body: some View {
        ZStack {
            if timelineStore.loadingState == .empty {
                EmptyStateView()
            } else if case .error(let errorMessage) = timelineStore.loadingState {
                ErrorStateView(errorType: .databaseError(errorMessage))
            } else if let playbackError = playbackController.playbackError {
                playbackErrorView(playbackError)
            } else {
                timelineContentView
            }
        }
        .onAppear {
            revealVideo = false
            latestDataLoaded = false
            setupEventHandlers()
            timelineStore.resume()
            // OCR search indexing runs ONLY while the timeline is open, so the
            // background recording path never spends CPU on text recognition.
            ProcessingService.shared.beginTimelineIndexing()
            // If segments are already loaded when view appears,
            // immediately position at the most recent instant; otherwise show
            // "Now" until the data arrives.
            if let latest = timelineStore.latestTS {
                centerTime = latest
                playbackController.update(for: latest, store: timelineStore)
            } else {
                centerTime = Date().timeIntervalSince1970
                playbackController.currentTime = centerTime
            }
        }
        .onDisappear {
            cleanupEventHandlers()
            playbackController.releaseResources()
            timelineStore.suspend()
            TimelineView.clearCaches()
            // Stop indexing and kill any in-flight OCR helper the moment the
            // timeline closes — no OCR CPU survives the window.
            ProcessingService.shared.endTimelineIndexing()
            searchIndex.deactivate()
            showSearch = false
            revealVideo = false
            latestDataLoaded = false
        }
        // Load/decrypt the OCR index into memory only while the search modal is
        // open; drop it again the moment it closes.
        .onChange(of: showSearch) { _, isOpen in
            if isOpen {
                searchIndex.activate()
            } else {
                searchIndex.deactivate()
                pointerInSearchPanel = false
                matchHighlight = nil
            }
        }
        // Clear the match highlight once the user scrubs away from the moment it
        // belongs to (centerTime is the canonical scrub position, set exactly on
        // jump, so this never fires on the jump itself).
        .onChange(of: centerTime) { _, center in
            if let highlight = matchHighlight, abs(center - highlight.ts) > 0.5 {
                withAnimation(.easeOut(duration: 0.15)) { matchHighlight = nil }
            }
        }
        // Playback advances past the highlighted frame — drop the now-stale box.
        .onChange(of: playbackController.isPlaying) { _, playing in
            if playing, matchHighlight != nil {
                withAnimation(.easeOut(duration: 0.15)) { matchHighlight = nil }
            }
        }
        // Whenever segment count changes (initial load or reload),
        // reposition centerTime to the latest available timestamp.
        .onChange(of: timelineStore.segments.count) { _, newCount in
            guard newCount > 0, let latest = timelineStore.latestTS else { return }
            Log.ui.debug("segments.count changed to \(newCount); repositioning centerTime to latestTS=\(latest)")
            centerTime = latest
            // Until the initial load completes (backlog encoded + store
            // reloaded), don't load intermediate segments into the player —
            // the video area is black and every load spins up a decoder for
            // frames nobody sees. The reload completion performs the final load.
            if !revealVideo && !latestDataLoaded { return }
            playbackController.update(for: latest, store: timelineStore)
        }
        // When the opening backlog finishes encoding, reload the store so the
        // just-encoded segments are visible, then jump to the true latest
        // frame; the black cover lifts once the player is ready there.
        .onChange(of: processingService.isRunning) { _, running in
            guard !running, !revealVideo else { return }
            timelineStore.reload {
                latestDataLoaded = true
                guard let latest = timelineStore.latestTS else { return }
                centerTime = latest
                playbackController.update(for: latest, store: timelineStore)
                maybeRevealVideo()
            }
        }
        .onChange(of: playbackController.isCurrentItemReady) { _, _ in
            maybeRevealVideo()
        }
        // Allow pinch zoom in ANY window area, not just over segment bar.
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    guard !showDatePicker else { return }
                    guard value.isFinite, value > 0 else { return }

                    if pinchBaseVisibleWindowSeconds == nil {
                        pinchBaseVisibleWindowSeconds = visibleWindowSeconds
                        pinchAnchorTimestamp = centerTime
                        Log.ui.info("Pinch zoom started — visibleWindowSeconds=\(visibleWindowSeconds)")
                    }
                    guard let base = pinchBaseVisibleWindowSeconds else { return }
                    guard let anchorTimestamp = pinchAnchorTimestamp else { return }

                    let zoomFactor = pow(Double(value), pinchZoomExponent)

                    var newWindow = base / zoomFactor
                    if newWindow < minVisibleWindowSeconds {
                        newWindow = minVisibleWindowSeconds
                    } else if newWindow > maxVisibleWindowSeconds {
                        newWindow = maxVisibleWindowSeconds
                    }

                    if abs(newWindow - visibleWindowSeconds) > 0.001 {
                        let oldWindow = visibleWindowSeconds
                        visibleWindowSeconds = newWindow
                        centerTime = anchorTimestamp + (centerTime - anchorTimestamp) * (newWindow / oldWindow)

                        Log.ui.info("Pinch zoom -> visibleWindowSeconds=\(visibleWindowSeconds), centerTime=\(centerTime)")
                    }
                }
                .onEnded { _ in
                    Log.ui.info("Pinch zoom ended — visibleWindowSeconds=\(visibleWindowSeconds)")
                    pinchBaseVisibleWindowSeconds = nil
                    pinchAnchorTimestamp = nil
                }
        )
    }

    @ViewBuilder
    private var timelineContentView: some View {
        ZStack {
            VideoBackgroundView(player: playbackController.player)
                .ignoresSafeArea()

            // While a new segment is loading, show the last known frame as fallback
            // to avoid abrupt black screens. Crossfades in/out over 200ms.
            if playbackController.showFrozenFrame, let image = playbackController.frozenFrame {
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }

            // Initial load: cover the video (and frozen frame) with black until
            // the latest frame is decoded, instead of flashing through
            // partially loaded frames.
            if !revealVideo {
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }

            // Yellow highlight over the exact spot the search match sits on the
            // frame, mapped from Vision's normalized boxes into the aspect-fit
            // video rect.
            if revealVideo, let highlight = matchHighlight, !highlight.rects.isEmpty,
               let segment = playbackController.currentSegment, segment.width > 0, segment.height > 0 {
                GeometryReader { geo in
                    let aspect = CGFloat(segment.width) / CGFloat(segment.height)
                    ForEach(Array(highlight.rects.enumerated()), id: \.offset) { _, box in
                        let rect = Self.screenRect(for: box, videoAspect: aspect, in: geo.size)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.yellow.opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(Color.yellow.opacity(0.9), lineWidth: 1.5)
                            )
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                .allowsHitTesting(false)
                .ignoresSafeArea()
                .transition(.opacity)
            }

            // Subtle bottom gradient in gray-blue tones
            VStack {
                Spacer()
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color(.sRGB, red: 0.60, green: 0.68, blue: 0.98, opacity: 0.25)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                .ignoresSafeArea(edges: .bottom)
            }

            // Timeline + playhead + bubble
            GeometryReader { geo in
                VStack {
                    Spacer()

                    TimelineView(
                        centerTime: $centerTime,
                        visibleWindowSeconds: $visibleWindowSeconds,
                        showDatePicker: $showDatePicker
                    )
                    .environmentObject(timelineStore)
                    .environmentObject(playbackController)
                    .frame(height: 120)
                    .padding(.bottom, 40)
                    .animation(
                        .spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.15),
                        value: visibleWindowSeconds
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            if showDatePicker {
                DateTimePickerView(
                    isPresented: $showDatePicker,
                    selectedTime: Binding(
                        get: { playbackController.currentTime },
                        set: { newTime in
                            centerTime = newTime
                            playbackController.scrub(to: newTime, store: timelineStore)
                        }
                    )
                )
                .environmentObject(timelineStore)
                .transition(.opacity)
            }

            // Top-right search modal. No background dimming — the timeline stays
            // fully visible behind it.
            if showSearch {
                // Transparent catcher: a click anywhere outside the panel closes
                // the modal. It doesn't tint the background, so the timeline
                // stays fully visible.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { showSearch = false }
                    .zIndex(9)

                SearchOverlayView(
                    index: searchIndex,
                    focusTrigger: focusSearchTrigger
                ) { ts, id, query in
                    jumpToMoment(ts, id: id, query: query)
                }
                .onHover { pointerInSearchPanel = $0 }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 28)
                .padding(.trailing, 28)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .zIndex(10)
            }

        }
        .animation(.easeInOut(duration: 0.15), value: showDatePicker)
        .animation(.easeInOut(duration: 0.18), value: showSearch)
    }

    @ViewBuilder
    private func playbackErrorView(_ error: PlaybackError) -> some View {
        switch error {
        case .videoFileMissing(let filename):
            ErrorStateView(errorType: .videoFileMissing(filename))
        case .segmentLoadingFailure(let message):
            ErrorStateView(errorType: .segmentLoadingFailure(message))
        case .permissionDenied:
            ErrorStateView(errorType: .permissionDenied)
        case .multipleConsecutiveFailures(let count):
            ErrorStateView(errorType: .multipleConsecutiveFailures(count))
        }
    }

    private func setupEventHandlers() {
        // Listen for retry loading notification
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RetryLoadingTimeline"),
            object: nil,
            queue: .main
        ) { [self] _ in
            timelineStore.loadSegments()
        }

        // Keyboard monitor for global shortcuts
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // keyCode 53 = ESC, 49 = Space, 123 = Left Arrow, 124 = Right Arrow

            let isCmdF = event.modifierFlags.contains(.command)
                && event.charactersIgnoringModifiers?.lowercased() == "f"

            // CMD+F always opens search (if needed) and focuses the field —
            // pressing it again while open just re-focuses.
            if isCmdF {
                showSearch = true
                focusSearchTrigger += 1
                return nil
            }

            // While the search modal is open it owns the keyboard: ESC closes it,
            // and everything else (typing, arrows to move the caret) flows to the
            // search field instead of scrubbing the timeline behind it.
            if showSearch {
                if event.keyCode == 53 {
                    showSearch = false
                    return nil
                }
                return event
            }

            // While the date picker modal is open, ESC dismisses the modal and
            // every other key is left for the modal to handle — playback
            // shortcuts must not scrub the video behind it.
            if showDatePicker {
                if event.keyCode == 53 {
                    showDatePicker = false
                    return nil
                }
                return event
            }

            switch event.keyCode {
            case 53:  // ESC - Close window
                NSApp.keyWindow?.close()
                return nil

            case 49:  // Space - Play/Pause
                self.togglePlayPause()
                return nil

            case 123:  // Left Arrow - Seek backward 5 seconds
                let newTime = max(playbackController.currentTime - 5, timelineStore.timelineStart ?? 0)
                playbackController.scrub(to: newTime, store: timelineStore)
                centerTime = newTime
                return nil

            case 124:  // Right Arrow - Seek forward 5 seconds
                let newTime = min(playbackController.currentTime + 5, timelineStore.timelineEnd ?? playbackController.currentTime)
                playbackController.scrub(to: newTime, store: timelineStore)
                centerTime = newTime
                return nil

            default:
                return event
            }
        }

        // Global scroll monitor to control video time without blocking clicks on timeline.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
            // When the pointer is over the search panel, let the scroll wheel
            // reach its results list instead of scrubbing the timeline behind it.
            if showSearch && pointerInSearchPanel {
                stopMomentum()
                return event
            }

            // While the date picker modal is open, let scroll events through
            // untouched so its time list can scroll instead of scrubbing the
            // timeline behind the modal.
            if showDatePicker {
                stopMomentum()
                return event
            }

            let rawDx = event.scrollingDeltaX
            let rawDy = event.scrollingDeltaY

            // Momentum events generated by the OS (trackpad) — let them apply normally.
            // These are already logarithmically decelerated by macOS.
            // For non-trackpad wheels (momentumPhase == .none, phase == .none),
            // we generate our own momentum after the scroll ends.
            let isOSMomentum = event.momentumPhase != []

            // Stop custom momentum when user starts a new scroll gesture.
            if event.phase == .began || event.phase == .changed {
                stopMomentum()
            }

            Log.ui.debug("ScrollCapture event dx=\(rawDx), dy=\(rawDy), phase=\(event.phase.rawValue), momentumPhase=\(event.momentumPhase.rawValue)")

            guard rawDx != 0 || rawDy != 0 else { return nil }
            let primaryRaw: CGFloat = abs(rawDx) >= abs(rawDy) ? rawDx : rawDy

            let fingerDelta: CGFloat
            if event.isDirectionInvertedFromDevice {
                fingerDelta = -primaryRaw
            } else {
                fingerDelta = primaryRaw
            }

            // Scale by visible window so each scroll point changes a few seconds.
            let secondsPerPoint: Double = visibleWindowSeconds / 1000.0
            let secondsDelta = Double(fingerDelta) * secondsPerPoint

            guard secondsDelta != 0 else { return nil }

            applyScrollDelta(secondsDelta)

            // For non-precise (mouse wheel) events with no OS momentum,
            // record velocity and start custom momentum on scroll end.
            if !event.hasPreciseScrollingDeltas && !isOSMomentum {
                // Accumulate velocity (seconds per scroll-point * points scrolled this tick)
                momentumVelocity = secondsDelta

                if event.phase == .ended || (event.phase == [] && event.momentumPhase == []) {
                    startMomentum()
                }
            }

            return nil
        }
    }

    private func cleanupEventHandlers() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        stopMomentum()
    }

    /// Apply a time delta to the timeline, clamping to timeline bounds.
    private func applyScrollDelta(_ secondsDelta: Double) {
        let base = playbackController.currentTime
        var newTime = base + secondsDelta

        if let start = timelineStore.timelineStart {
            newTime = max(start, newTime)
        }
        if let end = timelineStore.timelineEnd {
            newTime = min(end, newTime)
        }

        playbackController.scrub(to: newTime, store: timelineStore)
        centerTime = playbackController.currentTime
    }

    /// Start custom logarithmic momentum deceleration for non-trackpad scroll wheels.
    /// Each tick decays velocity as v(t) = v0 / (1 + k*n) where n is the tick count,
    /// producing a natural "coast-to-stop" feeling.
    private func startMomentum() {
        stopMomentum()
        guard abs(momentumVelocity) > 0.001 else { return }

        var tickCount = 0
        let initialVelocity = momentumVelocity
        let tickInterval: TimeInterval = 1.0 / 60.0  // 60 fps
        let decayConstant = 0.15  // Controls how quickly momentum decays

        momentumTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [self] timer in
            tickCount += 1
            // Logarithmic deceleration: v(n) = v0 / (1 + k*n)
            let currentVelocity = initialVelocity / (1.0 + decayConstant * Double(tickCount))

            if abs(currentVelocity) < 0.001 {
                stopMomentum()
                return
            }

            applyScrollDelta(currentVelocity)
        }
    }

    private func stopMomentum() {
        momentumTimer?.invalidate()
        momentumTimer = nil
        momentumVelocity = 0
    }

    private func togglePlayPause() {
        playbackController.togglePlayPause()
    }

    /// Jump the timeline to the moment behind a search result. Keeps the search
    /// modal open and does not steal focus from the search field. Then highlights
    /// exactly where the matched text sits on the frame.
    private func jumpToMoment(_ ts: TimeInterval, id: String, query: String) {
        var target = ts
        if let start = timelineStore.timelineStart { target = max(start, target) }
        if let end = timelineStore.timelineEnd { target = min(end, target) }
        matchHighlight = nil
        centerTime = target
        // Pause first so scrub won't auto-resume playback — the highlight is for
        // this exact frame and would go stale the moment the video advances.
        playbackController.pause()
        playbackController.scrub(to: target, store: timelineStore)
        Log.ui.info("Search jump to ts=\(target, privacy: .public)")
        Task {
            let rects = await searchIndex.highlightRects(for: id, query: query)
            guard !rects.isEmpty else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                matchHighlight = MatchHighlight(ts: target, rects: rects)
            }
        }
    }

    /// Map a normalized Vision box (bottom-left origin) into the on-screen rect of
    /// the aspect-fit video within `size`.
    private static func screenRect(for box: CGRect, videoAspect: CGFloat, in size: CGSize) -> CGRect {
        guard videoAspect > 0, size.width > 0, size.height > 0 else { return .zero }
        let windowAspect = size.width / size.height
        let dispW: CGFloat, dispH: CGFloat, offX: CGFloat, offY: CGFloat
        if windowAspect > videoAspect {
            dispH = size.height; dispW = dispH * videoAspect
            offX = (size.width - dispW) / 2; offY = 0
        } else {
            dispW = size.width; dispH = dispW / videoAspect
            offX = 0; offY = (size.height - dispH) / 2
        }
        let x = offX + box.origin.x * dispW
        let width = box.width * dispW
        let height = box.height * dispH
        // Vision's y is bottom-up; flip to top-down screen coordinates.
        // Vision's text boxes sit low relative to the rendered glyphs (they include
        // descender padding), so nudge the highlight up. The offset is proportional
        // to the box height, so it scales correctly with the text size.
        let verticalNudge = height * 0.07
        let y = offY + (1 - box.origin.y - box.height) * dispH - verticalNudge
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Lift the black initial-load cover once the opening backlog is encoded,
    /// the store has been reloaded with the freshly encoded segments, and the
    /// player is ready at the latest frame.
    private func maybeRevealVideo() {
        guard !revealVideo else { return }
        guard latestDataLoaded,
              !processingService.isRunning,
              playbackController.isCurrentItemReady else { return }
        Log.ui.info("Initial load complete — revealing video at latest frame")
        revealVideo = true
    }
}
