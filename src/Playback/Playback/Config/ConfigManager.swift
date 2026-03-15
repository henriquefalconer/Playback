// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import Combine

@MainActor
final class ConfigManager: ObservableObject {
    @Published private(set) var config: Config

    private let configPath: URL

    static let shared = ConfigManager()

    private init() {
        self.configPath = Paths.configPath()
        self.config = Config.defaultConfig
        loadConfiguration()
    }

    internal init(configPath: URL) {
        self.configPath = configPath
        self.config = Config.defaultConfig
        loadConfiguration()
    }

    func loadConfiguration() {
        do {
            let data = try Data(contentsOf: configPath)
            let loadedConfig = try JSONDecoder().decode(Config.self, from: data)
            self.config = loadedConfig.validated()
        } catch {
            #if DEBUG
            print("Failed to load config from \(configPath.path): \(error)")
            print("Using default configuration")
            #endif

            if !FileManager.default.fileExists(atPath: configPath.path) {
                saveConfiguration()
            }
        }
    }

    func saveConfiguration() {
        do {
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
        } catch {
            #if DEBUG
            print("Failed to save config to \(configPath.path): \(error)")
            #endif
        }
    }

    func updateConfig(_ newConfig: Config) {
        self.config = newConfig.validated()
        saveConfiguration()

        // Notify observers (e.g., RecordingService) of config change
        NotificationCenter.default.post(name: NSNotification.Name("ConfigDidChange"), object: nil)
    }
}
