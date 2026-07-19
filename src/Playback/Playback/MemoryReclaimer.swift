// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import os

/// Forces freed memory back to the OS.
///
/// Video encoding and frame decoding allocate large buffers that malloc keeps
/// in its large-object cache (as compressed pages) after they're freed, instead
/// of returning them to the kernel. A single `malloc_zone_pressure_relief` call
/// frees only what's releasable at that instant — and right after an encode,
/// AVFoundation/VideoToolbox are still tearing down asynchronously, so most of
/// the memory isn't releasable yet. `reclaimSoon()` spreads several calls over a
/// few seconds to catch that teardown, dropping the footprint promptly instead
/// of over the ~70s it would take to drip out via the recording loop.
enum MemoryReclaimer {
    private static let queue = DispatchQueue(label: "com.falconer.Playback.memoryReclaim", qos: .utility)

    /// Immediately return all currently-freeable memory to the OS.
    static func reclaimNow() {
        _ = malloc_zone_pressure_relief(nil, 0)
    }

    /// Reclaim now and again over the next several seconds, to catch memory that
    /// AVFoundation/VideoToolbox release asynchronously after an encode or a
    /// player teardown. The later passes (8–15s) matter on timeline close: the
    /// decode pipeline drains its buffers well after the window closes, and
    /// without a late pass those freed pages sit in malloc's cache instead of
    /// returning to the OS.
    static func reclaimSoon() {
        let delays: [TimeInterval] = [0, 0.5, 1.5, 3.0, 5.0, 8.0, 12.0, 15.0]
        for delay in delays {
            queue.asyncAfter(deadline: .now() + delay) {
                _ = malloc_zone_pressure_relief(nil, 0)
            }
        }
        Log.system.debug("Scheduled staged memory reclaim")
    }
}
