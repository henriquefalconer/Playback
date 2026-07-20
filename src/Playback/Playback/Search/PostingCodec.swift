// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation

/// Delta + LEB128 varint codec for a token's posting list — the ascending list of
/// frame rowids (`fid`) that contain a given blind-index trigram token.
///
/// The old index stored one `(tok, fid)` row per posting: an 8-byte token repeated
/// ~168 times on average (once per frame it appears in), plus a full duplicate
/// covering index. Here every token stores its fids exactly once, as gaps between
/// consecutive ids encoded as varints — typically a single byte per posting — so
/// the whole trigram index shrinks by more than an order of magnitude.
///
/// fids are frame rowids, assigned monotonically at insert time, so a token's
/// postings are always appended in ascending order and the deltas are positive.
enum PostingCodec {
    /// Encode a strictly-ascending list of non-negative fids as delta varints.
    static func encode(_ fids: [Int64]) -> Data {
        var out = Data()
        out.reserveCapacity(fids.count)
        var prev: Int64 = 0
        for fid in fids {
            appendVarint(UInt64(fid - prev), to: &out)
            prev = fid
        }
        return out
    }

    /// Decode a posting blob back into the ascending fid list.
    static func decode(_ data: Data) -> [Int64] {
        var out: [Int64] = []
        let bytes = [UInt8](data)
        var prev: Int64 = 0
        var i = 0
        while i < bytes.count {
            var shift: UInt64 = 0
            var value: UInt64 = 0
            while i < bytes.count {
                let byte = bytes[i]; i += 1
                value |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { break }
                shift += 7
            }
            prev += Int64(bitPattern: value)
            out.append(prev)
        }
        return out
    }

    /// Merge `newFids` into an existing posting blob and re-encode. The result is
    /// strictly ascending and de-duplicated, so it is byte-identical whether a
    /// token's postings were built incrementally (live indexing, batch by batch)
    /// or all at once (migration) — a migrated posting is indistinguishable from a
    /// natively-built one.
    static func appending(_ blob: Data?, fids newFids: [Int64]) -> Data {
        guard !newFids.isEmpty else { return blob ?? Data() }
        let existing = blob.map(decode) ?? []
        if existing.isEmpty { return encode(dedupedAscending(newFids)) }
        return encode(dedupedAscending(existing + newFids))
    }

    /// Intersect several posting lists — the frames containing ALL query tokens.
    /// Each input is assumed ascending; the result is ascending. Empty when any
    /// list is empty (a query trigram that never occurs excludes every frame).
    static func intersect(_ lists: [[Int64]]) -> [Int64] {
        guard let first = lists.min(by: { $0.count < $1.count }) else { return [] }
        if lists.contains(where: { $0.isEmpty }) { return [] }
        var acc = Set(first)
        for list in lists where list.count != first.count || !acc.isEmpty {
            acc.formIntersection(list)
            if acc.isEmpty { return [] }
        }
        return acc.sorted()
    }

    private static func dedupedAscending(_ fids: [Int64]) -> [Int64] {
        var seen = Set<Int64>(minimumCapacity: fids.count)
        var out: [Int64] = []
        out.reserveCapacity(fids.count)
        for fid in fids where seen.insert(fid).inserted { out.append(fid) }
        return out.sorted()
    }

    private static func appendVarint(_ v: UInt64, to out: inout Data) {
        var value = v
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
    }
}
