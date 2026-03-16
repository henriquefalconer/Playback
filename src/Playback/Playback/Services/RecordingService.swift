// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import AppKit
import CoreGraphics
import ApplicationServices
import Combine
import ScreenCaptureKit
import CoreMedia
import os

/// Recording service that captures screenshots at regular intervals
/// Runs in-process, uses app's Screen Recording permission.
/// A minimal background SCStream keeps the macOS purple recording indicator always visible.
@MainActor
final class RecordingService: ObservableObject {
    static let shared = RecordingService()

    @Published private(set) var isRecording = false
    @Published private(set) var lastCaptureTime: Date?
    @Published private(set) var captureCount: UInt64 = 0

    private var timer: Timer?
    private let fileManager = FileManager.default

    // Background SCStream solely to keep the recording indicator visible (not flashing)
    private var indicatorStream: SCStream?
    private var indicatorDelegate: IndicatorStreamDelegate?

    // Config
    private var captureInterval: TimeInterval = 2.0 // seconds
    private var excludedApps: [String] = []

    // Capture cycle summary counters (logged every 60 captures)
    private var summaryCapturesSinceLastLog: UInt64 = 0
    private var summarySkippedByTimeline: UInt64 = 0
    private var summaryTotalFileBytes: UInt64 = 0
    private var cumulativeSessionBytes: UInt64 = 0

    private init() {
        Log.recording.debug("Initializing singleton")
        loadConfig()
        setupConfigObserver()
        Log.recording.debug("Initialization complete")
    }

    // MARK: - Public API

    /// Start recording (captures screenshots every 2 seconds)
    func start() {
        Log.recording.debug("start() called, isRecording=\(self.isRecording)")
        guard !isRecording else {
            Log.recording.debug("Already recording, ignoring start()")
            return
        }

        // Check Screen Recording permission
        let hasPermission = CGPreflightScreenCaptureAccess()
        Log.recording.info("Screen Recording permission check: \(hasPermission)")
        guard hasPermission else {
            Log.recording.error("Screen Recording permission not granted")
            return
        }

        Log.recording.info("Permission granted, starting recording")
        isRecording = true
        captureCount = 0

        // Start background stream to keep the purple recording indicator always visible
        Task {
            await startIndicatorStream()
        }

        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            Log.recording.debug("Timer fired")
            Task { @MainActor in
                await self?.captureScreenshot()
            }
        }
        Log.recording.debug("Timer created with interval \(self.captureInterval)s")

        // Fire immediately
        Log.recording.debug("Firing initial capture")
        Task {
            await captureScreenshot()
        }

