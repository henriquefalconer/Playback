// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI
import AppKit

/// A native, fully virtualized results list.
///
/// A common query ("the") matches many thousands of frames, and both SwiftUI scroll
/// containers choke on that: `LazyVStack` builds an attribute node per row (so
/// `scrollTo` realizes everything up to the target), and `List` walks its whole view
/// list — copying every element's `AttributedString` — just to locate a scroll
/// target. Either way jumping to an old date stalls the main thread for seconds.
///
/// `NSTableView` addresses rows by integer index instead: it renders only the visible
/// rows and, with a fixed row height, scrolls to any row in O(1). Each row hosts the
/// same SwiftUI `SearchResultRow`, and the list's status line rides along as a final
/// footer row so it only appears once you scroll to the very end.
///
/// As indexing surfaces more matches, the result set grows in place. Rather than
/// reloading (which rebuilds visible cells — reloading every thumbnail, and flashing),
/// the update is applied as a minimal set of row *insertions* at the exact
/// chronological positions the new matches occupy, and the scroll offset is nudged to
/// keep whatever you were looking at pinned. Existing cells are never touched, so
/// there's no flicker and no lost place.
struct SearchResultsTable: NSViewRepresentable {
    let results: [SearchResult]
    let index: SearchIndex
    let onSelect: (SearchResult) -> Void
    /// The row pitch (row height + spacing) must stay in lockstep with the hosted
    /// row's intrinsic height so nothing clips and O(1) scrolling is exact.
    let rowHeight: CGFloat
    /// Handed the live table so the ruler can drive scrolling by row index.
    let controller: SearchResultsTableController
    /// Fired once the first screen of thumbnails has finished loading, so paused
    /// background work (OCR indexing) can resume for normal operation.
    let onThumbnailsSettled: () -> Void

    private static let footerHeight: CGFloat = 40
    private static let rowSpacing: CGFloat = 2

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.usesAutomaticRowHeights = false
        table.rowHeight = rowHeight
        table.intercellSpacing = NSSize(width: 0, height: Self.rowSpacing)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        // Clicks are handled here (AppKit), not by a SwiftUI Button inside the cell —
        // a nested hosted Button breaks the surrounding SwiftUI gesture routing.
        table.target = context.coordinator
        table.action = #selector(Coordinator.rowClicked(_:))

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)

        context.coordinator.table = table
        context.coordinator.current = results
        controller.table = table
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.parent = self
        guard let table = nsView.documentView as? NSTableView else { return }

        let old = coord.current
        let new = results
        // Unchanged (same query refresh that added nothing) — leave the table be.
        if old.count == new.count, old.first?.id == new.first?.id, old.last?.id == new.last?.id {
            coord.current = new
            return
        }
        coord.current = new

        let clip = nsView.contentView
        let pitch = rowHeight + Self.rowSpacing

        // First fill (or cleared): a plain reload, pinned to the top.
        guard !old.isEmpty else {
            table.reloadData()
            clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: 0))
            nsView.reflectScrolledClipView(clip)
            if !new.isEmpty { coord.beginSettleWatch() }
            return
        }

        // The row currently at the top of the viewport, in the OLD indexing — used to
        // keep that same row visually put after rows insert above it.
        let topOldRow = max(0, Int((clip.bounds.origin.y + 0.5) / pitch))

        // Diff: because indexing only ever *adds* matches, the old list is a
        // subsequence of the new one. Walk both in lockstep; every new element that
        // isn't the next expected old element is a fresh insertion.
        var inserted: [Int] = []
        var insertedAboveTop = 0
        var i = 0
        for j in 0..<new.count {
            if i < old.count, old[i].id == new[j].id {
                i += 1
            } else {
                inserted.append(j)
                if i < topOldRow { insertedAboveTop += 1 }
            }
        }

        // If every old row was accounted for, apply the incremental insert; otherwise
        // (a genuinely different set — e.g. the query changed) fall back to a reload.
        if i == old.count {
            table.insertRows(at: IndexSet(inserted), withAnimation: [])
            if insertedAboveTop > 0 {
                let origin = NSPoint(x: clip.bounds.origin.x,
                                     y: clip.bounds.origin.y + CGFloat(insertedAboveTop) * pitch)
                clip.setBoundsOrigin(origin)
                nsView.reflectScrolledClipView(clip)
            }
        } else {
            table.reloadData()
            // Same query, same first row → keep the place; otherwise reset to top.
            if new.first?.id == old.first?.id {
                nsView.reflectScrolledClipView(clip)
            } else {
                clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: 0))
                nsView.reflectScrolledClipView(clip)
            }
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: SearchResultsTable
        weak var table: NSTableView?
        /// The result set the table currently reflects — the diff baseline.
        var current: [SearchResult] = []
        /// Result ids whose thumbnail is still decoding — used to detect when the
        /// first screen has fully loaded so paused indexing can resume.
        private var pendingThumbs = Set<String>()
        private var settleWatching = false
        private var settled = false

        init(_ parent: SearchResultsTable) { self.parent = parent }

        /// Arm the one-shot "first thumbnails loaded" signal when results first appear.
        /// A fallback timer covers the all-cached / nothing-to-load case.
        func beginSettleWatch() {
            guard !settleWatching, !settled else { return }
            settleWatching = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.fireSettle() }
        }

        private func fireSettle() {
            guard settleWatching, !settled else { return }
            settled = true
            parent.onThumbnailsSettled()
        }

        @objc func rowClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < parent.results.count else { return }
            parent.onSelect(parent.results[row])
        }

        // One extra row past the matches: the footer status line.
        func numberOfRows(in tableView: NSTableView) -> Int { parent.results.count + 1 }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            row < parent.results.count ? parent.rowHeight : SearchResultsTable.footerHeight
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            // The footer's own row.
            guard row < parent.results.count else {
                let id = NSUserInterfaceItemIdentifier("footer")
                if let reused = tableView.makeView(withIdentifier: id, owner: self) as? RowHostingView {
                    reused.currentID = nil
                    reused.rootView = AnyView(SearchListFooter())
                    return reused
                }
                let hosting = RowHostingView(rootView: AnyView(SearchListFooter()))
                hosting.identifier = id
                return hosting
            }

            let result = parent.results[row]
            let id = NSUserInterfaceItemIdentifier("row")
            let hosting: RowHostingView
            if let reused = tableView.makeView(withIdentifier: id, owner: self) as? RowHostingView {
                hosting = reused
            } else {
                hosting = RowHostingView(rootView: AnyView(EmptyView()))
                hosting.identifier = id
            }

            // Thumbnails are loaded here, imperatively, rather than via SwiftUI's
            // `.task` inside the hosted row — that lifecycle doesn't fire in an
            // NSTableView cell, so rows would sit blank until something forced a
            // redraw. `viewFor` *is* called the moment a row scrolls in, so this
            // loads exactly the visible rows, right on time.
            hosting.currentID = result.id
            let cached = parent.index.cachedThumbnail(for: result)
            hosting.rootView = Self.rowView(result, thumbnail: cached)
            if cached == nil {
                let index = parent.index
                pendingThumbs.insert(result.id)
                Task { @MainActor in
                    let image = await index.thumbnail(for: result)
                    self.pendingThumbs.remove(result.id)
                    if self.settleWatching, self.pendingThumbs.isEmpty { self.fireSettle() }
                    // Ignore if the cell was recycled for another row meanwhile.
                    guard hosting.currentID == result.id, let image else { return }
                    hosting.rootView = Self.rowView(result, thumbnail: image)
                }
            }
            return hosting
        }

        private static func rowView(_ result: SearchResult, thumbnail: NSImage?) -> AnyView {
            AnyView(SearchResultRow(result: result, thumbnail: thumbnail))
        }
    }
}

