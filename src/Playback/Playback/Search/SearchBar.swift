import SwiftUI
import Combine

struct SearchBar: View {
    @ObservedObject var searchController: SearchController
    @Binding var isPresented: Bool
    @FocusState private var isTextFieldFocused: Bool
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 12) {
            // Search icon
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 16))

            // Search text field
            TextField("Search text in screenshots...", text: $searchController.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isTextFieldFocused)
                .onSubmit {
                    debounceTask?.cancel()
                    debounceTask = Task {
                        await performSearch()
                    }
                }
                .onChange(of: searchController.query) { oldValue, newValue in
                    // Debounced search (300ms delay)
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                        if !Task.isCancelled {
                            await performSearch()
                        }
                    }
                }
                .accessibilityIdentifier("search.textField")

            // Result counter
            if !searchController.results.isEmpty {
                Text(searchController.resultCountText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                // Navigation buttons
                Button(action: {
                    searchController.previousResult()
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Previous result (Shift+Enter)")
                .accessibilityIdentifier("search.previousButton")

                Button(action: {
                    searchController.nextResult()
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Next result (Enter)")
                .accessibilityIdentifier("search.nextButton")
            }

            // Loading indicator
            if searchController.isSearching {
                ProgressView()
                    .scaleEffect(0.7)
            }

            // Clear button
            if !searchController.query.isEmpty {
                Button(action: {
                    searchController.clearSearch()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityIdentifier("search.clearButton")
            }

            // Close button
            Button(action: {
                isPresented = false
                searchController.clearSearch()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close search (ESC)")
            .accessibilityIdentifier("search.closeButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .frame(width: 400)
        .onAppear {
            isTextFieldFocused = true
        }
        .onKeyPress(.escape) {
            isPresented = false
            searchController.clearSearch()
            return .handled
        }
        .onKeyPress(.return, phases: .up) { press in
            if press.modifiers.contains(.shift) {
                searchController.previousResult()
            } else {
                searchController.nextResult()
            }
            return .handled
        }
    }

    private func performSearch() async {
        await searchController.search(query: searchController.query)
    }
}
