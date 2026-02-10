// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import Combine

@MainActor
final class ConfigManager: ObservableObject {
    @Published private(set) var config: Config

    private let configPath: URL
    private var watcher: ConfigWatcher?
    private var lastModificationDate: Date?

    static let shared = ConfigManager()

    private init() {
        self.configPath = Paths.configPath()
        self.config = Config.defaultConfig
        loadConfiguration()
        startWatching()
    }

    internal init(configPath: URL, enableWatcher: Bool = false) {
        self.configPath = configPath
        self.config = Config.defaultConfig
        loadConfiguration()
        if enableWatcher {
            startWatching()
        }
    }

    deinit {
        watcher = nil
    }

    func loadConfiguration() {
        do {
            let data = try Data(contentsOf: configPath)
            var loadedConfig = try JSONDecoder().decode(Config.self, from: data)

            loadedConfig = loadedConfig.validated()

            if loadedConfig.version != config.version {
                loadedConfig = migrateConfig(loadedConfig)
            }

            self.config = loadedConfig
            self.lastModificationDate = try? FileManager.default.attributesOfItem(atPath: configPath.path)[.modificationDate] as? Date
        } catch {
            if Paths.isDevelopment {
                print("Failed to load config from \(configPath.path): \(error)")
                print("Using default configuration")
            }

            if !FileManager.default.fileExists(atPath: configPath.path) {
                saveConfiguration()
            }
        }
    }

    func saveConfiguration() {
        do {
            createBackup()

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)

            let tempPath = configPath.appendingPathExtension("tmp")
            try data.write(to: tempPath, options: .atomic)

            if FileManager.default.fileExists(atPath: configPath.path) {
                try FileManager.default.removeItem(at: configPath)
            }
            try FileManager.default.moveItem(at: tempPath, to: configPath)

            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: configPath.path)

            if let fileHandle = try? FileHandle(forUpdating: configPath) {
                try? fileHandle.synchronize()
                try? fileHandle.close()
            }

            self.lastModificationDate = try? FileManager.default.attributesOfItem(atPath: configPath.path)[.modificationDate] as? Date
        } catch {
            if Paths.isDevelopment {
                print("Failed to save config to \(configPath.path): \(error)")
            }
        }
    }

    func updateConfig(_ newConfig: Config) {
        self.config = newConfig.validated()
        saveConfiguration()

        // Notify observers (e.g., RecordingService) of config change
        NotificationCenter.default.post(name: NSNotification.Name("ConfigDidChange"), object: nil)
    }

    private func createBackup() {
        guard FileManager.default.fileExists(atPath: configPath.path) else { return }

        let backupDir = configPath.deletingLastPathComponent().appendingPathComponent("backups")
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let timestamp = dateFormatter.string(from: Date())
        let backupPath = backupDir.appendingPathComponent("config_\(timestamp).json")

        try? FileManager.default.copyItem(at: configPath, to: backupPath)

        cleanupOldBackups(in: backupDir)
    }

    private func cleanupOldBackups(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return }

        let backupFiles = files
            .filter { $0.lastPathComponent.hasPrefix("config_") && $0.pathExtension == "json" }
            .sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }

        if backupFiles.count > 5 {
            for file in backupFiles.dropFirst(5) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func migrateConfig(_ oldConfig: Config) -> Config {
        var migrated = oldConfig
        let startVersion = oldConfig.version

        // Migration chain: apply all migrations from old version to current
        // Each migration transforms config to the next version
        let migrations: [(from: String, to: String, migrate: (inout Config) -> Void)] = [
            // Example future migration from 1.0.0 to 1.1.0
            // ("1.0.0", "1.1.0", migrate_1_0_to_1_1),

            // Example future migration from 1.1.0 to 1.2.0
            // ("1.1.0", "1.2.0", migrate_1_1_to_1_2),
        ]

        // Apply migrations sequentially
        for migration in migrations {
            if migrated.version == migration.from {
                if Paths.isDevelopment {
                    print("[Config] Migrating from \(migration.from) to \(migration.to)")
                }
                migration.migrate(&migrated)
                migrated.version = migration.to
            }
        }

        // Log if migration occurred
        if migrated.version != startVersion {
            if Paths.isDevelopment {
                print("[Config] Migration complete: \(startVersion) → \(migrated.version)")
            }
        } else if startVersion != Config.defaultConfig.version {
            // Version mismatch but no migration available
            if Paths.isDevelopment {
                print("[Config] Warning: Config version \(startVersion) differs from default \(Config.defaultConfig.version), but no migration path exists. Using config as-is.")
            }
        }

        return migrated
    }

    // Example migration function template (for future use)
    // private func migrate_1_0_to_1_1(_ config: inout Config) {
    //     // Add new fields with defaults
    //     // config.newField = defaultValue
    //
    //     // Transform existing fields if needed
    //     // if config.oldField == "deprecated_value" {
    //     //     config.oldField = "new_value"
    //     // }
    //
    //     // Remove obsolete fields (if using custom Codable)
    //     // Note: Swift's Codable ignores unknown fields automatically
    // }

    private func startWatching() {
        watcher = ConfigWatcher(configPath: configPath.path) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }

                let currentModDate = try? FileManager.default.attributesOfItem(atPath: self.configPath.path)[.modificationDate] as? Date

                if currentModDate != self.lastModificationDate {
                    self.loadConfiguration()
                }
            }
        }
        watcher?.startWatching()
    }
}

private class ConfigWatcher {
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private let configPath: String
    private let onChange: () -> Void

    init(configPath: String, onChange: @escaping () -> Void) {
        self.configPath = configPath
        self.onChange = onChange
    }

    func startWatching() {
        fileDescriptor = open(configPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            if Paths.isDevelopment {
                print("Failed to open config file for watching: \(configPath)")
            }
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.main
        )

        source?.setEventHandler { [weak self] in
            self?.onChange()
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        source?.resume()
    }

    deinit {
        source?.cancel()
    }
}
