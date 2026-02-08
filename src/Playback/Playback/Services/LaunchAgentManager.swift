// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation

enum LaunchAgentError: Error {
    case templateNotFound(String)
    case invalidPlist(String)
    case launchctlFailed(String, Int32)
    case installationFailed(String)
}

enum AgentType: String, CaseIterable {
    case recording
    case processing
    case cleanup

    var label: String {
        let isDev = Paths.isDevelopment
        let prefix = isDev ? "com.playback.dev" : "com.playback"
        return "\(prefix).\(rawValue)"
    }

    var templateName: String {
        "\(rawValue).plist.template"
    }

    var plistName: String {
        "\(label).plist"
    }
}

struct LaunchAgentStatus {
    let isLoaded: Bool
    let isRunning: Bool
    let pid: Int?
    let lastExitStatus: Int?
}

@MainActor
final class LaunchAgentManager {
    static let shared = LaunchAgentManager()

    private let fileManager = FileManager.default
    private let launchAgentsDir: URL

    private init() {
        self.launchAgentsDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
    }

    func installAgent(_ type: AgentType) throws {
        let templatePath = Bundle.main.resourceURL?
            .appendingPathComponent("launchagents")
            .appendingPathComponent(type.templateName)

        guard let templatePath = templatePath,
              fileManager.fileExists(atPath: templatePath.path) else {
            throw LaunchAgentError.templateNotFound(type.templateName)
        }

        var content = try String(contentsOf: templatePath, encoding: .utf8)

        let variables = buildVariables(for: type)
        for (key, value) in variables {
            content = content.replacingOccurrences(of: "{{\(key)}}", with: value)
        }

        try fileManager.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let plistPath = launchAgentsDir.appendingPathComponent(type.plistName)
        try content.write(to: plistPath, atomically: true, encoding: .utf8)

        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistPath.path)

        try validatePlist(at: plistPath)

