import SwiftUI

/// A refusal from the step a sheet's button took, shown in the sheet. An
/// alert would wait behind the sheet until it closed. VoiceOver reads it as
/// it appears, and again for a new one; keyboard focus stays on the button,
/// so Return tries again once it is fixed.
struct SheetProblem: View {
    let text: String

    var body: some View {
        NoticeLabel.problem(text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: text) { Speech.say(text, priority: .high) }
    }
}
