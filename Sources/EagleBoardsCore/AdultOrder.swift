import Foundation

extension Adult {
    /// Orders adults by last name, then first name, the way a person reads a
    /// list of names: ignoring case and using the Mac's locale, so "de Silva"
    /// sorts among the D's and "McDonald" beside "Mcdonald". The plain tuple
    /// comparison it replaces put every capital letter before every lowercase
    /// one. `PersonFind` orders its results the same way.
    ///
    /// - Returns: Whether `first` comes before `second`.
    public static func byName(_ first: Adult, _ second: Adult) -> Bool {
        let order = first.last.localizedCaseInsensitiveCompare(second.last)
        guard order == .orderedSame else { return order == .orderedAscending }
        return first.first.localizedCaseInsensitiveCompare(second.first) == .orderedAscending
    }
}
