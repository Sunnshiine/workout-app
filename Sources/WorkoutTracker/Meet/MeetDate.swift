import Foundation

/// A Meet's day on the calendar, not an instant, so a flight across time zones or a look at the
/// phone near midnight never moves it.
struct MeetDate: Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    /// Reads `2026-12-05`. Rejects a day the calendar does not have.
    init?(_ text: String) {
        let parts = text.trimmed.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2] else { return nil }
        self.init(year: year, month: month, day: day)
    }

    init?(year: Int, month: Int, day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    init(containing instant: Date, in calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        // A Gregorian calendar always names a real day for an instant.
        year = components.year ?? 1
        month = components.month ?? 1
        day = components.day ?? 1
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Whole days from the calendar day `now` falls on to this one: 0 is today, negative is past.
    func daysUntil(from now: Date, in calendar: Calendar) -> Int {
        let today = MeetDate(containing: now, in: calendar)
        var fixed = Calendar(identifier: .gregorian)
        fixed.timeZone = .gmt
        guard
            let from = fixed.date(from: DateComponents(year: today.year, month: today.month, day: today.day)),
            let to = fixed.date(from: DateComponents(year: year, month: month, day: day))
        else { return 0 }
        return fixed.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// The noon of this day in `calendar`, which a date picker and a formatter can show safely.
    func noon(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    /// `Today`, `Tomorrow`, `In 29 days`, `Yesterday`, `3 days ago`.
    func countdownLabel(from now: Date, in calendar: Calendar) -> String {
        let days = daysUntil(from: now, in: calendar)
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case ..<0: return "\(-days) days ago"
        default: return "In \(days) days"
        }
    }
}

extension MeetDate: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = MeetDate(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(text) is not a calendar day.")
        }
        self = date
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
