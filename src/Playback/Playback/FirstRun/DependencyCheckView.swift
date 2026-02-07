// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI

struct DependencyCheckView: View {
    @ObservedObject var coordinator: FirstRunCoordinator

    var body: some View {
        VStack(spacing: 24) {
            Text("Dependencies")
                .font(.title)
                .fontWeight(.bold)

            Text("Playback requires Python and FFmpeg to process recordings.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 20) {
                DependencyCard(
                    icon: "terminal.fill",
                    title: "Python 3.12+",
                    description: "Required for recording and processing scripts",
                    state: coordinator.pythonValidation,
                    onCheck: { checkPython() },
                    installInstructions: "brew install python@3.12"
                )

                DependencyCard(
                    icon: "film.fill",
                    title: "FFmpeg 7.0+ with libx264",
                    description: "Required for video encoding",
                    state: coordinator.ffmpegValidation,
                    onCheck: { checkFFmpeg() },
                    installInstructions: "brew install ffmpeg"
                )
            }
            .padding(.top, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            checkPython()
            checkFFmpeg()
        }
    }

    private func checkPython() {
        coordinator.pythonValidation = .checking

        runCommand("/usr/bin/which", ["python3"]) { result in
            guard case .success(let output) = result, !output.isEmpty else {
                DispatchQueue.main.async {
                    coordinator.pythonValidation = .invalid("Python 3 not found")
                }
                return
            }

            runCommand("/usr/bin/python3", ["--version"]) { versionResult in
                DispatchQueue.main.async {
                    guard case .success(let version) = versionResult else {
                        coordinator.pythonValidation = .invalid("Could not check Python version")
                        return
                    }

                    let versionStr = version.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let versionNumber = extractVersion(from: versionStr),
                       versionNumber >= (3, 12, 0) {
                        coordinator.pythonValidation = .valid
                    } else {
                        coordinator.pythonValidation = .invalid("Python 3.12+ required (found: \(versionStr))")
                    }
                }
            }
        }
    }

    private func checkFFmpeg() {
        coordinator.ffmpegValidation = .checking

        let possiblePaths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]

        var foundPath: String?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                foundPath = path
                break
            }
        }

        guard let ffmpegPath = foundPath else {
            runCommand("/usr/bin/which", ["ffmpeg"]) { result in
                if case .success(let output) = result, !output.isEmpty {
                    verifyFFmpegVersion(output.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    DispatchQueue.main.async {
                        coordinator.ffmpegValidation = .invalid("FFmpeg not found in common locations")
                    }
                }
            }
            return
        }

        verifyFFmpegVersion(ffmpegPath)
    }

    private func verifyFFmpegVersion(_ ffmpegPath: String) {
        runCommand(ffmpegPath, ["-version"]) { result in
            DispatchQueue.main.async {
                guard case .success(let output) = result else {
                    coordinator.ffmpegValidation = .invalid("Could not check FFmpeg version")
                    return
                }

                let lines = output.split(separator: "\n")
                guard let firstLine = lines.first else {
                    coordinator.ffmpegValidation = .invalid("Could not parse FFmpeg version")
                    return
                }

                let components = firstLine.split(separator: " ")
                var versionStr = ""
                for component in components {
                    if let version = extractVersion(from: String(component)) {
                        versionStr = String(component)
                        if version >= (7, 0, 0) {
                            break
                        }
                    }
                }

                guard let version = extractVersion(from: versionStr), version >= (7, 0, 0) else {
                    coordinator.ffmpegValidation = .invalid("FFmpeg 7.0+ required (found: \(versionStr.isEmpty ? "unknown version" : versionStr))")
                    return
                }

                runCommand(ffmpegPath, ["-codecs"]) { codecResult in
                    DispatchQueue.main.async {
                        guard case .success(let codecOutput) = codecResult else {
                            coordinator.ffmpegValidation = .invalid("Could not check FFmpeg codecs")
                            return
                        }

                        if codecOutput.contains("libx264") {
                            coordinator.ffmpegValidation = .valid
                        } else {
                            coordinator.ffmpegValidation = .invalid("FFmpeg missing libx264 support")
                        }
                    }
                }
            }
        }
    }

    private func runCommand(_ path: String, _ args: [String], completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let outputPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    completion(.success(output))
                } else {
                    completion(.failure(NSError(domain: "Command failed", code: Int(process.terminationStatus))))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func extractVersion(from versionString: String) -> (Int, Int, Int)? {
        let pattern = #"(\d+)\.(\d+)\.(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: versionString, range: NSRange(versionString.startIndex..., in: versionString)),
              match.numberOfRanges >= 4 else {
            return nil
        }

        let major = Int((versionString as NSString).substring(with: match.range(at: 1))) ?? 0
        let minor = Int((versionString as NSString).substring(with: match.range(at: 2))) ?? 0
        let patch = Int((versionString as NSString).substring(with: match.range(at: 3))) ?? 0

        return (major, minor, patch)
    }
}

struct DependencyCard: View {
    let icon: String
    let title: String
    let description: String
    let state: FirstRunValidationState
    let onCheck: () -> Void
    let installInstructions: String

    @State private var showInstructions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                statusIcon
            }

            if case .invalid(let message) = state {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    Button(showInstructions ? "Hide Instructions" : "Show Installation Instructions") {
                        showInstructions.toggle()
                    }
                    .font(.caption)
                }

                if showInstructions {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To install using Homebrew:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Text(installInstructions)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(4)

                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(installInstructions, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Link("Open Homebrew website", destination: URL(string: "https://brew.sh")!)
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }
            }

            HStack(spacing: 8) {
                Button("Check Again") {
                    onCheck()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .notStarted:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .valid:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .invalid:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
}
