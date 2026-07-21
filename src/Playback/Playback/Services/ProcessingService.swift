// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import AVFoundation
import Combine
import CoreVideo
import CoreGraphics
import SQLite3
import AppKit
import Security
import CryptoKit
import UniformTypeIdentifiers
import os
import MachO
import IOKit.ps

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension Notification.Name {
    /// Posted each time a segment finishes OCR indexing, so an open search can
    /// pull the newly-indexed matches in.
    static let ocrIndexProgressed = Notification.Name("com.falconer.Playback.ocrIndexProgressed")
}

@MainActor
final class ProcessingService: ObservableObject {
    static let shared = ProcessingService()

    private var timer: Timer?
    private var heartbeatTimer: Timer?
    /// Run-loop source that fires when the power source (AC/battery) changes, so a
    /// just-connected charger can drain OCR windows deferred while on battery.
    private var powerNotifySource: CFRunLoopSource?
    private let queue = DispatchQueue(label: "com.falconer.Playback.processing", qos: .utility)
    /// Serial worker that OCR-indexes encoded segments for search. It runs ONLY
    /// while the timeline window is open (started/stopped by `ContentView`), so
    /// the background recording path never spends any CPU on text recognition.
    /// Concurrent so a *pool* of OCR helpers can index several segments at once
    /// while the timeline is open — the whole backlog (every date) is cleared far
    /// sooner. Idle only while the timeline is closed (no worker is dispatched).
    private let indexQueue = DispatchQueue(label: "com.falconer.Playback.ocrindex", qos: .utility, attributes: .concurrent)
    /// Guards the indexing state below, touched from the main actor (begin/end)
    /// and every index worker thread.
    private let indexLock = NSLock()
    private var indexingActive = false
    /// Which lifecycle owns the current indexing session. `.timeline` runs while
    /// the window is open (larger pool, drives the search "Loading" UI, killed on
    /// close). `.background` runs on the 5-minute processing cycle while the
    /// timeline is CLOSED, so newly-encoded frames become searchable without
    /// needing the timeline open. Timeline always preempts background.
    private enum IndexMode { case timeline, background }
    private var indexMode: IndexMode = .timeline
    /// The queued (`ocr_bg_queue`) segments the in-flight background pass is scoped
    /// to, so its claims never wander into legacy segments. Loaded from the DB when
    /// a pass starts; empty in timeline mode (which OCRs everything).
    private var backgroundScopeIDs: Set<String> = []
    /// True while the timeline window is open, set by `ContentView` on appear/
    /// disappear. Tracked separately from `indexingActive` because timeline OCR is
    /// deferred until the newest frame is on screen — during that gap the window is
    /// open but no indexing session exists yet, and the background pass must still
    /// stay out (it would starve the decoder the newest frame is waiting on).
    private var timelineOpen = false
    /// Incremented on every `beginTimelineIndexing`. A worker captures its epoch
    /// and stops the moment a newer one supersedes it, so a fast close→reopen can
    /// never leave stale workers running.
    private var indexEpoch = 0
    /// Every in-flight `--ocr-segment` helper, so closing the timeline can kill
    /// them all mid-segment and reclaim their CPU + RAM immediately.
    private var currentIndexProcesses: [Process] = []
    /// Segment ids currently being OCR'd by some worker, so concurrent workers
    /// never pick the same segment. Cleared on each begin; per-id on completion.
    private var indexingSegmentIDs: Set<String> = []
    /// How many OCR helpers may run at once. OCR is CPU-bound (~1 core each), so
    /// throughput scales with the pool: use all cores but one (kept free for the
    /// timeline UI + recording). All are killed on timeline close, so this load
    /// only exists while viewing.
    private var indexConcurrency: Int { max(1, ProcessInfo.processInfo.activeProcessorCount - 1) }
    /// The background (timeline-closed) pass uses the SAME n-1 pool as the timeline
    /// path so the per-cycle backlog drains in a short burst (seconds) rather than
    /// trickling across cycles. The helpers are niced (see `launchIndexHelper`), so
    /// this burst yields to the user's foreground apps instead of pegging the
    /// machine while nobody is watching the rewind view (see the nice in
    /// `indexFrameBatch`).
    private var backgroundIndexConcurrency: Int { indexConcurrency }
    /// The search key, loaded once per indexing session (not per segment) so the
    /// keychain is touched at most once each time the timeline opens — one prompt
    /// after an app update instead of one per segment, and no repeated reads.
    private var indexKey: SymmetricKey?
    /// True while a processing cycle (screenshot → video encoding) is in flight.
    @Published private(set) var isRunning = false
    /// True while the OCR backlog is still being indexed with the timeline open.
    /// Drives the search panel's "Loading results…" vs "No more results" footer.
    @Published private(set) var indexingInProgress = false
    /// Fraction (0…1) of all recorded frames that have been OCR-indexed, shown as
    /// the "Loading results… (XX%)" percentage. Frame-weighted, so long segments
    /// count for more than short ones.
    @Published private(set) var indexingProgress: Double = 0
    /// Count of live index workers; when it drops to 0 the backlog is drained.
    private var activeIndexWorkers = 0
    /// Names of temp manifest/output files currently in use by a live encoder or
    /// OCR helper. The orphan sweep must skip these — deleting one mid-flight
    /// makes the helper fail (unreadable manifest) and silently drops a segment.
    private let tempFilesLock = NSLock()
    private var inFlightTempFiles: Set<String> = []
    private var lastProcessingTime: Date?
    private var totalSegmentsCreated = 0
    private var triggerCount = 0
    private init() {}

