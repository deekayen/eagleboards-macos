import EagleBoardsCore
import Foundation
import Testing

@Suite("Adult name order")
struct AdultOrderTests {
    private func adult(_ first: String, _ last: String) -> Adult {
        var adult = Adult.blank(at: Date())
        adult.first = first
        adult.last = last
        return adult
    }

    @Test func listsReadAsNamesDoNotAsCodePoints() {
        let adults = [
            adult("Ines", "Zimmer"), adult("Kenji", "de Silva"), adult("Femi", "Dunn"),
            adult("Lorna", "McDonald"), adult("Marisol", "Mcdonald"), adult("Quillon", "Abara"),
        ]
        let ordered = adults.sorted(by: Adult.byName).map { "\($0.first) \($0.last)" }
        #expect(
            ordered == [
                "Quillon Abara", "Kenji de Silva", "Femi Dunn", "Lorna McDonald", "Marisol Mcdonald", "Ines Zimmer",
            ])
    }

    @Test func theSameLastNameIsOrderedByFirstName() {
        let ordered = [adult("beth", "Smith"), adult("Alan", "Smith")].sorted(by: Adult.byName)
        #expect(ordered.map(\.first) == ["Alan", "beth"])
    }
}
