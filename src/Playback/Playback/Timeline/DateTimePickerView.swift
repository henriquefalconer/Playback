// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import os
import SwiftUI
import SQLite3

/// A 15-minute slot in the time list. The label shows the slot boundary,
/// but jumping targets the earliest recording inside the slot so the
/// playhead never lands in a gap before the footage starts.
private struct TimeSlot: Identifiable, Equatable {
    let bucket: TimeInterval
    let jumpTime: TimeInterval

    var id: TimeInterval { bucket }
}

/// Shows the pointing-hand cursor while hovering, tracking push/pop balance
/// so the cursor is restored even if the view disappears mid-hover.
struct PointerCursor: ViewModifier {
    let isActive: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                guard isActive else { return }
                if inside && !pushed {
                    NSCursor.pointingHand.push()
                    pushed = true
                } else if !inside && pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

extension View {
    func pointerCursor(when isActive: Bool = true) -> some View {
        modifier(PointerCursor(isActive: isActive))
    }
}

/// Rounded rectangle with a centered downward arrow on the bottom edge,
/// drawn as one continuous outline so fill and stroke have no seam.
private struct PopoverArrowShape: Shape {
    let cornerRadius: CGFloat
    let arrowWidth: CGFloat
    let arrowHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = cornerRadius
        let bodyBottom = rect.maxY - arrowHeight
        let midX = rect.midX

        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: bodyBottom - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: bodyBottom - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: midX + arrowWidth / 2, y: bodyBottom))
        p.addLine(to: CGPoint(x: midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: midX - arrowWidth / 2, y: bodyBottom))
        p.addLine(to: CGPoint(x: rect.minX + r, y: bodyBottom))
        p.addArc(center: CGPoint(x: rect.minX + r, y: bodyBottom - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct DateTimePickerView: View {
    @EnvironmentObject var timelineStore: TimelineStore
    @Binding var isPresented: Bool
    @Binding var selectedTime: TimeInterval

    private static let slotInterval: TimeInterval = 15 * 60
    private static let arrowHeight: CGFloat = 12
    /// Distance from the window bottom to the arrow tip, tuned so the arrow
    /// points at the time pill sitting above the timeline bar.
    private static let bottomAnchorPadding: CGFloat = 112

    @State private var availableDates: Set<String> = []
    @State private var availableSlots: [TimeSlot] = []
    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    @State private var isLoading = false

    private let cardColor = Color(.sRGB, red: 0.13, green: 0.14, blue: 0.17, opacity: 0.97)

    /// 15-minute boundary containing the current playback time.
    private var currentBucket: TimeInterval {
        floor(selectedTime / Self.slotInterval) * Self.slotInterval
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 0) {
                Spacer()

                HStack(spacing: 0) {
                    calendarView
                        .frame(width: 300, height: 400)

                    Divider()
                        .overlay(Color.white.opacity(0.15))
                        .frame(height: 400)

                    timeListView
                        .frame(width: 200, height: 400)
                }
                .fixedSize()
                .padding(.bottom, Self.arrowHeight)
                .background(
                    PopoverArrowShape(cornerRadius: 12, arrowWidth: 24, arrowHeight: Self.arrowHeight)
                        .fill(cardColor)
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 8)
                )
                .overlay(
                    PopoverArrowShape(cornerRadius: 12, arrowWidth: 24, arrowHeight: Self.arrowHeight)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
            }
            .padding(.bottom, Self.bottomAnchorPadding)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            // Open on the date currently being viewed, not on today.
            if selectedTime > 0 {
                let viewedDate = Date(timeIntervalSince1970: selectedTime)
                selectedDate = viewedDate
                currentMonth = viewedDate
            }
            loadAvailableDates()
            loadAvailableTimesForSelectedDate()
        }
    }

    private var calendarView: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityIdentifier("datepicker.previousMonthButton")

                Text(monthYearString(currentMonth))
                    .font(.headline)

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityIdentifier("datepicker.nextMonthButton")

                Spacer()

                Button("Today") {
                    currentMonth = Date()
                    selectedDate = Date()
                    loadAvailableTimesForSelectedDate()
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .accessibilityIdentifier("datepicker.todayButton")
            }
            .padding(.horizontal)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.55))
                }

                ForEach(daysInMonth, id: \.self) { date in
                    if let date = date {
                        let dateString = dateFormatter.string(from: date)
                        let hasRecordings = availableDates.contains(dateString)

                        Button(action: {
                            selectedDate = date
                            loadAvailableTimesForSelectedDate()
                            jumpToFirstRecording(onDate: dateString)
                        }) {
                            Text("\(Calendar.current.component(.day, from: date))")
                                .font(.system(size: 14, weight: hasRecordings ? .bold : .regular))
                                .foregroundColor(hasRecordings ? .white : .white.opacity(0.3))
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(
                                            Calendar.current.isDate(date, inSameDayAs: selectedDate)
                                                ? Color.accentColor.opacity(0.5)
                                                : Color.clear
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasRecordings)
                        .pointerCursor(when: hasRecordings)
                        .accessibilityIdentifier("datepicker.dayButton.\(dateString)")
                    } else {
                        Color.clear
                            .frame(width: 32, height: 32)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

    private var timeListView: some View {
        VStack(spacing: 0) {
            Text(dayHeaderString(selectedDate))
                .font(.headline)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)

            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if availableSlots.isEmpty {
                Text("No recordings on this date")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(availableSlots) { slot in
                                timeSlotButton(slot)
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: availableSlots) { _, slots in
                        if slots.contains(where: { $0.bucket == currentBucket }) {
                            proxy.scrollTo(currentBucket, anchor: .center)
                        }
                    }
                    .onChange(of: currentBucket) { _, bucket in
                        if availableSlots.contains(where: { $0.bucket == bucket }) {
                            withAnimation {
                                proxy.scrollTo(bucket, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    private func timeSlotButton(_ slot: TimeSlot) -> some View {
        let isCurrent = slot.bucket == currentBucket

        return Button(action: {
            selectedTime = slot.jumpTime
        }) {
            HStack {
                Text(timeFormatter.string(from: Date(timeIntervalSince1970: slot.bucket)))
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isCurrent ? Color.accentColor.opacity(0.55) : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .id(slot.bucket)
        .accessibilityIdentifier("datepicker.timeButton.\(Int(slot.bucket))")
    }

    private var daysInMonth: [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: currentMonth),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: firstDay)

        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }

        return days
    }

    private func previousMonth() {
        if let newMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    private func nextMonth() {
        if let newMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newMonth
        }
    }

    private func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private func dayHeaderString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    private func loadAvailableDates() {
        DispatchQueue.global(qos: .userInitiated).async {
            var db: OpaquePointer?
            let dbPath = Paths.databasePath.path
            let rc = sqlite3_open(dbPath, &db)

            guard rc == SQLITE_OK, let db = db else {
                Log.timeline.error("DatePicker: failed to open database (rc=\(rc))")
                return
            }
            defer { sqlite3_close(db) }

            let query = "SELECT DISTINCT DATE(start_ts, 'unixepoch', 'localtime') FROM segments ORDER BY start_ts"
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                let errMsg = String(cString: sqlite3_errmsg(db))
                Log.timeline.debug("DatePicker: dates query failed — \(errMsg)")
                return
            }
            defer { sqlite3_finalize(stmt) }

            var dates: Set<String> = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cString = sqlite3_column_text(stmt, 0) {
                    dates.insert(String(cString: cString))
                }
            }

            DispatchQueue.main.async {
                self.availableDates = dates
            }
        }
    }

    /// Jumps playback to the first recording of the given day. The modal stays
    /// open — only clicking outside it (or ESC) dismisses it.
    private func jumpToFirstRecording(onDate dateString: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var db: OpaquePointer?
            let dbPath = Paths.databasePath.path
            let rc = sqlite3_open(dbPath, &db)

            guard rc == SQLITE_OK, let db = db else {
                Log.timeline.error("DatePicker: failed to open database for day jump (rc=\(rc))")
                return
            }
            defer { sqlite3_close(db) }

            let query = "SELECT MIN(start_ts) FROM segments WHERE DATE(start_ts, 'unixepoch', 'localtime') = ?"
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                let errMsg = String(cString: sqlite3_errmsg(db))
                Log.timeline.debug("DatePicker: day jump query failed — \(errMsg)")
                return
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (dateString as NSString).utf8String, -1, nil)

            guard sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL else {
                Log.timeline.debug("DatePicker: no recordings on \(dateString) — staying open")
                return
            }
            let firstTime = sqlite3_column_double(stmt, 0)

            DispatchQueue.main.async {
                self.selectedTime = firstTime
            }
        }
    }

    private func loadAvailableTimesForSelectedDate() {
        isLoading = true
        availableSlots = []

        let dateString = dateFormatter.string(from: selectedDate)

        DispatchQueue.global(qos: .userInitiated).async {
            var db: OpaquePointer?
            let dbPath = Paths.databasePath.path
            let rc = sqlite3_open(dbPath, &db)

            guard rc == SQLITE_OK, let db = db else {
                Log.timeline.error("DatePicker: failed to open database for times query (rc=\(rc))")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            defer { sqlite3_close(db) }

            let query = "SELECT start_ts FROM segments WHERE DATE(start_ts, 'unixepoch', 'localtime') = ? ORDER BY start_ts"
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
                let errMsg = String(cString: sqlite3_errmsg(db))
                Log.timeline.debug("DatePicker: times query failed — \(errMsg)")
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, (dateString as NSString).utf8String, -1, nil)

            var times: [TimeInterval] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let timestamp = sqlite3_column_double(stmt, 0)
                times.append(timestamp)
            }

            var earliestByBucket: [TimeInterval: TimeInterval] = [:]
            for time in times {
                let bucket = floor(time / Self.slotInterval) * Self.slotInterval
                earliestByBucket[bucket] = min(earliestByBucket[bucket] ?? time, time)
            }
            let slots = earliestByBucket
                .map { TimeSlot(bucket: $0.key, jumpTime: $0.value) }
                .sorted { $0.bucket < $1.bucket }

            DispatchQueue.main.async {
                self.availableSlots = slots
                self.isLoading = false
            }
        }
    }
}
