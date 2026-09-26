import EagleBoardsCore
import SwiftUI

/// The status of a youth as a small tinted badge: a symbol and the word, in
/// a system color, so it reads in light and dark mode and does not rely on
/// color alone.
///
/// The Java scheduler's status colors are still in `config.properties`, and
/// are still written back unchanged for it, but they were chosen for dark
/// text on a light page and are not used here.
struct StatusBadge: View {
    let statusText: String

    var body: some View {
        let status = BoardStatus(rawValue: statusText)
        Label(status?.label ?? statusText, systemImage: status?.symbolName ?? "questionmark.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(status?.tint ?? .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill((status?.tint ?? .secondary).opacity(0.15)))
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

    var tint: Color {
        switch self {
        case .registered, .verified: .secondary
        case .seated: .orange
        case .inProgress: .blue
        case .completed: .green
        case .postponed: .purple
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

    var withCommasRestored: String {
        replacingOccurrences(of: "~", with: ",")
    }
}
