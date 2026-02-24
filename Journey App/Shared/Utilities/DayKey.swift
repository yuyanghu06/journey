import Foundation

// MARK: - DayKey
// A local-timezone calendar date in YYYY-MM-DD format.
// Used as the primary identifier to scope all chat and journal data
// to a single calendar day (midnight-to-midnight, user's local timezone).

struct DayKey: RawRepresentable, Hashable, Codable, CustomStringConvertible, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ string: String) { self.rawValue = string }
    init(stringLiteral value: StringLiteralType) { self.rawValue = value }

    var description: String { rawValue }

    // MARK: - Factory

    /// Returns a DayKey for today in the user's local timezone.
    static var today: DayKey {
        DayKey(rawValue: Self.formatter.string(from: Date()))
    }

    /// Constructs a DayKey from any Date using the user's local timezone.
    static func from(_ date: Date) -> DayKey {
        DayKey(rawValue: Self.formatter.string(from: date))
    }

    // MARK: - Conversion

    /// Parses this DayKey back to a midnight Date in the local timezone.
    /// Returns nil if the string is malformed.
    var date: Date? {
        Self.formatter.date(from: rawValue)
    }

    /// Human-readable display string, e.g. "Monday, March 3".
    var displayString: String {
        guard let d = date else { return rawValue }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        f.locale = .autoupdatingCurrent
        f.timeZone = .current
        return f.string(from: d)
    }

    // MARK: - Private

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
