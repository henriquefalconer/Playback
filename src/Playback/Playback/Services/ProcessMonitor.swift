// Copyright (c) 2026 Henrique Falconer. All rights reserved.
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
    }

    func startMonitoring() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.checkProcessStatusAsync()
            }
        }

        // Check initial status asynchronously
        Task { @MainActor in
            await checkProcessStatusAsync()
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
        do {
            let result = try ShellCommand.run("/usr/bin/pgrep", arguments: ["-f", processName])
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isSuccess && !output.isEmpty
        } catch {
            return false
        }
    }
}
