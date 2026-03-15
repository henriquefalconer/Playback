// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import SQLite3
import AppKit
import Security
import os

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class ProcessingService {
    static let shared = ProcessingService()

    private var timer: Timer?
    private var heartbeatTimer: Timer?
    private let queue = DispatchQueue(label: "com.falconer.Playback.processing", qos: .utility)
    private var isRunning = false
    private var lastProcessingTime: Date?
    private var totalSegmentsCreated = 0
    private var triggerCount = 0

    private init() {}

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            self?.triggerProcessing()
        }
        // Heartbeat every 5 minutes
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Log.processing.info("Heartbeat — running=\(self.isRunning, privacy: .public), lastProcessing=\(self.lastProcessingTime?.description ?? "never", privacy: .public), totalSegmentsCreated=\(self.totalSegmentsCreated, privacy: .public)")
        }
        triggerProcessing()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func triggerProcessing() {
        guard !isRunning else {
            Log.processing.info("Processing trigger skipped — already running")
            return
        }
        isRunning = true
        triggerCount += 1
        let trigger = triggerCount
        let source = trigger == 1 ? "initial_start" : "timer"
        Log.processing.info("Processing cycle #\(trigger, privacy: .public) started — trigger=\(source, privacy: .public)")
        queue.async { [weak self] in
            let cycleStart = CFAbsoluteTimeGetCurrent()
            var segmentsCreated = 0
            var framesProcessed = 0
            self?.processAllPendingDays(segmentsCreated: &segmentsCreated, framesProcessed: &framesProcessed)
            let elapsed = CFAbsoluteTimeGetCurrent() - cycleStart
            Log.processing.info("Processing cycle #\(trigger, privacy: .public) completed — segments=\(segmentsCreated, privacy: .public), frames=\(framesProcessed, privacy: .public), duration=\(String(format: "%.1f", elapsed), privacy: .public)s")
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.lastProcessingTime = Date()
                self?.totalSegmentsCreated += segmentsCreated
            }
        }
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

        // Screenshot files have no extension, named YYYYMMDD-HHMMSS-<uuid>-<bundleid>
        let screenshotFiles = files
            .filter { $0.pathExtension.isEmpty && isScreenshotFilename($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !screenshotFiles.isEmpty else { return }

        // Load frame metadata (size) without loading full image data
        var frames: [FrameInfo] = []
        for fileURL in screenshotFiles {
            guard let (timestamp, appId) = parseFilename(fileURL.lastPathComponent) else { continue }

            // Read image dimensions without loading full pixel data
            guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int else {
                continue
            }

            frames.append(FrameInfo(url: fileURL, timestamp: timestamp, appId: appId, width: width, height: height))
        }

        guard !frames.isEmpty else { return }

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

    private func encodeVideo(frames: [FrameInfo], outputURL: URL, width: Int, height: Int) throws {  // swiftlint:disable:this function_body_length
        do {
            try FileManager.default.removeItem(at: outputURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // File doesn't exist yet, that's fine
        } catch {
            Log.processing.debug("Could not remove pre-existing video file: \(error.localizedDescription)")
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(500_000, width * height),
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttribs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttribs
        )

        guard writer.canAdd(input) else {
            throw ProcessingError.encodingSetupFailed
        }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let encodeLoopStart = CFAbsoluteTimeGetCurrent()
        for (index, frame) in frames.enumerated() {
            guard let image = NSImage(contentsOf: frame.url),
                  let pixelBuffer = createPixelBuffer(from: image, width: width, height: height) else {
                Log.processing.notice("Skipping unreadable frame: \(frame.url.lastPathComponent)")
                continue
            }

            // Wait for input to be ready
            var waited = 0
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.01)
                waited += 1
                if waited > 1000 { break }  // Timeout after 10s
            }

            let presentationTime = CMTime(value: CMTimeValue(index), timescale: 30)
            adaptor.append(pixelBuffer, withPresentationTime: presentationTime)

            if (index + 1) % 100 == 0 {
                let elapsed = CFAbsoluteTimeGetCurrent() - encodeLoopStart
                Log.processing.info("Encoding progress — frame \(index + 1, privacy: .public)/\(frames.count, privacy: .public), elapsed=\(String(format: "%.1f", elapsed), privacy: .public)s")
            }
        }

        input.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting { semaphore.signal() }
        semaphore.wait()

        if writer.status == .failed {
            throw writer.error ?? ProcessingError.encodingFailed
        }
    }

    private func createPixelBuffer(from image: NSImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return buffer
    }

    // MARK: - Database

    private func openDatabase(_ path: String) -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }

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
            CREATE TABLE IF NOT EXISTS schema_version (
                version TEXT PRIMARY KEY,
                applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
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
            """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, initSQL, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            Log.processing.fault("Schema initialization failed: \(msg)")
        }

        return db
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

    // MARK: - Errors

    enum ProcessingError: Error {
        case encodingSetupFailed
        case encodingFailed
    }
}