        if Paths.isDevelopment {
            print("[LaunchAgent] Installed \(type.label) at \(plistPath.path)")
        }
    }

    func loadAgent(_ type: AgentType) throws {
        let plistPath = launchAgentsDir.appendingPathComponent(type.plistName)
        guard fileManager.fileExists(atPath: plistPath.path) else {
            try installAgent(type)
            return
        }

        let (output, exitCode) = try runLaunchctl(["load", plistPath.path])

        if exitCode != 0 {
            throw LaunchAgentError.launchctlFailed("load", exitCode)
        }

        if Paths.isDevelopment {
            print("[LaunchAgent] Loaded \(type.label)")
        }
    }

    func unloadAgent(_ type: AgentType) throws {
        let plistPath = launchAgentsDir.appendingPathComponent(type.plistName)

        let (output, exitCode) = try runLaunchctl(["unload", plistPath.path])

        if exitCode != 0 && exitCode != 3 {
            throw LaunchAgentError.launchctlFailed("unload", exitCode)
        }

        if Paths.isDevelopment {
            print("[LaunchAgent] Unloaded \(type.label)")
        }
    }

    func startAgent(_ type: AgentType) throws {
        try ensureAgentLoaded(type)

        let (output, exitCode) = try runLaunchctl(["start", type.label])

        if exitCode != 0 {
            throw LaunchAgentError.launchctlFailed("start", exitCode)
        }

        if Paths.isDevelopment {
            print("[LaunchAgent] Started \(type.label)")
        }
    }

    func stopAgent(_ type: AgentType) throws {
        let (output, exitCode) = try runLaunchctl(["stop", type.label])

        if exitCode != 0 && exitCode != 3 {
            throw LaunchAgentError.launchctlFailed("stop", exitCode)
        }

        if Paths.isDevelopment {
            print("[LaunchAgent] Stopped \(type.label)")
        }
    }

    func restartAgent(_ type: AgentType) throws {
        try stopAgent(type)
        try startAgent(type)
    }

    func reloadAgent(_ type: AgentType) throws {
        try unloadAgent(type)
        try installAgent(type)
        try loadAgent(type)
    }

    func getAgentStatus(_ type: AgentType) -> LaunchAgentStatus {
        guard let (output, exitCode) = try? runLaunchctl(["list", type.label]),
              exitCode == 0 else {
            return LaunchAgentStatus(isLoaded: false, isRunning: false, pid: nil, lastExitStatus: nil)
        }

        let lines = output.split(separator: "\n")
        guard lines.count >= 2 else {
            return LaunchAgentStatus(isLoaded: true, isRunning: false, pid: nil, lastExitStatus: nil)
        }

        let parts = lines[1].split(separator: "\t").map(String.init)
        guard parts.count >= 3 else {
            return LaunchAgentStatus(isLoaded: true, isRunning: false, pid: nil, lastExitStatus: nil)
        }

        let pid = parts[0] == "-" ? nil : Int(parts[0])
        let lastExitStatus = parts[1] == "-" ? nil : Int(parts[1])
        let isRunning = pid != nil

        return LaunchAgentStatus(isLoaded: true, isRunning: isRunning, pid: pid, lastExitStatus: lastExitStatus)
    }

    func removeAgent(_ type: AgentType) throws {
        try? unloadAgent(type)

        let plistPath = launchAgentsDir.appendingPathComponent(type.plistName)
        if fileManager.fileExists(atPath: plistPath.path) {
            try fileManager.removeItem(at: plistPath)
            if Paths.isDevelopment {
                print("[LaunchAgent] Removed \(type.label)")
            }
        }
    }

    func updateProcessingInterval(minutes: Int) throws {
        try reloadAgent(.processing)
    }

    private func buildVariables(for type: AgentType) -> [String: String] {
        let isDev = Paths.isDevelopment

        let scriptPath: String
        let workingDir: String
        let logPath: String
        let configPath: String
        let dataDir: String

        if isDev {
            let projectRoot = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            scriptPath = projectRoot.appendingPathComponent("src/scripts").path
            workingDir = projectRoot.path
            logPath = projectRoot.appendingPathComponent("dev_logs").path
            configPath = projectRoot.appendingPathComponent("dev_config.json").path
            dataDir = projectRoot.appendingPathComponent("dev_data").path
        } else {
            let appPath = "/Applications/Playback.app"
            scriptPath = "\(appPath)/Contents/Resources/scripts"
            workingDir = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Playback").path
            logPath = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/Playback").path
            configPath = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Playback/config.json").path
            dataDir = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Playback/data").path
        }

        var variables = [
            "LABEL": type.label,
            "SCRIPT_PATH": scriptPath,
            "WORKING_DIR": workingDir,
            "LOG_PATH": logPath,
            "CONFIG_PATH": configPath,
            "DATA_DIR": dataDir,
            "DEV_MODE": isDev ? "1" : "0"
        ]

        if type == .processing {
            let intervalMinutes = ConfigManager.shared.config.processingIntervalMinutes
            variables["INTERVAL_SECONDS"] = String(intervalMinutes * 60)
        }

        return variables
    }

    private func validatePlist(at path: URL) throws {
        let (output, exitCode) = try runCommand("/usr/bin/plutil", ["-lint", path.path])

        if exitCode != 0 {
            throw LaunchAgentError.invalidPlist(output)
        }
    }

    private func ensureAgentLoaded(_ type: AgentType) throws {
        let status = getAgentStatus(type)
        if !status.isLoaded {
            try loadAgent(type)
        }
    }

    private func runLaunchctl(_ args: [String]) throws -> (String, Int32) {
        try runCommand("/bin/launchctl", args)
    }

    private func runCommand(_ path: String, _ args: [String]) throws -> (String, Int32) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        let combinedOutput = output.isEmpty ? error : output

        return (combinedOutput, process.terminationStatus)
    }
}
