// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI

/// A Time Machine-style vertical ruler that replaces the results scrollbar.
///
/// Every tick — minor mark or major date divider — lives on a single, uniformly
/// spaced grid of `slotCount` slots. Each slot is exactly one tick: most are
/// minor, a few are "major" (a wider bar plus a date label). Because major bars
/// occupy real grid slots (each date boundary is snapped to its nearest slot),
/// the whole column shares one consistent pitch and nothing ever overlaps — it
/// reads as one ruler, not a minor layout with dividers floating over it.
///
/// At rest the ticks fill the central band, leaving a reserved margin
/// (`marginFraction`) top and bottom. As the cursor approaches, nearby ticks
/// **grow in both width and height** and, via an error-function position warp,
/// **spread apart** — shoving their neighbours outward into those reserved
/// margins. The tick directly under the cursor stays pinned. Clicking
/// fast-travels the list to the nearest match.
///
/// It's a pure view over the already-loaded results — it holds no OCR data and
/// does nothing once search (and the timeline) closes.
struct SearchTimelineRuler: View {
    let results: [SearchResult]
    /// Travel the list to this continuous position (0 = newest/top, 1 = oldest/end).
    let onSeek: (CGFloat) -> Void

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
    private let minorMaxHeightExtra: CGFloat = 8
    /// Resting centre-to-centre spacing of every tick. The number of slots is
    /// derived from this and the ruler height (results are sampled to fit), so
    /// ticks never overlap however many results there are: the warp only ever
    /// *expands* spacing (its slope is ≥ 1 everywhere), so as long as the resting
    /// pitch clears the base height and the max magnified growth stays within the
    /// warp's peak expansion of the pitch, magnified ticks stay separated too.
    private let minorPitch: CGFloat = 4.5
    /// Minimum vertical room a date label needs so two adjacent dividers' labels
    /// don't stack. Enforced in slot units when placing majors on the grid.
    private let labelGap: CGFloat = 15

    /// The unified tick grid: one entry per slot, evenly spaced, each mapped to a
    /// result. A subset of slots are majors (date dividers with a label).
    private struct RulerLayout {
        let slotCount: Int
        let slotY: [CGFloat]              // resting (pre-warp) Y per slot
        let resultIndex: [Int]           // result each slot represents
        let majorLabel: [Int: String]    // slot → date label, for major slots only
    }

    /// What the layout depends on. Hovering (which changes only `hoverY`) is
    /// deliberately absent, so a hover never invalidates the cache.
    private struct LayoutKey: Equatable {
        let count: Int
        let firstID: String?
        let lastID: String?
        let height: CGFloat
    }

    /// Memoizes the last `RulerLayout`. Computing it scans every result with
    /// `Calendar` to find day boundaries — cheap once, ruinous if repeated on every
    /// mouse-move while hovering a list of thousands. A reference type so `body` can
    /// refresh it without mutating `@State` (which would re-enter `body`).
    private final class LayoutCache {
        var key: LayoutKey?
        var layout: RulerLayout?
    }
    @State private var layoutCache = LayoutCache()

    /// The cached layout for this height, recomputed only when the results (by
    /// count and endpoints) or the height actually change.
    private func cachedLayout(height h: CGFloat) -> RulerLayout {
        let key = LayoutKey(count: results.count, firstID: results.first?.id,
                            lastID: results.last?.id, height: h)
        if layoutCache.key == key, let layout = layoutCache.layout { return layout }
        let computed = computeLayout(height: h)
        layoutCache.key = key
        layoutCache.layout = computed
        return computed
    }

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let layout = cachedLayout(height: h)
            let labelWidth = max(0, geo.size.width - majorTickLength - 8)

            ZStack(alignment: .topLeading) {
                // Ticks + date labels. Clipped to the container so ticks warped into
                // the reserved 10% margins slide off-screen (like Time Machine).
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        draw(ctx, size: size, height: h, layout: layout)
                    }

