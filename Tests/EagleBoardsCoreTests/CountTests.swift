import EagleBoardsCore
import Foundation
import Testing

/// Numbers, units and dates in the words the screen shows and VoiceOver
/// reads, as Windows' `Display` writes them (c0b18db).
@Suite("Counts, minutes and ordinals")
struct CountTests {
    @Test(arguments: [(0, "0 members"), (1, "1 member"), (2, "2 members")])
    func aCountTakesItsNounSingularOrPlural(count: Int, words: String) {
        #expect(Count.of(count, "member", "members") == words)
    }

    @Test(arguments: [(0, "0 minutes"), (1, "1 minute"), (2, "2 minutes")])
    func minutesAreWordsNeverMin(count: Int, words: String) {
        #expect(Count.minutes(count) == words)
    }

    @Test(arguments: [
        (1, "1st"), (2, "2nd"), (3, "3rd"), (4, "4th"), (11, "11th"), (12, "12th"), (13, "13th"),
        (21, "21st"), (22, "22nd"), (23, "23rd"), (101, "101st"), (111, "111th"), (112, "112th"),
    ])
    func ordinalsAreEnglishWhateverTheMacsLanguage(number: Int, words: String) {
        #expect(Count.ordinal(number) == words)
    }
}

@Suite("The sign-in number's help")
struct SignInNumberHelpTests {
    private func youth(_ regNum: String) -> Scout {
        Scout(fields: ["Type": "SCOUT", "ID": "SCOUT:Doe:Jan:1", "First": "Jan", "Last": "Doe", "RegNum": regNum])
    }

    /// "#3" was read aloud as "number sign 3".
    @Test(arguments: [
        ("P1", "Pre-registered: matched a sign-up. The 1st pre-registered youth to sign in."),
        ("W2", "Walk-in: no pre-registration matched. The 2nd walk-in to sign in."),
        ("P3", "Pre-registered: matched a sign-up. The 3rd pre-registered youth to sign in."),
        ("W11", "Walk-in: no pre-registration matched. The 11th walk-in to sign in."),
        ("W12", "Walk-in: no pre-registration matched. The 12th walk-in to sign in."),
        ("W13", "Walk-in: no pre-registration matched. The 13th walk-in to sign in."),
        ("W22", "Walk-in: no pre-registration matched. The 22nd walk-in to sign in."),
    ])
    func itSaysTheOrdinal(regNum: String, help: String) {
        #expect(youth(regNum).regNumHelp == help)
    }

    @Test(arguments: ["P", "Px", "W1a", "", "X3"])
    func aNumberThatIsNotOneHasNoHelp(regNum: String) {
        #expect(youth(regNum).regNumHelp.isEmpty)
    }
}

@Suite("Units in full")
struct UnitInFullTests {
    @Test(arguments: [
        ("Troop1409", "Troop 1409"), ("Crew55", "Crew 55"), ("1409", "1409"), ("District", "District"), ("", ""),
    ])
    func aUnitIsSpacedOnlyWhenATypeComesBeforeItsNumber(unitName: String, shown: String) {
        #expect(UnitLabel.spaced(unitName) == shown)
    }
}
