// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation

/// Formats absolute date+times as `dd/MM/yyyy HH:mm`, but with the day/month
/// order taken from the user's system locale (so it reads `MM/dd/yyyy HH:mm`
/// wherever month-first is the convention).
enum DateDisplay {
    /// Whether the user's locale writes the day before the month. Derived
    /// natively by asking the system for a day+month pattern and checking which
    /// field it places first.
    private static let dayBeforeMonth: Bool = {
        let template = DateFormatter.dateFormat(fromTemplate: "MMdd", options: 0, locale: .current) ?? "MM/dd"
        guard let dayIndex = template.firstIndex(of: "d"),
              let monthIndex = template.firstIndex(of: "M") else {
            return false
        }
        return dayIndex < monthIndex
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        // POSIX locale keeps the literal slashes and 24-hour clock regardless of
        // locale; only the day/month order is chosen from the system setting.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = dayBeforeMonth ? "dd/MM/yyyy HH:mm" : "MM/dd/yyyy HH:mm"
        return formatter
    }()

    static func absolute(_ date: Date) -> String {
        formatter.string(from: date)
    }
}
