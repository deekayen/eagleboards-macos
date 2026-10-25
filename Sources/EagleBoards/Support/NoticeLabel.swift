import SwiftUI

/// A refusal, a warning or a confirmation: the symbol in its color, the words
/// in the style around them (primary in a row, secondary in a footer). System
/// orange, red and green text falls short of the contrast body text needs on
/// a light background; the symbol keeps the color, and its shape says which
/// kind of notice it is.
struct NoticeLabel: View {
    let text: String
    let systemImage: String
    let tint: Color

    init(_ text: String, systemImage: String, tint: Color) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(tint)
        }
    }
}

extension NoticeLabel {
    /// Something that stops the step.
    static func problem(_ text: String) -> NoticeLabel {
        NoticeLabel(text, systemImage: "xmark.octagon.fill", tint: .red)
    }

    /// Something worth a second look.
    static func warning(_ text: String) -> NoticeLabel {
        NoticeLabel(text, systemImage: "exclamationmark.triangle.fill", tint: .orange)
    }
}
