// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI
import AppKit

/// The CMD+F search panel: a translucent, top-right modal with a live-updating
/// result list. It never dims the background and stays open when a result is
/// clicked, so the timeline behind it jumps while the panel remains available.
struct SearchOverlayView: View {
    @ObservedObject var index: SearchIndex
    /// Drives the list footer: "Loading results…" while the OCR backlog is still
    /// being indexed, "No more results" once every frame is searchable.
    @ObservedObject private var processing = ProcessingService.shared
    /// Bumped by the parent (on CMD+F) to (re)focus the field without closing.
    let focusTrigger: Int
    /// Invoked with the timestamp, frame id, and current query of a clicked result.
    let onSelect: (_ ts: TimeInterval, _ id: String, _ query: String) -> Void

    @State private var query: String = ""
    @FocusState private var fieldFocused: Bool
    /// Live drag translation while the header is being dragged.
    @State private var dragOffset: CGSize = .zero
    /// Committed drag translation from previous drags — the modal can be moved
    /// anywhere inside the app view by dragging its header.
    @State private var committedOffset: CGSize = .zero
    /// Handle to the native results table so the ruler can jump it by row index.
    @State private var tableController = SearchResultsTableController()

    private let panelWidth: CGFloat = 520
    /// Row pitch of the results table — matches `SearchResultRow`'s intrinsic height
    /// (52pt thumbnail + 2×8pt padding) so rows never clip and scroll math is exact.
    private let rowHeight: CGFloat = 68

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .contentShape(Rectangle())
                .gesture(dragGesture)
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Divider().opacity(0.4)
                resultsList
            }
        }
        .frame(width: panelWidth)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        // Offset the fully-composited panel (chrome + content) so the whole
        // modal moves together, not just its contents.
        .offset(
            x: committedOffset.width + dragOffset.width,
            y: committedOffset.height + dragOffset.height
        )
        .onAppear { focusField() }
        .onChange(of: focusTrigger) { _, _ in focusField() }
    }

    /// Focus the field on the next runloop tick, so it works even when the field
    /// isn't yet in the responder chain (first open) or lost focus to a result.
    private func focusField() {
        DispatchQueue.main.async { fieldFocused = true }
    }

    /// Drag the whole panel by its header, freeing it from the top-right corner
    /// so it can be repositioned anywhere inside the app view.
    ///
    /// The translation is measured in `.global` space, not the gesture's default
    /// `.local` space: the panel's own `.offset` moves the view — and with it a
    /// `.local` reference frame — every frame, which feeds the offset back into
    /// the reported translation (yielding half the mouse distance plus jitter).
    /// Global space is fixed to the window, so it stays a stable reference.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                committedOffset.width += value.translation.width
                committedOffset.height += value.translation.height
                dragOffset = .zero
            }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search everything you've seen", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($fieldFocused)
                .onChange(of: query) { _, newValue in
                    index.search(newValue)
                }
                .onSubmit {
                    if let first = index.results.first { onSelect(first.ts, first.id, query) }
                }
                .accessibilityIdentifier("search.field")

            if !query.isEmpty {
                Button {
                    query = ""
                    index.search("")
                    fieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.clear")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Results

    /// The search body's state ladder, in strict precedence order (highest first):
    ///
    /// 1. **Keep typing** — a 1–2 char query is below the trigram index minimum and
    ///    can never match, so it overrides everything, including any in-flight
    ///    loading spinner or stale rows from a previous longer query.
    /// 2. **Results** — any matching frame is listed, whether it was OCR-ed earlier
    ///    or *just* indexed during this session. Rows always win over the loading
    ///    state; the "Loading results…" footer sits *below* them, never replacing
    ///    them. So the moment a match exists, the user sees it.
    /// 3. **Loading** — no rows yet, but still fetching or still indexing the
    ///    backlog: a spinner, since matches may yet appear.
    /// 4. **No matches** — the query is long enough, the search finished, indexing
    ///    is done, and nothing matched.
    @ViewBuilder
    private var resultsList: some View {
        if isQueryTooShort {
            centeredHint("Keep typing…")
        } else if !index.results.isEmpty {
            resultsScroll
        } else if index.isSearching || processing.indexingInProgress {
            spinnerLabel
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 18)
        } else {
            centeredHint("No matches")
        }
    }

    /// A 1–2 char query (after whitespace-normalization) is below the trigram
    /// index's minimum length and cannot be served — so it resolves straight to
    /// "Keep typing…", ahead of any result or loading state.
    private var isQueryTooShort: Bool {
        let length = Trigrams.normalize(query).count
        return length > 0 && length < Trigrams.minLength
    }

    /// The scrolling result list plus its Time Machine-style ruler. Ends with a
    /// footer that reads "Loading results…" while the backlog is still indexing,
    /// so newly-OCR-ed matches keep streaming in above it.
    ///
    /// A native `NSTableView` (see `SearchResultsTable`) — not `ScrollView { LazyVStack }`
    /// or `List` — is essential: a common word matches thousands of frames, and both
    /// SwiftUI containers are O(n) to locate a scroll target (LazyVStack realizes every
    /// row up to it; List walks its whole view list copying each element), stalling the
    /// UI for seconds on a jump to an old date. The table addresses rows by index, so
    /// it renders only what's visible and jumps in O(1) no matter the match count.
    private var resultsScroll: some View {
        HStack(spacing: 0) {
            // The footer ("Loading results…" / "No more results") is the list's own
            // last row, so it only shows once you scroll to the very end.
            SearchResultsTable(
                results: index.results,
                index: index,
                onSelect: { onSelect($0.ts, $0.id, query) },
                rowHeight: rowHeight,
                controller: tableController
            )

            // Time Machine-style ruler replaces the scrollbar: click to fast-travel
            // the list to the nearest match at that moment (by row index, O(1)).
            SearchTimelineRuler(results: index.results) { row in
                tableController.scrollToRow(row)
            }
            .frame(width: 116)
            .padding(.vertical, 6)
            .padding(.trailing, 6)
        }
        .frame(maxHeight: 520)
        .accessibilityIdentifier("search.results")
    }

    /// A single centered, secondary-styled hint line ("Keep typing…"/"No matches"),
    /// sized to match the loading row so the box height never jumps between states.
    private func centeredHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 18)
    }

    /// Centered spinner + label for the empty state (no rows yet, still working).
    private var spinnerLabel: some View {
        SearchLoadingLabel(fontSize: 13)
    }
}

