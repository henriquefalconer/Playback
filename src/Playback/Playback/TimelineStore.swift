import Foundation
import Combine
import SQLite3
import os

enum LoadingState: Equatable {
    case loading
    case loaded
    case empty
    case error(String)
}

struct Segment: Identifiable {
    let id: String
    let startTS: TimeInterval
    let endTS: TimeInterval
    let frameCount: Int
    let fps: Double?
    let videoURL: URL
    let width: Int
    let height: Int

    var duration: TimeInterval {
        max(0, endTS - startTS)
    }

    /// Actual video duration (in seconds), estimated from frameCount and fps.
    var videoDuration: TimeInterval? {
        guard let fps, fps > 0, frameCount > 0 else { return nil }
        return TimeInterval(Double(frameCount) / fps)
    }

    /// Converts an absolute timestamp (global timeline) to an offset within the
    /// video file corresponding to this segment.
    func videoOffset(forAbsoluteTime time: TimeInterval) -> TimeInterval {
        let clampedTime = min(max(time, startTS), endTS)
        let timelineOffset = max(0, min(clampedTime - startTS, duration))

        guard let videoDuration, duration > 0, let fps, fps > 0, frameCount > 0 else {
            return timelineOffset
        }

        let ratio = timelineOffset / duration
        if !ratio.isFinite || ratio < 0 {
            return 0
        }
        // Seek to the CENTER of the frame the OCR indexer recorded for this instant,
        // not the frame's start edge. The index maps the timeline interval
        // [startTS, endTS] onto the frames [0, frameCount); a zero-tolerance seek to
        // the exact edge PTS (index/fps) rounds *down* into the previous frame, so a
        // search jump lands one frame early — a different app at a boundary, with none
        // of the matched text. Landing mid-frame keeps playback/highlight in lockstep
        // with the index, and each frame is ~2s of a screenshot time-lapse anyway.
        let lastIndex = Double(max(0, frameCount - 1))
        let index = min(lastIndex, (min(1.0, ratio) * Double(frameCount)).rounded())
        return max(0, min(videoDuration, (index + 0.5) / fps))
    }

    /// Approximate inverse of `videoOffset(forAbsoluteTime:)`.
    /// Given an offset within the video (in seconds), returns the corresponding
    /// absolute timestamp on the global timeline.
    ///
    /// This ensures that when AVPlayer reports the current video time,
    /// we can map it back to the "real" timeline time without causing
    /// unexpected jumps to the segment start.
    func absoluteTime(forVideoOffset offset: TimeInterval) -> TimeInterval {
        let clampedOffset = max(0, offset)

        guard let videoDuration, videoDuration > 0, duration > 0 else {
            // Without reliable metadata: assume 1:1 local mapping to the segment.
            let local = min(clampedOffset, duration)
            return startTS + local
        }

        let ratio = min(max(clampedOffset / videoDuration, 0), 1)
        let timelineOffset = ratio * duration
        return startTS + timelineOffset
    }
}

struct AppSegment: Identifiable {
    let id: String
    let startTS: TimeInterval
    let endTS: TimeInterval
    let appId: String?
    /// True for the latest still-unprocessed run (temp frames not yet encoded to
    /// a chunk). Its colored bar + accessibility render exactly like a normal
    /// segment, but its frames play back black until the encode lands.
    var isPending: Bool = false

    var duration: TimeInterval {
        max(0, endTS - startTS)
    }
}

/// The single latest run of recorded frames that hasn't been encoded into a video
/// chunk yet. It has no playable video, so its span on the timeline plays back as
/// black frames until processing turns it into a real `Segment`.
struct PendingSegment {
    let startTS: TimeInterval
    let endTS: TimeInterval
}

final class TimelineStore: ObservableObject {
    @Published private(set) var segments: [Segment] = []
    @Published private(set) var appSegments: [AppSegment] = []
    /// The latest recorded-but-not-yet-encoded run, surfaced so it's visible and
    /// navigable on the timeline the instant it opens. `nil` when everything
    /// recorded has already been encoded into chunks.
    @Published private(set) var pendingSegment: PendingSegment?
    @Published private(set) var loadingState: LoadingState = .loading

