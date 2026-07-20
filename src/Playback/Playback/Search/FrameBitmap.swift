// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation

/// Per-frame OCR-processed tracking, conceptually decoupled from any segment
/// ordering: bit `i` means frame `i` has been OCR-processed, independent of every
/// other frame. This is the *status layer* — it knows nothing about batches,
/// scheduling, or decoding; a scheduler asks it which frames are still pending and
/// tells it which just finished.
///
/// Storage is `ceil(count/8)` bytes — a handful of bytes per segment — and callers
/// collapse it to a bare count once `allProcessed`, so a finished segment keeps no
/// per-frame detail at all (the smallest representation of "done").
struct FrameBitmap: Equatable {
    let count: Int
    private var bytes: [UInt8]

    init(count: Int, blob: Data? = nil) {
        self.count = max(0, count)
        let needed = (self.count + 7) / 8
        var storage = blob.map(Array.init) ?? []
        if storage.count < needed { storage.append(contentsOf: repeatElement(0, count: needed - storage.count)) }
        self.bytes = storage
    }

    func isProcessed(_ i: Int) -> Bool {
        guard i >= 0, i < count else { return true } // out of range: nothing to do
        return (bytes[i / 8] >> (i % 8)) & 1 == 1
    }

    mutating func markProcessed(_ range: Range<Int>) {
        for i in range where i >= 0 && i < count {
            bytes[i / 8] |= UInt8(1 << (i % 8))
        }
    }

    /// Number of processed frames. Unused high bits of the final byte stay 0, so a
    /// plain popcount is exact.
    var processedCount: Int { bytes.reduce(0) { $0 + $1.nonzeroBitCount } }

    var allProcessed: Bool { processedCount >= count }

    /// The newest (highest-index) contiguous run of *unprocessed* frames, capped at
    /// `maxLen`. Newest-first so the most recent content is OCR'd soonest; contiguous
    /// so the OCR layer can decode the range in one efficient sweep. Nil when no
    /// frame is pending. Robust to gaps (a failed frame in the middle just splits the
    /// runs), which is what makes each frame independently schedulable.
    func newestPendingRun(maxLen: Int) -> Range<Int>? {
        guard count > 0, maxLen > 0 else { return nil }
        var hi = count
        while hi > 0, isProcessed(hi - 1) { hi -= 1 } // hi = (highest unprocessed) + 1
        guard hi > 0 else { return nil }
        var lo = hi
        while lo > 0, !isProcessed(lo - 1), hi - (lo - 1) <= maxLen { lo -= 1 }
        return lo..<hi
    }

    /// The compact on-disk form: empty once every frame is done (the count alone
    /// records that), otherwise the raw bit bytes.
    var storageBlob: Data { allProcessed ? Data() : Data(bytes) }
}
