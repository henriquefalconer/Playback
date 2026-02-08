// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation

enum ShellCommand {
    struct Result {
        let output: String
        let exitCode: Int32

        var isSuccess: Bool {
            exitCode == 0
        }
    }

    enum ShellCommandError: Error, LocalizedError {
        case executionFailed(String)
        case invalidExecutable(String)

        var errorDescription: String? {
            switch self {
            case .executionFailed(let message):
                return "Shell command execution failed: \(message)"
            case .invalidExecutable(let path):
                return "Invalid executable path: \(path)"
            }
        }
    }

    static func run(_ executablePath: String, arguments: [String] = []) throws -> Result {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        guard FileManager.default.fileExists(atPath: executablePath) else {
            throw ShellCommandError.invalidExecutable(executablePath)
        }

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        let combinedOutput = output.isEmpty ? error : output

        return Result(output: combinedOutput, exitCode: process.terminationStatus)
    }

    static func runAsync(_ executablePath: String, arguments: [String] = []) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try run(executablePath, arguments: arguments)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