    var timelineStart: TimeInterval? {
        guard let pending = pendingSegment else { return segments.first?.startTS }
        guard let segStart = segments.first?.startTS else { return pending.startTS }
        return min(segStart, pending.startTS)
    }

    var timelineEnd: TimeInterval? {
        guard let pending = pendingSegment else { return segments.last?.endTS }
        guard let segEnd = segments.last?.endTS else { return pending.endTS }
        return max(segEnd, pending.endTS)
    }

    var latestTS: TimeInterval? {
        timelineEnd
    }

    /// True when `time` lands inside the pending (un-encoded) run, i.e. there's no
    /// video to show and playback should render black.
    func isPendingTime(_ time: TimeInterval) -> Bool {
        guard let pending = pendingSegment else { return false }
        return time >= pending.startTS && time <= pending.endTS
    }

    private let dbPath: String
    private let baseDir: URL
    private var refreshTimer: Timer?

    init() {
        // Use environment-aware paths from Paths utility
        self.baseDir = Paths.baseDataDirectory
        self.dbPath = Paths.databasePath.path

        // Ensure directories exist before loading data
        do {
            try Paths.ensureDirectoriesExist()
        } catch {
            Log.timeline.error("Error creating directories: \(error.localizedDescription)")
        }

        // Data is loaded lazily via resume() when the timeline window opens;
        // the store stays empty while the app runs menu-bar-only.

        NotificationCenter.default.addObserver(forName: DataManager.recordingsDidResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.refreshTimer != nil else { return }
            Log.timeline.info("Reloading segments after data reset")
            self.loadSegments()
        }
    }

    init(dbPath: String, baseDir: URL, autoRefresh: Bool = true) {
        self.dbPath = dbPath
        self.baseDir = baseDir

        loadSegments()
        if autoRefresh {
            startAutoRefresh()
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshIfNeeded()
        }
    }

    /// Reload segments and invoke `completion` on the main queue after the
    /// freshly loaded data has been published.
    func reload(then completion: @escaping () -> Void) {
        loadSegments()
        // loadSegments publishes its results via an async hop to the main
        // queue; enqueueing the completion afterwards guarantees it runs with
        // the fresh data visible.
        DispatchQueue.main.async(execute: completion)
    }

    /// Load data and start auto-refresh while the timeline window is open.
    func resume() {
        guard refreshTimer == nil else { return }
        loadingState = .loading
        loadSegments()
        startAutoRefresh()
    }

