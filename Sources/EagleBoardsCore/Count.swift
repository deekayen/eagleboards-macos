/// Numbers as the screen writes them and VoiceOver reads them: a count with
/// its noun, singular or plural, never "1 adults" or "member(s)"; minutes in
/// full, never "min", which is read as minimum; and an ordinal, "the 3rd",
/// where "#3" is read as "number sign 3". The same as `Display.Count`,
/// `Display.Minutes` and `Display.Ordinal` in the Windows version.
///
/// The app's text is English only, so the ordinal is English whatever the
/// Mac's language: a formatter in the user's locale would put "3." or "3e"
/// inside an English sentence.
public enum Count {
    /// "1 member", "2 members", "0 members".
    public static func of(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }

    /// "1 minute", "12 minutes".
    public static func minutes(_ count: Int) -> String {
        of(count, "minute", "minutes")
    }

    /// "1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "22nd".
    public static func ordinal(_ number: Int) -> String {
        let suffix: String
        switch (number % 100, number % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(number)\(suffix)"
    }
}