/// Spinner + "Loading results… (XX.XX%)" — the percent is revealed only once loading
/// has stayed up past 10s, so a quick pass never flashes a number. Owns its own timer
/// and observes indexing, so it renders correctly wherever it's placed (the empty
/// state or, hosted in a table cell, the list's footer row). Two decimals because
/// each 1% is minutes of OCR — the fine digits visibly tick to show progress.
struct SearchLoadingLabel: View {
    var fontSize: CGFloat = 13
    @ObservedObject private var processing = ProcessingService.shared
    @State private var showPercent = false

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.system(size: fontSize))
                .foregroundStyle(.secondary)
        }
        .task(id: processing.indexingInProgress) {
            showPercent = false
            guard processing.indexingInProgress else { return }
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if !Task.isCancelled { showPercent = true }
        }
    }

    private var text: String {
        let pct = processing.indexingProgress * 100
        return (showPercent && pct > 0)
            ? String(format: "Loading results… (%.2f%%)", pct)
            : "Loading results…"
    }
}

/// The list's own last row: the loading label while the OCR backlog is still
/// indexing, "No more results" once everything is searchable — so the list never
/// just trails off, and the status only shows when you scroll to the very end.
struct SearchListFooter: View {
    @ObservedObject private var processing = ProcessingService.shared

    var body: some View {
        Group {
            if processing.indexingInProgress {
                SearchLoadingLabel(fontSize: 12)
            } else {
                Text("No more results")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
    }
}

/// A single result row: squircle preview + highlighted two-line snippet.
struct SearchResultRow: View {
    let result: SearchResult
    let index: SearchIndex
    let onTap: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                thumbnailView

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.snippet)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovering ? Color.white.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("search.result")
        .task(id: result.id) {
            // Seed from the cache synchronously so a reused cell shows the right
            // frame immediately — never the previous row's image, never a flash of
            // empty — and only decode when it isn't cached yet.
            thumbnail = index.cachedThumbnail(for: result)
            if thumbnail == nil {
                thumbnail = await index.thumbnail(for: result)
            }
        }
    }

    private var thumbnailView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .animation(.easeOut(duration: 0.15), value: thumbnail != nil)
    }

    private var subtitle: String {
        var parts: [String] = [Self.relativeString(from: result.ts)]
        if let appId = result.appId, let name = Self.appDisplayName(for: appId) {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }

    private static func relativeString(from ts: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: ts)
        // Show the absolute date whenever the moment isn't on today's date.
        guard Calendar.current.isDateInToday(date) else {
            return DateDisplay.absolute(date)
        }
        let delta = max(0, Date().timeIntervalSince1970 - ts)
        if delta < 60 { return "just now" }
        if delta < 3600 {
            let m = Int(delta / 60); return m == 1 ? "1 min ago" : "\(m) mins ago"
        }
        let h = Int(delta / 3600)
        return h == 1 ? "1 hour ago" : "\(h) hours ago"
    }

    private static var appNameCache: [String: String] = [:]

    private static func appDisplayName(for appId: String) -> String? {
        if let cached = appNameCache[appId] { return cached }
        let name: String
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appId) {
            name = url.deletingPathExtension().lastPathComponent
        } else {
            name = appId.components(separatedBy: ".").last ?? appId
        }
        appNameCache[appId] = name
        return name
    }
}