    /// Stop auto-refresh and drop loaded data when the timeline window closes,
    /// so the background (menu-bar-only) process keeps no segment arrays alive
    /// and stops polling the database every 5 seconds.
    func suspend() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        segments = []
        appSegments = []
        pendingSegment = nil
        loadingState = .loading
    }

    private func refreshIfNeeded() {
        let previousCount = segments.count
        loadSegments()
        if segments.count != previousCount {
            Log.timeline.debug("Auto-refreshed: \(self.segments.count) segments (was \(previousCount))")
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    /// Publish store changes on the main thread. When already on main (the normal
    /// case — resume/refresh/reload all run there), this runs SYNCHRONOUSLY so the
    /// freshly loaded segments and pending run are visible the instant loadSegments
    /// returns. That lets `positionAtLatest()` land on the true latest on the first
    /// frame instead of flashing "Now" and then jumping once an async publish lands.
    private func runOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    func loadSegments() {
        runOnMain {
            self.loadingState = .loading
        }

        var db: OpaquePointer?
        let rc = sqlite3_open(dbPath, &db)
        guard rc == SQLITE_OK, let db else {
            let errorMessage: String
            if let db {
                errorMessage = String(cString: sqlite3_errmsg(db))
                sqlite3_close(db)
            } else {
                errorMessage = "sqlite3_open returned code \(rc) and db == nil"
            }
            Log.timeline.fault("Failed to open meta.sqlite3 at \(self.dbPath). rc=\(rc), error=\(errorMessage)")
            runOnMain {
                self.loadingState = .error(errorMessage)
            }
            return
        }
        defer { sqlite3_close(db) }

        let query = """
        SELECT id, start_ts, end_ts, frame_count, fps, video_path, width, height
        FROM segments
        ORDER BY start_ts ASC;
        """

        var stmt: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &stmt, nil)
        guard prepareResult == SQLITE_OK, let stmt else {
            let errMsg = String(cString: sqlite3_errmsg(db))
            // Don't spam logs when table simply doesn't exist yet (processing hasn't run)
            if errMsg.contains("no such table") {
                Log.timeline.debug("segments table not yet created (processing service hasn't run)")
                runOnMain {
                    self.segments = []
                    self.appSegments = []
                    self.loadingState = .empty
                }
            } else {
                Log.timeline.error("Error preparing segments query: rc=\(prepareResult), \(errMsg)")
            }
            return
        }
        defer { sqlite3_finalize(stmt) }

        var loaded: [Segment] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let idC = sqlite3_column_text(stmt, 0),
                let videoPathC = sqlite3_column_text(stmt, 5)
            else { continue }

            let id = String(cString: idC)
            let startTS = sqlite3_column_double(stmt, 1)
            let endTS = sqlite3_column_double(stmt, 2)
            let frameCount = Int(sqlite3_column_int(stmt, 3))
            let fpsValue = sqlite3_column_double(stmt, 4)
            let fps: Double? = fpsValue > 0 ? fpsValue : nil
            let videoPath = String(cString: videoPathC)
            let width = Int(sqlite3_column_int(stmt, 6))
            let height = Int(sqlite3_column_int(stmt, 7))

            // Skip rows with impossible timestamps (end before start, or end in
            // the future) — a single corrupt span that overlaps the whole
            // timeline hijacks every segment(for:) lookup.
            let now = Date().timeIntervalSince1970
            guard endTS > startTS, endTS <= now + 120 else {
                Log.timeline.error("Skipping segment \(id, privacy: .public) with invalid span: start=\(startTS, privacy: .public), end=\(endTS, privacy: .public)")
                continue
            }

            let url = baseDir.appendingPathComponent(videoPath)
            loaded.append(
                Segment(
                    id: id,
                    startTS: startTS,
                    endTS: endTS,
                    frameCount: frameCount,
                    fps: fps,
                    videoURL: url,
                    width: width,
                    height: height
                )
            )
        }

        // Also load appsegments, if the table exists.
        let appQuery = """
        SELECT id, app_id, start_ts, end_ts
        FROM appsegments
        ORDER BY start_ts ASC;
        """

        var appStmt: OpaquePointer?
        var loadedAppSegments: [AppSegment] = []

        if sqlite3_prepare_v2(db, appQuery, -1, &appStmt, nil) == SQLITE_OK, let appStmt {
            defer { sqlite3_finalize(appStmt) }

            while sqlite3_step(appStmt) == SQLITE_ROW {
                guard let idC = sqlite3_column_text(appStmt, 0) else { continue }
                let id = String(cString: idC)

                let appId: String?
                if let appIdC = sqlite3_column_text(appStmt, 1) {
                    appId = String(cString: appIdC)
                } else {
                    appId = nil
                }

                let startTS = sqlite3_column_double(appStmt, 2)
                let endTS = sqlite3_column_double(appStmt, 3)

                loadedAppSegments.append(
                    AppSegment(
                        id: id,
                        startTS: startTS,
                        endTS: endTS,
                        appId: appId
                    )
                )
            }
        } else {
            Log.timeline.notice("appsegments table not found or error preparing query; only segments will be loaded.")
        }

        // Surface the latest still-unprocessed run (temp frames beyond the last
        // encoded chunk) so it's visible/navigable immediately — its frames play
        // back black until a processing cycle turns it into a real segment.
        let lastChunkEnd = loaded.last?.endTS ?? 0
        let pending = loadPendingSegment(afterTS: lastChunkEnd)

        runOnMain {
            self.segments = loaded
            self.appSegments = loadedAppSegments + (pending?.appSegments ?? [])
            self.pendingSegment = pending?.segment

            if loaded.isEmpty && pending == nil {
                self.loadingState = .empty
            } else {
                self.loadingState = .loaded
            }

            Log.timeline.debug("Loaded \(loaded.count) segments, \(loadedAppSegments.count) appsegments; pending=\(pending != nil)")
        }
    }

    // MARK: - Pending (un-encoded) run

    private struct PendingFrame {
        let ts: TimeInterval
        let appId: String?
    }

    /// Scan the temp screenshot directory for the latest temporally-contiguous run
    /// of frames not yet encoded into a chunk (everything after `afterTS`), and
    /// return it as a `PendingSegment` plus its per-app colored sub-segments.
    /// Frames are named `YYYYMMDD-HHMMSS-<uuid>-<bundleid>` so timestamp + app can
    /// be read from the filename alone — no image decode.
    private func loadPendingSegment(afterTS: TimeInterval) -> (segment: PendingSegment, appSegments: [AppSegment])? {
        let fm = FileManager.default
        let tempDir = Paths.tempDirectory
        guard let monthDirs = try? fm.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return nil }

        var frames: [PendingFrame] = []
        for monthDir in monthDirs {
            guard let dayDirs = try? fm.contentsOfDirectory(
                at: monthDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }
            for dayDir in dayDirs {
                guard let files = try? fm.contentsOfDirectory(
                    at: dayDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
                ) else { continue }
                for file in files {
                    let name = file.lastPathComponent
                    guard let (ts, appId) = Self.parseScreenshotFilename(name), ts > afterTS else { continue }
                    frames.append(PendingFrame(ts: ts, appId: appId))
                }
            }
        }
        guard !frames.isEmpty else { return nil }
        frames.sort { $0.ts < $1.ts }

        // Keep only the latest contiguous run — the same 10s gap the encoder uses
        // to split segments. That run is "the current segment still being recorded
        // / awaiting processing"; earlier orphaned runs (if any) encode separately.
        let maxFrameGap: TimeInterval = 10.0
        var groupStart = 0
        for i in 1..<frames.count where frames[i].ts - frames[i - 1].ts > maxFrameGap {
            groupStart = i
        }
        let group = Array(frames[groupStart...])
        guard let first = group.first, let last = group.last else { return nil }
        let startTS = first.ts
        let endTS = last.ts + 2.0  // last frame covers its ~2s capture interval
        guard endTS > afterTS else { return nil }

        // Split the run into per-app colored sub-segments, matching the encoder.
        var appSegs: [AppSegment] = []
        var curApp = group[0].appId
        var segStart = group[0].ts
        for i in 1..<group.count where group[i].appId != curApp {
            appSegs.append(AppSegment(
                id: "pending-\(segStart)", startTS: segStart,
                endTS: group[i - 1].ts + 2.0, appId: curApp, isPending: true
            ))
            curApp = group[i].appId
            segStart = group[i].ts
        }
        appSegs.append(AppSegment(
            id: "pending-\(segStart)", startTS: segStart,
            endTS: last.ts + 2.0, appId: curApp, isPending: true
        ))

        return (PendingSegment(startTS: startTS, endTS: endTS), appSegs)
    }

    private static let filenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd HHmmss"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Parse `YYYYMMDD-HHMMSS-<uuid>-<bundleid>` into (timestamp, appId).
    private static func parseScreenshotFilename(_ name: String) -> (ts: TimeInterval, appId: String?)? {
        let parts = name.split(separator: "-", maxSplits: 3)
        guard parts.count >= 2 else { return nil }
        let datePart = String(parts[0])
        let timePart = String(parts[1])
        guard datePart.count == 8, timePart.count == 6 else { return nil }
        guard let date = filenameFormatter.date(from: "\(datePart) \(timePart)") else { return nil }

        let appId: String? = parts.count >= 4 ? String(parts[3]) : nil
        return (date.timeIntervalSince1970, appId)
    }

    /// Simple version (without explicit direction) used in places where we're not
    /// doing continuous scrubbing. In these cases, the "nearest
    /// segment" rule is sufficient.
    func segment(for time: TimeInterval) -> (Segment, TimeInterval)? {
        segment(for: time, direction: 0)
    }

    /// Extended version that also receives the direction of movement:
    ///  - direction > 0  -> going to the FUTURE
    ///  - direction < 0  -> going to the PAST
    ///  - direction == 0 -> no clear direction (e.g., isolated call)
    ///
    /// This allows correctly handling "gaps" between segments without
    /// causing unexpected jumps.
    func segment(for time: TimeInterval, direction: TimeInterval) -> (Segment, TimeInterval)? {
        guard !segments.isEmpty else { return nil }

        let dirSign: Int
        if direction > 0 {
            dirSign = 1
        } else if direction < 0 {
            dirSign = -1
        } else {
            dirSign = 0
        }

        // 1) Outside the global range (before first or after last)?
        if let first = segments.first, time < first.startTS {
            let offset = first.videoOffset(forAbsoluteTime: first.startTS)
            Log.timeline.debug("segment(for:\(time), dir=\(direction)) -> before first, using \(first.id) @ start, videoOffset=\(offset)")
            return (first, offset)
        }
        if let last = segments.last, time > last.endTS {
            let offset = last.videoOffset(forAbsoluteTime: last.endTS)
            Log.timeline.debug("segment(for:\(time), dir=\(direction)) -> after last, using \(last.id) @ end, videoOffset=\(offset)")
            return (last, offset)
        }

        // 2) Inside any segment?
        for seg in segments {
            if time >= seg.startTS && time <= seg.endTS {
                let offset = seg.videoOffset(forAbsoluteTime: time)
                Log.timeline.debug("segment(for:\(time), dir=\(direction)) -> inside \(seg.id), videoOffset=\(offset)")
                return (seg, offset)
            }
        }

        // 3) Between segments (in "gaps").
        // Explicitly detects the (previous, next) pair whose gap contains `time`.
        if segments.count >= 2 {
            for i in 0..<(segments.count - 1) {
                let a = segments[i]
                let b = segments[i + 1]

                if time > a.endTS && time < b.startTS {
                    if dirSign < 0 {
                        // Going to the PAST: use the END of the previous segment.
                        let offset = a.videoOffset(forAbsoluteTime: a.endTS)
                        Log.timeline.debug("segment(for:\(time), dir=\(direction)) -> gap, BACKWARD: using end of \(a.id), videoOffset=\(offset)")
                        return (a, offset)
                    } else if dirSign > 0 {
                        // Going to the FUTURE: use the START of the next segment.
                        let offset = b.videoOffset(forAbsoluteTime: b.startTS)
                        Log.timeline.debug("segment(for:\(time), dir=\(direction)) -> gap, FORWARD: using start of \(b.id), videoOffset=\(offset)")
                        return (b, offset)
                    } else {
                        // No clear direction (e.g., isolated call): keep the old rule
                        // of "nearest segment".
                        let distA = min(abs(time - a.startTS), abs(time - a.endTS))
                        let distB = min(abs(time - b.startTS), abs(time - b.endTS))
                        let chosen = distA <= distB ? a : b
                        let clamped = min(max(time, chosen.startTS), chosen.endTS)
                        let offset = chosen.videoOffset(forAbsoluteTime: clamped)
                        Log.timeline.debug("segment(for:\(time), dir=\(direction)) -> gap, NO DIRECTION: using \(chosen.id), videoOffset=\(offset)")
                        return (chosen, offset)
                    }
                }
            }
        }

        // 4) Safety fallback: choose the nearest segment.
        var bestSeg: Segment?
        var bestOffset: TimeInterval = 0
        var bestDistance = TimeInterval.greatestFiniteMagnitude

        for seg in segments {
            let clamped = min(max(time, seg.startTS), seg.endTS)
            let distance = abs(time - clamped)
            if distance < bestDistance {
                bestDistance = distance
                bestSeg = seg
                bestOffset = seg.videoOffset(forAbsoluteTime: clamped)
            }
        }

        if let seg = bestSeg {
            Log.timeline.debug("segment(for:\(time), dir=\(direction)) -> fallback, using \(seg.id), videoOffset=\(bestOffset)")
            return (seg, bestOffset)
        }
        Log.timeline.fault("segment(for:\(time), dir=\(direction)) -> no segment found (UNEXPECTED CASE)")
        return nil
    }
}
