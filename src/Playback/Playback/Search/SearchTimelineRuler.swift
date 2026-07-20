// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI

/// A Time Machine-style vertical ruler that replaces the results scrollbar.
///
/// At rest the ticks sit in the central band, leaving a reserved margin
/// (`marginFraction`) top and bottom. As the cursor approaches, nearby ticks
/// **grow in both width and height** and, via an error-function position warp,
/// **spread apart** — shoving their neighbours (including the fixed-size major
/// date dividers) outward into those reserved margins. The tick directly under
/// the cursor stays pinned in place. Clicking fast-travels the list to the
/// nearest match.
///
/// It's a pure view over the already-loaded results — it holds no OCR data and
/// does nothing once search (and the timeline) closes.
struct SearchTimelineRuler: View {
    let results: [SearchResult]
    /// Scroll the list so the result with this id is at the top.
    let onSeek: (String) -> Void

    @State private var hoverY: CGFloat?

    // MARK: - Tunables
    /// How far, as a fraction of the height, magnified content may push
    /// non-hovered ticks *past* the top and bottom edges. Those overflow zones
    /// live outside the container and are clipped, so pushed-out ticks simply
    /// slide off-screen (like Time Machine). 0.10 = 10%.
    private let marginFraction: CGFloat = 0.10
    /// Small inset so the top/bottom resting ticks aren't clipped by their own size.
    private let edgeInset: CGFloat = 4
    /// Gaussian spread (σ) of the fisheye, as a fraction of the height.
    private let falloffFraction: CGFloat = 0.055
    private let majorTickLength: CGFloat = 22
    private let majorThickness: CGFloat = 2
    private let minorBaseWidth: CGFloat = 6
    private let minorMaxWidthExtra: CGFloat = 16
    private let minorBaseHeight: CGFloat = 1.5
    private let minorMaxHeightExtra: CGFloat = 9
    private let maxMinorTicks = 200

    private struct DateMarker: Identifiable {
        let id: Int          // result index
        let label: String
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let markers = dateMarkers()

            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    draw(ctx, size: size, height: h, markers: markers)
                }

                // Major date labels, right-aligned just left of their (warped) tick.
                ForEach(markers) { marker in
                    let labelWidth = max(0, geo.size.width - majorTickLength - 8)
                    Text(marker.label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: labelWidth, alignment: .trailing)
                        .position(x: labelWidth / 2, y: warp(baseY(marker.id, height: h), height: h))
                        .allowsHitTesting(false)
                }

                // Hover tooltip: "Today at 14:30" for the nearest match, pinned at
                // the cursor, floating left of the tick column.
                if let hoverY, let focus = nearestResult(toY: hoverY, height: h) {
                    tooltip(text: timeLabel(for: focus.ts))
                        .position(
                            x: (geo.size.width - majorTickLength) / 2,
                            y: min(max(hoverY, 12), h - 12)
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Clip to the container so ticks warped into the reserved 10% zones
            // (which sit outside these bounds) are not visible.
            .clipped()
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hoverY = point.y
                case .ended: hoverY = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        if let result = nearestResult(toY: value.location.y, height: h) {
                            onSeek(result.id)
                        }
                    }
            )
        }
    }

    // MARK: - Drawing

    private func draw(_ ctx: GraphicsContext, size: CGSize, height: CGFloat, markers: [DateMarker]) {
        let right = size.width
        let majorIndices = Set(markers.map { $0.id })

        // Minor ticks (sampled): grow in width + height and warp with proximity.
        let step = max(1, results.count / maxMinorTicks)
        var i = 0
        while i < results.count {
            if !majorIndices.contains(i) {
                let by = baseY(i, height: height)
                let dy = warp(by, height: height)
                let m = magnification(by, height: height)
                let w = minorBaseWidth + m * minorMaxWidthExtra
                let tall = minorBaseHeight + m * minorMaxHeightExtra
                let rect = CGRect(x: right - w, y: dy - tall / 2, width: w, height: tall)
                ctx.fill(Path(roundedRect: rect, cornerRadius: majorThickness / 2),
                         with: .color(.primary.opacity(0.16 + m * 0.5)))
            }
            i += step
        }

        // Major date dividers: fixed size, only their position warps.
        for marker in markers {
            let dy = warp(baseY(marker.id, height: height), height: height)
            let rect = CGRect(x: right - majorTickLength, y: dy - majorThickness / 2,
                              width: majorTickLength, height: majorThickness)
            ctx.fill(Path(roundedRect: rect, cornerRadius: majorThickness / 2),
                     with: .color(.primary.opacity(0.5)))
        }
    }

    private func tooltip(text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(.regularMaterial))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }

    // MARK: - Fisheye geometry

    /// Resting position: ticks fill the whole visible height (minus a tiny inset).
    private func baseY(_ index: Int, height: CGFloat) -> CGFloat {
        let top = edgeInset
        let bottom = height - edgeInset
        guard results.count > 1 else { return (top + bottom) / 2 }
        return top + (bottom - top) * CGFloat(index) / CGFloat(results.count - 1)
    }

    /// Warp a resting position around the cursor: an error-function displacement
    /// that spreads points near the cursor apart and pushes far points outward by
    /// up to `marginFraction * height` — past the top/bottom edges and into the
    /// clipped overflow zones. The cursor point is a fixed point (erf(0) = 0), so
    /// the hovered tick never moves. Not clamped: out-of-bounds ticks are clipped.
    private func warp(_ y: CGFloat, height: CGFloat) -> CGFloat {
        guard let yc = hoverY else { return y }
        let sigma = max(1, falloffFraction * height)
        let spread = marginFraction * height
        return y + spread * CGFloat(erf(Double((y - yc) / sigma)))
    }

    /// 0…1 proximity magnification (Gaussian) of a resting position to the cursor.
    private func magnification(_ y: CGFloat, height: CGFloat) -> CGFloat {
        guard let yc = hoverY else { return 0 }
        let sigma = max(1, falloffFraction * height)
        let d = Double((y - yc) / sigma)
        return CGFloat(exp(-d * d))
    }

    private func nearestResult(toY y: CGFloat, height: CGFloat) -> SearchResult? {
        guard !results.isEmpty else { return nil }
        guard results.count > 1 else { return results[0] }
        let top = edgeInset
        let bottom = height - edgeInset
        let frac = min(1, max(0, (y - top) / max(1, bottom - top)))
        let index = Int((frac * CGFloat(results.count - 1)).rounded())
        return results[min(max(index, 0), results.count - 1)]
    }

    private func dateMarkers() -> [DateMarker] {
        guard !results.isEmpty else { return [] }
        let cal = Calendar.current
        var markers: [DateMarker] = []
        var lastDay: Date?
        for (index, result) in results.enumerated() {
            let day = cal.startOfDay(for: Date(timeIntervalSince1970: result.ts))
            if lastDay == nil || day != lastDay {
                markers.append(DateMarker(id: index, label: dayLabel(for: result.ts)))
                lastDay = day
            }
        }
        return markers
    }

    // MARK: - Formatting

    private func dayLabel(for ts: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: ts)
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func timeLabel(for ts: TimeInterval) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(dayLabel(for: ts)) at \(f.string(from: Date(timeIntervalSince1970: ts)))"
    }
}
