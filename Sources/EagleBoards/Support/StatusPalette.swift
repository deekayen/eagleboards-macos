import AppKit
import EagleBoardsCore
import SwiftUI

/// The status palette all three versions share (SPEC.md D-13 in
/// eagleboards-shared): the status badges' and room timers' colors, light
/// and dark. The values are the spec's palette table, where
/// `scripts/check-palette.js` measures them for contrast and color
/// blindness; change them there first. Its `check-drift.sh` finds any that
/// differ here. System colors can't promise that: orange and red, and
/// orange and green, look alike to many color-blind operators.
enum StatusPalette {
    /// A badge's fill and the color of its word and symbol on it.
    struct Pair: Sendable {
        let background: Color
        let foreground: Color
    }

    static let neutral = Pair(background: color("#dddddd", "#565457"), foreground: color("#5b5a5b", "#d4d3d3"))
    static let seated = Pair(background: color("#f3dfc4", "#685b3e"), foreground: color("#875107", "#ffdd78"))
    static let review = Pair(background: color("#c9e3ea", "#425c62"), foreground: color("#146377", "#9ae5ee"))
    static let completed = Pair(background: color("#ddd7ef", "#504a65"), foreground: color("#5e4aa0", "#cbc2f7"))
    static let long = Pair(background: color("#f8d9ce", "#67493e"), foreground: color("#994122", "#fdbe9f"))
    static let overdue = Pair(background: color("#c23d65", "#ff6188"), foreground: color("#ffffff", "#221f22"))

    /// `light` in the light appearance and `dark` in the dark one, including
    /// their Increase Contrast variants.
    private static func color(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            rgb(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    private static func rgb(_ hex: String) -> NSColor {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255,
                       green: CGFloat((value >> 8) & 0xff) / 255,
                       blue: CGFloat(value & 0xff) / 255,
                       alpha: 1)
    }
}

extension BoardStatus {
    /// The badge's colors. Waiting and Postponed share the neutral pair; each
    /// status still has its own symbol and word.
    var palette: StatusPalette.Pair {
        switch self {
        case .registered, .verified, .postponed: StatusPalette.neutral
        case .seated: StatusPalette.seated
        case .inProgress: StatusPalette.review
        case .completed: StatusPalette.completed
        }
    }
}
