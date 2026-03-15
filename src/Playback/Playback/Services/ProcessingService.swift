// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import SQLite3
import AppKit
import Security

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
final class ProcessingService {
    static let shared = ProcessingService()

    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.falconer.Playback.processing", qos: .utility)
    private var isRunning = false

    private init() {}

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            self?.triggerProcessing()
        }
        triggerProcessing()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func triggerProcessing() {
        guard !isRunning else { return }
        isRunning = true
        queue.async { [weak self] in
            self?.processAllPendingDays()
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
    }

    // MARK: - Processing Pipeline

    private func processAllPendingDays() {
        let tempDir = Paths.tempDirectory
        let fm = FileManager.default

        guard let monthDirs = try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return
        }

        for monthDir in monthDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: monthDir.path, isDirectory: &isDir), isDir.boolValue else { continue }

            guard let dayDirs = try? fm.contentsOfDirectory(at: monthDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
                continue
            }

            for dayDir in dayDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard fm.fileExists(atPath: dayDir.path, isDirectory: &isDir), isDir.boolValue else { continue }
                processDayDirectory(dayDir)
            }
        }
    }

    private func processDayDirectory(_ dayDir: URL) {
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
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

        for group in groups {
            processFrameGroup(group, dayDir: dayDir)
        }
    }

    private func processFrameGroup(_ frames: [FrameInfo], dayDir: URL) {
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
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: chunksDir.path)
        } catch {
            #if DEBUG
            print("[ProcessingService] Failed to create chunks dir: \(error)")
            #endif
            return
        }

        let videoURL = chunksDir.appendingPathComponent("\(segmentId).mp4")

        do {
            try encodeVideo(frames: frames, outputURL: videoURL, width: width, height: height)
            // 0600 — user-readable only (sensitive screen content)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: videoURL.path)
        } catch {
            #if DEBUG
            print("[ProcessingService] Encoding failed for \(segmentId): \(error)")
            #endif
            // Preserve temp files for retry on encoding failure
            return
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int) ?? 0
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
            #if DEBUG
            print("[ProcessingService] Failed to open database, preserving temp files")
            #endif
            try? FileManager.default.removeItem(at: videoURL)
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
                #if DEBUG
                print("[ProcessingService] Failed to insert segment: \(String(cString: sqlite3_errmsg(db)))")
                #endif
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
                    #if DEBUG
                    print("[ProcessingService] Failed to insert appsegment: \(String(cString: sqlite3_errmsg(db)))")
                    #endif
                }
            }
        }

        // Delete processed temp files after successful DB write
        for frame in frames {
            try? FileManager.default.removeItem(at: frame.url)
        }

        #if DEBUG
        print("[ProcessingService] Processed \(frames.count) frames → segment \(segmentId)")
        #endif
    }

    // MARK: - Video Encoding

    private func encodeVideo(frames: [FrameInfo], outputURL: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: outputURL)

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

        for (index, frame) in frames.enumerated() {
            guard let image = NSImage(contentsOf: frame.url),
                  let pixelBuffer = createPixelBuffer(from: image, width: width, height: height) else {
                #if DEBUG
                print("[ProcessingService] Skipping unreadable frame: \(frame.url.lastPathComponent)")
                #endif
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
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)

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
        sqlite3_exec(db, initSQL, nil, nil, nil)

        return db
    }

    private func prepareStatement(_ db: OpaquePointer, sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            #if DEBUG
            print("[ProcessingService] Failed to prepare statement: \(String(cString: sqlite3_errmsg(db)))")
            #endif
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
