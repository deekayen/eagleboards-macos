import Foundation

/// A section of the operator's guide: its title and its paragraphs. The words
/// themselves belong to the Help window; this is how its search narrows them.
public struct HelpSection: Identifiable, Equatable, Sendable {
    public let title: String
    public let items: [String]
    public var id: String { title }

    public init(_ title: String, _ items: [String]) {
        self.title = title
        self.items = items
    }

    /// The paragraphs that hold every word searched for, in any order and
    /// ignoring case and accents, kept in their sections. A word may be in
    /// the section's title instead, so searching for a title shows the whole
    /// section. A section with nothing found is left out, and an empty search
    /// keeps everything.
    public static func matching(_ search: String, in sections: [HelpSection]) -> [HelpSection] {
        let words = search.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return sections }
        return sections.compactMap { section in
            let found = section.items.filter { item in
                words.allSatisfy { section.title.localizedStandardContains($0) || item.localizedStandardContains($0) }
            }
            return found.isEmpty ? nil : HelpSection(section.title, found)
        }
    }
}
