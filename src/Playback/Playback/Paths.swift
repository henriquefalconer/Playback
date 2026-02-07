import Foundation

enum Paths {
    /// Checks if the app is running in development mode
    static var isDevelopment: Bool {
        ProcessInfo.processInfo.environment["PLAYBACK_DEV_MODE"] == "1"
    }

    /// Base data directory (dev or production)
    static var baseDataDirectory: URL {
        if isDevelopment {
            // Development: use dev_data/ relative to project root
            // Assumes project root is 3 levels up from Playback.app location
            let projectRoot = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            return projectRoot.appendingPathComponent("dev_data")
        } else {
            // Production: use ~/Library/Application Support/Playback/data/
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            return appSupport
                .appendingPathComponent("Playback")
                .appendingPathComponent("data")
        }
    }

    /// Database file path
    static var databasePath: URL {
        baseDataDirectory.appendingPathComponent("meta.sqlite3")
    }

    /// Timeline open signal file path
    static var timelineOpenSignalPath: URL {
        baseDataDirectory.appendingPathComponent(".timeline_open")
    }

    /// Chunks directory path
    static var chunksDirectory: URL {
        baseDataDirectory.appendingPathComponent("chunks")
    }

    /// Ensure all required directories exist
    static func ensureDirectoriesExist() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: baseDataDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: chunksDirectory,
            withIntermediateDirectories: true
        )
    }
}

final class SignalFileManager {
    private let signalPath: URL
    private let fileManager = FileManager.default

    init(signalPath: URL = Paths.timelineOpenSignalPath) {
        self.signalPath = signalPath
    }

    /// Create the signal file to indicate timeline viewer is open
    func createSignalFile() throws {
        // Ensure parent directory exists
        let parentDir = signalPath.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parentDir,
            withIntermediateDirectories: true
        )

        // Create empty signal file with timestamp
        let timestamp = Date().timeIntervalSince1970
        let content = "Timeline viewer opened at \(timestamp)\n"
        try content.write(to: signalPath, atomically: true, encoding: .utf8)

        print("[Playback] Signal file created: \(signalPath.path)")
    }

    /// Remove the signal file to indicate timeline viewer is closed
    func removeSignalFile() {
        guard fileManager.fileExists(atPath: signalPath.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: signalPath)
            print("[Playback] Signal file removed: \(signalPath.path)")
        } catch {
            print("[Playback] Warning: Failed to remove signal file: \(error)")
        }
    }

    /// Check if signal file exists
    var exists: Bool {
        fileManager.fileExists(atPath: signalPath.path)
    }

    deinit {
        // Ensure signal file is removed when manager is deallocated
        removeSignalFile()
    }
}