/// An `NSHostingView` that remembers which result it's currently showing (so an
/// async thumbnail load can tell whether the cell was recycled before it finished)
/// and is transparent to the mouse: `hitTest` returns nil so clicks fall through to
/// the `NSTableView`, which selects the row and fires its action. This both makes
/// the click land reliably and keeps SwiftUI out of the mouse-event path — a hosted
/// interactive control there wedges the surrounding SwiftUI gesture routing.
private final class RowHostingView: NSHostingView<AnyView> {
    var currentID: String?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A thin handle the SwiftUI layer keeps so the ruler can command the native table
/// to jump — kept out of the representable so it survives view-value churn.
final class SearchResultsTableController {
    weak var table: NSTableView?

    /// Scroll so `row` sits at the top of the viewport. O(1): `rect(ofRow:)` is pure
    /// arithmetic with a fixed row height, so no rows between here and there are
    /// touched.
    func scrollToRow(_ row: Int) {
        guard let table, let scroll = table.enclosingScrollView,
              row >= 0, row < table.numberOfRows else { return }
        let clip = scroll.contentView
        let rect = table.rect(ofRow: row)
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: rect.minY - scroll.contentInsets.top))
        scroll.reflectScrolledClipView(clip)
    }

    /// Scroll to a continuous position: `fraction` 0→1 maps the list's whole scroll
    /// range like a scrollbar, so clicking partway down the ruler lands partway down
    /// the results — smooth sub-row travel, not a snap to the nearest indexed row.
    func scrollToFraction(_ fraction: CGFloat) {
        guard let table, let scroll = table.enclosingScrollView else { return }
        let clip = scroll.contentView
        let maxOffset = max(0, table.bounds.height - clip.bounds.height)
        let y = min(maxOffset, max(0, fraction * maxOffset))
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: y - scroll.contentInsets.top))
        scroll.reflectScrolledClipView(clip)
    }
}
