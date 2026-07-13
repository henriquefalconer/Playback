import SwiftUI
import AppKit
import CoreImage
import os

// Extension to obtain an average color from an icon using only native APIs (CoreImage).
extension NSImage {
    var averageColor: NSColor? {
        guard
            let tiffData = self.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let cgImage = bitmap.cgImage
        else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent

        guard let filter = CIFilter(name: "CIAreaAverage") else {
            return nil
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)

        guard let outputImage = filter.value(forKey: kCIOutputImageKey) as? CIImage else {
            return nil
        }

        let context = CIContext(options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull()
        ])

        var bitmapData = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
            toBitmap: &bitmapData,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let r = CGFloat(bitmapData[0]) / 255.0
        let g = CGFloat(bitmapData[1]) / 255.0
        let b = CGFloat(bitmapData[2]) / 255.0
        let a = CGFloat(bitmapData[3]) / 255.0

        return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }
}

/// Helper shape to shift the click area vertically relative to the bar,
/// without changing the visual position of the segments.
struct ExpandedVerticalHitShape: Shape {
    let extra: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Move the hit area down by `extra` points, keeping the same size.
        let shifted = rect.offsetBy(dx: 0, dy: extra)
        path.addRect(shifted)
        return path
    }
}

struct TimelineView: View {
    @EnvironmentObject var timelineStore: TimelineStore
    @EnvironmentObject var playbackController: PlaybackController

    @Binding var centerTime: TimeInterval
    @Binding var visibleWindowSeconds: TimeInterval
    @Binding var showDatePicker: Bool

    @GestureState private var dragTranslation: CGFloat = 0
    @State private var dragStartCenterTime: TimeInterval?

    private var windowSpan: (start: TimeInterval, end: TimeInterval) {
        let half = visibleWindowSeconds / 2
        let windowStart = centerTime - half
        let windowEnd = centerTime + half
        return (windowStart, windowEnd)
    }

    private var visibleAppSegments: [AppSegment] {
        let range = windowSpan
        return timelineStore.appSegments.filter { seg in
            seg.endTS >= range.start && seg.startTS <= range.end
        }
    }

