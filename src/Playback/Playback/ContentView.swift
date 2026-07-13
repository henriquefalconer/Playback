import SwiftUI
import AVKit
import AppKit
import os

struct ContentView: View {
    @EnvironmentObject var timelineStore: TimelineStore
    @EnvironmentObject var playbackController: PlaybackController

    @State private var centerTime: TimeInterval = 0
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
            setupEventHandlers()
            // If segments are already loaded when view appears,
            // immediately position at the most recent instant.
            if let latest = timelineStore.latestTS {
                centerTime = latest
                playbackController.update(for: latest, store: timelineStore)
            }
        }
        .onDisappear {
            cleanupEventHandlers()
            playbackController.releaseResources()
        }
        // Whenever segment count changes (initial load or reload),
        // reposition centerTime to the latest available timestamp.
        .onChange(of: timelineStore.segments.count) { _, newCount in
            guard newCount > 0, let latest = timelineStore.latestTS else { return }
            Log.ui.debug("segments.count changed to \(newCount); repositioning centerTime to latestTS=\(latest)")
            centerTime = latest
            playbackController.update(for: latest, store: timelineStore)
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
        }
        .animation(.easeInOut(duration: 0.15), value: showDatePicker)
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
}
