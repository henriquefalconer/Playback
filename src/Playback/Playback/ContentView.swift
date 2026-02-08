import SwiftUI
import AVKit
import AppKit

struct ContentView: View {
    @EnvironmentObject var timelineStore: TimelineStore
    @EnvironmentObject var playbackController: PlaybackController
    @EnvironmentObject var processMonitor: ProcessMonitor

    @State private var centerTime: TimeInterval = 0
    @State private var showDatePicker = false
    @State private var showSearch = false
    @StateObject private var searchController: SearchController
    // Visible time window in timeline (in seconds).
    // 3600s = 1h visible around current instant.
    @State private var visibleWindowSeconds: TimeInterval = 60 * 1
    // Zoom limits: prevents zooming in/out beyond these values.
    private let minVisibleWindowSeconds: TimeInterval = 60          // 1 minute
    private let maxVisibleWindowSeconds: TimeInterval = 60 * 60     // 60 minutes
    // Base used for pinch gesture (zoom) applied to entire window.
    @State private var pinchBaseVisibleWindowSeconds: TimeInterval?
    // Exponent that controls pinch zoom sensitivity.
    // Higher values => more aggressive zoom for same pinch distance.
    private let pinchZoomExponent: Double = 3.0
    @State private var keyMonitor: Any?
    @State private var scrollMonitor: Any?

    init() {
        let dbPath = Paths.databasePath.path
        _searchController = StateObject(wrappedValue: SearchController(databasePath: dbPath))
    }