                    // Major date labels, right-aligned just left of their (warped) bar.
                    ForEach(Array(layout.majorLabel.keys), id: \.self) { slot in
                        Text(layout.majorLabel[slot] ?? "")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: labelWidth, alignment: .trailing)
                            .position(x: labelWidth / 2, y: warp(layout.slotY[slot], height: h))
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                // Hover label: "Yesterday at 23:59" styled exactly like the major
                // date dividers (same font/size/weight/colour), snapped to the centre
                // of the closest minor tick — except when the cursor is nearer a major
                // divider, where its own date label already sits, so we hide it. It's
                // right-aligned in the same column as the major labels (perfect edge
                // alignment) but grows leftward via fixedSize, and it sits outside the
                // clip above so a long label is never truncated.
                if let hoverY,
                   let snap = snappedMinorLabel(hoverY: hoverY, height: h, layout: layout) {
                    Text(snap.text)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: labelWidth, alignment: .trailing)
                        .position(x: labelWidth / 2, y: snap.y)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hoverY = point.y
                case .ended: hoverY = nil
                }
            }
            .gesture(
                // Live-scrub while pressing/dragging: the point under the cursor is a
                // fixed point of the fisheye warp, so the raw Y maps straight to a
                // fraction of the ruler — clicking or dragging anywhere travels the
                // list to exactly that continuous position.
                DragGesture(minimumDistance: 0)
                    .onChanged { onSeek(fraction(forY: $0.location.y, height: h)) }
                    .onEnded { onSeek(fraction(forY: $0.location.y, height: h)) }
            )
        }
    }

    // MARK: - Layout

    /// Build the uniform tick grid: evenly spaced slots mapped to results, with the
    /// date boundaries snapped onto slots as majors. Each date boundary lands on its
    /// nearest free slot, but consecutive majors are kept at least `labelGap` apart
    /// (in slot units) so their labels never stack — the price is a slightly
    /// approximate divider position, which is fine.
    private func computeLayout(height: CGFloat) -> RulerLayout {
        let count = results.count
        guard count > 0 else { return RulerLayout(slotCount: 0, slotY: [], resultIndex: [], majorLabel: [:]) }

        let top = edgeInset
        let bottom = max(top, height - edgeInset)
        let slotCount = max(1, min(count, Int(height / minorPitch)))

        var slotY = [CGFloat](repeating: 0, count: slotCount)
        var resultIndex = [Int](repeating: 0, count: slotCount)
        for j in 0..<slotCount {
            let frac = slotCount > 1 ? CGFloat(j) / CGFloat(slotCount - 1) : 0.5
            slotY[j] = top + (bottom - top) * frac
            let idx = slotCount > 1
                ? Int((Double(j) * Double(count - 1) / Double(slotCount - 1)).rounded())
                : 0
            resultIndex[j] = min(max(idx, 0), count - 1)
        }

        // Date boundaries (first result of each day), in order. Bucketing by local
        // day is pure arithmetic — one divide per result — because `Calendar`
        // (startOfDay/isDate) is ~100× slower and, over thousands of results, that
        // cost lands on the main thread and stalls the very first hover. The GMT
        // offset can be a few seconds stale across a DST flip, which at worst nudges
        // one divider by an hour: invisible on a date ruler.
        let dayOffset = Double(TimeZone.current.secondsFromGMT())
        var boundaries: [(index: Int, label: String)] = []
        var lastDayIndex: Int?
        for (index, r) in results.enumerated() {
            let dayIndex = Int((r.ts + dayOffset) / 86_400)
            if dayIndex != lastDayIndex {
                boundaries.append((index, dayLabel(for: r.ts)))
                lastDayIndex = dayIndex
            }
        }

        // Snap each boundary to its nearest slot, keeping consecutive majors at
        // least `gapSlots` apart. Forward pass pushes down; if it overflows the
        // bottom, a backward pass pulls the run back in.
        let pitch = slotCount > 1 ? (bottom - top) / CGFloat(slotCount - 1) : max(height, 1)
        let gapSlots = max(1, Int((labelGap / max(pitch, 0.001)).rounded(.up)))
        var slots = boundaries.map { b -> Int in
            slotCount > 1 ? Int((Double(b.index) * Double(slotCount - 1) / Double(count - 1)).rounded()) : 0
        }
        for i in 1..<max(slots.count, 1) where slots.count > 1 {
            slots[i] = max(slots[i], slots[i - 1] + gapSlots)
        }
        if let last = slots.last, last > slotCount - 1 {
            slots[slots.count - 1] = slotCount - 1
            for i in stride(from: slots.count - 2, through: 0, by: -1) {
                slots[i] = min(slots[i], slots[i + 1] - gapSlots)
            }
        }

        var majorLabel: [Int: String] = [:]
        for (b, slot) in zip(boundaries, slots) where slot >= 0 && slot < slotCount {
            majorLabel[slot] = b.label
        }
        return RulerLayout(slotCount: slotCount, slotY: slotY, resultIndex: resultIndex, majorLabel: majorLabel)
    }

    // MARK: - Drawing

    private func draw(_ ctx: GraphicsContext, size: CGSize, height: CGFloat, layout: RulerLayout) {
        let right = size.width
        for j in 0..<layout.slotCount {
            let dy = warp(layout.slotY[j], height: height)
            if layout.majorLabel[j] != nil {
                // Major date divider: a fixed-size wide bar sitting on the same grid.
                let rect = CGRect(x: right - majorTickLength, y: dy - majorThickness / 2,
                                  width: majorTickLength, height: majorThickness)
                ctx.fill(Path(roundedRect: rect, cornerRadius: majorThickness / 2),
                         with: .color(.primary.opacity(0.5)))
            } else {
                // Minor tick: grows in width + height with proximity to the cursor.
                let m = magnification(layout.slotY[j], height: height)
                let w = minorBaseWidth + m * minorMaxWidthExtra
                let tall = minorBaseHeight + m * minorMaxHeightExtra
                let rect = CGRect(x: right - w, y: dy - tall / 2, width: w, height: tall)
                ctx.fill(Path(roundedRect: rect, cornerRadius: majorThickness / 2),
                         with: .color(.primary.opacity(0.16 + m * 0.5)))
            }
        }
    }

    /// The minor tick nearest the cursor (compared in warped/screen space, so it
    /// matches what the eye sees) and its label. Returns nil when a major divider is
    /// closer than that minor tick — the divider carries its own date label there.
    private func snappedMinorLabel(hoverY: CGFloat, height: CGFloat,
                                   layout: RulerLayout) -> (y: CGFloat, text: String)? {
        var best: (slot: Int, y: CGFloat, dist: CGFloat)?
        var nearestMajorDist = CGFloat.greatestFiniteMagnitude
        for j in 0..<layout.slotCount {
            let wy = warp(layout.slotY[j], height: height)
            let dist = abs(wy - hoverY)
            if layout.majorLabel[j] != nil {
                nearestMajorDist = min(nearestMajorDist, dist)
            } else if best == nil || dist < best!.dist {
                best = (j, wy, dist)
            }
        }
        guard let minor = best, nearestMajorDist >= minor.dist else { return nil }
        return (minor.y, timeLabel(for: results[layout.resultIndex[minor.slot]].ts))
    }

    // MARK: - Fisheye geometry

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

    /// The click/drag Y as a clamped 0…1 fraction of the ruler's resting span — the
    /// tick band between the top and bottom insets.
    private func fraction(forY y: CGFloat, height: CGFloat) -> CGFloat {
        let top = edgeInset
        let bottom = max(top, height - edgeInset)
        guard bottom > top else { return 0 }
        return min(1, max(0, (y - top) / (bottom - top)))
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
