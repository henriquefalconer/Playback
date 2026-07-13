import Foundation
import AVFoundation
import Combine
import AppKit
import CoreImage
import os

enum PlaybackError: Equatable {
    case videoFileMissing(String)
    case segmentLoadingFailure(String)
    case permissionDenied
    case multipleConsecutiveFailures(Int)
}

final class PlaybackController: ObservableObject {
    let player = AVPlayer()

    /// Separate AVPlayer instance for preloading next segment in background
    private var preloadPlayer: AVPlayer?
    /// Reference to the next segment being preloaded
    private var preloadedSegment: Segment?
    /// Track whether we've triggered preloading for current segment
    private var hasPreloadedNext: Bool = false
    /// Weak reference to TimelineStore for segment queries
    weak var timelineStore: TimelineStore?

    @Published private(set) var currentSegment: Segment?
    /// Starts at "now" so the time bubble reads "Now" while the timeline
    /// data is still loading, instead of rendering the epoch as a wall time.
    @Published var currentTime: TimeInterval = Date().timeIntervalSince1970
    @Published var isPlaying: Bool = false
    @Published var playbackError: PlaybackError?
    /// Last "frozen" frame used as visual fallback while a new
    /// segment is loading or when we navigate outside the recorded range.
    @Published var frozenFrame: NSImage?
    /// When `true`, the UI should display `frozenFrame` over the video.
    @Published var showFrozenFrame: Bool = false
    /// True once the player's current item is ready to display frames.
    /// Reset whenever the item is swapped.
    @Published private(set) var isCurrentItemReady: Bool = false

    /// Indicates whether we're in the middle of an active scrubbing (via scroll/drag).
    /// While `true`, we ignore periodic updates from `timeObserver`
    /// to avoid overwriting the `currentTime` calculated from the gesture.
    private var isScrubbing: Bool = false
    /// Tracks whether the player was playing before scrubbing started, so we can
    /// resume playback automatically when the scrub ends.
    private var wasPlayingBeforeScrub: Bool = false
    /// Indicates whether the current time is "stuck" at the absolute start of the timeline.
    /// When true, we keep the last displayed frame as a visual
    /// fallback, even after scrubbing ends.
    private var atStartBoundary: Bool = false

    private var timeObserverToken: Any?

    private var pendingWorkItem: DispatchWorkItem?
    private var statusObserver: NSKeyValueObservation?
    private var scrubEndWorkItem: DispatchWorkItem?
    private var consecutiveFailures: Int = 0

    /// Timestamp when frozenFrame was last shown (for duration logging)
    private var frozenFrameShownAt: TimeInterval = 0

    /// Video output kept attached to the player's current item so the on-screen
    /// frame can be snapshotted for the frozen-frame fallback.
    private let frozenFrameOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    /// Shared context for converting snapshot pixel buffers to CGImage.
    private static let frozenFrameContext = CIContext()
    /// Counter for time observer ticks to sample logging every ~5s (25 ticks at 0.2s interval)
    private var timeObserverTickCount: Int = 0

    init() {
        // Disable stalling wait so playback starts immediately without buffering delays.
        player.automaticallyWaitsToMinimizeStalling = false

        // Periodically observe the player's time to keep `currentTime`
        // always in sync with what's being displayed on screen,
        // including when the user scrolls/gestures directly on the video.
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] cmTime in
            guard let self = self else { return }
            // During scrubbing, DO NOT let the player "pull" currentTime
            // back to the real video time, as this causes noticeable
            // jumps in the timeline between scroll events.
            if self.isScrubbing { return }
            guard let segment = self.currentSegment else { return }

            let seconds = CMTimeGetSeconds(cmTime)
            guard seconds.isFinite, seconds >= 0 else { return }

            // Instead of assuming 1:1 mapping (startTS + seconds), we use the
            // inverse of the `videoOffset(forAbsoluteTime:)` function to go back from
            // video time to absolute timeline time. This prevents
            // "teleportation" to the segment start when we're in
            // the middle of it.
            self.currentTime = segment.absoluteTime(forVideoOffset: seconds)

