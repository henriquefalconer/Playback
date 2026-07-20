// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import Compression

/// zlib DEFLATE for OCR text, applied *before* encryption.
///
/// AES-GCM ciphertext is indistinguishable from random noise, so it cannot be
/// compressed — the only useful order is compress-then-encrypt. Screen text
/// (code, terminals, paths, prose) is highly redundant and shrinks ~3–4×, so the
/// text column, though already the smallest, gets smaller still for free.
///
/// The blob is `varint(originalByteCount)` followed by the raw DEFLATE stream, so
/// decompression can size its output buffer exactly. A zero original length is
/// encoded as the single byte 0x00 with no stream.
enum SearchCompression {
    private static let schemeZlib: UInt8 = 0x00
    private static let schemeStored: UInt8 = 0x01

    static func compress(_ data: Data) -> Data {
        func stored() -> Data {
            var out = Data([schemeStored])
            appendVarint(UInt64(data.count), to: &out)
            out.append(data)
            return out
        }
        guard !data.isEmpty else { return stored() }
        let src = [UInt8](data)
        // DEFLATE can slightly exceed the input on incompressible data; add headroom.
        let cap = src.count + (src.count / 2) + 64
        var dst = [UInt8](repeating: 0, count: cap)
        let written = src.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                compression_encode_buffer(d.baseAddress!, cap, s.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        // 0 = couldn't fit; a larger-than-input result isn't worth encrypting either.
        guard written > 0, written < src.count else { return stored() }
        var out = Data([schemeZlib])
        appendVarint(UInt64(data.count), to: &out)
        out.append(contentsOf: dst[0..<written])
        return out
    }

    static func decompress(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard let scheme = bytes.first else { return Data() }
        var i = 1
        let originalCount = readVarint(bytes, &i)
        guard let originalCount else { return nil }
        if originalCount == 0 { return Data() }
        let payload = Array(bytes[i...])
        if scheme == 0x01 { // stored raw
            return Data(payload)
        }
        guard scheme == 0x00 else { return nil }
        var dst = [UInt8](repeating: 0, count: Int(originalCount))
        let written = payload.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                compression_decode_buffer(d.baseAddress!, d.count, s.baseAddress!, payload.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == Int(originalCount) else { return nil }
        return Data(dst)
    }

    // MARK: - Varint

    private static func appendVarint(_ v: UInt64, to out: inout Data) {
        var value = v
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            out.append(byte)
        } while value != 0
    }

    private static func readVarint(_ bytes: [UInt8], _ i: inout Int) -> UInt64? {
        var shift: UInt64 = 0
        var value: UInt64 = 0
        while i < bytes.count {
            let byte = bytes[i]; i += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }
}
