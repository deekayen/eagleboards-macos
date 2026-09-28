import EagleBoardsCore
import SwiftUI

/// The status of a youth as a small tinted badge: a symbol and the word, in
/// the shared status palette (`StatusPalette`, SPEC.md D-13), so it reads in
/// light and dark mode and with color blindness, and does not rely on color
/// alone. Status colors are not settings (D-19). With Increase Contrast the
/// badge gets a border.
struct StatusBadge: View {
    let statusText: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let status = BoardStatus(rawValue: statusText)
        let colors = status?.palette ?? StatusPalette.neutral
        Label(status?.label ?? statusText, systemImage: status?.symbolName ?? "questionmark.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(colors.background))
            .overlay {
                if contrast == .increased {
                    Capsule().strokeBorder(colors.foreground)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status?.label ?? statusText)
    }
}

extension BoardStatus {
    var symbolName: String {
        switch self {
        case .registered, .verified: "clock"
        case .seated: "hourglass"
        case .inProgress: "person.3.fill"
        case .completed: "checkmark.circle.fill"
        case .postponed: "pause.circle"
        }
    }
}

extension String {
    /// The data files turn commas into `~` to keep a row in one piece. Lists
    /// of names and free-text notes read better with them put back.
    var withListSeparators: String {
        split(whereSeparator: { $0 == "," || $0 == "~" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: ", ")
    }

    /// A list of names, one per line.
    var memberLines: [String] {
        split(whereSeparator: { $0 == "," || $0 == "~" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var withCommasRestored: String {
        replacingOccurrences(of: "~", with: ",")
    }
}
