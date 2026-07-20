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

    /// Load the index key from the keychain, minting and persisting a fresh 256-bit
    /// key ONLY when none exists yet. Thread-safe.
    ///
    /// Critically, a read *failure* (the item is present but momentarily unreadable
    /// — e.g. an ACL/partition hiccup right after a rebuild) never mints a
    /// replacement: overwriting here would orphan every already-encrypted OCR row.
    /// New keys are created solely when the item is genuinely absent.
    nonisolated static func loadOrCreateKey() -> SymmetricKey {
        keyLock.lock()
        defer { keyLock.unlock() }
        if let cachedKey { return cachedKey }

        // A self-signed (macos-codesigning) build has no Apple Team ID, so the
        // keychain re-prompts on every deploy. Such builds opt into the recovery-file
        // hook — the key briefly lives in a 0600 file so the next build adopts it
        // prompt-free. Team-ID builds skip it entirely and stay keychain-only (the
        // most secure path); any stray recovery file is removed for them.
        let selfSigned = isSelfSignedBuild()
        if !selfSigned { try? FileManager.default.removeItem(at: recoveryKeyURL) }

        let (key, isReal) = resolveKey(selfSigned: selfSigned)
        if isReal {
            cachedKey = key
            if selfSigned { persistRecoveryKey(key) }
        }
        return key
    }

    private static func resolveKey(selfSigned: Bool) -> (key: SymmetricKey, isReal: Bool) {
        // Recovery hook (self-signed only): adopt a key from the hex file, consumed once.
        if selfSigned, let recovered = consumeRecoveryKey() {
            store(key: recovered)
            return (recovered, true)
        }
        switch loadKey() {
        case .found(let key):
            return (key, true)
        case .notFound:
            let key = SymmetricKey(size: .bits256)
            store(key: key)
            // Re-read so a concurrent creator's key wins consistently.
            if case .found(let stored) = loadKey() { return (stored, true) }
            return (key, true)
        case .failed(let status):
            // Leave the item intact and surface an ephemeral key: search stays empty
            // until the item is readable again, but nothing encrypted is lost.
            Log.search.fault("OCR key unreadable (OSStatus \(status, privacy: .public)); refusing to overwrite existing key")
            return (SymmetricKey(size: .bits256), false)
        }
    }

    private enum KeyResult { case found(SymmetricKey); case notFound; case failed(OSStatus) }
    /// Resolved once per process so a self-signed build doesn't re-churn the keychain
    /// (and recovery file) on every call.
    nonisolated(unsafe) private static var cachedKey: SymmetricKey?

    /// True when this build is signed by the self-signed `macos-codesigning` cert
    /// (no Apple Team ID). Conservatively assumes self-signed if it can't tell.
    nonisolated private static func isSelfSignedBuild() -> Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return true }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return true }
        var infoCF: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
              let info = infoCF as? [String: Any] else { return true }
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String
        return (team ?? "").isEmpty
    }

    /// Write the key as hex to the 0600 recovery file so the next self-signed build
    /// adopts it without a keychain prompt.
    nonisolated private static func persistRecoveryKey(_ key: SymmetricKey) {
        let hex = key.withUnsafeBytes { $0.map { String(format: "%02x", $0) }.joined() }
        do {
            try hex.write(to: recoveryKeyURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recoveryKeyURL.path)
        } catch {
            Log.search.debug("Could not persist recovery key: \(error.localizedDescription)")
        }
    }

    nonisolated private static func loadKey() -> KeyResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            return .found(SymmetricKey(data: data))
        }
        if status == errSecItemNotFound { return .notFound }
        return .failed(status)
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

    /// A file (64 hex chars) that, when present at launch, restores a known key
    /// into the keychain and is then deleted — a safe path to recover a key without
    /// routing raw bytes through the `security` CLI's string handling.
    nonisolated private static var recoveryKeyURL: URL {
        Paths.baseDataDirectory.appendingPathComponent(".search-key-recovery")
    }

    nonisolated private static func consumeRecoveryKey() -> SymmetricKey? {
        let url = recoveryKeyURL
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: url)
        let hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var bytes = Data()
        var index = hex.startIndex
        while index < hex.endIndex, let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
            guard let byte = UInt8(hex[index..<next], radix: 16) else { break }
            bytes.append(byte)
            index = next
        }
        guard bytes.count == 32 else {
            Log.search.error("Recovery key file malformed (got \(bytes.count) bytes); ignored")
            return nil
        }
        Log.search.notice("Restored OCR key from recovery file")
        return SymmetricKey(data: bytes)
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
