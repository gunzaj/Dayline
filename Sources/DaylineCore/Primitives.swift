import Foundation

// MARK: - Time primitives

/// Minutes since midnight, independent of any date.
public struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    public var minutes: Int

    public init(_ minutes: Int) {
        self.minutes = max(0, min(24 * 60 - 1, minutes))
    }

    public init(hour: Int, minute: Int = 0) {
        self.init(hour * 60 + minute)
    }

    /// Parses "09:00" or "09:00:00".
    public init?(_ string: String) {
        let parts = string.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        self.init(hour: h, minute: m)
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }
    public var display: String { String(format: "%02d:%02d", hour, minute) }

    public func date(on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool { lhs.minutes < rhs.minutes }

    public static func now(_ date: Date = Date(), calendar: Calendar = .current) -> TimeOfDay {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }
}

public struct TimeRange: Codable, Hashable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = min(start, end)
        self.end = max(start, end)
    }

    public var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
    public var isValid: Bool { end > start }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }
    public func overlaps(_ other: TimeRange) -> Bool { start < other.end && other.start < end }

    public func intersection(_ other: TimeRange) -> TimeRange? {
        let s = max(start, other.start), e = min(end, other.end)
        return e > s ? TimeRange(start: s, end: e) : nil
    }

    public static func minutesBetween(_ a: Date, _ b: Date) -> Int {
        max(0, Int(b.timeIntervalSince(a) / 60))
    }
}

// MARK: - Day keys

public enum DayKey {
    public static func make(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    public static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        return calendar.date(from: c)
    }

    public static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func adding(days: Int, to date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    public static func weekday(_ date: Date, calendar: Calendar = .current) -> Int {
        // 1 = Sunday ... 7 = Saturday
        calendar.component(.weekday, from: date)
    }

    public static func isWeekend(_ date: Date, calendar: Calendar = .current) -> Bool {
        let w = weekday(date, calendar: calendar)
        return w == 1 || w == 7
    }

    /// Monday-based index 0...4 for a weekday.
    public static func mondayIndex(_ date: Date, calendar: Calendar = .current) -> Int {
        (weekday(date, calendar: calendar) + 5) % 7
    }

    public static func monday(of date: Date, calendar: Calendar = .current) -> Date {
        let idx = mondayIndex(date, calendar: calendar)
        return adding(days: -idx, to: startOfDay(date, calendar: calendar), calendar: calendar)
    }
}

// MARK: - Small formatting helpers

public enum Fmt {
    public static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    public static let weekdayShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    public static let weekdayLong: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    public static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    public static let dayMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    public static let monthShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    public static func duration(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return "\(m) min" }
        let h = m / 60, rem = m % 60
        return rem == 0 ? "\(h) h" : "\(h) h \(rem) min"
    }

    public static func compactDuration(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return "\(m)m" }
        let h = m / 60, rem = m % 60
        return rem == 0 ? "\(h)h" : "\(h)h \(rem)m"
    }
}

extension Date {
    public func adding(minutes: Int) -> Date { addingTimeInterval(TimeInterval(minutes * 60)) }
    public func adding(minutes: Double) -> Date { addingTimeInterval(minutes * 60) }
    public func adding(days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: self) ?? self
    }
    public var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    public var dayKey: String { DayKey.make(self) }
}

// MARK: - Identifiers

public enum IDGen {
    public static func make(_ prefix: String) -> String {
        prefix + "-" + UUID().uuidString.prefix(8).lowercased()
    }
}
