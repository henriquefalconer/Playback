// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import AppKit
import CoreGraphics
import ApplicationServices
import Combine
import ScreenCaptureKit

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
    private var lastLoggedError: String?

    // Config
    private var captureInterval: TimeInterval = 2.0 // seconds
    private var excludedApps: [String] = []

    private init() {
        print("[RecordingService] Initializing singleton")
        loadConfig()
        setupConfigObserver()
        print("[RecordingService] Initialization complete")
    }

    // MARK: - Public API

    /// Start recording (captures screenshots every 2 seconds)
    func start() {
        print("[RecordingService] start() called, isRecording=\(isRecording)")
        guard !isRecording else {
            print("[RecordingService] Already recording, ignoring start()")
            return
        }

        // Check Screen Recording permission
        let hasPermission = CGPreflightScreenCaptureAccess()
        print("[RecordingService] Screen Recording permission check: \(hasPermission)")
        guard hasPermission else {
            logError("Screen Recording permission not granted")
            return
        }

        print("[RecordingService] Permission granted, starting recording")
        isRecording = true
        captureCount = 0

        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.captureScreenshot()
            }
        }

        // Fire immediately
        Task {
            await captureScreenshot()
        }

        log("Recording service started", metadata: ["interval_seconds": captureInterval])
    }

    /// Stop recording
    func stop() {
        guard isRecording else { return }

        timer?.invalidate()
        timer = nil
        isRecording = false

        log("Recording service stopped", metadata: ["total_captures": captureCount])
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
        // Check if timeline is open (pause recording)
        if fileManager.fileExists(atPath: Paths.timelineOpenSignalPath.path) {
            if Paths.isDevelopment {
                print("[RecordingService] Timeline open - pausing capture")
            }
            return
        }

        // Get frontmost app
        guard let frontmostApp = getFrontmostApp() else {
            logError("Could not determine frontmost app")
            return
        }

        // Check if app is excluded
        if excludedApps.contains(frontmostApp) {
            if Paths.isDevelopment {
                print("[RecordingService] Skipping excluded app: \(frontmostApp)")
            }
            return
        }

        // Capture display using ScreenCaptureKit (modern API)
        guard let pngData = await captureScreen() else {
            logError("Failed to capture screen")
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

        // Create directory if needed
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            logError("Failed to create temp directory: \(error.localizedDescription)")
            return
        }

        // Write file
        let filePath = tempDir.appendingPathComponent(filename)
        do {
            try pngData.write(to: filePath)

            let sizeKB = Double(pngData.count) / 1024.0
            captureCount += 1
            lastCaptureTime = timestamp

            log("Screenshot captured", metadata: [
                "path": filePath.path,
                "size_kb": String(format: "%.1f", sizeKB),
                "app_id": frontmostApp
            ])

        } catch {
            logError("Failed to write screenshot: \(error.localizedDescription)")
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
            if Paths.isDevelopment {
                print("[RecordingService] Screen capture error: \(error)")
            }
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

    // MARK: - Logging

    private func log(_ message: String, metadata: [String: Any] = [:]) {
        if Paths.isDevelopment {
            var logDict: [String: Any] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "level": "INFO",
                "component": "recording",
                "message": message
            ]
            if !metadata.isEmpty {
                logDict["metadata"] = metadata
            }

            if let jsonData = try? JSONSerialization.data(withJSONObject: logDict, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            }
        }
    }

    private func logError(_ message: String) {
        // Avoid duplicate error logs
        if lastLoggedError == message {
            return
        }
        lastLoggedError = message

        let logDict: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "level": "ERROR",
            "component": "recording",
            "message": message
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: logDict, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
    }

    deinit {
        // Clean up - timer will be invalidated when released
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
