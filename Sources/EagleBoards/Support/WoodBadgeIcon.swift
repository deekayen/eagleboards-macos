import EagleBoardsCore
import SwiftUI

/// Marks an adult who is counting today toward a Wood Badge ticket item: a
/// pentagon banded in the course's five colors around a white face and a
/// black center, after the course's emblem pared down to read at text size.
/// The face is white, as the emblem's is, so the navy, green and black stay
/// visible in dark mode.
struct WoodBadgeIcon: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 16

    /// Clockwise from the top corner, as on the emblem: navy, red, black
    /// along the bottom, green, yellow.
    private static let sideColors: [Color] = [
        Color(red: 0.13, green: 0.19, blue: 0.42),
        Color(red: 0.75, green: 0.13, blue: 0.21),
        .black,
        Color(red: 0.12, green: 0.40, blue: 0.20),
        Color(red: 0.95, green: 0.72, blue: 0.10),
    ]

    var body: some View {
        Canvas { context, canvas in
            let center = CGPoint(x: canvas.width / 2, y: canvas.height * 0.53)
            let outerRadius = min(canvas.width, canvas.height) * 0.5
            // The bands are 28% of the radius deep, measured square to each side.
            let apothem = outerRadius * cos(Double.pi / 5)
            let innerRadius = (apothem - outerRadius * 0.28) / cos(Double.pi / 5)
            let outer = Self.corners(center: center, radius: outerRadius)
            let inner = Self.corners(center: center, radius: innerRadius)

            var face = Path()
            face.addLines(inner)
            face.closeSubpath()
            context.fill(face, with: .color(.white))

            // Each band is cut square to the corner, with a slit between
            // neighbours as on the emblem.
            let gap = outerRadius * 0.06
            for (index, color) in Self.sideColors.enumerated() {
                let next = (index + 1) % 5
                var band = Path()
                band.addLines([
                    Self.point(from: outer[index], toward: outer[next], by: gap),
                    Self.point(from: outer[next], toward: outer[index], by: gap),
                    Self.point(from: inner[next], toward: inner[index], by: gap),
                    Self.point(from: inner[index], toward: inner[next], by: gap),
                ])
                band.closeSubpath()
                context.fill(band, with: .color(color))
            }

            let dot = outerRadius * 0.24
            context.fill(Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)),
                         with: .color(.black))
        }
        .frame(width: size, height: size)
        .help("Counting today toward a Wood Badge ticket item")
        .accessibilityElement()
        .accessibilityLabel("Wood Badge")
    }

    /// A pentagon's corners, point up, clockwise from the top.
    private static func corners(center: CGPoint, radius: Double) -> [CGPoint] {
        (0..<5).map { index in
            let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / 5
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }

    private static func point(from start: CGPoint, toward end: CGPoint, by distance: Double) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        return CGPoint(x: start.x + dx / length * distance, y: start.y + dy / length * distance)
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
