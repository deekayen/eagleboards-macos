import EagleBoardsCore
import SwiftUI

/// Two wooden beads on a leather thong, the Wood Badge itself, marking an
/// adult who is counting today toward a Wood Badge ticket item. SF Symbols
/// has nothing like it, so it is drawn; it scales with the text beside it.
struct WoodBadgeIcon: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 14

    var body: some View {
        Canvas { context, canvas in
            let width = canvas.width, height = canvas.height
            // The thong: a V from the neck down to the beads.
            var cord = Path()
            cord.move(to: CGPoint(x: width * 0.08, y: 0))
            cord.addLine(to: CGPoint(x: width * 0.3, y: height * 0.4))
            cord.move(to: CGPoint(x: width * 0.92, y: 0))
            cord.addLine(to: CGPoint(x: width * 0.7, y: height * 0.4))
            context.stroke(cord, with: .color(.secondary), lineWidth: max(1, width * 0.07))
            // The beads: two long wooden toggles hanging side by side, each
            // with a grain line across it.
            for x in [width * 0.16, width * 0.56] {
                let rect = CGRect(x: x, y: height * 0.34, width: width * 0.28, height: height * 0.64)
                let bead = Path(roundedRect: rect, cornerRadius: rect.width * 0.45)
                context.fill(bead, with: .color(.brown))
                context.stroke(bead, with: .color(.black.opacity(0.35)), lineWidth: max(0.5, width * 0.04))
                var grain = Path()
                grain.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.midY))
                grain.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.midY))
                context.stroke(grain, with: .color(.black.opacity(0.3)), lineWidth: max(0.5, width * 0.035))
            }
        }
        .frame(width: size, height: size)
        .help("Counting today toward a Wood Badge ticket item")
        .accessibilityElement()
        .accessibilityLabel("Wood Badge")
    }
}

/// The small marks after an adult's name: Wood Badge, and a warning when
/// they are in the youth's own unit.
struct AdultMarks: View {
    let adult: Adult
    var youth: Scout?

    var body: some View {
        if adult.woodBadge == "Y" {
            WoodBadgeIcon()
        }
        if let youth, !BoardRules.unitConflicts(scoutUnitName: youth.unitName, members: [adult]).isEmpty {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("Same unit as \(youth.fullName)")
                .accessibilityLabel("Same unit")
        }
    }
}
