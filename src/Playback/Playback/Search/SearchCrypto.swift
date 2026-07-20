// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import CryptoKit
import Security
import os

/// Symmetric encryption for the on-disk OCR search index.
///
/// The OCR text and preview thumbnails are derived from screen contents and are
/// therefore sensitive. They are never written to disk in plaintext: every blob
/// is sealed with AES-GCM (256-bit) before it reaches SQLite, and opened only in
/// memory while the timeline window is open.
///
/// The key lives in the login keychain (`kSecClassGenericPassword`). Access is
/// granted silently across rebuilds because the app is signed by the
/// `macos-codesigning` certificate, which is marked trusted on this machine — so
/// the keychain's "Always Allow" grant binds to the app's stable designated
/// requirement rather than a per-build cdhash. The encoder helper subprocess
/// receives the key as a base64 string in its manifest (a short-lived temp file)
/// so it can seal OCR results directly — the main app is the only component that
/// touches the keychain.
enum SearchCrypto {
    private static let service = "com.falconer.Playback.search"
    private static let account = "ocr-index-key"

    /// Serializes key load-or-create so two threads (the processing queue and the
    /// search actor) can't both miss the keychain and each mint a different key —
    /// which would leave rows encrypted under a key nobody can read back.
    private static let keyLock = NSLock()

    // MARK: - Key management (main app only)

    /// Load the index key from the keychain, creating and persisting a fresh
    /// 256-bit key on first use. Thread-safe.
    nonisolated static func loadOrCreateKey() -> SymmetricKey {
        keyLock.lock()
        defer { keyLock.unlock() }
        if let existing = loadKey() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        store(key: key)
        // Re-read after storing so a concurrent creator's key wins consistently.
        return loadKey() ?? key
    }

    nonisolated private static func loadKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
            if status != errSecItemNotFound {
                Log.search.error("Keychain read failed for index key: OSStatus \(status)")
            }
            return nil
        }
        return SymmetricKey(data: data)
    }

    nonisolated private static func store(key: SymmetricKey) {
        let data = key.withUnsafeBytes { Data($0) }
        // Remove any stale entry first so add never collides.
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)

        var attrs = base
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attrs as CFDictionary, nil)
        // errSecDuplicateItem means another thread just created it — not an error.
        if status != errSecSuccess && status != errSecDuplicateItem {
            Log.search.error("Keychain write failed for index key: OSStatus \(status)")
        }
    }

    // MARK: - Key transport (for the encoder subprocess)

    /// The key is handed to the encoder subprocess over its stdin pipe (never
    /// written to disk), so these convert to/from the wire representation.
    nonisolated static func exportBase64(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { Data($0) }.base64EncodedString()
    }

    nonisolated static func key(fromBase64 string: String) -> SymmetricKey? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    // MARK: - Seal / open

    /// AES-GCM seal, returning the combined (nonce + ciphertext + tag) blob.
    nonisolated static func seal(_ plaintext: Data, key: SymmetricKey) -> Data? {
        do {
            return try AES.GCM.seal(plaintext, using: key).combined
        } catch {
            Log.search.error("AES-GCM seal failed: \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated static func open(_ blob: Data, key: SymmetricKey) -> Data? {
        do {
            let box = try AES.GCM.SealedBox(combined: blob)
            return try AES.GCM.open(box, using: key)
        } catch {
            Log.search.error("AES-GCM open failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Blind index tokens

    /// Length (bytes) of a stored blind-index token. 8 bytes = 64 bits of a
    /// keyed MAC; collisions are astronomically rare and would only ever produce
    /// a candidate that the exact-substring verify step discards anyway.
    static let tokenLength = 8

    /// A MAC key derived from the index key, kept distinct from the encryption
    /// key by domain separation (HKDF) so the same material is never reused
    /// across AES-GCM and HMAC.
    nonisolated static func deriveTokenKey(_ key: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            info: Data("playback.ocr.blind-index.v1".utf8),
            outputByteCount: 32
        )
    }

    /// Keyed, irreversible token for one normalized trigram. Same input + key
    /// always yields the same token (so a query trigram matches indexed ones),
    /// but the plaintext trigram cannot be recovered from it.
    nonisolated static func token(for trigram: String, tokenKey: SymmetricKey) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(trigram.utf8), using: tokenKey)
        return Data(mac.prefix(tokenLength))
    }
}
