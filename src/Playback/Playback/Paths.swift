import Foundation

enum Paths {
    /// Checks if the app is running in development mode
    static var isDevelopment: Bool {
        ProcessInfo.processInfo.environment["PLAYBACK_DEV_MODE"] == "1"
    }

    /// Base data directory (dev or production)
    static var baseDataDirectory: URL {
        // Check for PLAYBACK_DATA_DIR environment variable override
        if let dataDir = ProcessInfo.processInfo.environment["PLAYBACK_DATA_DIR"] {
            return URL(fileURLWithPath: dataDir)
        }

        if isDevelopment {
            // Development: use SRCROOT environment variable
            guard let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] else {
                fatalError("SRCROOT environment variable not set - required in development mode")
            }
            let expandedPath = NSString(string: srcRoot).expandingTildeInPath
            let projectRoot = URL(fileURLWithPath: expandedPath)
            return projectRoot.appendingPathComponent("dev_data")
        } else {
            // Production: use ~/Library/Application Support/Playback/data/
            guard let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                fatalError("Application Support directory not available")
            }
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

    /// Config file path
    static func configPath() -> URL {
        // Check for PLAYBACK_CONFIG environment variable override
        if let configPath = ProcessInfo.processInfo.environment["PLAYBACK_CONFIG"] {
            return URL(fileURLWithPath: configPath)
        }

        if isDevelopment {
            // Development: use SRCROOT environment variable
            guard let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] else {
                fatalError("SRCROOT environment variable not set - required in development mode")
            }
            let expandedPath = NSString(string: srcRoot).expandingTildeInPath
            let projectRoot = URL(fileURLWithPath: expandedPath)
            return projectRoot.appendingPathComponent("dev_config.json")
        } else {
            guard let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                fatalError("Application Support directory not available")
            }
            return appSupport
                .appendingPathComponent("Playback")
                .appendingPathComponent("config.json")
        }
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

        if Paths.isDevelopment {
            print("[Playback] Signal file created: \(signalPath.path)")
        }
    }

    /// Remove the signal file to indicate timeline viewer is closed
    func removeSignalFile() {
        guard fileManager.fileExists(atPath: signalPath.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: signalPath)
            if Paths.isDevelopment {
                print("[Playback] Signal file removed: \(signalPath.path)")
            }
        } catch {
            if Paths.isDevelopment {
                print("[Playback] Warning: Failed to remove signal file: \(error)")
            }
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
