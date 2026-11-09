import Foundation

public struct ClockZone: Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var showLabel: Bool
    public init(id: String, label: String, showLabel: Bool = true) {
        self.id = id; self.label = label; self.showLabel = showLabel
    }

    private enum CodingKeys: String, CodingKey { case id, label, showLabel }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        label = try values.decode(String.self, forKey: .label)
        showLabel = try values.decodeIfPresent(Bool.self, forKey: .showLabel) ?? true
    }

    public func displayText(time: String) -> String {
        showLabel ? "\(label) \(time)" : time
    }
}

public enum ClockFont: String, Codable {
    case system
    case monospaced
}

public enum ClockLanguage: String, Codable {
    case simplifiedChinese
    case english
    public var locale: Locale { Locale(identifier: self == .english ? "en_US_POSIX" : "zh_CN") }
    public func text(_ chinese: String, _ english: String) -> String { self == .english ? english : chinese }
}

public enum ClockSeparator: String, Codable, CaseIterable {
    case dot, pipe, dash, space
    public var text: String {
        switch self {
        case .dot: return " · "
        case .pipe: return " | "
        case .dash: return " - "
        case .space: return "  "
        }
    }
}

public struct ZoneComparison {
    public var offsetSeconds: Int
    public var dayDifference: Int
}

public struct ClockSettings: Codable, Equatable {
    public var zones: [ClockZone]
    public var format: String
    public var language: ClockLanguage = .simplifiedChinese
    public var separator: ClockSeparator = .dot
    public var automaticallyAdjustDST = true
    public var fixedOffsets: [String: Int] = [:]
    public var showCalendar = true
    public var font: ClockFont
    public init(zones: [ClockZone], format: String, font: ClockFont = .system) {
        self.zones = zones; self.format = format; self.font = font
    }

    private enum CodingKeys: String, CodingKey { case zones, format, font, language, separator, automaticallyAdjustDST, fixedOffsets, showCalendar }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        zones = try values.decode([ClockZone].self, forKey: .zones)
        format = try values.decode(String.self, forKey: .format)
        font = try values.decodeIfPresent(ClockFont.self, forKey: .font) ?? .system
        language = try values.decodeIfPresent(ClockLanguage.self, forKey: .language) ?? .simplifiedChinese
        separator = try values.decodeIfPresent(ClockSeparator.self, forKey: .separator) ?? .dot
        automaticallyAdjustDST = try values.decodeIfPresent(Bool.self, forKey: .automaticallyAdjustDST) ?? true
        fixedOffsets = try values.decodeIfPresent([String: Int].self, forKey: .fixedOffsets) ?? [:]
        showCalendar = try values.decodeIfPresent(Bool.self, forKey: .showCalendar) ?? true
    }
    public static let defaults = ClockSettings(zones: [ClockZone(id: "Asia/Shanghai", label: "上海"), ClockZone(id: "America/Los_Angeles", label: "洛杉矶")], format: "HH:mm")

    public func normalized(at date: Date = Date()) -> ClockSettings {
        var seen = Set<String>()
        let valid = zones.compactMap { zone -> ClockZone? in
            guard TimeZone(identifier: zone.id) != nil, seen.insert(zone.id).inserted else { return nil }
            let label = zone.label.components(separatedBy: .controlCharacters).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            return ClockZone(id: zone.id, label: label.isEmpty ? String(zone.id.split(separator: "/").last ?? "UTC").replacingOccurrences(of: "_", with: " ") : String(label.prefix(24)), showLabel: zone.showLabel)
        }
        let pattern = format.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = self
        result.zones = valid.isEmpty ? Self.defaults.zones : valid
        result.format = pattern.isEmpty ? "HH:mm" : String(pattern.prefix(100))
        result.fixedOffsets = [:]
        if !automaticallyAdjustDST {
            for zone in result.zones {
                if let offset = fixedOffsets[zone.id], TimeZone(secondsFromGMT: offset) != nil {
                    result.fixedOffsets[zone.id] = offset
                } else {
                    result.fixedOffsets[zone.id] = TimeZone(identifier: zone.id)!.secondsFromGMT(for: date)
                }
            }
        }
        return result
    }

    public mutating func setAutomaticallyAdjustDST(_ enabled: Bool, at date: Date = Date()) {
        automaticallyAdjustDST = enabled
        fixedOffsets = [:]
        if !enabled {
            for zone in zones { fixedOffsets[zone.id] = TimeZone(identifier: zone.id)?.secondsFromGMT(for: date) ?? 0 }
        }
    }

    public func timeZone(for zone: ClockZone) -> TimeZone {
        if !automaticallyAdjustDST, let offset = fixedOffsets[zone.id], let fixed = TimeZone(secondsFromGMT: offset) { return fixed }
        return TimeZone(identifier: zone.id) ?? TimeZone(secondsFromGMT: 0)!
    }

    public func comparison(for zone: ClockZone, at date: Date) -> ZoneComparison {
        let reference = timeZone(for: zones.first ?? zone)
        let target = timeZone(for: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = reference
        let referenceDay = calendar.dateComponents([.year, .month, .day], from: date)
        calendar.timeZone = target
        let targetDay = calendar.dateComponents([.year, .month, .day], from: date)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let days = calendar.dateComponents([.day], from: calendar.date(from: referenceDay)!, to: calendar.date(from: targetDay)!).day ?? 0
        return ZoneComparison(offsetSeconds: target.secondsFromGMT(for: date) - reference.secondsFromGMT(for: date), dayDifference: days)
    }

    /// Ignore quoted literals when deciding whether the display needs seconds.
    public var refreshInterval: TimeInterval {
        let characters = Array(format)
        var quoted = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "'" {
                if index + 1 < characters.count && characters[index + 1] == "'" { index += 2; continue }
                quoted.toggle()
            } else if !quoted && "sSA".contains(character) { return 1 }
            index += 1
        }
        return 60
    }

    public func nextRefresh(after date: Date) -> Date {
        let interval = refreshInterval
        return Date(timeIntervalSince1970: (floor(date.timeIntervalSince1970 / interval) + 1) * interval)
    }

    public func formatter(for zone: ClockZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone(for: zone)
        formatter.dateFormat = format
        return formatter
    }

    public func title(at date: Date) -> String {
        zones.map { $0.displayText(time: formatter(for: $0).string(from: date)) }.joined(separator: separator.text)
    }
}

/// Owned by one UI store; updated only when preferences change.
public final class ClockRenderer {
    private struct Key: Hashable { let zone: String; let format: String }
    private var settings: ClockSettings
    private var formatters: [Key: DateFormatter] = [:]

    public init(settings: ClockSettings) { self.settings = settings }

    public func update(_ settings: ClockSettings) {
        guard self.settings != settings else { return }
        self.settings = settings
        formatters.removeAll(keepingCapacity: true)
    }

    public func string(for zone: ClockZone, at date: Date, format: String? = nil) -> String {
        let pattern = format ?? settings.format
        let key = Key(zone: zone.id, format: pattern)
        if let formatter = formatters[key] { return formatter.string(from: date) }
        var configuration = settings
        configuration.format = pattern
        let formatter = configuration.formatter(for: zone)
        formatters[key] = formatter
        return formatter.string(from: date)
    }

    public func title(at date: Date) -> String {
        settings.zones.map { $0.displayText(time: string(for: $0, at: date)) }.joined(separator: settings.separator.text)
    }
}
