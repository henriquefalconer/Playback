// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import SwiftUI

// The app re-execs itself as a short-lived helper to encode video (see
// VideoEncoder / ProcessingService). Handle that mode here, before any AppKit
// or SwiftUI machinery is created, then exit — so the helper never becomes a
// UI app and its entire (large) encode working set is reclaimed by the kernel
// on exit.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--encode-video" {
    let exitCode = VideoEncoder.runHelper(manifestPath: CommandLine.arguments[2])
    exit(exitCode)
}

// Backfill OCR for an already-encoded segment (see OCRBackfill / ProcessingService).
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--ocr-segment" {
    let exitCode = OCRBackfill.runHelper(manifestPath: CommandLine.arguments[2])
    exit(exitCode)
}

PlaybackApp.main()
