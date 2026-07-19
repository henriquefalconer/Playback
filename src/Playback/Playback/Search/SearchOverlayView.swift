// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI
import AppKit

/// The CMD+F search panel: a translucent, top-right modal with a live-updating
/// result list. It never dims the background and stays open when a result is
/// clicked, so the timeline behind it jumps while the panel remains available.
struct SearchOverlayView: View {
    @ObservedObject var index: SearchIndex
    /// Bumped by the parent (on CMD+F) to (re)focus the field without closing.
    let focusTrigger: Int
    /// Invoked with the timestamp, frame id, and current query of a clicked result.
    let onSelect: (_ ts: TimeInterval, _ id: String, _ query: String) -> Void

    @State private var query: String = ""
    @FocusState private var fieldFocused: Bool

    private let panelWidth: CGFloat = 460

    var body: some View {
        VStack(spacing: 0) {
            searchField
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
        .onAppear { fieldFocused = true }
        .onChange(of: focusTrigger) { _, _ in fieldFocused = true }
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

    @ViewBuilder
    private var resultsList: some View {
        if index.results.isEmpty {
            HStack {
                Text(Trigrams.normalize(query).count < Trigrams.minLength ? "Keep typing…" : "No matches")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(index.results) { result in
                        SearchResultRow(result: result, index: index) {
                            onSelect(result.ts, result.id, query)
                        }
                    }
                }
                .padding(6)
                .background(OverlayScrollerConfigurator())
            }
            .frame(maxHeight: 520)
            .accessibilityIdentifier("search.results")
        }
    }
}

/// Forces the enclosing scroll view to use the thin, floating "overlay" scroller
/// (the narrow, auto-hiding one) instead of the wide always-on legacy scroller,
/// regardless of the user's system "Show scroll bars" preference.
private struct OverlayScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { view.enclosingScrollView?.scrollerStyle = .overlay }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.enclosingScrollView?.scrollerStyle = .overlay }
    }
}

/// A single result row: squircle preview + highlighted two-line snippet.
private struct SearchResultRow: View {
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
            thumbnail = nil
            index.thumbnail(for: result.id) { image in
                thumbnail = image
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
