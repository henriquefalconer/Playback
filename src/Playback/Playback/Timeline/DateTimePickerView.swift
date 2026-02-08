// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI
import SQLite3

struct DateTimePickerView: View {
    @EnvironmentObject var timelineStore: TimelineStore
    @Binding var isPresented: Bool
    @Binding var selectedTime: TimeInterval

    @State private var availableDates: Set<String> = []
    @State private var availableTimes: [TimeInterval] = []
    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            HStack(spacing: 0) {
                calendarView
                    .frame(width: 300, height: 400)

                Divider()

                timeListView
                    .frame(width: 200, height: 400)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .onAppear {
            loadAvailableDates()
        }
    }

    private var calendarView: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("datepicker.previousMonthButton")

                Text(monthYearString(currentMonth))
                    .font(.headline)

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("datepicker.nextMonthButton")

                Spacer()

                Button("Today") {
                    currentMonth = Date()
                    selectedDate = Date()
                    loadAvailableTimesForSelectedDate()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("datepicker.todayButton")
            }
            .padding(.horizontal)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                ForEach(daysInMonth, id: \.self) { date in
                    if let date = date {
                        let dateString = dateFormatter.string(from: date)
                        let hasRecordings = availableDates.contains(dateString)

                        Button(action: {
                            selectedDate = date
                            loadAvailableTimesForSelectedDate()
                        }) {
                            Text("\(Calendar.current.component(.day, from: date))")
                                .font(.system(size: 14, weight: hasRecordings ? .bold : .regular))
                                .foregroundColor(hasRecordings ? .primary : .secondary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Calendar.current.isDate(date, inSameDayAs: selectedDate)
                                        ? Color.accentColor.opacity(0.3)
                                        : Color.clear
                                )
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasRecordings)
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
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if availableTimes.isEmpty {
                Text("No recordings on this date")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(availableTimes, id: \.self) { time in
                            Button(action: {
                                selectedTime = time
                                isPresented = false
                            }) {
                                HStack {
                                    Text(timeFormatter.string(from: Date(timeIntervalSince1970: time)))
                                        .font(.system(size: 14))
                                    Spacer()
                                    if abs(time - selectedTime) < 60 {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    abs(time - selectedTime) < 60
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.clear
                                )
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("datepicker.timeButton.\(Int(time))")
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("datepicker.cancelButton")

                Spacer()

                Button("Jump") {
                    if let time = availableTimes.first {
                        selectedTime = time
                    }
                    isPresented = false
                }
                .buttonStyle(.plain)
                .disabled(availableTimes.isEmpty)
                .accessibilityIdentifier("datepicker.jumpButton")
            }
            .padding(12)
        }
    }

    private var daysInMonth: [Date?] {
        let calendar = Calendar.current
        let range = calendar.range(of: .day, in: .month, for: currentMonth)!
        let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
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
                return
            }
            defer { sqlite3_close(db) }

            let query = "SELECT DISTINCT DATE(start_ts, 'unixepoch', 'localtime') FROM segments ORDER BY start_ts"
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
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

    private func loadAvailableTimesForSelectedDate() {
        isLoading = true
        availableTimes = []

        let dateString = dateFormatter.string(from: selectedDate)

        DispatchQueue.global(qos: .userInitiated).async {
            var db: OpaquePointer?
            let dbPath = Paths.databasePath.path
            let rc = sqlite3_open(dbPath, &db)

            guard rc == SQLITE_OK, let db = db else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }
            defer { sqlite3_close(db) }

            let query = "SELECT start_ts FROM segments WHERE DATE(start_ts, 'unixepoch', 'localtime') = ? ORDER BY start_ts"
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
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

            let roundedTimes = times.map { time -> TimeInterval in
                let interval: TimeInterval = 15 * 60
                return floor(time / interval) * interval
            }

            let uniqueTimes = Array(Set(roundedTimes)).sorted()

            DispatchQueue.main.async {
                self.availableTimes = uniqueTimes
                self.isLoading = false
            }
        }
    }
}
