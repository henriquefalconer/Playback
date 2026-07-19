// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation

/// Text normalization and character-trigram generation shared by the blind-index
/// write path (encoder subprocess) and the query path (search), so an indexed
/// frame and a live query tokenize identically.
enum Trigrams {
    /// Minimum query length that can be served by the trigram index.
    static let minLength = 3

    /// Collapse newlines and whitespace runs to single spaces, preserving case
    /// (case is kept for readable snippets; matching lowercases separately).
    static func normalize(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// The set of unique lowercased 3-character shingles of `text`. Empty for
    /// text shorter than 3 characters.
    static func shingles(_ text: String) -> Set<String> {
        let chars = Array(text.lowercased())
        guard chars.count >= minLength else { return [] }
        var set = Set<String>(minimumCapacity: chars.count)
        for index in 0...(chars.count - minLength) {
            set.insert(String(chars[index..<index + minLength]))
        }
        return set
    }
}
