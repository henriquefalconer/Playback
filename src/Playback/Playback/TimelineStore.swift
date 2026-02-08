import Foundation
import Combine
import SQLite3

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

        guard let videoDuration, duration > 0 else {
            return timelineOffset
        }

        // Simple linear mapping: the entire timeline interval of this segment
        // [startTS, endTS] spans 100% of the video duration [0, videoDuration].
        // This prevents video "freezing" at the start or end of the segment and ensures
        // continuous scrubbing throughout the entire segment.
        let ratio = timelineOffset / duration
        if !ratio.isFinite || ratio < 0 {
            return 0
        }
        let mapped = videoDuration * min(1.0, ratio)
        return max(0, min(videoDuration, mapped))
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

    var duration: TimeInterval {
        max(0, endTS - startTS)
    }
}

final class TimelineStore: ObservableObject {
    @Published private(set) var segments: [Segment] = []
    @Published private(set) var appSegments: [AppSegment] = []
    @Published private(set) var loadingState: LoadingState = .loading

    var timelineStart: TimeInterval? {
        segments.first?.startTS
    }

    var timelineEnd: TimeInterval? {
        segments.last?.endTS
    }

    var latestTS: TimeInterval? {
        timelineEnd
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
            if Paths.isDevelopment {
                print("[TimelineStore] Error creating directories: \(error)")
            }
        }

        loadSegments()
        startAutoRefresh()
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

    private func refreshIfNeeded() {
        let previousCount = segments.count
        loadSegments()
        if segments.count != previousCount {
            if Paths.isDevelopment {
                print("[TimelineStore] Auto-refreshed: \(segments.count) segments (was \(previousCount))")
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func loadSegments() {
        DispatchQueue.main.async {
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
            if Paths.isDevelopment {
                print("[TimelineStore] Failed to open meta.sqlite3 at \(dbPath). rc=\(rc), error=\(errorMessage)")
            }
            DispatchQueue.main.async {
                self.loadingState = .error(errorMessage)
            }
            return
        }
        defer { sqlite3_close(db) }

        let query = """
        SELECT id, start_ts, end_ts, frame_count, fps, video_path
        FROM segments
        ORDER BY start_ts ASC;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            if Paths.isDevelopment {
                print("[TimelineStore] Error preparing segments query")
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

            let url = baseDir.appendingPathComponent(videoPath)
            loaded.append(
                Segment(
                    id: id,
                    startTS: startTS,
                    endTS: endTS,
                    frameCount: frameCount,
                    fps: fps,
                    videoURL: url
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
            if Paths.isDevelopment {
                print("[TimelineStore] appsegments table not found or error preparing query; only segments will be loaded.")
            }
        }

        DispatchQueue.main.async {
            self.segments = loaded
            self.appSegments = loadedAppSegments

            if loaded.isEmpty {
                self.loadingState = .empty
            } else {
                self.loadingState = .loaded
            }

            if Paths.isDevelopment {
                print("[TimelineStore] Loaded \(loaded.count) segments and \(loadedAppSegments.count) appsegments")
            }
        }
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
            if Paths.isDevelopment {
                print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> before first, using \(first.id) @ start, videoOffset=\(offset)")
            }
            return (first, offset)
        }
        if let last = segments.last, time > last.endTS {
            let offset = last.videoOffset(forAbsoluteTime: last.endTS)
            if Paths.isDevelopment {
                print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> after last, using \(last.id) @ end, videoOffset=\(offset)")
            }
            return (last, offset)
        }

        // 2) Inside any segment?
        for seg in segments {
            if time >= seg.startTS && time <= seg.endTS {
                let offset = seg.videoOffset(forAbsoluteTime: time)
                if Paths.isDevelopment {
                    print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> inside \(seg.id), videoOffset=\(offset)")
                }
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
                        if Paths.isDevelopment {
                            print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> gap, BACKWARD: using end of \(a.id), videoOffset=\(offset)")
                        }
                        return (a, offset)
                    } else if dirSign > 0 {
                        // Going to the FUTURE: use the START of the next segment.
                        let offset = b.videoOffset(forAbsoluteTime: b.startTS)
                        if Paths.isDevelopment {
                            print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> gap, FORWARD: using start of \(b.id), videoOffset=\(offset)")
                        }
                        return (b, offset)
                    } else {
                        // No clear direction (e.g., isolated call): keep the old rule
                        // of "nearest segment".
                        let distA = min(abs(time - a.startTS), abs(time - a.endTS))
                        let distB = min(abs(time - b.startTS), abs(time - b.endTS))
                        let chosen = distA <= distB ? a : b
                        let clamped = min(max(time, chosen.startTS), chosen.endTS)
                        let offset = chosen.videoOffset(forAbsoluteTime: clamped)
                        if Paths.isDevelopment {
                            print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> gap, NO DIRECTION: using \(chosen.id), videoOffset=\(offset)")
                        }
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
            if Paths.isDevelopment {
                print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> fallback, using \(seg.id), videoOffset=\(bestOffset)")
            }
            return (seg, bestOffset)
        }
        if Paths.isDevelopment {
            print("[TimelineStore] segment(for:\(time), dir=\(direction)) -> no segment found (UNEXPECTED CASE)")
        }
        return nil
    }
}

