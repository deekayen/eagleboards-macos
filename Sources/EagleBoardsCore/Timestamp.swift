import Foundation

/// The two date shapes the data files use, parsed and written by hand so they
/// never depend on the machine's locale.
///
///   RegTime / LastUpdateTime   `2026-09-22_19:05-0400`   (Java `yyyy-MM-dd_HH:mmZ`)
///   event folder name          `2026-09-22`
public enum Timestamp {
    private static let calendar = Calendar(identifier: .gregorian)

    /// `2026-09-22_19:05-0400`, in the Mac's current time zone.
    public static func recordStamp(for date: Date, timeZone: TimeZone = .current) -> String {
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        let parts = localCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let offsetSeconds = timeZone.secondsFromGMT(for: date)
        let offsetSign = offsetSeconds < 0 ? "-" : "+"
        let offsetMinutesTotal = abs(offsetSeconds) / 60
        return String(
            format: "%04d-%02d-%02d_%02d:%02d%@%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0,
            offsetSign, offsetMinutesTotal / 60, offsetMinutesTotal % 60
        )
    }

    /// Parses a `recordStamp`. Returns nil for anything else, including the
    /// empty string, exactly where the Java app's parse would have failed.
    public static func date(fromRecordStamp stamp: String) -> Date? {
        let characters = Array(stamp.trimmingCharacters(in: .whitespaces))
        guard characters.count == 21,
              characters[4] == "-", characters[7] == "-", characters[10] == "_", characters[13] == ":",
              characters[16] == "+" || characters[16] == "-"
        else { return nil }

        func number(_ range: Range<Int>) -> Int? {
            Int(String(characters[range]))
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16),
              let offsetHours = number(17..<19), let offsetMinutes = number(19..<21),
              let zone = TimeZone(secondsFromGMT: (characters[16] == "-" ? -1 : 1) * (offsetHours * 3600 + offsetMinutes * 60))
        else { return nil }

        var zonedCalendar = calendar
        zonedCalendar.timeZone = zone
        return zonedCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    /// Whole minutes from `stamp` to `now`, or nil when the stamp is unreadable.
    /// This is the number the room timers run on.
    public static func minutesSince(recordStamp stamp: String, now: Date) -> Int? {
        guard let then = date(fromRecordStamp: stamp) else { return nil }
        return Int(now.timeIntervalSince(then) / 60)
    }

    /// The start of the minute after `date`. Record stamps fall on whole
    /// minutes, so this is when every room timer next goes up by one, and
    /// when the overdue check next has anything new to find (SPEC.md D-15).
    public static func nextMinute(after date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60 + 60)
    }

    /// `19:05` out of a record stamp, for the sign-in list.
    public static func hourMinute(ofRecordStamp stamp: String) -> String {
        let characters = Array(stamp)
        guard characters.count >= 16 else { return "" }
        return String(characters[11..<16])
    }

    /// `2026-09-22`: the name of an event's folder, and the stamp added
    /// to an adult's board history.
    public static func dayStamp(for date: Date, timeZone: TimeZone = .current) -> String {
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        let parts = localCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `2026-09`: SignUpGenius entries are filtered by calendar month, as the
    /// Java app did, so two board events in one month both import.
    public static func monthStamp(for date: Date, timeZone: TimeZone = .current) -> String {
        String(dayStamp(for: date, timeZone: timeZone).prefix(7))
    }

    /// An event's date as the Mac writes dates, "October 24, 2026" in the
    /// US: the long date style, which has no weekday, in `locale`'s order and
    /// words. Folder and export names stay stamps. Anything that is not a
    /// `dayStamp`, or not a real date, comes back as it was.
    public static func shownDate(_ stamp: String, locale: Locale = .current) -> String {
        guard isDayStamp(stamp),
              let year = Int(stamp.prefix(4)), let month = Int(stamp.dropFirst(5).prefix(2)), let day = Int(stamp.suffix(2))
        else { return stamp }
        // Midday UTC, written in UTC, so no time zone can move it to another day.
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = DateComponents(year: year, month: month, day: day, hour: 12)
        guard parts.isValidDate(in: utcCalendar), let date = utcCalendar.date(from: parts) else { return stamp }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = utcCalendar.timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Is `name` shaped like an event folder (`YYYY-MM-DD`)?
    public static func isDayStamp(_ name: String) -> Bool {
        let characters = Array(name)
        guard characters.count == 10, characters[4] == "-", characters[7] == "-" else { return false }
        return characters.enumerated().allSatisfy { position, character in
            position == 4 || position == 7 || character.isASCII && character.isNumber
        }
    }
}