        Log.recording.info("Recording service started, interval=\(self.captureInterval)s")
        Log.recording.debug("start() complete, isRecording=\(self.isRecording)")
    }

    /// Stop recording
    func stop() {
        Log.recording.debug("stop() called, isRecording=\(self.isRecording)")
        guard isRecording else {
            Log.recording.debug("Already stopped, ignoring")
            return
        }

        timer?.invalidate()
        timer = nil
        stopIndicatorStream()
        isRecording = false
        Log.recording.debug("Recording stopped")

        Log.recording.info("Recording service stopped, total_captures=\(self.captureCount)")
    }

    /// Reload configuration
    func reload() {
        let wasRecording = isRecording
        let oldInterval = captureInterval
        let oldExcludedCount = excludedApps.count
        if wasRecording {
            stop()
        }

        loadConfig()

        if captureInterval != oldInterval {
            Log.recording.info("Capture interval changed: \(oldInterval, privacy: .public)s -> \(self.captureInterval, privacy: .public)s")
        }
        if excludedApps.count != oldExcludedCount {
            Log.recording.info("Excluded apps changed: count \(oldExcludedCount, privacy: .public) -> \(self.excludedApps.count, privacy: .public), apps=\(self.excludedApps.joined(separator: ","), privacy: .public)")
        }

        if wasRecording && ConfigManager.shared.config.recordingEnabled {
            start()
        }
    }

    // MARK: - Screenshot Capture

    private func captureScreenshot() async {
        Log.recording.debug("captureScreenshot() called")

        // Check if timeline is open (pause recording)
        if fileManager.fileExists(atPath: Paths.timelineOpenSignalPath.path) {
            summarySkippedByTimeline += 1
            Log.recording.debug("Timeline open - pausing capture")
            return
        }

        // Get frontmost app
        guard let frontmostApp = getFrontmostApp() else {
            Log.recording.error("Could not determine frontmost app")
            return
        }

        Log.recording.debug("Frontmost app: \(frontmostApp)")

        // Capture display using ScreenCaptureKit (excluded apps are filtered out at capture level)
        guard let pngData = await captureScreen() else {
            Log.recording.error("Failed to capture screen")
            return
        }

        // Generate filename
        let timestamp = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let dateString = dateFormatter.string(from: timestamp)
        let uuid = UUID().uuidString.prefix(8).lowercased()
        let filename = "\(dateString)-\(uuid)-\(frontmostApp)"

        // Create date-based directory structure
        let yearMonthFormatter = DateFormatter()
        yearMonthFormatter.dateFormat = "yyyyMM"
        let yearMonth = yearMonthFormatter.string(from: timestamp)

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "dd"
        let day = dayFormatter.string(from: timestamp)

        let tempDir = Paths.baseDataDirectory
            .appendingPathComponent("temp")
            .appendingPathComponent(yearMonth)
            .appendingPathComponent(day)

        // Create directory if needed (0700 — user-accessible only)
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            do {
                try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tempDir.path)
            } catch {
                Log.recording.debug("Could not set permissions on temp dir: \(error.localizedDescription)")
            }
        } catch {
            Log.recording.error("Failed to create temp directory: \(error.localizedDescription)")
            return
        }

        // Write file
        let filePath = tempDir.appendingPathComponent(filename)
        do {
            try pngData.write(to: filePath)
            // 0600 — user-readable only (sensitive screen content)
            do {
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filePath.path)
            } catch {
                Log.recording.debug("Could not set permissions on screenshot: \(error.localizedDescription)")
            }

            let sizeBytes = UInt64(pngData.count)
            let sizeKB = Double(sizeBytes) / 1024.0
            captureCount += 1
            lastCaptureTime = timestamp
            cumulativeSessionBytes += sizeBytes
            summaryTotalFileBytes += sizeBytes
            summaryCapturesSinceLastLog += 1

            let cumulativeMB = String(format: "%.1f", Double(self.cumulativeSessionBytes) / 1024.0 / 1024.0)
            Log.recording.info("Screenshot captured: size=\(String(format: "%.1f", sizeKB), privacy: .public)KB, app=\(frontmostApp, privacy: .public), cumulative=\(cumulativeMB, privacy: .public)MB")

            // Capture cycle summary every 60 captures
            if summaryCapturesSinceLastLog >= 60 {
                let avgSizeKB = String(format: "%.1f", Double(summaryTotalFileBytes) / Double(summaryCapturesSinceLastLog) / 1024.0)
                let cumMB = String(format: "%.1f", Double(self.cumulativeSessionBytes) / 1024.0 / 1024.0)
                Log.recording.info("Capture summary: total=\(self.captureCount, privacy: .public), recent=\(self.summaryCapturesSinceLastLog, privacy: .public), skipped_timeline=\(self.summarySkippedByTimeline, privacy: .public), avg_size=\(avgSizeKB, privacy: .public)KB, cumulative=\(cumMB, privacy: .public)MB")
                summaryCapturesSinceLastLog = 0
                summarySkippedByTimeline = 0
                summaryTotalFileBytes = 0
            }

        } catch {
            Log.recording.error("Failed to write screenshot: \(error.localizedDescription)")
        }
    }

    // MARK: - Helper Methods

    private func getFrontmostApp() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return app.bundleIdentifier ?? "unknown"
    }

    private func captureScreen() async -> Data? {
        do {
            // Get available displays
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard !content.displays.isEmpty else {
                Log.recording.error("No displays found for screen capture")
                return nil
            }

            // Select the display containing the mouse cursor
            let mouseLocation = NSEvent.mouseLocation
            let display = content.displays.first { scDisplay in
                // NSEvent.mouseLocation uses bottom-left origin; SCDisplay frame uses top-left origin.
                // Compare using CGDirectDisplayID to match against NSScreen.
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
                    return scDisplay.displayID == screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                }
                return false
            } ?? content.displays.first!

            Log.recording.debug("Display enumeration: count=\(content.displays.count), selected=\(display.width)x\(display.height)")

            // Filter out windows belonging to excluded apps
            let excludedSCApps = content.applications.filter { app in
                excludedApps.contains(app.bundleIdentifier)
            }
            if !excludedSCApps.isEmpty {
                Log.recording.debug("Excluding \(excludedSCApps.count) app(s) from capture")
            }

            // Create screenshot with excluded apps filtered out
            let filter = SCContentFilter(display: display, excludingApplications: excludedSCApps, exceptingWindows: [])
            let config = SCStreamConfiguration()

            // Capture at native resolution
            config.width = display.width
            config.height = display.height
            config.pixelFormat = kCVPixelFormatType_32BGRA

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            // Convert CGImage to PNG
            let nsImage = NSImage(cgImage: image, size: NSZeroSize)
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                return nil
            }

            return pngData
        } catch {
            Log.recording.error("Screen capture error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Indicator Stream (keeps purple dot visible)

    /// Starts a minimal 1x1 SCStream solely to keep the macOS recording indicator always visible.
    /// Actual screenshots are still captured via SCScreenshotManager for correct multi-display
    /// and excluded app handling.
    private func startIndicatorStream() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                Log.recording.error("No display found for indicator stream")
                return
            }

            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let config = SCStreamConfiguration()
            // Absolute minimum resource usage — this stream exists only for the indicator
            config.width = 1
            config.height = 1
            config.minimumFrameInterval = CMTime(value: 10, timescale: 1) // 0.1 FPS
            config.queueDepth = 1
            config.pixelFormat = kCVPixelFormatType_32BGRA

            let delegate = IndicatorStreamDelegate()
            let stream = SCStream(filter: filter, configuration: config, delegate: delegate)
            try stream.addStreamOutput(delegate, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .background))
            try await stream.startCapture()

            self.indicatorStream = stream
            self.indicatorDelegate = delegate
            Log.recording.debug("Indicator stream started (recording indicator will stay visible)")
        } catch {
            Log.recording.error("Failed to start indicator stream: \(error.localizedDescription)")
        }
    }

    private func stopIndicatorStream() {
        guard let stream = indicatorStream else { return }
        indicatorStream = nil
        indicatorDelegate = nil
        Task {
            do {
                try await stream.stopCapture()
                Log.recording.debug("Indicator stream stopped")
            } catch {
                Log.recording.debug("Indicator stream stop error: \(error.localizedDescription)")
            }
        }
    }

    private func loadConfig() {
        let config = ConfigManager.shared.config
        captureInterval = 2.0 // Fixed at 2 seconds for now
        excludedApps = config.excludedApps
    }

    private func setupConfigObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ConfigDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Log.recording.info("Config change notification received, reloading")
            Task { @MainActor in
                self?.reload()
            }
        }
    }

    deinit {
        // Clean up - timer will be invalidated when released
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Indicator Stream Delegate

/// Minimal delegate that discards all frames — exists only to keep the SCStream alive
/// so the macOS recording indicator stays visible.
private final class IndicatorStreamDelegate: NSObject, SCStreamDelegate, SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Intentionally discard — this stream only exists for the recording indicator
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.recording.info("Indicator stream stopped externally (user clicked Stop Presenting), quitting app")
        Task { @MainActor in
            NSApplication.shared.terminate(nil)
        }
    }
}
