import SwiftUI

struct SearchResultRow: View {
    let result: SearchController.SearchResult
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                // Timestamp and confidence
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.formattedTime)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)

                    Text(String(format: "%.0f%% confidence", result.confidence * 100))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(width: 120, alignment: .leading)

                // Text snippet
                Text(result.snippet)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
}
