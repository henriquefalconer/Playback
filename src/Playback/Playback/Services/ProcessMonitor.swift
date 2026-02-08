// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import Combine

@MainActor
final class ProcessMonitor: ObservableObject {
    @Published private(set) var isProcessing: Bool = false

    private var timer: Timer?
    private let processName = "build_chunks_from_temp.py"
    private let pollingInterval: TimeInterval = 0.5

    static let shared = ProcessMonitor()

    private init() {
        checkProcessStatus()
    }

    func startMonitoring() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.checkProcessStatusAsync()
            }
        }

        if Paths.isDevelopment {
            print("[ProcessMonitor] Started monitoring for \(processName)")
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil

        if Paths.isDevelopment {
            print("[ProcessMonitor] Stopped monitoring")
        }
    }

    nonisolated private func checkProcessStatusAsync() async {
        let isRunning = isProcessRunning()
        await MainActor.run {
            let wasProcessing = self.isProcessing
            self.isProcessing = isRunning

            if wasProcessing != self.isProcessing {
                if Paths.isDevelopment {
                    print("[ProcessMonitor] Processing status changed: \(self.isProcessing)")
                }
            }
        }
    }

    private func checkProcessStatus() {
        let wasProcessing = isProcessing
        isProcessing = isProcessRunning()

        if wasProcessing != isProcessing {
            if Paths.isDevelopment {
                print("[ProcessMonitor] Processing status changed: \(isProcessing)")
            }
        }
    }

    nonisolated private func isProcessRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", processName]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            return process.terminationStatus == 0 && !output.isEmpty
        } catch {
            return false
        }
    }
}
