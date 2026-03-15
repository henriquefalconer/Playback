// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import AppKit
import CoreGraphics
import ApplicationServices
import Combine
import ScreenCaptureKit
import os

/// Recording service that captures screenshots at regular intervals
/// Runs in-process, uses app's Screen Recording permission
@MainActor
final class RecordingService: ObservableObject {
    static let shared = RecordingService()

    @Published private(set) var isRecording = false
    @Published private(set) var lastCaptureTime: Date?
    @Published private(set) var captureCount: UInt64 = 0

    private var timer: Timer?
    private let fileManager = FileManager.default

    // Config
    private var captureInterval: TimeInterval = 2.0 // seconds
    private var excludedApps: [String] = []

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
        isRecording = false
        Log.recording.debug("Recording stopped")

        Log.recording.info("Recording service stopped, total_captures=\(self.captureCount)")
    }

    /// Reload configuration
    func reload() {
        let wasRecording = isRecording
        if wasRecording {
            stop()
        }

        loadConfig()

        if wasRecording && ConfigManager.shared.config.recordingEnabled {
            start()
        }
    }

    // MARK: - Screenshot Capture

    private func captureScreenshot() async {
        Log.recording.debug("captureScreenshot() called")

        // Check if timeline is open (pause recording)
        if fileManager.fileExists(atPath: Paths.timelineOpenSignalPath.path) {
            Log.recording.debug("Timeline open - pausing capture")
            return
        }

        // Get frontmost app
        guard let frontmostApp = getFrontmostApp() else {
            Log.recording.error("Could not determine frontmost app")
            return
        }

        Log.recording.debug("Frontmost app: \(frontmostApp)")

        // Check if app is excluded
        if excludedApps.contains(frontmostApp) {
            Log.recording.notice("Skipping excluded app: \(frontmostApp)")
            return
        }

        // Capture display using ScreenCaptureKit (modern API)
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
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tempDir.path)
        } catch {
            Log.recording.error("Failed to create temp directory: \(error.localizedDescription)")
            return
        }

        // Write file
        let filePath = tempDir.appendingPathComponent(filename)
        do {
            try pngData.write(to: filePath)
            // 0600 — user-readable only (sensitive screen content)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: filePath.path)

            let sizeKB = Double(pngData.count) / 1024.0
            captureCount += 1
            lastCaptureTime = timestamp

            Log.recording.debug("Screenshot captured: \(filePath.path), size=\(String(format: "%.1f", sizeKB))KB, app=\(frontmostApp)")

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

            guard let display = content.displays.first else {
                return nil
            }

            // Create screenshot
            let filter = SCContentFilter(display: display, excludingWindows: [])
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