    private func formattedTimestamp(_ time: TimeInterval) -> String {
        let now = Date().timeIntervalSince1970
        let delta = max(0, now - time)

        if delta < 1 {
            return "Now"
        } else if delta < 60 {
            let seconds = Int(delta)
            return seconds == 1 ? "1 second ago" : "\(seconds) seconds ago"
        } else if delta < 3600 {
            let minutes = Int(delta / 60)
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else if delta < 24 * 3600 {
            let hours = Int(delta / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }

        let date = Date(timeIntervalSince1970: time)
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private static var appNameCache: [String: String] = [:]

    private func appDisplayName(for appId: String) -> String {
        if let cached = Self.appNameCache[appId] {
            return cached
        }
        var name: String
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appId) {
            name = url.deletingPathExtension().lastPathComponent
        } else {
            name = appId.components(separatedBy: ".").last ?? appId
        }
        Self.appNameCache[appId] = name
        return name
    }

    private static var appIconCache: [String: NSImage] = [:]

    private func appIcon(for appId: String) -> Image? {
        if let cached = Self.appIconCache[appId] {
            return Image(nsImage: cached)
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appId) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 18, height: 18)
        Self.appIconCache[appId] = icon
        return Image(nsImage: icon)
    }

    private static var appColorCache: [String: Color] = [:]

    /// "Representative" color of the app, natively derived from the app icon.
    private func appColor(for appId: String) -> Color {
        if let cached = Self.appColorCache[appId] {
            return cached
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appId) else {
            return Color.blue
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)

        let color: Color
        if let avg = icon.averageColor {
            let targetBrightness: CGFloat = 0.70
            let minSaturation: CGFloat = 0.80

            let rgbColor = avg.usingColorSpace(.deviceRGB) ?? avg
            let h = rgbColor.hueComponent
            let s = rgbColor.saturationComponent
            let b = rgbColor.brightnessComponent
            let a = rgbColor.alphaComponent

            let boostedSaturation: CGFloat = s < 0.25 ? 1.0 : max(s, minSaturation)
            let boostedBrightness: CGFloat = max(b, targetBrightness)

            let vibrant = NSColor(
                calibratedHue: h,
                saturation: boostedSaturation,
                brightness: boostedBrightness,
                alpha: max(a, 1.0)
            )
            color = Color(nsColor: vibrant)
        } else {
            color = .blue
        }

        Self.appColorCache[appId] = color
        return color
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * 0.8
            let height: CGFloat = 20
            let barY = geo.size.height - height / 2 - 8
            let segmentsY = barY + 22
            let span = windowSpan
            let windowStart = span.start
            let pixelsPerSecond = width / visibleWindowSeconds
            let currentTime = playbackController.currentTime

            ZStack {
                // Time ticks and labels
                TimeTicksView(
                    windowStart: windowStart,
                    windowEnd: span.end,
                    visibleWindowSeconds: visibleWindowSeconds,
                    width: width,
                    barY: barY
                )

                // Appsegments with size proportional to absolute duration
                ZStack {
                    ForEach(visibleAppSegments, id: \.id) { (segment: AppSegment) in
                        let segStartX = CGFloat(segment.startTS - windowStart) * pixelsPerSecond
                        let segWidth = max(6, CGFloat(segment.endTS - segment.startTS) * pixelsPerSecond)
                        let segCenterX = segStartX + segWidth / 2

                        let baseColor = segment.appId.map { appColor(for: $0) } ?? Color.blue
                        let isCurrentTimeInside = currentTime >= segment.startTS && currentTime <= segment.endTS
                        let opacity = isCurrentTimeInside ? 0.865 : 0.65

                        ZStack {
                            RoundedRectangle(cornerRadius: height / 2)
                                .fill(baseColor.opacity(opacity))
                                .frame(width: segWidth, height: height)

                            if let appId = segment.appId,
                               let icon = appIcon(for: appId) {
                                icon
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                            }
                        }
                        .position(x: segCenterX, y: height / 2)
                    }
                }
                .frame(width: width, height: height)
                .position(x: geo.size.width / 2, y: segmentsY)

                // Playhead central
                RoundedRectangle(cornerRadius: 999)
                    .fill(Color.white)
                    .frame(width: 4, height: 110)
                    .position(x: geo.size.width / 2, y: barY + 48)

                // Timestamp bubble
                Button(action: {
                    showDatePicker = true
                }) {
                    VStack(spacing: 2) {
                        Text(formattedTimestamp(currentTime))
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.92))
                    )
                    .foregroundColor(.black)
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .position(x: geo.size.width / 2, y: barY - 32)
                .accessibilityIdentifier("timeline.timeBubbleButton")
            }
            .contentShape(ExpandedVerticalHitShape(extra: 20))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let rawLocation = value.location
                        let geoWidth = geo.size.width
                        let leftEdgeX = (geoWidth - width) / 2
                        Log.timeline.debug("Click/drag ended. rawLocation=\(rawLocation.debugDescription), geoWidth=\(geoWidth), width=\(width), leftEdgeX=\(leftEdgeX)")

                        let localX = max(0, min(rawLocation.x - leftEdgeX, width))
                        Log.timeline.debug("  localX (adjusted)=\(localX)")

                        var newTime = windowStart + TimeInterval(localX / width) * visibleWindowSeconds
                        Log.timeline.debug("  newTime (before clamp)=\(newTime), windowStart=\(windowStart), visibleWindowSeconds=\(visibleWindowSeconds)")

                        if let start = timelineStore.timelineStart {
                            newTime = max(start, newTime)
                        }
                        if let end = timelineStore.timelineEnd {
                            newTime = min(end, newTime)
                        }

                        Log.timeline.debug("  newTime (after clamp)=\(newTime)")

                        playbackController.scrub(to: newTime, store: timelineStore)
                        Log.timeline.debug("  playbackController.currentTime after scrub=\(playbackController.currentTime)")
                        centerTime = playbackController.currentTime
                        Log.timeline.debug("  centerTime updated=\(centerTime)")
                    }
            )
        }
    }
}

struct TimeTicksView: View {
    let windowStart: TimeInterval
    let windowEnd: TimeInterval
    let visibleWindowSeconds: TimeInterval
    let width: CGFloat
    let barY: CGFloat

    private var tickInterval: TimeInterval {
        if visibleWindowSeconds <= 180 {
            return 10
        } else if visibleWindowSeconds <= 600 {
            return 30
        } else if visibleWindowSeconds <= 1200 {
            return 60
        } else if visibleWindowSeconds <= 2400 {
            return 300
        } else {
            return 600
        }
    }

    private var ticks: [TimeInterval] {
        let start = (windowStart / tickInterval).rounded(.down) * tickInterval
        var result: [TimeInterval] = []
        var current = start

        while current <= windowEnd {
            if current >= windowStart {
                result.append(current)
            }
            current += tickInterval
        }

        return result
    }

    var body: some View {
        ZStack {
            ForEach(ticks, id: \.self) { tick in
                let offset = tick - windowStart
                let x = (offset / visibleWindowSeconds) * width

                VStack(spacing: 2) {
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 1, height: isMajorTick(tick) ? 12 : 6)

                    if isMajorTick(tick) {
                        Text(formatTime(tick))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .position(x: x, y: barY + 60)
            }
        }
        .frame(width: width)
    }

    private func isMajorTick(_ time: TimeInterval) -> Bool {
        let majorInterval = tickInterval * 5
        return (time / majorInterval).truncatingRemainder(dividingBy: 1) == 0
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: time)
        let formatter = DateFormatter()
        formatter.dateFormat = tickInterval < 300 ? "h:mm a" : "h a"
        return formatter.string(from: date)
    }
}