    var body: some View {
        ZStack {
            if processMonitor.isProcessing {
                LoadingScreenView()
            } else if timelineStore.loadingState == .loading {
                LoadingStateContentView()
            } else if timelineStore.loadingState == .empty {
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
        }
        // Whenever segment count changes (initial load or reload),
        // reposition centerTime to the latest available timestamp.
        .onChange(of: timelineStore.segments.count) { _, newCount in
            guard newCount > 0, let latest = timelineStore.latestTS else { return }
            if Paths.isDevelopment {
                print("[ContentView] segments.count changed to \(newCount); repositioning centerTime to latestTS=\(latest)")
            }
            centerTime = latest
            playbackController.update(for: latest, store: timelineStore)
        }
        // Allow pinch zoom in ANY window area, not just over segment bar.
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    guard value.isFinite, value > 0 else { return }

                    if pinchBaseVisibleWindowSeconds == nil {
                        pinchBaseVisibleWindowSeconds = visibleWindowSeconds
                    }
                    guard let base = pinchBaseVisibleWindowSeconds else { return }

                    // Increase zoom sensitivity by applying an exponent
                    // to the pinch value. This way, small gestures generate
                    // more perceptible changes in time scale.
                    let factor = pow(Double(value), pinchZoomExponent)

                    // Zoom in => smaller window (fewer visible seconds).
                    var newWindow = base / factor
                    if newWindow < minVisibleWindowSeconds {
                        newWindow = minVisibleWindowSeconds
                    } else if newWindow > maxVisibleWindowSeconds {
                        newWindow = maxVisibleWindowSeconds
                    }

                    if abs(newWindow - visibleWindowSeconds) > 0.001 {
                        visibleWindowSeconds = newWindow
                        if Paths.isDevelopment {
                            print("[ContentView] Pinch zoom -> visibleWindowSeconds=\(visibleWindowSeconds)")
                        }
                    }
                }
                .onEnded { _ in
                    pinchBaseVisibleWindowSeconds = nil
                }
        )
    }

    @ViewBuilder
    private var timelineContentView: some View {
        ZStack {
            VideoBackgroundView(player: playbackController.player)
                .ignoresSafeArea()

            // While a new segment is loading (or when navigating outside recorded range),
            // show the last known frame as fallback to avoid abrupt black screens.
            // To ensure no other background image appears around the frozen frame,
            // render the image on top of a black background that fills the entire screen.
            if playbackController.showFrozenFrame, let image = playbackController.frozenFrame {
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                }
            }

            // Subtle bottom gradient in gray-blue tones
            VStack {
                Spacer()
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color(.sRGB, red: 0.60, green: 0.68, blue: 0.98, opacity: 0.25) // subtle blue-gray
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
                        showDatePicker: $showDatePicker,
                        searchResults: searchController.results
                    )
                    .environmentObject(timelineStore)
                    .environmentObject(playbackController)
                    .frame(height: 120)
                    .padding(.bottom, 40)
                    // Smoothly animate zoom changes (visibleWindowSeconds),
                    // giving an inertia feel to the pinch gesture.
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

            // Phase 4.1: Search UI overlay (Command+F)
            if showSearch {
                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            SearchBar(searchController: searchController, isPresented: $showSearch)
                            SearchResultsList(searchController: searchController)
                        }
                        .padding(.top, 20)
                        .padding(.trailing, 20)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
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
        // Phase 4.1: Listen for search jump notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("JumpToTimestamp"),
            object: nil,
            queue: .main
        ) { [self] notification in
            if let timestamp = notification.userInfo?["timestamp"] as? Double {
                centerTime = timestamp
                playbackController.scrub(to: timestamp, store: timelineStore)
            }
        }

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
                // keyCode 53 = ESC, 49 = Space, 123 = Left Arrow, 124 = Right Arrow, 3 = F (for Command+F)

                // Command+F (keyCode 3 with command modifier)
                if event.keyCode == 3 && event.modifierFlags.contains(.command) {
                    self.showSearch.toggle()
                    return nil
                }

                switch event.keyCode {
                case 53:  // ESC - Close window or search
                    if self.showSearch {
                        self.showSearch = false
                    } else if self.processMonitor.isProcessing {
                        NSApp.keyWindow?.close()
                    } else {
                        NSApp.keyWindow?.close()
                    }
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
        // Unlike the previous ScrollCaptureView (which used a transparent NSView over everything),
        // this monitor only observes scroll events without interfering with UI hit-test hierarchy.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
                let rawDx = event.scrollingDeltaX
                let rawDy = event.scrollingDeltaY

                if Paths.isDevelopment {
                    print("[ScrollCapture] event dx=\(rawDx), dy=\(rawDy), inverted=\(event.isDirectionInvertedFromDevice)")
                }

                // Use the axis with greater magnitude as primary direction of gesture.
                guard rawDx != 0 || rawDy != 0 else { return nil }
                let primaryRaw: CGFloat = abs(rawDx) >= abs(rawDy) ? rawDx : rawDy

                // Real finger direction (corrected for "natural scrolling").
                let fingerDelta: CGFloat
                if event.isDirectionInvertedFromDevice {
                    fingerDelta = -primaryRaw
                } else {
                    fingerDelta = primaryRaw
                }

                if Paths.isDevelopment {
                    print("[ScrollCapture] primaryRaw=\(primaryRaw), fingerDelta=\(fingerDelta)")
                }

                // Sensitivity factor (fine-tuning scroll speed).
                // Instead of a fixed very small value (which barely moves timeline),
                // we scale by visible window: for 1h window, each scroll "point"
                // changes a few seconds, enough to perceive continuous displacement.
                //
                // Example: visibleWindowSeconds = 3600 -> ~3.6s per point.
                let secondsPerPoint: Double = visibleWindowSeconds / 1000.0

                // UX rule (now inverted):
                //  - finger/pointer to RIGHT => HIGHER time (future)
                //  - finger/pointer to LEFT  => LOWER time (past)
                let secondsDelta = Double(fingerDelta) * secondsPerPoint

                guard secondsDelta != 0 else {
                    if Paths.isDevelopment {
                        print("[ScrollCapture] secondsDelta == 0, ignoring")
                    }
                    return nil
                }

                // Base calculation on playbackController's currentTime (synchronized by timeObserver).
                let base = playbackController.currentTime
                var newTime = base + secondsDelta

                if Paths.isDevelopment {
                    print("[ScrollCapture] baseTime=\(base), secondsDelta=\(secondsDelta), tentative newTime=\(newTime)")
                }

                if let start = timelineStore.timelineStart {
                    newTime = max(start, newTime)
                }
                if let end = timelineStore.timelineEnd {
                    newTime = min(end, newTime)
                }

                if Paths.isDevelopment {
                    print("[ScrollCapture] clamped newTime=\(newTime), timelineStart=\(String(describing: timelineStore.timelineStart)), timelineEnd=\(String(describing: timelineStore.timelineEnd))")
                }

                // Update UI state and perform IMMEDIATE scrubbing (no debounce),
                // keeping video PAUSED while user is scrolling.
                if Paths.isDevelopment {
                    let beforeScrubCurrent = playbackController.currentTime
                    print("[ScrollCapture] -> calling scrub(to: \(newTime)). currentTime(before)=\(beforeScrubCurrent), centerTime(before)=\(centerTime)")
                }
                playbackController.scrub(to: newTime, store: timelineStore)
                // After scrub, always align centerTime with player's effective currentTime
                // (which may have been "snapped" to segment end/start during segment transitions).
                centerTime = playbackController.currentTime

                if Paths.isDevelopment {
                    print("[ScrollCapture] <- after scrub. playback.currentTime=\(playbackController.currentTime), centerTime=\(centerTime)")
                }

                // Return nil to prevent any default view (e.g. NSScrollView)
                // from also processing this scroll.
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
    }

    private func togglePlayPause() {
        playbackController.togglePlayPause()
    }
}