    func start() {
        // Sweep any encoder temp files orphaned by a previous run that was killed
        // mid-encode (its `defer` cleanup couldn't run). A fresh process has no
        // in-flight encodes, so anything left over is safe to remove.
        cleanOrphanedEncodeTempFiles()

        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            self?.triggerProcessing()
        }
        // Heartbeat every 5 minutes
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Log.processing.info("Heartbeat — running=\(self.isRunning, privacy: .public), lastProcessing=\(self.lastProcessingTime?.description ?? "never", privacy: .public), totalSegmentsCreated=\(self.totalSegmentsCreated, privacy: .public)")
        }
        startPowerMonitor()
        triggerProcessing()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        if let src = powerNotifySource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
            powerNotifySource = nil
        }
    }

    /// Watch for AC/battery transitions so a just-connected charger can drain OCR
    /// windows that were deferred while on battery.
    private func startPowerMonitor() {
        guard powerNotifySource == nil else { return }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let service = Unmanaged<ProcessingService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { service.powerStateChanged() }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, ctx)?.takeRetainedValue() else {
            Log.processing.error("Failed to create power-source notification")
            return
        }
        powerNotifySource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    func triggerProcessing(source: String? = nil) {
        guard !isRunning else {
            Log.processing.info("Processing trigger skipped — already running")
            return
        }
        isRunning = true
        triggerCount += 1
        let trigger = triggerCount
        let source = source ?? (trigger == 1 ? "initial_start" : "timer")
        Log.processing.info("Processing cycle #\(trigger, privacy: .public) started — trigger=\(source, privacy: .public)")
        queue.async { [weak self] in
            let cycleStart = CFAbsoluteTimeGetCurrent()
            var segmentsCreated = 0
            var framesProcessed = 0
            self?.logMemory("cycle #\(trigger) start")
            self?.processAllPendingDays(segmentsCreated: &segmentsCreated, framesProcessed: &framesProcessed)
            // Hand freed encode buffers back to the OS. AVFoundation/VideoToolbox
            // release their working set asynchronously after the writer finishes,
            // so a staged reclaim over the next few seconds catches it — otherwise
            // hundreds of MB linger as compressed pages and the app looks bloated
            // in Activity Monitor long after the cycle.
            MemoryReclaimer.reclaimSoon()
            let elapsed = CFAbsoluteTimeGetCurrent() - cycleStart
            self?.logMemory("cycle #\(trigger) end")
            Log.processing.info("Processing cycle #\(trigger, privacy: .public) completed — segments=\(segmentsCreated, privacy: .public), frames=\(framesProcessed, privacy: .public), duration=\(String(format: "%.1f", elapsed), privacy: .public)s")
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.lastProcessingTime = Date()
                self?.totalSegmentsCreated += segmentsCreated
                // With the timeline closed, OCR ONLY the segments this cycle just
                // encoded (enqueued to the persistent `ocr_bg_queue`) in the
                // background, so recent activity stays searchable without needing the
                // timeline open. The legacy backlog is left for the timeline pass.
                // No-op when the timeline is open, a pass is running, or on battery.
                self?.maybeStartBackgroundIndexing()
            }
        }
    }

    /// Remove stale `encode-*.json` / `ocr-*.json` files left in the temp
    /// directory by a killed encoder. (Older builds embedded the index key in the
    /// manifest; sweeping guarantees no such file survives a crash.)
    private func cleanOrphanedEncodeTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }
        let prefixes = ["encode-", "ocr-", "ocrseg-"]
        // Never delete files a live helper is mid-flight on — only true orphans.
        tempFilesLock.lock()
        let protected = inFlightTempFiles
        tempFilesLock.unlock()
        var removed = 0
        for url in contents {
            let name = url.lastPathComponent
            guard name.hasSuffix(".json"), prefixes.contains(where: { name.hasPrefix($0) }) else { continue }
            if protected.contains(name) { continue }
            if (try? FileManager.default.removeItem(at: url)) != nil { removed += 1 }
        }
        if removed > 0 {
            Log.processing.info("Swept \(removed, privacy: .public) orphaned encoder temp file(s)")
        }
    }

    private func registerTempFile(_ url: URL) {
        tempFilesLock.lock(); inFlightTempFiles.insert(url.lastPathComponent); tempFilesLock.unlock()
    }
    private func unregisterTempFile(_ url: URL) {
        tempFilesLock.lock(); inFlightTempFiles.remove(url.lastPathComponent); tempFilesLock.unlock()
    }

    // MARK: - Processing Pipeline

    private func processAllPendingDays(segmentsCreated: inout Int, framesProcessed: inout Int) {
        let tempDir = Paths.tempDirectory
        let fm = FileManager.default

        let monthDirs: [URL]
        do {
            monthDirs = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        } catch {
            Log.processing.error("Failed to list temp directory \(tempDir.path): \(error.localizedDescription)")
            return
        }

        var pendingDayCount = 0
        for monthDir in monthDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: monthDir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let dayDirs: [URL]
            do {
                dayDirs = try fm.contentsOfDirectory(at: monthDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            } catch {
                Log.processing.error("Failed to list month directory \(monthDir.path): \(error.localizedDescription)")
                continue
            }

            for dayDir in dayDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard fm.fileExists(atPath: dayDir.path, isDirectory: &isDir), isDir.boolValue else { continue }
                pendingDayCount += 1
                processDayDirectory(dayDir, segmentsCreated: &segmentsCreated, framesProcessed: &framesProcessed)
            }
        }
        Log.processing.info("Day directory scan — \(pendingDayCount, privacy: .public) pending days found")
    }

    private func processDayDirectory(_ dayDir: URL, segmentsCreated: inout Int, framesProcessed: inout Int) {
        let fm = FileManager.default

        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        } catch {
            Log.processing.error("Failed to list day directory \(dayDir.path): \(error.localizedDescription)")
            return
        }

        let screenshotFiles = files
            .filter { isScreenshotFilename($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        Log.processing.info("Day \(dayDir.lastPathComponent, privacy: .public): \(files.count, privacy: .public) files, \(screenshotFiles.count, privacy: .public) screenshots")
        guard !screenshotFiles.isEmpty else { return }

        // Load frame metadata (size) without loading full image data
        var frames: [FrameInfo] = []
        for fileURL in screenshotFiles {
            guard let (timestamp, appId) = parseFilename(fileURL.lastPathComponent) else { continue }

            // Read image dimensions without loading full pixel data
            let hint = [kCGImageSourceTypeIdentifierHint: UTType.png.identifier as CFString] as CFDictionary
            guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, hint) else {
                Log.processing.error("CGImageSourceCreateWithURL failed for \(fileURL.lastPathComponent, privacy: .public)")
                continue
            }
            guard let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int else {
                Log.processing.error("Failed to read image properties for \(fileURL.lastPathComponent, privacy: .public)")
                continue
            }

            frames.append(FrameInfo(url: fileURL, timestamp: timestamp, appId: appId, width: width, height: height))
        }

        guard !frames.isEmpty else {
            Log.processing.error("No frames loaded from \(screenshotFiles.count, privacy: .public) screenshot files in \(dayDir.lastPathComponent, privacy: .public)")
            return
        }

        // Group frames into segments (split on resolution changes, max 900 frames)
        let maxFramesPerSegment = 900
        var groups: [[FrameInfo]] = []
        var currentGroup: [FrameInfo] = []

        for frame in frames {
            if let prev = currentGroup.last {
                let resolutionChanged = frame.width != prev.width || frame.height != prev.height
                if resolutionChanged || currentGroup.count >= maxFramesPerSegment {
                    groups.append(currentGroup)
                    currentGroup = []
                }
            }
            currentGroup.append(frame)
        }
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        Log.processing.info("Frame groups formed — \(groups.count, privacy: .public) groups from \(frames.count, privacy: .public) frames in \(dayDir.lastPathComponent, privacy: .public), frames/group=\(groups.map { $0.count }, privacy: .public), resolution=\(frames.first.map { "\($0.width)x\($0.height)" } ?? "unknown", privacy: .public)")

        for group in groups {
            processFrameGroup(group, dayDir: dayDir, segmentsCreated: &segmentsCreated, framesProcessed: &framesProcessed)
        }
    }

    private func processFrameGroup(_ frames: [FrameInfo], dayDir: URL, segmentsCreated: inout Int, framesProcessed: inout Int) {
        guard let first = frames.first, let last = frames.last else { return }

        let startTS = first.timestamp
        let endTS = last.timestamp + 2.0  // Add 2s capture interval for last frame
        let width = first.width
        let height = first.height
        let segmentId = generateSegmentId()

        // Output path: chunks/YYYYMM/DD/<segmentId>.mp4
        let monthDirName = dayDir.deletingLastPathComponent().lastPathComponent
        let dayDirName = dayDir.lastPathComponent
        let chunksDir = Paths.chunksDirectory
            .appendingPathComponent(monthDirName)
            .appendingPathComponent(dayDirName)

        do {
            try FileManager.default.createDirectory(at: chunksDir, withIntermediateDirectories: true)
            // 0700 — user-accessible only
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: chunksDir.path)
            } catch {
                Log.processing.debug("Could not set permissions on chunks dir: \(error.localizedDescription)")
            }
        } catch {
            Log.processing.error("Failed to create chunks dir: \(error.localizedDescription)")
            return
        }

        let videoURL = chunksDir.appendingPathComponent("\(segmentId).mp4")
        let bitrate = max(500_000, width * height)
        Log.processing.info("Video encoding started — segment=\(segmentId, privacy: .public), frames=\(frames.count, privacy: .public), \(width, privacy: .public)x\(height, privacy: .public), bitrate=\(bitrate, privacy: .public)")

        let encodeStart = CFAbsoluteTimeGetCurrent()
        do {
            try encodeVideo(frames: frames, outputURL: videoURL, width: width, height: height)
            // 0600 — user-readable only (sensitive screen content)
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: videoURL.path)
            } catch {
                Log.processing.debug("Could not set permissions on video file: \(error.localizedDescription)")
            }
        } catch {
            Log.processing.error("Encoding failed for \(segmentId): \(error.localizedDescription)")
            // Preserve temp files for retry on encoding failure
            return
        }

        let encodeDuration = CFAbsoluteTimeGetCurrent() - encodeStart
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int) ?? 0
        let effectiveFPS = encodeDuration > 0 ? Double(frames.count) / encodeDuration : 0
        Log.processing.info("Video encoding completed — segment=\(segmentId, privacy: .public), size=\(fileSize, privacy: .public)bytes, duration=\(String(format: "%.1f", encodeDuration), privacy: .public)s, effectiveFPS=\(String(format: "%.1f", effectiveFPS), privacy: .public)")
        logMemory("post-encode \(segmentId)")
        let basePath = Paths.baseDataDirectory.path
        let relativePath: String
        if videoURL.path.hasPrefix(basePath + "/") {
            relativePath = String(videoURL.path.dropFirst(basePath.count + 1))
        } else {
            relativePath = videoURL.path
        }

        let dateStr = dateString(from: startTS)
        let fps = 30.0

        guard let db = openDatabase(Paths.databasePath.path) else {
            Log.processing.fault("Failed to open database, preserving temp files")
            do {
                try FileManager.default.removeItem(at: videoURL)
            } catch {
                Log.processing.error("Failed to clean up video file after DB error: \(error.localizedDescription)")
            }
            return
        }
        defer { sqlite3_close(db) }

        // Insert segment
        let insertSegSQL = """
            INSERT OR IGNORE INTO segments (id, date, start_ts, end_ts, frame_count, fps, width, height, file_size_bytes, video_path)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        if let stmt = prepareStatement(db, sql: insertSegSQL) {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, segmentId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, dateStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, startTS)
            sqlite3_bind_double(stmt, 4, endTS)
            sqlite3_bind_int(stmt, 5, Int32(frames.count))
            sqlite3_bind_double(stmt, 6, fps)
            sqlite3_bind_int(stmt, 7, Int32(width))
            sqlite3_bind_int(stmt, 8, Int32(height))
            sqlite3_bind_int64(stmt, 9, Int64(fileSize))
            sqlite3_bind_text(stmt, 10, relativePath, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) != SQLITE_DONE {
                Log.processing.error("Failed to insert segment: \(String(cString: sqlite3_errmsg(db)))")
            } else {
                let duration = endTS - startTS
                Log.processing.info("DB segment inserted — id=\(segmentId, privacy: .public), date=\(dateStr, privacy: .public), duration=\(String(format: "%.1f", duration), privacy: .public)s, frames=\(frames.count, privacy: .public), size=\(fileSize, privacy: .public)bytes")
                segmentsCreated += 1
                framesProcessed += frames.count
                // Enqueue this window for background OCR (persisted, so it survives
                // a force-quit and open/close of the timeline). The claim is bounded
                // to these queued segments while the timeline is closed; legacy
                // segments are OCR'd only when the timeline is open.
                if let enq = prepareStatement(db, sql: "INSERT OR IGNORE INTO ocr_bg_queue (segment_id) VALUES (?);") {
                    defer { sqlite3_finalize(enq) }
                    sqlite3_bind_text(enq, 1, segmentId, -1, SQLITE_TRANSIENT)
                    _ = sqlite3_step(enq)
                }
            }
        }

        // Build and insert app segments
        let appSegs = buildAppSegments(from: frames)
        let insertAppSQL = """
            INSERT OR IGNORE INTO appsegments (id, app_id, date, start_ts, end_ts)
            VALUES (?, ?, ?, ?, ?);
            """
        for appSeg in appSegs {
            if let stmt = prepareStatement(db, sql: insertAppSQL) {
                defer { sqlite3_finalize(stmt) }
                let appSegId = generateSegmentId()
                sqlite3_bind_text(stmt, 1, appSegId, -1, SQLITE_TRANSIENT)
                if let appId = appSeg.appId {
                    sqlite3_bind_text(stmt, 2, appId, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 2)
                }
                sqlite3_bind_text(stmt, 3, dateString(from: appSeg.startTS), -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(stmt, 4, appSeg.startTS)
                sqlite3_bind_double(stmt, 5, appSeg.endTS)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    Log.processing.error("Failed to insert appsegment: \(String(cString: sqlite3_errmsg(db)))")
                } else {
                    let appDuration = appSeg.endTS - appSeg.startTS
                    Log.processing.info("DB appsegment inserted — app=\(appSeg.appId ?? "unknown", privacy: .public), duration=\(String(format: "%.1f", appDuration), privacy: .public)s")
                }
            }
        }

        // OCR is intentionally NOT run here. The search index is built lazily and
        // only while the timeline is open (see `TimelineOCRIndexer`), so recording
        // never spends CPU on text recognition. This segment stays absent from
        // `ocr_frames` / `ocr_done` and the indexer will pick it up on next open —
        // or right now, newest-first, if the timeline is already open (below).
        resumeIndexingIfDrained()

        // Delete processed temp files after successful DB write
        var deletedCount = 0
        var failedCount = 0
        for frame in frames {
            do {
                try FileManager.default.removeItem(at: frame.url)
                deletedCount += 1
            } catch {
                failedCount += 1
                Log.processing.debug("Failed to delete processed temp file \(frame.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        Log.processing.info("Temp cleanup — deleted=\(deletedCount, privacy: .public), failed=\(failedCount, privacy: .public)")
    }

    // MARK: - Video Encoding

    /// Encode the frames into `outputURL` by spawning a short-lived helper
    /// subprocess (this same binary, launched with `--encode-video`). The
    /// encoder's large VideoToolbox/AVFoundation working set — which the OS
    /// keeps cached in-process and which malloc pressure relief cannot reclaim —
    /// dies with the subprocess, so the main app's footprint stays flat.
    /// Encodes the frames into `outputURL` via the helper subprocess. Pure video
    /// encode — no OCR, no keys, no sidecar (search indexing happens later, only
    /// while the timeline is open).
    private func encodeVideo(frames: [FrameInfo], outputURL: URL, width: Int, height: Int) throws {
        let manifest = VideoEncoder.Manifest(
            outputPath: outputURL.path,
            width: width,
            height: height,
            framePaths: frames.map { $0.url.path }
        )
        let manifestURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("encode-\(UUID().uuidString).json")
        registerTempFile(manifestURL)
        defer {
            try? FileManager.default.removeItem(at: manifestURL)
            unregisterTempFile(manifestURL)
        }

        do {
            try JSONEncoder().encode(manifest).write(to: manifestURL)
            // 0600 — the manifest lists screenshot paths; keep it user-only.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
        } catch {
            Log.processing.error("Failed to write encode manifest: \(error.localizedDescription)")
            throw ProcessingError.encodingSetupFailed
        }

        guard let executableURL = Bundle.main.executableURL else {
            Log.processing.fault("Bundle.main.executableURL is nil — cannot spawn encoder")
            throw ProcessingError.encodingSetupFailed
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--encode-video", manifestURL.path]

        do {
            try process.run()
        } catch {
            Log.processing.error("Failed to launch encoder subprocess: \(error.localizedDescription)")
            throw ProcessingError.encodingSetupFailed
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            Log.processing.error("Encoder subprocess exited with status \(process.terminationStatus)")
            throw ProcessingError.encodingFailed
        }
    }

    // MARK: - Database

    private func openDatabase(_ path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }

        // Backfill and the normal cycle may write concurrently (separate
        // connections); wait rather than fail on a locked writer.
        sqlite3_busy_timeout(db, 5000)

        // 0600 — user-readable only (contains sensitive metadata)
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        } catch {
            Log.processing.debug("Could not set permissions on database file: \(error.localizedDescription)")
        }

        // Initialize schema
        let initSQL = """
            PRAGMA journal_mode=WAL;
            PRAGMA secure_delete=ON;
            CREATE TABLE IF NOT EXISTS segments (
                id TEXT PRIMARY KEY,
                date TEXT NOT NULL,
                start_ts REAL NOT NULL,
                end_ts REAL NOT NULL,
                frame_count INTEGER NOT NULL,
                fps REAL,
                width INTEGER,
                height INTEGER,
                file_size_bytes INTEGER,
                video_path TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_segments_date ON segments(date);
            CREATE INDEX IF NOT EXISTS idx_segments_start_ts ON segments(start_ts);
            CREATE INDEX IF NOT EXISTS idx_segments_end_ts ON segments(end_ts);
            CREATE TABLE IF NOT EXISTS appsegments (
                id TEXT PRIMARY KEY,
                app_id TEXT,
                date TEXT NOT NULL,
                start_ts REAL NOT NULL,
                end_ts REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_appsegments_date ON appsegments(date);
            CREATE INDEX IF NOT EXISTS idx_appsegments_app_id ON appsegments(app_id);
            CREATE INDEX IF NOT EXISTS idx_appsegments_start_ts ON appsegments(start_ts);
            CREATE INDEX IF NOT EXISTS idx_appsegments_end_ts ON appsegments(end_ts);
            CREATE TABLE IF NOT EXISTS ocr_frames (
                id TEXT PRIMARY KEY,
                segment_id TEXT NOT NULL,
                ts REAL NOT NULL,
                app_id TEXT,
                text_cipher BLOB NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_ocr_frames_ts ON ocr_frames(ts);
            CREATE INDEX IF NOT EXISTS idx_ocr_frames_segment ON ocr_frames(segment_id);
            CREATE TABLE IF NOT EXISTS ocr_postings (
                tok BLOB PRIMARY KEY,
                fids BLOB NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS ocr_done (
                segment_id TEXT PRIMARY KEY
            );
            CREATE TABLE IF NOT EXISTS ocr_frame_bitmap (
                segment_id TEXT PRIMARY KEY,
                bits BLOB NOT NULL,
                done_count INTEGER NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS ocr_bg_queue (
                segment_id TEXT PRIMARY KEY
            ) WITHOUT ROWID;
            """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, initSQL, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            Log.processing.fault("Schema initialization failed: \(msg)")
        }

        // Stamp per-component schema versions. A legacy OCR index is left unstamped
        // so the launch migrator still converts it.
        SchemaVersions.reconcile(db: db)

        return db
    }

    /// Insert a batch's OCR rows + posting updates and flip the `processed` frame
    /// bits, all in one transaction. A batch with no text still marks its frames
    /// processed (they were OCR'd, just empty).
    private func insertOCRRows(_ rows: [OCRSidecarRow], segmentId: String, frameCount: Int, processed: Range<Int>, db: OpaquePointer) {
        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        var inserted = 0
        // Accumulate every new (token → [fid]) posting for this whole batch, then
        // fold them into the posting lists in one pass — one read-modify-write per
        // distinct token instead of per (token, frame) pair.
        var batchPostings: [Data: [Int64]] = [:]
        let sql = """
            INSERT OR IGNORE INTO ocr_frames (id, segment_id, ts, app_id, text_cipher)
            VALUES (?, ?, ?, ?, ?);
            """
        for row in rows {
            guard let textData = Data(base64Encoded: row.textCipherB64) else { continue }
            guard let stmt = prepareStatement(db, sql: sql) else { continue }
            defer { sqlite3_finalize(stmt) }

            let ocrId = generateSegmentId()
            sqlite3_bind_text(stmt, 1, ocrId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, segmentId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, row.ts)
            if let appId = row.appId {
                sqlite3_bind_text(stmt, 4, appId, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            // SQLITE_TRANSIENT makes SQLite copy the blob during bind, so the
            // pointer only needs to be valid for the duration of the call.
            textData.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, 5, raw.baseAddress, Int32(textData.count), SQLITE_TRANSIENT)
            }

            if sqlite3_step(stmt) == SQLITE_DONE {
                inserted += 1
                let fid = sqlite3_last_insert_rowid(db)
                for token in Self.splitTokens(row.trigramTokensB64) {
                    batchPostings[token, default: []].append(fid)
                }
            } else {
                Log.processing.error("Failed to insert ocr_frame: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
        upsertPostings(batchPostings, db: db)
        markFramesProcessed(segmentId, frameCount: frameCount, range: processed, db: db)
        sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        Log.processing.info("OCR rows indexed — segment=\(segmentId, privacy: .public), inserted=\(inserted, privacy: .public)/\(rows.count, privacy: .public)")
    }

    /// Split a concatenated blind-index token blob into its fixed-width tokens.
    static func splitTokens(_ tokensB64: String) -> [Data] {
        guard let blob = Data(base64Encoded: tokensB64), !blob.isEmpty else { return [] }
        let width = SearchCrypto.tokenLength
        guard blob.count % width == 0 else { return [] }
        var tokens: [Data] = []
        var offset = 0
        while offset < blob.count {
            tokens.append(blob.subdata(in: offset..<offset + width))
            offset += width
        }
        return tokens
    }

    /// Append each token's new frame ids to its delta-varint posting list. fids in
    /// a batch are always larger than any already stored (rowids only grow), so the
    /// merged list stays ascending. Assumes an open transaction.
    private func upsertPostings(_ postings: [Data: [Int64]], db: OpaquePointer) {
        guard !postings.isEmpty else { return }
        let selectSQL = "SELECT fids FROM ocr_postings WHERE tok = ?;"
        let upsertSQL = "INSERT OR REPLACE INTO ocr_postings (tok, fids) VALUES (?, ?);"
        for (tok, newFids) in postings {
            var existing: Data?
            if let sel = prepareStatement(db, sql: selectSQL) {
                tok.withUnsafeBytes { raw in
                    sqlite3_bind_blob(sel, 1, raw.baseAddress, Int32(tok.count), SQLITE_TRANSIENT)
                }
                if sqlite3_step(sel) == SQLITE_ROW, let ptr = sqlite3_column_blob(sel, 0) {
                    existing = Data(bytes: ptr, count: Int(sqlite3_column_bytes(sel, 0)))
                }
                sqlite3_finalize(sel)
            }
            let merged = PostingCodec.appending(existing, fids: newFids)
            guard let up = prepareStatement(db, sql: upsertSQL) else { continue }
            defer { sqlite3_finalize(up) }
            tok.withUnsafeBytes { raw in
                sqlite3_bind_blob(up, 1, raw.baseAddress, Int32(tok.count), SQLITE_TRANSIENT)
            }
            merged.withUnsafeBytes { raw in
                sqlite3_bind_blob(up, 2, raw.baseAddress, Int32(merged.count), SQLITE_TRANSIENT)
            }
            if sqlite3_step(up) != SQLITE_DONE {
                Log.processing.error("Failed to upsert posting: \(String(cString: sqlite3_errmsg(db)))")
            }
        }
    }


    // MARK: - Timeline-gated OCR indexing

    /// Frames per OCR request handed to a persistent worker. It no longer needs to
    /// be large to hide the CoreML model load — the worker loads that ONCE and
    /// reuses it across every request, so there is no per-request cold start (that
    /// is what killed the old "~100% CPU every ~10s" pulsing). Kept modest instead
    /// so per-frame progress is flushed to `ocr_frame_bitmap` every ~50 frames:
    /// a force-quit (or timeline close) mid-segment loses at most this many frames
    /// of work and resumes exactly where it left off. Newest-first ordering is
    /// preserved (the claim always starts from the newest pending run).
    static let ocrFrameBatch = 50

    /// One unit of OCR work: the frame range `[lo, hi)` a helper will process. The
    /// range is chosen by the `FrameBitmap` status layer (newest pending run), so
    /// which frames are pending is tracked per frame, not by a segment high-water.
    private struct FrameBatch {
        let id: String
        let startTS: Double
        let endTS: Double
        let frameCount: Int
        let fps: Double
        let videoPath: String
        let lo: Int
        let hi: Int
    }

    /// Start indexing un-indexed segments for search. Called by `ContentView`
    /// when the timeline window appears. A pool of workers walks the segments
    /// newest-first (the content most likely to be searched becomes searchable
    /// soonest) and keeps going until every segment is indexed, so all history —
    /// including old dates recorded long ago — eventually becomes searchable.
    /// Idempotent — a second call while already running is a no-op.
    /// Record whether the timeline window is open. Called by `ContentView` on
    /// appear/disappear, up front — before OCR indexing is (later) started — so the
    /// background pass stays out for the whole time the window is up.
    func setTimelineOpen(_ open: Bool) {
        indexLock.lock()
        timelineOpen = open
        indexLock.unlock()
    }

    func beginTimelineIndexing() {
        indexLock.lock()
        if indexingActive && indexMode == .background {
            // The timeline takes priority over the background pass: retire its
            // workers (the epoch bump below supersedes them) and SIGKILL any
            // in-flight helper so interactive playback gets the CPU immediately,
            // then fall through to start a fresh timeline session.
            Log.processing.info("Preempting background OCR — timeline opened")
            terminateInFlightHelpersLocked()
        } else if indexingActive {
            // Already open (timeline mode). If the pool has drained (all workers
            // exited) but new segments were recorded since, re-fan-out so the
            // latest content gets indexed — newest-first — instead of no-op'ing
            // until a full close/open.
            if activeIndexWorkers == 0, let key = indexKey {
                _ = key
                let epoch = indexEpoch
                let workers = indexConcurrency
                activeIndexWorkers = workers
                indexLock.unlock()
                setIndexingInProgress(true)
                Log.processing.info("OCR indexing re-fanned-out on timeline show — \(workers, privacy: .public) worker(s)")
                for _ in 0..<workers { indexQueue.async { self.runIndexer(epoch: epoch) } }
                return
            }
            let activeWorkers = activeIndexWorkers
            indexLock.unlock()
            Log.processing.debug("beginTimelineIndexing: already active with \(activeWorkers, privacy: .public) worker(s) — no-op")
            return
        }
        Log.processing.info("beginTimelineIndexing: starting fresh")
        // Preserve `ocr_bg_queue` across timeline open/close: the timeline pass OCRs
        // everything newest-first regardless, and finished windows are pruned from
        // the queue lazily on the next background scope load — so nothing is lost if
        // the timeline is closed again before the whole backlog is indexed.
        backgroundScopeIDs.removeAll()
        indexingActive = true
        indexMode = .timeline
        indexEpoch += 1
        let epoch = indexEpoch
        indexingSegmentIDs.removeAll()
        indexKey = nil
        let workers = indexConcurrency
        indexLock.unlock()
        // Assert "indexing" up front — before the (possibly keychain-blocked) key
        // load — so a search opened right now reads "Loading results…" instead of
        // a premature "No matches"/"No more results". It flips to done only once a
        // worker actually drains the backlog.
        setIndexingInProgress(true)
        // Load the key once, off the main thread (it may block on a keychain
        // prompt), then fan out the worker pool. Every worker reuses this key.
        indexQueue.async { [weak self] in
            guard let self else { return }
            // Publish the starting percentage even while the key load is pending.
            self.recomputeIndexingProgress()
            Log.processing.info("beginTimelineIndexing: loading key…")
            let key = SearchCrypto.loadOrCreateKey()
            Log.processing.info("beginTimelineIndexing: key loaded, fanning out")
            self.indexLock.lock()
            guard self.indexingActive, self.indexEpoch == epoch else {
                self.indexLock.unlock()
                Log.processing.info("beginTimelineIndexing: aborted after key load (epoch/active changed)")
                return
            }
            self.indexKey = key
            self.activeIndexWorkers = workers
            self.indexLock.unlock()
            Log.processing.info("OCR indexing started (timeline open) — \(workers, privacy: .public) worker(s)")
            for _ in 0..<workers {
                self.indexQueue.async { self.runIndexer(epoch: epoch) }
            }
        }
    }

    /// Start a background OCR pass over the queued recent windows — but only when
    /// the timeline is closed, no session is already running, and the machine is on
    /// AC power. The queue lives in the DB (`ocr_bg_queue`), so it survives a
    /// force-quit and any number of timeline open/close cycles; per-frame progress
    /// lives in `ocr_frame_bitmap`, so a partially-OCR'd window resumes exactly
    /// where it left off. On battery the windows just stay queued (compression
    /// already ran); `powerStateChanged` retries the moment the charger is
    /// connected. Called after each cycle and on power/drain events. Idempotent.
    func maybeStartBackgroundIndexing() {
        indexLock.lock()
        // Never run while the timeline is open (even in the gap before its OCR
        // starts) — it would starve the newest frame's decode.
        guard !timelineOpen, !indexingActive else { indexLock.unlock(); return }
        // Battery: defer. Compression already happened; OCR waits for AC power.
        guard Self.isOnACPower() else {
            indexLock.unlock()
            Log.processing.info("Background OCR deferred — on battery (waiting for AC power)")
            return
        }
        // Load the still-pending queued windows from the DB (drop finished/pruned
        // entries while we're here). Nothing pending → nothing to do.
        let scope = loadPendingBackgroundScopeLocked()
        guard !scope.isEmpty else { indexLock.unlock(); return }
        backgroundScopeIDs = Set(scope)
        indexingActive = true
        indexMode = .background
        indexEpoch += 1
        let epoch = indexEpoch
        indexingSegmentIDs.removeAll()
        indexKey = nil
        let workers = backgroundIndexConcurrency
        indexLock.unlock()
        // Load the key off the main thread (the keychain is already trusted, so
        // this is silent), then fan out. Every worker reuses this one key.
        indexQueue.async { [weak self] in
            guard let self else { return }
            let key = SearchCrypto.loadOrCreateKey()
            self.indexLock.lock()
            guard self.indexingActive, self.indexEpoch == epoch else {
                self.indexLock.unlock()
                return
            }
            self.indexKey = key
            self.activeIndexWorkers = workers
            self.indexLock.unlock()
            Log.processing.info("Background OCR started (timeline closed, on AC) — \(scope.count, privacy: .public) window(s), \(workers, privacy: .public) worker(s)")
            for _ in 0..<workers {
                self.indexQueue.async { self.runIndexer(epoch: epoch) }
            }
        }
    }

    /// Return the queued (`ocr_bg_queue`) segments that still have un-OCR'd frames,
    /// and opportunistically delete queue rows whose segment is finished or gone —
    /// so the queue can't grow without bound. Caller holds `indexLock`.
    private func loadPendingBackgroundScopeLocked() -> [String] {
        guard let db = openDatabase(Paths.databasePath.path) else { return [] }
        defer { sqlite3_close(db) }
        // Drop finished/pruned entries.
        sqlite3_exec(db, """
            DELETE FROM ocr_bg_queue WHERE segment_id IN (
              SELECT q.segment_id FROM ocr_bg_queue q
              LEFT JOIN segments s ON s.id = q.segment_id
              LEFT JOIN ocr_frame_bitmap b ON b.segment_id = q.segment_id
              WHERE s.id IS NULL OR s.frame_count = 0
                 OR COALESCE(b.done_count, 0) >= s.frame_count
            );
            """, nil, nil, nil)
        var ids: [String] = []
        let sql = """
            SELECT q.segment_id FROM ocr_bg_queue q
            JOIN segments s ON s.id = q.segment_id
            LEFT JOIN ocr_frame_bitmap b ON b.segment_id = q.segment_id
            WHERE COALESCE(b.done_count, 0) < s.frame_count AND s.frame_count > 0;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { ids.append(String(cString: c)) }
        }
        return ids
    }

    /// Whether the Mac is running on AC power (or is a desktop with no battery).
    /// The background OCR pass is gated on this; segment compression is not.
    static func isOnACPower() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            return true // no power sources → desktop, always "plugged in"
        }
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let state = desc[kIOPSPowerSourceStateKey] as? String else { continue }
            if state == kIOPSACPowerValue { return true }
        }
        return false
    }

    /// Called when the power source changes: if the charger was just connected,
    /// drain the windows that were queued while on battery — no timeline needed.
    private func powerStateChanged() {
        if Self.isOnACPower() {
            Log.processing.info("Power connected — draining any battery-deferred OCR windows")
            maybeStartBackgroundIndexing()
        }
    }

    /// SIGKILL every in-flight OCR helper and clear the list. Caller holds
    /// `indexLock`. Used to preempt the background pass when the timeline opens.
    private func terminateInFlightHelpersLocked() {
        let processes = currentIndexProcesses
        currentIndexProcesses.removeAll()
        let killed = processes.filter { $0.isRunning }
        killed.forEach { kill($0.processIdentifier, SIGKILL) }
        if !killed.isEmpty {
            Log.processing.info("SIGKILLed \(killed.count, privacy: .public) in-flight OCR helper(s)")
        }
    }

    /// Set `indexingInProgress` on the main thread (it's a `@Published` the search
    /// UI observes), from any worker thread.
    private func setIndexingInProgress(_ value: Bool) {
        if Thread.isMainThread { indexingInProgress = value }
        else { DispatchQueue.main.async { self.indexingInProgress = value } }
    }

    private func setIndexingProgress(_ value: Double) {
        if Thread.isMainThread { indexingProgress = value }
        else { DispatchQueue.main.async { self.indexingProgress = value } }
    }

    /// Recompute the OCR-indexed fraction on demand (off-main), so the search
    /// footer can tell "everything is indexed" from "more is pending" even when no
    /// indexing session is currently running (e.g. right after the search opens).
    func refreshIndexingProgress() {
        indexQueue.async { [weak self] in self?.recomputeIndexingProgress() }
    }

    /// Recompute the frame-weighted OCR-indexed fraction from the DB. Cheap
    /// (two SUMs); called at start and after each segment so the "(XX%)" ticks up.
    private func recomputeIndexingProgress() {
        guard let db = openDatabase(Paths.databasePath.path) else { return }
        defer { sqlite3_close(db) }
        // Frame-level: done frames = the per-segment processed bit count. Ticks up
        // per batch, not per segment.
        let sql = """
            SELECT
              COALESCE(SUM(COALESCE(
                (SELECT done_count FROM ocr_frame_bitmap b WHERE b.segment_id = s.id), 0)), 0),
              COALESCE(SUM(s.frame_count), 0)
            FROM segments s;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return }
        let done = sqlite3_column_double(stmt, 0)
        let total = sqlite3_column_double(stmt, 1)
        setIndexingProgress(total > 0 ? min(1.0, done / total) : 1.0)
    }

    /// Re-fan-out indexing workers if the timeline is open but the pool has drained,
    /// so a segment encoded *after* the initial pass gets indexed promptly (and
    /// newest-first) instead of waiting for the timeline to be reopened. No-op when
    /// the timeline is closed or workers are already running.
    func resumeIndexingIfDrained() {
        indexLock.lock()
        guard indexMode == .timeline, indexingActive, activeIndexWorkers == 0, indexKey != nil else { indexLock.unlock(); return }
        let epoch = indexEpoch
        let workers = indexConcurrency
        activeIndexWorkers = workers
        indexLock.unlock()
        setIndexingInProgress(true)
        Log.processing.info("OCR indexing resumed for newly-encoded segment — \(workers, privacy: .public) worker(s)")
        for _ in 0..<workers {
            indexQueue.async { self.runIndexer(epoch: epoch) }
        }
    }

    /// Stop indexing and reclaim CPU + RAM immediately. Called when the timeline
    /// window disappears. Every in-flight `--ocr-segment` helper is terminated at
    /// once so no OCR CPU or memory survives the window closing.
    func endTimelineIndexing() {
        indexLock.lock()
        indexingActive = false
        activeIndexWorkers = 0
        let processes = currentIndexProcesses
        indexLock.unlock()
        setIndexingInProgress(false)
        // Vision OCR runs in-process in each helper (~0.4 GB working set); it is
        // fully reclaimed when the subprocess dies here, so no OCR memory survives
        // the timeline closing. (The main app's own player/decoder buffers are
        // reclaimed by PlaybackController.releaseResources.)
        // SIGKILL, not terminate()/SIGTERM: a helper deep in a Vision/VideoToolbox
        // decode won't service a catchable signal for many seconds, and until it
        // dies it keeps hogging the video decoder the interactive UI needs. SIGKILL
        // frees it at once; a killed batch is simply re-claimed later (indexing is
        // transactional per batch).
        let killed = processes.filter { $0.isRunning }
        killed.forEach { kill($0.processIdentifier, SIGKILL) }
        indexLock.lock()
        currentIndexProcesses.removeAll()
        indexLock.unlock()
        Log.processing.info("OCR indexing stopped — SIGKILLed \(killed.count, privacy: .public) in-flight helper(s)")
    }

    /// True only while indexing is on AND this worker is still the current epoch.
    private func isIndexingActive(epoch: Int) -> Bool {
        indexLock.lock(); defer { indexLock.unlock() }
        return indexingActive && indexEpoch == epoch
    }

    /// One pool worker: launches a single persistent OCR helper (which loads the
    /// Vision model ONCE), then feeds it segment after segment over its lifetime.
    /// Because the same warm helper handles every batch, the CPU stays busy
    /// continuously — no per-segment cold-start stall, so no pulsing.
    private func runIndexer(epoch: Int) {
        var processed = 0
        if let worker = launchOCRWorker(epoch: epoch) {
            while isIndexingActive(epoch: epoch), worker.process.isRunning {
                guard let batch = claimNextFrameBatch(epoch: epoch) else {
                    Log.processing.info("OCR worker exiting: no more pending frames (processed \(processed, privacy: .public) batch(es))")
                    break
                }
                let ok = runBatch(batch, on: worker, epoch: epoch)
                releaseSegmentClaim(batch.id)
                if ok {
                    processed += 1
                    // Update the percentage, then tell any open search fresh matches
                    // exist — per batch, so a just-OCR'd frame's match surfaces soon.
                    recomputeIndexingProgress()
                    NotificationCenter.default.post(name: .ocrIndexProgressed, object: nil)
                }
            }
            shutdownOCRWorker(worker)
        }
        if processed > 0 {
            Log.processing.info("OCR indexing worker ended — processed \(processed, privacy: .public) batch(es)")
        }
        // Last worker out drains the backlog. The decrement is epoch-guarded so a
        // worker superseded by a newer session (e.g. background preempted by the
        // timeline) never corrupts the new session's live worker count.
        indexLock.lock()
        var drainedTimeline = false
        var drainedBackground = false
        if indexEpoch == epoch {
            activeIndexWorkers = max(0, activeIndexWorkers - 1)
            if activeIndexWorkers == 0 {
                if indexMode == .timeline {
                    // Clear the search "Loading results…" state.
                    drainedTimeline = true
                } else {
                    // Background pass finished — end the session. Finished windows
                    // are pruned from `ocr_bg_queue` by the next scope load; if any
                    // remain (queued while this pass ran, or left partial), start
                    // another pass for them.
                    backgroundScopeIDs.removeAll()
                    indexingActive = false
                    drainedBackground = true
                    Log.processing.info("Background OCR drained")
                }
            }
        }
        indexLock.unlock()
        if drainedTimeline { setIndexingInProgress(false) }
        if drainedBackground { maybeStartBackgroundIndexing() }
    }

    /// A live persistent OCR helper plus the handles to talk to it.
    private struct OCRWorker {
        let process: Process
        let requests: FileHandle      // write one Manifest JSON line per batch
        let replies: PipeLineReader   // read one "OK"/"ERR" line per batch
    }

    /// Launch one persistent `--ocr-worker` subprocess and hand it the session key
    /// as the first stdin line. Registered in `currentIndexProcesses` so a timeline
    /// close/preempt SIGKILLs it with the rest. Nil if the session ended first.
    private func launchOCRWorker(epoch: Int) -> OCRWorker? {
        indexLock.lock()
        let sessionKey = indexKey
        indexLock.unlock()
        guard let key = sessionKey, let executableURL = Bundle.main.executableURL else { return nil }

        let inPipe = Pipe()
        let outPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--ocr-worker"]
        process.standardInput = inPipe
        process.standardOutput = outPipe

        indexLock.lock()
        guard indexingActive, indexEpoch == epoch else { indexLock.unlock(); return nil }
        do {
            try process.run()
        } catch {
            indexLock.unlock()
            Log.processing.error("Indexing: failed to launch OCR worker: \(error.localizedDescription)")
            return nil
        }
        currentIndexProcesses.append(process)
        indexLock.unlock()

        let requests = inPipe.fileHandleForWriting
        // First line: the AES key. (SIGPIPE is ignored process-wide, so a write to
        // an already-dead worker fails the write instead of killing us.)
        try? requests.write(contentsOf: Data((SearchCrypto.exportBase64(key) + "\n").utf8))
        return OCRWorker(process: process, requests: requests, replies: PipeLineReader(outPipe.fileHandleForReading))
    }

    /// Send one batch to a persistent worker and record its result. Returns true
    /// only when the batch was durably indexed (or its video is gone, so the frames
    /// are marked done and never retried); false leaves the frames pending for a
    /// later pass (worker killed on timeline close, decode error, etc.).
    private func runBatch(_ batch: FrameBatch, on worker: OCRWorker, epoch: Int) -> Bool {
        let videoURL = Paths.baseDataDirectory.appendingPathComponent(batch.videoPath)
        // Video gone (pruned by retention): mark every frame processed, don't retry.
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            if let db = openDatabase(Paths.databasePath.path) {
                markFramesProcessed(batch.id, frameCount: batch.frameCount, range: 0..<batch.frameCount, db: db)
                sqlite3_close(db)
            }
            return true
        }

        let ocrOutputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-index-\(UUID().uuidString).json")
        registerTempFile(ocrOutputURL)
        defer {
            try? FileManager.default.removeItem(at: ocrOutputURL)
            unregisterTempFile(ocrOutputURL)
        }

        let manifest = OCRBackfill.Manifest(
            videoPath: videoURL.path,
            startTS: batch.startTS,
            endTS: batch.endTS,
            frameCount: batch.frameCount,
            fps: batch.fps,
            loFrame: batch.lo,
            hiFrame: batch.hi,
            ocrOutputPath: ocrOutputURL.path
        )
        guard var request = try? JSONEncoder().encode(manifest) else { return false }
        request.append(0x0A) // newline-delimit the request

        // Send the request and block for the worker's single-line reply.
        guard worker.process.isRunning else { return false }
        do {
            try worker.requests.write(contentsOf: request)
        } catch {
            return false
        }
        guard let ack = worker.replies.readLine() else { return false } // EOF → worker died

        // Timeline closed mid-batch (helper SIGKILLed) — leave frames pending.
        guard isIndexingActive(epoch: epoch) else { return false }
        guard ack == "OK" else {
            Log.processing.error("Indexing: worker failed segment=\(batch.id, privacy: .public) frames [\(batch.lo, privacy: .public),\(batch.hi, privacy: .public)) — leaving for retry")
            return false
        }

        let rows: [OCRSidecarRow]
        if let data = FileManager.default.contents(atPath: ocrOutputURL.path),
           let decoded = try? JSONDecoder().decode([OCRSidecarRow].self, from: data) {
            rows = decoded
        } else {
            rows = []
        }

        guard let db = openDatabase(Paths.databasePath.path) else { return false }
        defer { sqlite3_close(db) }
        // Frames decoded from the video carry no app id; recover it from appsegments.
        let enriched = enrichAppIds(rows, startTS: batch.startTS, endTS: batch.endTS, db: db)
        // Insert this batch's rows and flip its frame bits in the SAME transaction,
        // so the batch is durably indexed exactly once.
        insertOCRRows(enriched, segmentId: batch.id, frameCount: batch.frameCount,
                      processed: batch.lo..<batch.hi, db: db)
        Log.processing.info("Indexed segment=\(batch.id, privacy: .public) frames [\(batch.lo, privacy: .public),\(batch.hi, privacy: .public)) — rows=\(rows.count, privacy: .public)")
        return true
    }

    /// Close a worker's stdin so it hits EOF and exits cleanly (dropping the Vision
    /// model's working set with the process). No-op if it was already SIGKILLed on
    /// timeline close.
    private func shutdownOCRWorker(_ worker: OCRWorker) {
        try? worker.requests.close()
        indexLock.lock()
        currentIndexProcesses.removeAll { $0 === worker.process }
        indexLock.unlock()
        if worker.process.isRunning { worker.process.waitUntilExit() }
    }

    /// Atomically claim the newest batch of pending frames. Picks the newest segment
    /// with frames still to do (`done_from > 0`), excluding segments a worker is
    /// mid-flight on, and returns its top pending batch `[done_from-N, done_from)`.
    /// Claims are in-memory (a killed worker's segment is simply re-eligible; its
    /// `done_from` never advanced, so nothing is lost or double-counted).
    private func claimNextFrameBatch(epoch: Int) -> FrameBatch? {
        indexLock.lock()
        defer { indexLock.unlock() }
        guard indexingActive, indexEpoch == epoch else { return nil }
        guard let db = openDatabase(Paths.databasePath.path) else { return nil }
        defer { sqlite3_close(db) }

        // Scheduling layer: newest segment that still has unprocessed frames
        // (done_count < frame_count), excluding segments a worker is mid-flight on.
        // In background mode the search space is ALSO restricted to this pass's
        // window (`backgroundScopeIDs`) so it never wanders into legacy segments —
        // those are timeline-open-only.
        let inFlight = Array(indexingSegmentIDs)
        let scope = indexMode == .background ? Array(backgroundScopeIDs) : []
        let inFlightClause = inFlight.isEmpty ? "" : "AND s.id NOT IN (\(inFlight.map { _ in "?" }.joined(separator: ",")))"
        let scopeClause = indexMode == .background
            ? (scope.isEmpty ? "AND 0" : "AND s.id IN (\(scope.map { _ in "?" }.joined(separator: ",")))")
            : ""
        let sql = """
            SELECT s.id, s.start_ts, s.end_ts, s.frame_count, COALESCE(s.fps, 1.0), s.video_path, b.bits
            FROM segments s LEFT JOIN ocr_frame_bitmap b ON b.segment_id = s.id
            WHERE COALESCE(b.done_count, 0) < s.frame_count AND s.frame_count > 0 \(inFlightClause) \(scopeClause)
            ORDER BY s.start_ts DESC LIMIT 1;
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        var bindIndex: Int32 = 1
        for id in inFlight {
            sqlite3_bind_text(stmt, bindIndex, id, -1, SQLITE_TRANSIENT); bindIndex += 1
        }
        for id in scope {
            sqlite3_bind_text(stmt, bindIndex, id, -1, SQLITE_TRANSIENT); bindIndex += 1
        }
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let idC = sqlite3_column_text(stmt, 0),
              let pathC = sqlite3_column_text(stmt, 5) else { return nil }
        let id = String(cString: idC)
        let frameCount = Int(sqlite3_column_int(stmt, 3))
        // Status layer decides which frames are next (newest pending contiguous run).
        let bits = sqlite3_column_blob(stmt, 6).map { Data(bytes: $0, count: Int(sqlite3_column_bytes(stmt, 6))) }
        let bitmap = FrameBitmap(count: frameCount, blob: bits)
        guard let run = bitmap.newestPendingRun(maxLen: Self.ocrFrameBatch) else { return nil }
        indexingSegmentIDs.insert(id)
        Log.processing.debug("OCR claim segment=\(id, privacy: .public) frames [\(run.lowerBound, privacy: .public),\(run.upperBound, privacy: .public)) of \(frameCount, privacy: .public)")
        return FrameBatch(
            id: id,
            startTS: sqlite3_column_double(stmt, 1),
            endTS: sqlite3_column_double(stmt, 2),
            frameCount: frameCount,
            fps: sqlite3_column_double(stmt, 4),
            videoPath: String(cString: pathC),
            lo: run.lowerBound, hi: run.upperBound
        )
    }

    private func releaseSegmentClaim(_ id: String) {
        indexLock.lock()
        indexingSegmentIDs.remove(id)
        indexLock.unlock()
    }

    /// Persistence layer: flip the bits for `range` in a segment's frame bitmap,
    /// collapsing to an empty blob once every frame is done (smallest "done" form).
    private func markFramesProcessed(_ segmentId: String, frameCount: Int, range: Range<Int>, db: OpaquePointer) {
        var bitmap = loadFrameBitmap(segmentId, frameCount: frameCount, db: db)
        bitmap.markProcessed(range)
        guard let stmt = prepareStatement(db, sql: "INSERT OR REPLACE INTO ocr_frame_bitmap (segment_id, bits, done_count) VALUES (?, ?, ?);") else { return }
        defer { sqlite3_finalize(stmt) }
        let blob = bitmap.storageBlob
        sqlite3_bind_text(stmt, 1, segmentId, -1, SQLITE_TRANSIENT)
        blob.withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, 2, raw.baseAddress, Int32(blob.count), SQLITE_TRANSIENT)
        }
        sqlite3_bind_int(stmt, 3, Int32(bitmap.processedCount))
        _ = sqlite3_step(stmt)
    }

    private func loadFrameBitmap(_ segmentId: String, frameCount: Int, db: OpaquePointer) -> FrameBitmap {
        guard let stmt = prepareStatement(db, sql: "SELECT bits FROM ocr_frame_bitmap WHERE segment_id = ?;") else {
            return FrameBitmap(count: frameCount)
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, segmentId, -1, SQLITE_TRANSIENT)
        var blob: Data?
        if sqlite3_step(stmt) == SQLITE_ROW, let ptr = sqlite3_column_blob(stmt, 0) {
            blob = Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 0)))
        }
        return FrameBitmap(count: frameCount, blob: blob)
    }

    /// Fill in each row's app id from the appsegments covering its timestamp.
    private func enrichAppIds(_ rows: [OCRSidecarRow], startTS: Double, endTS: Double, db: OpaquePointer) -> [OCRSidecarRow] {
        // (start_ts, end_ts, app_id) intervals overlapping this segment's window.
        var intervals: [(start: Double, end: Double, appId: String)] = []
        let sql = """
            SELECT start_ts, end_ts, app_id FROM appsegments
            WHERE app_id IS NOT NULL AND end_ts >= ? AND start_ts <= ? ORDER BY start_ts;
            """
        if let stmt = prepareStatement(db, sql: sql) {
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, startTS)
            sqlite3_bind_double(stmt, 2, endTS)
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let appC = sqlite3_column_text(stmt, 2) else { continue }
                intervals.append((sqlite3_column_double(stmt, 0), sqlite3_column_double(stmt, 1), String(cString: appC)))
            }
        }
        guard !intervals.isEmpty else { return rows }

        return rows.map { row in
            guard row.appId == nil,
                  let match = intervals.first(where: { row.ts >= $0.start && row.ts <= $0.end }) else { return row }
            return OCRSidecarRow(
                ts: row.ts, appId: match.appId,
                textCipherB64: row.textCipherB64,
                trigramTokensB64: row.trigramTokensB64
            )
        }
    }

    private func prepareStatement(_ db: OpaquePointer, sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.processing.error("Failed to prepare statement: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        return stmt
    }

    // MARK: - Helpers

    private struct FrameInfo {
        let url: URL
        let timestamp: TimeInterval
        let appId: String?
        let width: Int
        let height: Int
    }

    private struct AppSegmentRecord {
        let appId: String?
        let startTS: TimeInterval
        let endTS: TimeInterval
    }

    private func isScreenshotFilename(_ name: String) -> Bool {
        // Format: YYYYMMDD-HHMMSS-<uuid>-<bundleid> (at least 3 dash-separated parts)
        let parts = name.split(separator: "-")
        return parts.count >= 3 && parts[0].count == 8 && parts[1].count == 6
    }

    private func parseFilename(_ name: String) -> (timestamp: TimeInterval, appId: String?)? {
        // Format: YYYYMMDD-HHMMSS-<uuid>-<bundleid>
        let parts = name.split(separator: "-", maxSplits: 3)
        guard parts.count >= 2 else { return nil }

        let datePart = String(parts[0])
        let timePart = String(parts[1])
        guard datePart.count == 8, timePart.count == 6 else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd HHmmss"
        formatter.timeZone = TimeZone.current

        guard let date = formatter.date(from: "\(datePart) \(timePart)") else { return nil }

        let appId: String? = parts.count >= 4 ? String(parts[3]) : nil
        return (timestamp: date.timeIntervalSince1970, appId: appId)
    }

    private func generateSegmentId() -> String {
        var bytes = [UInt8](repeating: 0, count: 10)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func dateString(from timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private func buildAppSegments(from frames: [FrameInfo]) -> [AppSegmentRecord] {
        guard !frames.isEmpty else { return [] }

        var result: [AppSegmentRecord] = []
        var currentAppId = frames[0].appId
        var segStart = frames[0].timestamp

        for i in 1..<frames.count {
            if frames[i].appId != currentAppId {
                result.append(AppSegmentRecord(
                    appId: currentAppId,
                    startTS: segStart,
                    endTS: frames[i - 1].timestamp + 2.0
                ))
                currentAppId = frames[i].appId
                segStart = frames[i].timestamp
            }
        }

        // Close last segment
        result.append(AppSegmentRecord(
            appId: currentAppId,
            startTS: segStart,
            endTS: frames.last!.timestamp + 2.0
        ))

        return result
    }

    // MARK: - Memory

    private func currentMemoryStats() -> (resident: Double, footprint: Double)? {
        var basicInfo = mach_task_basic_info()
        var basicCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let basicResult = withUnsafeMutablePointer(to: &basicInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount)
            }
        }

        var vmInfo = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let vmResult = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }

        guard basicResult == KERN_SUCCESS, vmResult == KERN_SUCCESS else { return nil }
        return (
            resident: Double(basicInfo.resident_size) / 1_048_576.0,
            footprint: Double(vmInfo.phys_footprint) / 1_048_576.0
        )
    }

    private func logMemory(_ label: String) {
        guard let stats = currentMemoryStats() else { return }
        Log.processing.notice("Memory [\(label, privacy: .public)] — resident=\(String(format: "%.1f", stats.resident), privacy: .public) MB, footprint=\(String(format: "%.1f", stats.footprint), privacy: .public) MB")
    }

    // MARK: - Errors

    enum ProcessingError: Error {
        case encodingSetupFailed
        case encodingFailed
    }
}