            // Log time observer tick every ~5 seconds (25 ticks × 0.2s)
            self.timeObserverTickCount += 1
            if self.timeObserverTickCount >= 25 {
                self.timeObserverTickCount = 0
                Log.playback.info("Time tick: absoluteTime=\(self.currentTime, privacy: .public), videoOffset=\(seconds, privacy: .public), segmentID=\(segment.id, privacy: .public), playing=\(self.isPlaying, privacy: .public), frozenFrame=\(self.showFrozenFrame, privacy: .public)")
            }

            // Segment preloading: When playback reaches 80% of current segment,
            // preload the next segment in background for seamless transition
            self.checkAndPreloadNextSegment(videoOffset: seconds, segment: segment)
        }
    }

    /// Snapshots the frame currently displayed by the player and publishes it
    /// to `frozenFrame`. Reads the player's own decoded output — do NOT use
    /// AVAssetImageGenerator here: every generation spins up a fresh decoder
    /// session whose mapped frame memory is never reclaimed (~7 MB per call,
    /// dozens of calls per scrub session).
    private func captureFrozenFrame() {
        let itemTime = player.currentTime()
        guard player.currentItem != nil,
              let buffer = frozenFrameOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
            // No decoded frame available yet — keep the previous frozen frame
            // as the visual fallback instead of failing.
            Log.playback.debug("No pixel buffer available for frozen frame at itemTime=\(itemTime.seconds)")
            return
        }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = Self.frozenFrameContext.createCGImage(ciImage, from: ciImage.extent) else {
            Log.playback.error("Failed to create CGImage for frozen frame")
            return
        }
        frozenFrame = NSImage(cgImage: cgImage, size: .zero)
        showFrozenFrame = true
    }

    /// Swap the player's current item, keeping the frozen-frame video output
    /// attached to whichever item is current.
    private func installItem(_ item: AVPlayerItem?) {
        player.currentItem?.remove(frozenFrameOutput)
        if let item {
            item.add(frozenFrameOutput)
        }
        isCurrentItemReady = item?.status == .readyToPlay
        player.replaceCurrentItem(with: item)
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        preloadPlayer = nil
    }

    /// Release all playback resources when the timeline window closes.
    /// The controller outlives the window (it's an app-level @StateObject), so
    /// without this the video decoder, its IOSurfaces, and the frozen frame
    /// stay resident for the whole background (menu-bar-only) lifetime.
    func releaseResources() {
        player.pause()
        isPlaying = false
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        scrubEndWorkItem?.cancel()
        scrubEndWorkItem = nil
        statusObserver?.invalidate()
        statusObserver = nil
        installItem(nil)
        preloadPlayer?.replaceCurrentItem(with: nil)
        preloadPlayer = nil
        preloadedSegment = nil
        hasPreloadedNext = false
        currentSegment = nil
        frozenFrame = nil
        showFrozenFrame = false
        currentTime = Date().timeIntervalSince1970
        Log.playback.info("Playback resources released (timeline closed)")
    }

    /// Check if we should preload the next segment. Triggers at 80% of current segment duration.
    private func checkAndPreloadNextSegment(videoOffset: TimeInterval, segment: Segment) {
        // Skip if already preloaded for this segment
        if hasPreloadedNext { return }

        // Calculate segment progress as percentage
        guard let videoDuration = segment.videoDuration, videoDuration > 0 else { return }
        let progress = videoOffset / videoDuration

        // Trigger preload at 80% threshold
        guard progress >= 0.8 else { return }

        hasPreloadedNext = true

        // Find next segment in timeline
        guard let nextSegment = findNextSegment(after: segment) else {
            Log.playback.debug("No next segment to preload after \(segment.id)")
            return
        }

        Log.playback.info("Preload triggered: progress=\(Int(progress * 100), privacy: .public)%, currentSegment=\(segment.id, privacy: .public), nextSegment=\(nextSegment.id, privacy: .public)")

        preloadSegmentInBackground(nextSegment)
    }

    /// Find the next segment chronologically after the given segment
    private func findNextSegment(after segment: Segment) -> Segment? {
        guard let store = timelineStore else { return nil }
        let segments = store.segments

        // Find current segment index
        guard let currentIndex = segments.firstIndex(where: { $0.id == segment.id }) else {
            return nil
        }

        // Return next segment if available
        let nextIndex = currentIndex + 1
        guard nextIndex < segments.count else {
            return nil
        }

        return segments[nextIndex]
    }

    /// Preload a segment in background using separate AVPlayer instance
    private func preloadSegmentInBackground(_ segment: Segment) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let item = AVPlayerItem(url: segment.videoURL)
            let player = AVPlayer(playerItem: item)

            // Wait for item to be ready
            let semaphore = DispatchSemaphore(value: 0)
            var statusObserver: NSKeyValueObservation?

            statusObserver = item.observe(\.status, options: [.new]) { item, _ in
                if item.status == .readyToPlay || item.status == .failed {
                    semaphore.signal()
                }
            }

            // Wait up to 5 seconds for preload to complete
            _ = semaphore.wait(timeout: .now() + 5.0)
            statusObserver?.invalidate()

            DispatchQueue.main.async {
                if item.status == .readyToPlay {
                    self.preloadPlayer = player
                    self.preloadedSegment = segment
                    Log.playback.debug("Successfully preloaded segment \(segment.id)")
                } else {
                    Log.playback.error("Failed to preload segment \(segment.id): \(item.error?.localizedDescription ?? "unknown")")
                    self.preloadPlayer = nil
                    self.preloadedSegment = nil
                }
            }
        }
    }

    /// Use preloaded segment if available, otherwise load normally
    private func usePreloadedSegmentIfAvailable(_ segment: Segment) -> Bool {
        if let preloadedSeg = preloadedSegment,
           preloadedSeg.id == segment.id,
           let preloadedPlayer = preloadPlayer {
            Log.playback.debug("Using preloaded segment \(segment.id) - seamless transition")
            // Transfer the player item to main player
            if let item = preloadedPlayer.currentItem {
                preloadedPlayer.replaceCurrentItem(with: nil)
                installItem(item)
                // Clean up preload state
                self.preloadPlayer = nil
                self.preloadedSegment = nil
                return true
            }
        }
        return false
    }

    /// Updates the player to a given time **without starting playback**.
    /// Used for real-time scrubbing (e.g., scroll/drag gesture on the timeline),
    /// keeping the frame always synchronized with the current position, but paused.
    func scrub(to time: TimeInterval, store: TimelineStore) {
        // Save play state before first scrub event in this gesture, then mark scrubbing.
        if !isScrubbing {
            wasPlayingBeforeScrub = isPlaying
        }
        isScrubbing = true
        scrubEndWorkItem?.cancel()

        let segments = store.segments
        guard let first = segments.first, let last = segments.last else {
            Log.playback.debug("(scrub) No segments available (empty list)")
            isScrubbing = false
            return
        }

        // Clamp the requested time to within the global timeline range.
        var clampedTime = min(max(time, first.startTS), last.endTS)

        // Detect if we're exactly at the absolute start of the timeline.
        // In this condition, we want to keep the last displayed frame as a visual
        // fallback, since there's no video "before" the first segment.
        let nowAtStartBoundary = abs(clampedTime - first.startTS) < 0.001
        if nowAtStartBoundary {
            // Ensure we have a frozen frame to show. If there isn't one yet,
            // we use the frame from the current segment (if it exists).
            if frozenFrame == nil || !atStartBoundary, let seg = currentSegment {
                captureFrozenFrame()
            }
            if !showFrozenFrame {
                Log.playback.info("Frozen frame shown: reason=start_boundary")
                frozenFrameShownAt = ProcessInfo.processInfo.systemUptime
            }
            showFrozenFrame = true
        }
        atStartBoundary = nowAtStartBoundary

        // --- Fix 1: slightly "stick" to the edges of the current segment ---
        // When the user is exactly at the start/end of a segment and makes a
        // VERY small scroll to the past/future, we don't want to jump
        // immediately to the previous/next segment (especially if
        // there's a large "gap" between them).
        //
        // Instead, we keep the time "stuck" at the current edge while the
        // displacement is small, and only allow crossing the edge when the
        // user persists a bit more.
        if let seg = currentSegment {
            let boundaryStick: TimeInterval = 0.5   // up to 0.5s beyond the edge stays stuck

            if clampedTime < seg.startTS {
                let delta = seg.startTS - clampedTime
                if delta <= boundaryStick {
                    clampedTime = seg.startTS
                }
            } else if clampedTime > seg.endTS {
                let delta = clampedTime - seg.endTS
                if delta <= boundaryStick {
                    clampedTime = seg.endTS
                }
            }
        }

        let direction = clampedTime - currentTime

        // Default case: use the canonical mapping from TimelineStore, which already handles:
        //  - time within segment
        //  - gaps between segments (considering direction)
        //  - before the first / after the last segment
        guard let (seg, offset) = store.segment(for: clampedTime, direction: direction) else {
            Log.playback.debug("(scrub) segment(for: \(clampedTime), dir=\(direction)) returned nil")
            return
        }

        // Update the current absolute time on the timeline (continuous coordinate).
        currentTime = clampedTime

        Log.playback.debug("(scrub) time=\(time), clamped=\(clampedTime), direction=\(direction)")

        let distToStart = clampedTime - seg.startTS
        let distToEnd = seg.endTS - clampedTime

        Log.playback.debug("(scrub) segment id=\(seg.id), videoOffset=\(offset), distToStart=\(distToStart), distToEnd=\(distToEnd)")
        seek(to: seg, offset: offset, isScrub: true)

        // Schedule the end of scrubbing 500ms after the last scroll event (per spec).
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isScrubbing = false
            // When scrubbing finishes, if the player already has a new valid
            // frame ready (status READY) and we are **not** at
            // the absolute start of the timeline, we can hide the frozen frame.
            if !self.atStartBoundary {
                if self.showFrozenFrame {
                    let frozenDuration = ProcessInfo.processInfo.systemUptime - self.frozenFrameShownAt
                    if self.frozenFrameShownAt > 0 { Log.playback.info("Frozen frame hidden: duration=\(frozenDuration, privacy: .public)s, reason=scrub_end") }
                }
                self.showFrozenFrame = false
            }
            // Resume playback if the user was watching before they started scrubbing.
            if self.wasPlayingBeforeScrub {
                self.player.play()
                self.isPlaying = true
            }
        }
        scrubEndWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        Log.playback.info("Play/pause toggled: now \(self.isPlaying ? "playing" : "paused", privacy: .public), segmentID=\(self.currentSegment?.id ?? "none", privacy: .public), time=\(self.currentTime, privacy: .public)")
    }

    func play() {
        player.play()
        isPlaying = true
        Log.playback.info("Play started: segmentID=\(self.currentSegment?.id ?? "none", privacy: .public), time=\(self.currentTime, privacy: .public)")
    }

    func pause() {
        player.pause()
        isPlaying = false
        Log.playback.info("Pause triggered: segmentID=\(self.currentSegment?.id ?? "none", privacy: .public), time=\(self.currentTime, privacy: .public)")
    }

    private func seek(to segment: Segment, offset: TimeInterval, isScrub: Bool) {
        // If the segment changed, we swap the player item.
        if currentSegment?.id != segment.id {
            let oldSegmentID = currentSegment?.id ?? "none"
            if let oldSeg = currentSegment {
                // Before switching segments, freeze the last frame to
                // avoid the black "flash" while the new video loads.
                captureFrozenFrame()
                Log.playback.info("Frozen frame shown: reason=segment_transition, oldSegment=\(oldSegmentID, privacy: .public), newSegment=\(segment.id, privacy: .public)")
                frozenFrameShownAt = ProcessInfo.processInfo.systemUptime
            }

            currentSegment = segment
            // Reset preload flag for new segment
            hasPreloadedNext = false
            let willUsePreload = preloadedSegment?.id == segment.id && preloadPlayer != nil
            Log.playback.info("Segment transition: \(oldSegmentID, privacy: .public) → \(segment.id, privacy: .public), type=\(willUsePreload ? "preloaded" : "fresh_load", privacy: .public), isScrub=\(isScrub, privacy: .public)")

            // Try to use preloaded segment if available
            if usePreloadedSegmentIfAvailable(segment) {
                // Preloaded segment successfully used, skip manual loading
                // Status observer not needed since segment is already ready
                consecutiveFailures = 0
                playbackError = nil
                Log.playback.info("Error state cleared: recovery via preloaded segment \(segment.id, privacy: .public)")
                if !isScrubbing {
                    showFrozenFrame = false
                    let frozenDuration = ProcessInfo.processInfo.systemUptime - frozenFrameShownAt
                    if frozenFrameShownAt > 0 { Log.playback.info("Frozen frame hidden: duration=\(frozenDuration, privacy: .public)s") }
                }
            } else {
                // No preloaded segment, load normally
                let url = segment.videoURL
                let item = AVPlayerItem(url: url)

                // Keep the status observer for debugging if something goes wrong during loading.
                statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay:
                        Log.playback.debug("\(isScrub ? "(scrub) " : "")READY to play \(url.path)")
                        DispatchQueue.main.async {
                            self.isCurrentItemReady = true
                            let hadError = self.playbackError != nil
                            self.consecutiveFailures = 0
                            self.playbackError = nil
                            if hadError {
                                Log.playback.info("Error state cleared: recovery after segment ready")
                            }
                            // Only hide the frozen frame if we're no longer
                            // in scrubbing. During scrubbing, we keep the
                            // last displayed frame to avoid black flashes
                            // even if the new segment is already ready.
                            if !self.isScrubbing {
                                self.showFrozenFrame = false
                                let frozenDuration = ProcessInfo.processInfo.systemUptime - self.frozenFrameShownAt
                                if self.frozenFrameShownAt > 0 { Log.playback.info("Frozen frame hidden: duration=\(frozenDuration, privacy: .public)s") }
                            }
                        }
                    case .failed:
                        Log.playback.error("\(isScrub ? "(scrub) " : "")FAILED for \(url.path): \(item.error?.localizedDescription ?? "(no error)")")
                        DispatchQueue.main.async {
                            self.consecutiveFailures += 1
                            Log.playback.info("Consecutive failure count: \(self.consecutiveFailures, privacy: .public), threshold=3")
                            let errorDesc = item.error?.localizedDescription ?? "Unknown error"
                            if !FileManager.default.fileExists(atPath: url.path) {
                                self.playbackError = .videoFileMissing(url.lastPathComponent)
                                Log.playback.error("Error state entered: videoFileMissing(\(url.lastPathComponent, privacy: .public))")
                            } else if self.consecutiveFailures >= 3 {
                                self.playbackError = .multipleConsecutiveFailures(self.consecutiveFailures)
                                Log.playback.error("Error state entered: multipleConsecutiveFailures(\(self.consecutiveFailures, privacy: .public))")
                            } else {
                                self.playbackError = .segmentLoadingFailure(errorDesc)
                                Log.playback.error("Error state entered: segmentLoadingFailure(\(errorDesc, privacy: .public))")
                            }
                            if !self.isScrubbing {
                                self.showFrozenFrame = true
                                self.frozenFrameShownAt = ProcessInfo.processInfo.systemUptime
                                Log.playback.info("Frozen frame shown: reason=loading_failure")
                            }
                        }
                    case .unknown:
                        Log.playback.notice("\(isScrub ? "(scrub) " : "")status UNKNOWN for \(url.path)")
                    @unknown default:
                        Log.playback.notice("\(isScrub ? "(scrub) " : "")unknown status for \(url.path)")
                    }
                }

                installItem(item)
            }
        }

        let cm = CMTime(seconds: offset, preferredTimescale: 600)
        if isScrub {
            // Always pause during scrubbing to avoid "elastic" feeling.
            player.pause()
            player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func update(for time: TimeInterval, store: TimelineStore) {
        guard let (segment, offset) = store.segment(for: time) else {
            Log.playback.notice("No segment found for time=\(time)")
            return
        }
        Log.playback.debug("Updating to segment \(segment.id) (videoOffset=\(offset)), URL: \(segment.videoURL.path), exists: \(FileManager.default.fileExists(atPath: segment.videoURL.path))")
        currentTime = time

        if currentSegment?.id != segment.id {
            let oldSegmentID = currentSegment?.id ?? "none"
            if let oldSeg = currentSegment {
                // Freeze the last frame of the previous segment before switching.
                captureFrozenFrame()
                Log.playback.info("Frozen frame shown: reason=segment_transition_update, oldSegment=\(oldSegmentID, privacy: .public)")
                frozenFrameShownAt = ProcessInfo.processInfo.systemUptime
            }

            currentSegment = segment
            // Reset preload flag for new segment
            hasPreloadedNext = false
            let willUsePreload = preloadedSegment?.id == segment.id && preloadPlayer != nil
            Log.playback.info("Segment transition (update): \(oldSegmentID, privacy: .public) → \(segment.id, privacy: .public), type=\(willUsePreload ? "preloaded" : "fresh_load", privacy: .public)")

            // Try to use preloaded segment if available
            if usePreloadedSegmentIfAvailable(segment) {
                // Preloaded segment successfully used
                consecutiveFailures = 0
                playbackError = nil
                Log.playback.info("Error state cleared: recovery via preloaded segment (update) \(segment.id, privacy: .public)")
                if !isScrubbing {
                    showFrozenFrame = false
                    let frozenDuration = ProcessInfo.processInfo.systemUptime - frozenFrameShownAt
                    if frozenFrameShownAt > 0 { Log.playback.info("Frozen frame hidden: duration=\(frozenDuration, privacy: .public)s") }
                }
            } else {
                // No preloaded segment, load normally
                let url = segment.videoURL
                let item = AVPlayerItem(url: url)

                // Observe status to understand decoding/loading failures
                statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay:
                        Log.playback.debug("READY to play \(url.path)")
                        DispatchQueue.main.async {
                            self.isCurrentItemReady = true
                            let hadError = self.playbackError != nil
                            self.consecutiveFailures = 0
                            self.playbackError = nil
                            if hadError {
                                Log.playback.info("Error state cleared: recovery after segment ready (update)")
                            }
                            if !self.isScrubbing {
                                self.showFrozenFrame = false
                                let frozenDuration = ProcessInfo.processInfo.systemUptime - self.frozenFrameShownAt
                                if self.frozenFrameShownAt > 0 { Log.playback.info("Frozen frame hidden: duration=\(frozenDuration, privacy: .public)s") }
                            }
                        }
                    case .failed:
                        Log.playback.error("FAILED for \(url.path): \(item.error?.localizedDescription ?? "(no error)")")
                        DispatchQueue.main.async {
                            self.consecutiveFailures += 1
                            Log.playback.info("Consecutive failure count: \(self.consecutiveFailures, privacy: .public), threshold=3")
                            let errorDesc = item.error?.localizedDescription ?? "Unknown error"
                            if !FileManager.default.fileExists(atPath: url.path) {
                                self.playbackError = .videoFileMissing(url.lastPathComponent)
                                Log.playback.error("Error state entered: videoFileMissing(\(url.lastPathComponent, privacy: .public))")
                            } else if self.consecutiveFailures >= 3 {
                                self.playbackError = .multipleConsecutiveFailures(self.consecutiveFailures)
                                Log.playback.error("Error state entered: multipleConsecutiveFailures(\(self.consecutiveFailures, privacy: .public))")
                            } else {
                                self.playbackError = .segmentLoadingFailure(errorDesc)
                                Log.playback.error("Error state entered: segmentLoadingFailure(\(errorDesc, privacy: .public))")
                            }
                            if !self.isScrubbing {
                                self.showFrozenFrame = true
                                self.frozenFrameShownAt = ProcessInfo.processInfo.systemUptime
                                Log.playback.info("Frozen frame shown: reason=loading_failure (update)")
                            }
                        }
                    case .unknown:
                        Log.playback.notice("status UNKNOWN for \(url.path)")
                    @unknown default:
                        Log.playback.notice("unknown status for \(url.path)")
                    }
                }

                installItem(item)
            }

            let cm = CMTime(seconds: offset, preferredTimescale: 600)
            player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                self?.player.play()
            }
        } else {
            let cm = CMTime(seconds: offset, preferredTimescale: 600)
            player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func scheduleUpdate(for time: TimeInterval, store: TimelineStore) {
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.update(for: time, store: store)
            }
        }
        pendingWorkItem = work
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}
