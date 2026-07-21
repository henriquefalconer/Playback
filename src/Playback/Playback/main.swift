// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import SwiftUI
import Darwin

// Writing to a pipe whose reader has gone (a helper killed mid-request, or the
// parent gone) must fail the write, not kill this process with SIGPIPE.
signal(SIGPIPE, SIG_IGN)

// The app re-execs itself as a short-lived helper to encode video (see
// VideoEncoder / ProcessingService). Handle that mode here, before any AppKit
// or SwiftUI machinery is created, then exit — so the helper never becomes a
// UI app and its entire (large) encode working set is reclaimed by the kernel
// on exit.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--encode-video" {
    let exitCode = VideoEncoder.runHelper(manifestPath: CommandLine.arguments[2])
    exit(exitCode)
}

// Persistent OCR worker (see OCRBackfill / ProcessingService). Loads the Vision
// model ONCE, then services a stream of per-segment requests over stdin until the
// parent closes it — so the model is never reloaded per segment and OCR runs
// continuously (no per-segment "cold start" pulsing).
if CommandLine.arguments.count >= 2, CommandLine.arguments[1] == "--ocr-worker" {
    // Bulk OCR indexing decodes video frames just like the main app's on-demand
    // search thumbnails do, and a poolful of these workers will otherwise starve
    // that interactive decode (a just-clicked search sits thumbnail-less for many
    // seconds). Drop the whole helper to background priority so it always yields
    // the CPU and video decoder to the foreground app; indexing is never urgent.
    setpriority(PRIO_PROCESS, 0, 15)
    pthread_set_qos_class_self_np(QOS_CLASS_BACKGROUND, 0)
    let exitCode = OCRBackfill.runWorker()
    exit(exitCode)
}

PlaybackApp.main()
