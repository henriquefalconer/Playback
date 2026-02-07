// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let component: String
    let message: String
    let metadata: [String: String]?
    let exception: String?

    enum LogLevel: String, Codable, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case critical = "CRITICAL"

        var color: String {
            switch self {
            case .debug: return "gray"
            case .info: return "blue"
            case .warning: return "yellow"
            case .error: return "orange"
            case .critical: return "red"
            }
        }

        var icon: String {
            switch self {
            case .debug: return "ant.circle"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            case .critical: return "exclamationmark.octagon"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case timestamp, level, component, message, metadata, exception
    }

    init(id: UUID = UUID(), timestamp: Date, level: LogLevel, component: String, message: String, metadata: [String: String]? = nil, exception: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.component = component
        self.message = message
        self.metadata = metadata
        self.exception = exception
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = UUID()

        let timestampString = try container.decode(String.self, forKey: .timestamp)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestampString) {
            self.timestamp = date
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            self.timestamp = formatter.date(from: timestampString) ?? Date()
        }

        let levelString = try container.decode(String.self, forKey: .level)
        self.level = LogLevel(rawValue: levelString) ?? .info

        self.component = try container.decode(String.self, forKey: .component)
        self.message = try container.decode(String.self, forKey: .message)
        self.metadata = try container.decodeIfPresent([String: AnyCodable].self, forKey: .metadata)?.mapValues { $0.stringValue }
        self.exception = try container.decodeIfPresent(String.self, forKey: .exception)
    }
}

struct AnyCodable: Codable {
    let value: Any

    var stringValue: String {
        if let string = value as? String {
            return string
        } else if let number = value as? NSNumber {
            return number.stringValue
        } else if let bool = value as? Bool {
            return bool ? "true" : "false"
        } else if let dict = value as? [String: Any] {
            return dict.description
        } else if let array = value as? [Any] {
            return array.description
        } else {
            return String(describing: value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encode(String(describing: value))
        }
    }
}
