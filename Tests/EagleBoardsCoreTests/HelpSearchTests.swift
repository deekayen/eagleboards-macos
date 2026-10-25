import EagleBoardsCore
import Testing

@Suite("Searching Help")
struct HelpSearchTests {
    let guide = [
        HelpSection("Seat a board", [
            "Press Seat Board… in the inspector or the toolbar.",
            "Choose the chair. The sheet offers only members whose role is Chair.",
        ]),
        HelpSection("Room timers", [
            "Each busy room shows the minutes since its last step.",
            "They are prompts, not limits. Change them in Settings › Timers.",
        ]),
        HelpSection("Menus", [
            "To rename a room, right-click its card and choose Rename….",
            "Edit › Undo takes back the last step.",
        ]),
    ]

    @Test func anEmptySearchKeepsTheWholeGuide() {
        #expect(HelpSection.matching("", in: guide) == guide)
        #expect(HelpSection.matching("   ", in: guide) == guide)
    }

    @Test func aWordKeepsOnlyTheParagraphsThatHoldItInTheirSections() {
        let found = HelpSection.matching("step", in: guide)
        #expect(found.map(\.title) == ["Room timers", "Menus"])
        #expect(found.map(\.items) == [
            ["Each busy room shows the minutes since its last step."],
            ["Edit › Undo takes back the last step."],
        ])
    }

    @Test func everyWordMustBeFoundInAnyOrderIgnoringCase() {
        let found = HelpSection.matching("ROOM rename", in: guide)
        #expect(found == [HelpSection("Menus", ["To rename a room, right-click its card and choose Rename…."])])
    }

    @Test func aSectionsTitleShowsTheWholeSection() {
        #expect(HelpSection.matching("room timers", in: guide) == [guide[1]])
        // A word from the title and one from a paragraph narrow it again.
        #expect(HelpSection.matching("timers limits", in: guide)
            == [HelpSection("Room timers", ["They are prompts, not limits. Change them in Settings › Timers."])])
    }

    @Test func accentsAreIgnored() {
        #expect(HelpSection.matching("chaír", in: guide).map(\.title) == ["Seat a board"])
    }

    @Test func nothingFoundLeavesNoSections() {
        #expect(HelpSection.matching("projector", in: guide).isEmpty)
        #expect(HelpSection.matching("rename timers", in: guide).isEmpty)
    }
}
