import Foundation
import os

/// Manages bulk data operations like deleting all recordings.
@MainActor
final class DataManager {
    static let shared = DataManager()

    /// Notification posted after all recordings have been deleted and services restarted.
    static let recordingsDidResetNotification = Notification.Name("RecordingsDidReset")

    private init() {}

    /// Delete all recording data (temp screenshots, video chunks, database) while preserving config.
    /// Stops services before deletion and restarts them after.
    func deleteAllRecordings() throws {
        let start = CFAbsoluteTimeGetCurrent()
        Log.system.info("Delete all recordings: starting")

        // Stop services
        RecordingService.shared.stop()
        ProcessingService.shared.stop()
        Log.system.info("Delete all recordings: services stopped")

        let fm = FileManager.default

        // Delete temp directory
        deleteItem(at: Paths.tempDirectory, label: "temp", using: fm)

        // Delete chunks directory
        deleteItem(at: Paths.chunksDirectory, label: "chunks", using: fm)

        // Delete database files (SQLite WAL/SHM use hyphen: meta.sqlite3-wal, meta.sqlite3-shm)
        deleteItem(at: Paths.databasePath, label: "database", using: fm)
        let dbDir = Paths.databasePath.deletingLastPathComponent()
        let walURL = dbDir.appendingPathComponent("meta.sqlite3-wal")
        let shmURL = dbDir.appendingPathComponent("meta.sqlite3-shm")
        deleteItem(at: walURL, label: "database WAL", using: fm)
        deleteItem(at: shmURL, label: "database SHM", using: fm)

        // Delete timeline signal file
        deleteItem(at: Paths.timelineOpenSignalPath, label: "timeline signal", using: fm)

        // Recreate directories
        do {
            try Paths.ensureDirectoriesExist()
            Log.system.info("Delete all recordings: directories recreated")
        } catch {
            Log.system.error("Delete all recordings: failed to recreate directories: \(error.localizedDescription)")
            throw error
        }

        // Restart services
        ProcessingService.shared.start()
        if ConfigManager.shared.config.recordingEnabled {
            RecordingService.shared.start()
        }
        Log.system.info("Delete all recordings: services restarted")

        // Notify observers
        NotificationCenter.default.post(name: DataManager.recordingsDidResetNotification, object: nil)

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        Log.system.info("Delete all recordings: completed in \(String(format: "%.2f", elapsed))s")
    }

    private func deleteItem(at url: URL, label: String, using fm: FileManager) {
        guard fm.fileExists(atPath: url.path) else {
            Log.system.debug("Delete all recordings: \(label) not found at \(url.path), skipping")
            return
        }
        do {
            try fm.removeItem(at: url)
            Log.system.info("Delete all recordings: deleted \(label) at \(url.path)")
        } catch {
            Log.system.error("Delete all recordings: failed to delete \(label) at \(url.path): \(error.localizedDescription)")
        }
    }
}
