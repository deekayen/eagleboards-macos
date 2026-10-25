import Accessibility
import EagleBoardsCore
import SwiftUI

/// Says a sentence to VoiceOver and puts nothing on screen (SPEC.md D-14):
/// a step that worked, an Undo, a sign-in at the door. The sentences are
/// built in EagleBoardsCore (`StepSpeech` and its neighbors); nothing here
/// decides what is said.
@MainActor
enum Speech {
    typealias Priority = AttributeScopes.AccessibilityAttributes.AnnouncementPriorityAttribute.AnnouncementPriority

    /// High for what the operator just did, which a focus change as a sheet
    /// closes must not cut off; low for what happened at the door meanwhile.
    static func say(_ text: String, priority: Priority = .default) {
        guard !text.isEmpty else { return }
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = priority
        AccessibilityNotification.Announcement(announcement).post()
    }
}

extension View {
    /// A title or section title VoiceOver's Headings rotor finds, at the
    /// levels Windows gives them: the youth, a sheet or the window first,
    /// their sections second.
    func heading(_ level: AccessibilityHeadingLevel) -> some View {
        accessibilityAddTraits(.isHeader).accessibilityHeading(level)
    }

    /// Once typing in the toolbar search pauses, say how many of the page's
    /// rows it leaves: "12 of 40 records". Only when the count changed, and
    /// never for a sign-in that adds a row.
    func speaksSearchCount(_ search: String, shown: Int, total: Int) -> some View {
        modifier(SearchCountSpeech(search: search, shown: shown, total: total))
    }
}

private struct SearchCountSpeech: ViewModifier {
    let search: String
    let shown: Int
    let total: Int
    @State private var lastSaid: String?

    func body(content: Content) -> some View {
        content.task(id: search) {
            guard !search.trimmingCharacters(in: .whitespaces).isEmpty else {
                lastSaid = nil
                return
            }
            guard (try? await Task.sleep(for: .milliseconds(400))) != nil else { return }
            let text = SearchSpeech.tableCount(shown: shown, total: total)
            guard text != lastSaid else { return }
            lastSaid = text
            Speech.say(text)
        }
    }
}

/// A read-only table cell's text, read "Blank" when it is empty, as Windows
/// names such a cell, rather than passed over in silence.
struct CellText: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value).accessibilityLabel(value.isEmpty ? "Blank" : value)
    }
}
