// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI
import AppKit

struct StorageSetupView: View {
    @ObservedObject var coordinator: FirstRunCoordinator

    private let minimumRecommendedSpace: UInt64 = 100_000_000_000
    private var storagePath: URL {
        Paths.baseDataDirectory
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Storage Location")
                .font(.title)
                .fontWeight(.bold)

            Text("Playback will store your recordings in the default location.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                Text("Storage Location")
                    .font(.headline)

                HStack {
                    Text(storagePath.path)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                if coordinator.availableDiskSpace > 0 {
                    DiskSpaceInfo(
                        availableSpace: coordinator.availableDiskSpace,
                        minimumRecommended: minimumRecommendedSpace
                    )
                }

                if case .invalid(let message) = coordinator.storageValidation {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(message)
                            .font(.callout)
                            .foregroundColor(.orange)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Storage Estimates")
                        .font(.headline)

                    StorageEstimateRow(activity: "Light use (2-3 hours/day)", estimate: "5-10 GB/month")
                    StorageEstimateRow(activity: "Medium use (6-8 hours/day)", estimate: "20-30 GB/month")
                    StorageEstimateRow(activity: "Heavy use (10+ hours/day)", estimate: "40-60 GB/month")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(.top, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            validateStorageLocation()
        }
    }

    private func validateStorageLocation() {
        let path = storagePath

        coordinator.storageValidation = .checking

        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default

            guard let attributes = try? fileManager.attributesOfFileSystem(forPath: path.path),
                  let freeSpace = attributes[.systemFreeSize] as? UInt64 else {
                DispatchQueue.main.async {
                    coordinator.storageValidation = .invalid("Could not determine available disk space")
                }
                return
            }

            let testPath = path.appendingPathComponent(".playback_write_test")
            let canWrite: Bool
            do {
                try "test".write(to: testPath, atomically: true, encoding: .utf8)
                try fileManager.removeItem(at: testPath)
                canWrite = true
            } catch {
                canWrite = false
            }

            DispatchQueue.main.async {
                coordinator.availableDiskSpace = freeSpace

                if !canWrite {
                    coordinator.storageValidation = .invalid("No write permission for this location")
                } else if freeSpace < minimumRecommendedSpace {
                    coordinator.storageValidation = .invalid(
                        "Warning: Less than 100 GB available. Recommended minimum is 100 GB for optimal operation."
                    )
                } else {
                    coordinator.storageValidation = .valid
                }
            }
        }
    }
}

struct DiskSpaceInfo: View {
    let availableSpace: UInt64
    let minimumRecommended: UInt64

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: availableSpace >= minimumRecommended ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundColor(availableSpace >= minimumRecommended ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Available Space: \(formatBytes(availableSpace))")
                    .font(.callout)
                Text("Recommended: \(formatBytes(minimumRecommended))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct StorageEstimateRow: View {
    let activity: String
    let estimate: String

    var body: some View {
        HStack {
            Text(activity)
                .font(.callout)
            Spacer()
            Text(estimate)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
}
