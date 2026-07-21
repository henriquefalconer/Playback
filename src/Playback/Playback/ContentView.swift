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
    @EnvironmentObject var fullscreenManager: FullscreenManagerWrapper
    @ObservedObject private var processingService = ProcessingService.shared

    // Initial load: the video area stays black only until the latest AVAILABLE
    // frame is decoded, then lifts in one instant transition. It does NOT wait
    // for the opening backlog to finish encoding — that can take tens of seconds
    // and staring at black the whole time is the bug this avoids. Once the
    // backlog encodes, a single clean jump upgrades to the true newest frame.
    @State private var revealVideo = false
    // While true, new/reloaded data snaps the playhead to the latest frame. Set
    // false the moment the user navigates by hand, so the post-encode jump to the
    // newest frame never yanks them away from where they scrubbed to.
    @State private var followingLatest = true

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
            followingLatest = true
            // Mark the window open up front so the background OCR pass stays out
            // for the whole session (timeline OCR starts later, at reveal).
            ProcessingService.shared.setTimelineOpen(true)
            setupEventHandlers()
            timelineStore.resume()
            // Refresh the OCR-complete fraction so a search opened right away shows
            // the correct "Loading…" vs "No more results" footer.
            ProcessingService.shared.refreshIndexingProgress()
            // Flush any just-recorded frames into a segment right now (instead of
            // waiting up to 5 min for the next processing cycle), so the newest
            // content is immediately indexable — then index, newest-first.
            ProcessingService.shared.triggerProcessing(source: "timeline-open")
            // NB: OCR indexing is deliberately NOT started here. Its helper pool
            // saturates the video decoder + Neural Engine, and starting it now
            // keeps the newest frame from becoming ready for tens of seconds (the
            // black-screen delay). It starts once the latest frame is revealed —
            // see maybeRevealVideo().
            // Position at the latest available frame and start decoding it now;
            // the black cover lifts the instant that frame is ready. Segments
            // usually aren't loaded yet at onAppear (resume() loads async), in
            // which case onChange(segments.count) does the positioning.
            positionAtLatest()
        }
        .onDisappear {
            cleanupEventHandlers()
            playbackController.releaseResources()
            timelineStore.suspend()
            TimelineView.clearCaches()
            // Stop indexing and kill any in-flight OCR helper the moment the
            // timeline closes — no OCR CPU survives the window. Mark the window
            // closed so the next processing cycle's background pass may run.
            ProcessingService.shared.setTimelineOpen(false)
            ProcessingService.shared.endTimelineIndexing()
            searchIndex.deactivate()
            showSearch = false
            revealVideo = false
            followingLatest = true
        }
        // Load/decrypt the OCR index into memory only while the search modal is
        // open; drop it again the moment it closes.
        .onChange(of: showSearch) { _, isOpen in
            if isOpen {
                // Keep OCR indexing running WHILE searching: the workers are
                // background-QoS/niced so they yield the video decoder to the
                // results' on-demand thumbnails, and a query still being indexed
                // (or one with no matches, like a random string) must keep making
                // progress and streaming in results instead of stalling until the
                // panel closes.
                ProcessingService.shared.beginTimelineIndexing()
                // Make sure the footer's "Loading…"/"No more results" reflects the
                // true pending state the moment the panel opens.
                ProcessingService.shared.refreshIndexingProgress()
                searchIndex.activate()
            } else {
                searchIndex.deactivate()
                pointerInSearchPanel = false
                matchHighlight = nil
                ProcessingService.shared.beginTimelineIndexing()
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
        // Whenever segment count changes (initial load, or the opening backlog
        // finishing), snap to the latest frame and load it — even while black, so
        // it decodes and we can reveal the instant it's ready. Recording is paused
        // while the timeline is open, so `latest` advances at most once (when the
        // backlog encodes): a single clean jump, not a fast-forward. Skipped once
        // the user has scrubbed away, so their position is never yanked.
        .onChange(of: timelineStore.segments.count) { _, newCount in
            guard newCount > 0, followingLatest, let latest = timelineStore.latestTS else { return }
            Log.ui.debug("segments.count changed to \(newCount); snapping centerTime to latestTS=\(latest)")
            centerTime = latest
            playbackController.update(for: latest, store: timelineStore)
        }
        // When the opening backlog finishes encoding, reload the store so the
        // just-encoded segment becomes visible; onChange(segments.count) then
        // jumps to it. (The reveal itself is driven by isCurrentItemReady, so it
        // does not wait on this.)
        .onChange(of: processingService.isRunning) { _, running in
            guard !running else { return }
            timelineStore.reload {
                // If the user was parked on the pending (black) run and this cycle
                // just encoded it into a real segment, load that segment's frame in
                // place. The followingLatest path (onChange segments.count) already
                // handles the "watching the latest" case.
                if !followingLatest,
                   playbackController.isShowingPendingBlack,
                   !timelineStore.isPendingTime(centerTime) {
                    playbackController.update(for: centerTime, store: timelineStore)
                }
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

            // The playhead is over the latest still-unprocessed run: there's no
            // encoded video yet, so cover the frame with black. The timeline bar
            // (drawn later in this ZStack) stays visible on top, so the pending
            // segment's colored bar and accessibility show through immediately.
            if playbackController.isShowingPendingBlack {
                Color.black
                    .ignoresSafeArea()
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
                            followingLatest = false
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
            // keyCode 53 = ESC, 49 = Space, 123 = Left Arrow, 124 = Right Arrow, 3 = F

            // Control+Command+F is macOS's native full-screen toggle. Swallow it entirely
            // so it neither opens search nor toggles the timeline out of full screen.
            // (Using keyCode, not charactersIgnoringModifiers — Control can alter the char.)
            if event.keyCode == 3
                && event.modifierFlags.contains(.command)
                && event.modifierFlags.contains(.control) {
                return nil
            }

            // Shift+ESC minimizes the timeline (to the Dock) instead of closing it, and
            // — unlike plain ESC — leaves recording stopped. Handled before the search /
            // date-picker branches so it works even while a modal is open.
            if event.keyCode == 53 && event.modifierFlags.contains(.shift) {
                showSearch = false
                showDatePicker = false
                minimizeTimelineWindow()
                return nil
            }

            // Plain CMD+F (no Control) always opens search and focuses the field —
            // pressing it again while open just re-focuses.
            let isCmdF = event.keyCode == 3
                && event.modifierFlags.contains(.command)
                && !event.modifierFlags.contains(.control)
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
                closeTimelineWindow()
                return nil

            case 49:  // Space - Play/Pause
                self.togglePlayPause()
                return nil

            case 123:  // Left Arrow - Seek backward 5 seconds
                followingLatest = false
                let newTime = max(playbackController.currentTime - 5, timelineStore.timelineStart ?? 0)
                playbackController.scrub(to: newTime, store: timelineStore)
                centerTime = newTime
                return nil

            case 124:  // Right Arrow - Seek forward 5 seconds
                followingLatest = false
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
        // The user is driving the playhead by hand now — stop auto-snapping to the
        // latest frame so a late-arriving encode can't yank them back.
        followingLatest = false
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

    /// Close the timeline window on ESC. Calling `close()` directly on a native
    /// fullscreen window sometimes only drops it out of fullscreen and leaves it open
    /// (AppKit/SwiftUI entangle the fullscreen-exit with the close). So if we're
    /// fullscreen, exit first and close once `didExitFullScreen` lands — with a
    /// fallback close in case that notification never arrives.
    private func closeTimelineWindow() {
        let window = NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.identifier?.rawValue.contains("timeline") == true })
        guard let window else { return }

        guard window.styleMask.contains(.fullScreen) else {
            window.close()
            return
        }

        var token: NSObjectProtocol?
        var closed = false
        let close: () -> Void = {
            guard !closed else { return }
            closed = true
            if let token { NotificationCenter.default.removeObserver(token) }
            window.close()
        }
        token = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
        ) { _ in close() }
        fullscreenManager.beginIntentionalExit()
        window.toggleFullScreen(nil)
        // Fallback: if the exit transition never reports completion, close anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { close() }
    }

    /// Minimize the timeline to the Dock (Shift+ESC) without closing it. The window
    /// isn't destroyed, so `onDisappear` never fires and recording stays stopped — the
    /// opposite of a plain-ESC close, which resumes recording. A native fullscreen
    /// window can't be miniaturized, so exit fullscreen first and restore the normal
    /// menu bar / Dock before dropping to the Dock.
    private func minimizeTimelineWindow() {
        let window = NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.identifier?.rawValue.contains("timeline") == true })
        guard let window else { return }

        // When the user restores the window from the Dock, put it back into fullscreen
        // (recording stays paused until the timeline is actually closed with ESC).
        var restoreToken: NSObjectProtocol?
        restoreToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main
        ) { [fullscreenManager] _ in
            if let restoreToken { NotificationCenter.default.removeObserver(restoreToken) }
            // didDeminiaturize fires while the genie animation is still settling, which
            // reverts a just-entered fullscreen. enterFullscreenSticky re-enters until the
            // settle is done.
            fullscreenManager.enterFullscreenSticky(window)
        }

        let miniaturize: () -> Void = {
            NSApp.presentationOptions = []
            window.miniaturize(nil)
        }

        guard window.styleMask.contains(.fullScreen) else {
            miniaturize()
            return
        }

        var token: NSObjectProtocol?
        var done = false
        let run: () -> Void = {
            guard !done else { return }
            done = true
            if let token { NotificationCenter.default.removeObserver(token) }
            miniaturize()
        }
        token = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main
        ) { _ in run() }
        fullscreenManager.beginIntentionalExit()
        window.toggleFullScreen(nil)
        // Fallback: if the exit transition never reports completion, minimize anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { run() }
    }

    /// Jump the timeline to the moment behind a search result. Keeps the search
    /// modal open and does not steal focus from the search field. Then highlights
    /// exactly where the matched text sits on the frame.
    private func jumpToMoment(_ ts: TimeInterval, id: String, query: String) {
        followingLatest = false
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
            let rects = await searchIndex.highlightRects(at: ts, query: query)
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

    /// Position the playhead at the latest available frame and start decoding it.
    /// Falls back to "Now" when no segments have loaded yet (the subsequent
    /// onChange(segments.count) positions once they do).
    private func positionAtLatest() {
        if let latest = timelineStore.latestTS {
            centerTime = latest
            playbackController.update(for: latest, store: timelineStore)
        } else {
            centerTime = Date().timeIntervalSince1970
            playbackController.currentTime = centerTime
        }
    }

    /// Lift the black initial-load cover the instant the latest available frame
    /// is decoded — one clean transition, no fast-forward, and never before the
    /// frame is actually ready to display.
    private func maybeRevealVideo() {
        guard !revealVideo, playbackController.isCurrentItemReady else { return }
        Log.ui.info("Latest frame ready — revealing video")
        revealVideo = true
        // Only now start OCR search indexing. Its helper pool saturates the video
        // decoder + Neural Engine, so starting it before the newest frame is on
        // screen delays that frame's readiness by tens of seconds. Skipped while
        // the search modal is open — it drives indexing itself.
        if !showSearch { ProcessingService.shared.beginTimelineIndexing() }
    }
}
