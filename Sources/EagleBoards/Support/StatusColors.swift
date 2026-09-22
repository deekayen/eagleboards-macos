import AppKit
import EagleBoardsCore
import SwiftUI

extension Color {
    /// `#rrggbb` as saved in `config.properties`.
    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Back to `#rrggbb` for saving.
    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        func channel(_ component: CGFloat) -> Int { Int((component * 255).rounded()).clamped(to: 0...255) }
        return String(format: "#%02x%02x%02x", channel(color.redComponent), channel(color.greenComponent), channel(color.blueComponent))
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension Config {
    /// The status color from Settings, for the badges and the boards list.
    func color(for status: BoardStatus, highlighted: Bool = false) -> Color {
        Color(hex: colorHex(for: status, highlighted: highlighted)) ?? .secondary.opacity(0.2)
    }
}

/// The status of a youth as a small colored badge. The fill is the status
/// color from Settings; the text is always dark so it reads on any of the
/// light defaults, and the outline keeps a white one (Completed) visible.
struct StatusBadge: View {
    let statusText: String
    let config: Config

    var body: some View {
        let status = BoardStatus(rawValue: statusText)
        Text(status?.label ?? statusText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(status.map { config.color(for: $0) } ?? .secondary.opacity(0.2))
            )
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.18)))
            .accessibilityLabel(status?.label ?? statusText)
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
