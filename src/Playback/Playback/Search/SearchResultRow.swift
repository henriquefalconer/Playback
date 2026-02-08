import SwiftUI
import AppKit

struct SearchResultRow: View {
    let result: SearchController.SearchResult
    let query: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                // App icon and name
                HStack(spacing: 6) {
                    if let appId = result.appId,
                       let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appId) {
                        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "app.fill")
                            .resizable()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.appName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text(result.formattedTime)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 140, alignment: .leading)

                // Text snippet with highlighted search terms
                Text(highlightedSnippet())
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Confidence indicator
                Text(String(format: "%.0f%%", result.confidence * 100))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func highlightedSnippet() -> AttributedString {
        var attributedString = AttributedString(result.snippet)

        // If query is empty, return unmodified text
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return attributedString
        }

        // Find all occurrences of the search term (case-insensitive)
        let snippet = result.snippet
        let lowercaseSnippet = snippet.lowercased()
        let lowercaseQuery = query.lowercased()

        var searchStartIndex = lowercaseSnippet.startIndex

        while searchStartIndex < lowercaseSnippet.endIndex,
              let range = lowercaseSnippet.range(of: lowercaseQuery, range: searchStartIndex..<lowercaseSnippet.endIndex) {

            // Convert String.Index to AttributedString.Index
            let startOffset = snippet.distance(from: snippet.startIndex, to: range.lowerBound)
            let endOffset = snippet.distance(from: snippet.startIndex, to: range.upperBound)

            let attrStartIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: startOffset)
            let attrEndIndex = attributedString.index(attributedString.startIndex, offsetByCharacters: endOffset)

            attributedString[attrStartIndex..<attrEndIndex].backgroundColor = Color.yellow.opacity(0.3)

            // Move to next potential match
            searchStartIndex = range.upperBound
        }

        return attributedString
    }
}
