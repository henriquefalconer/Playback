import SwiftUI

struct SearchResultsList: View {
    @ObservedObject var searchController: SearchController

    var body: some View {
        VStack(spacing: 0) {
            if searchController.results.isEmpty && !searchController.query.isEmpty && !searchController.isSearching {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No results found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("Try different keywords or check your spelling")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 60)
            } else if !searchController.results.isEmpty {
                // Results list
                ScrollView {
                    ScrollViewReader { proxy in
                        LazyVStack(spacing: 4) {
                            ForEach(Array(searchController.results.enumerated()), id: \.element.id) { index, result in
                                SearchResultRow(
                                    result: result,
                                    isSelected: index == searchController.currentResultIndex,
                                    onSelect: {
                                        searchController.currentResultIndex = index
                                        searchController.jumpToResult(result)
                                    }
                                )
                                .id(result.id)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .onChange(of: searchController.currentResultIndex) { oldValue, newValue in
                            if newValue < searchController.results.count {
                                withAnimation {
                                    proxy.scrollTo(searchController.results[newValue].id, anchor: .center)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
            }
        }
    }
}
