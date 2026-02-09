import Foundation
import AVFoundation
import Combine
import AppKit

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
    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying: Bool = false
    @Published var playbackError: PlaybackError?
    /// Last "frozen" frame used as visual fallback while a new
    /// segment is loading or when we navigate outside the recorded range.
    @Published var frozenFrame: NSImage?
    /// When `true`, the UI should display `frozenFrame` over the video.
    @Published var showFrozenFrame: Bool = false

    /// Indicates whether we're in the middle of an active scrubbing (via scroll/drag).
    /// While `true`, we ignore periodic updates from `timeObserver`
    /// to avoid overwriting the `currentTime` calculated from the gesture.
    private var isScrubbing: Bool = false
    /// Indicates whether the current time is "stuck" at the absolute start of the timeline.
    /// When true, we keep the last displayed frame as a visual
    /// fallback, even after scrubbing ends.
    private var atStartBoundary: Bool = false

    private var timeObserverToken: Any?

    private var pendingWorkItem: DispatchWorkItem?
    private var statusObserver: NSKeyValueObservation?
    private var scrubEndWorkItem: DispatchWorkItem?
    private var consecutiveFailures: Int = 0

    init() {
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

            // Segment preloading: When playback reaches 80% of current segment,
            // preload the next segment in background for seamless transition
            self.checkAndPreloadNextSegment(videoOffset: seconds, segment: segment)
        }
    }

    /// Generates, in background, a video snapshot for `segment` at the position
    /// corresponding to the given absolute time, and publishes it to `frozenFrame`.
    private func captureFrozenFrame(from segment: Segment, atAbsoluteTime time: TimeInterval) {
        let offset = max(0, segment.videoOffset(forAbsoluteTime: time))
        let url = segment.videoURL

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true

            let cmTime = CMTime(seconds: offset, preferredTimescale: 600)
            generator.generateCGImageAsynchronously(for: cmTime) { [weak self] image, _, error in
                guard let self else { return }

                if let cgImage = image {
                    let nsImage = NSImage(cgImage: cgImage, size: .zero)
                    DispatchQueue.main.async {
                        self.frozenFrame = nsImage
                        self.showFrozenFrame = true
                    }
                } else if let error = error {
                    if Paths.isDevelopment {
                        let message = error.localizedDescription
                        print("[Playback] Failed to generate async frozen frame for \(url.path) at offset=\(offset): \(message)")
                    }
                } else {
                    if Paths.isDevelopment {
                        print("[Playback] Async frozen frame generation returned no image or error for \(url.path) at offset=\(offset)")
                    }
                }
            }
        }
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        preloadPlayer = nil
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
            if Paths.isDevelopment {
                print("[Playback] No next segment to preload after \(segment.id)")
            }
            return
        }

        if Paths.isDevelopment {
            print("[Playback] Preloading next segment at \(Int(progress * 100))% progress: \(nextSegment.id)")
        }

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
                    if Paths.isDevelopment {
                        print("[Playback] Successfully preloaded segment \(segment.id)")
                    }
                } else {
                    if Paths.isDevelopment {
                        print("[Playback] Failed to preload segment \(segment.id): \(item.error?.localizedDescription ?? "unknown")")
                    }
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
            if Paths.isDevelopment {
                print("[Playback] Using preloaded segment \(segment.id) - seamless transition")
            }
            // Transfer the player item to main player
            if let item = preloadedPlayer.currentItem {
                player.replaceCurrentItem(with: item)
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
        // Mark that we're in active scrubbing.
        isScrubbing = true
        scrubEndWorkItem?.cancel()

        let segments = store.segments
        guard let first = segments.first, let last = segments.last else {
            if Paths.isDevelopment {
                print("[Playback] (scrub) No segments available (empty list)")
            }
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
                captureFrozenFrame(from: seg, atAbsoluteTime: currentTime)
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
            if Paths.isDevelopment {
                print("[Playback] (scrub) segment(for: \(clampedTime), dir=\(direction)) returned nil")
            }
            return
        }

        // Update the current absolute time on the timeline (continuous coordinate).
        currentTime = clampedTime

        if Paths.isDevelopment {
            print("[Playback] (scrub) time=\(time), clamped=\(clampedTime), effectiveTime=\(clampedTime), direction=\(direction)")
        }

        let distToStart = clampedTime - seg.startTS
        let distToEnd = seg.endTS - clampedTime

        if Paths.isDevelopment {
            print(
                "[Playback] (scrub) using segment(for:): id=\(seg.id), " +
                "videoOffset=\(offset), " +
                "distToStart=\(distToStart), distToEnd=\(distToEnd)"
            )
        }
        seek(to: seg, offset: offset, isScrub: true)

        // Schedule the end of scrubbing shortly after the last scroll event.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isScrubbing = false
            // When scrubbing finishes, if the player already has a new valid
            // frame ready (status READY) and we are **not** at
            // the absolute start of the timeline, we can hide the frozen frame.
            if !self.atStartBoundary {
                self.showFrozenFrame = false
            }
        }
        scrubEndWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    private func seek(to segment: Segment, offset: TimeInterval, isScrub: Bool) {
        // If the segment changed, we swap the player item.
        if currentSegment?.id != segment.id {
            if let oldSeg = currentSegment {
                // Before switching segments, freeze the last frame to
                // avoid the black "flash" while the new video loads.
                captureFrozenFrame(from: oldSeg, atAbsoluteTime: currentTime)
            }

            currentSegment = segment
            // Reset preload flag for new segment
            hasPreloadedNext = false

            // Try to use preloaded segment if available
            if usePreloadedSegmentIfAvailable(segment) {
                // Preloaded segment successfully used, skip manual loading
                // Status observer not needed since segment is already ready
                consecutiveFailures = 0
                playbackError = nil
                if !isScrubbing {
                    showFrozenFrame = false
                }
            } else {
                // No preloaded segment, load normally
                let url = segment.videoURL
                let item = AVPlayerItem(url: url)

                // Keep the status observer for debugging if something goes wrong during loading.
                statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay:
                        if Paths.isDevelopment {
                            print("[Playback] \(isScrub ? "(scrub) " : "")READY to play \(url.path)")
                        }
                        DispatchQueue.main.async {
                            self.consecutiveFailures = 0
                            self.playbackError = nil
                            // Only hide the frozen frame if we're no longer
                            // in scrubbing. During scrubbing, we keep the
                            // last displayed frame to avoid black flashes
                            // even if the new segment is already ready.
                            if !self.isScrubbing {
                                self.showFrozenFrame = false
                            }
                        }
                    case .failed:
                        if Paths.isDevelopment {
                            print("[Playback] \(isScrub ? "(scrub) " : "")FAILED for \(url.path): \(item.error?.localizedDescription ?? "(no error)")")
                        }
                        DispatchQueue.main.async {
                            self.consecutiveFailures += 1
                            let errorDesc = item.error?.localizedDescription ?? "Unknown error"
                            if !FileManager.default.fileExists(atPath: url.path) {
                                self.playbackError = .videoFileMissing(url.lastPathComponent)
                            } else if self.consecutiveFailures >= 3 {
                                self.playbackError = .multipleConsecutiveFailures(self.consecutiveFailures)
                            } else {
                                self.playbackError = .segmentLoadingFailure(errorDesc)
                            }
                            if !self.isScrubbing {
                                self.showFrozenFrame = false
                            }
                        }
                    case .unknown:
                        if Paths.isDevelopment {
                            print("[Playback] \(isScrub ? "(scrub) " : "")status UNKNOWN for \(url.path)")
                        }
                    @unknown default:
                        if Paths.isDevelopment {
                            print("[Playback] \(isScrub ? "(scrub) " : "")unknown status for \(url.path)")
                        }
                    }
                }

                player.replaceCurrentItem(with: item)
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
            if Paths.isDevelopment {
                print("[Playback] No segment found for time=\(time)")
            }
            return
        }
        if Paths.isDevelopment {
            print("[Playback] Updating to segment \(segment.id) (videoOffset=\(offset))")
            print("          URL: \(segment.videoURL.path)")
            print("          exists: \(FileManager.default.fileExists(atPath: segment.videoURL.path))")
        }
        currentTime = time

        if currentSegment?.id != segment.id {
            if let oldSeg = currentSegment {
                // Freeze the last frame of the previous segment before switching.
                captureFrozenFrame(from: oldSeg, atAbsoluteTime: currentTime)
            }

            currentSegment = segment
            // Reset preload flag for new segment
            hasPreloadedNext = false

            // Try to use preloaded segment if available
            if usePreloadedSegmentIfAvailable(segment) {
                // Preloaded segment successfully used
                consecutiveFailures = 0
                playbackError = nil
                if !isScrubbing {
                    showFrozenFrame = false
                }
            } else {
                // No preloaded segment, load normally
                let url = segment.videoURL
                let item = AVPlayerItem(url: url)

                // Observe status to understand decoding/loading failures
                statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                    guard let self else { return }
                    switch item.status {
                    case .readyToPlay:
                        if Paths.isDevelopment {
                            print("[Playback] READY to play \(url.path)")
                        }
                        DispatchQueue.main.async {
                            self.consecutiveFailures = 0
                            self.playbackError = nil
                            if !self.isScrubbing {
                                self.showFrozenFrame = false
                            }
                        }
                    case .failed:
                        if Paths.isDevelopment {
                            print("[Playback] FAILED for \(url.path): \(item.error?.localizedDescription ?? "(no error)")")
                        }
                        DispatchQueue.main.async {
                            self.consecutiveFailures += 1
                            let errorDesc = item.error?.localizedDescription ?? "Unknown error"
                            if !FileManager.default.fileExists(atPath: url.path) {
                                self.playbackError = .videoFileMissing(url.lastPathComponent)
                            } else if self.consecutiveFailures >= 3 {
                                self.playbackError = .multipleConsecutiveFailures(self.consecutiveFailures)
                            } else {
                                self.playbackError = .segmentLoadingFailure(errorDesc)
                            }
                            if !self.isScrubbing {
                                self.showFrozenFrame = false
                            }
                        }
                    case .unknown:
                        if Paths.isDevelopment {
                            print("[Playback] status UNKNOWN for \(url.path)")
                        }
                    @unknown default:
                        if Paths.isDevelopment {
                            print("[Playback] unknown status for \(url.path)")
                        }
                    }
                }

                player.replaceCurrentItem(with: item)
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


