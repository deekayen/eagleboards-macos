import EagleBoardsCore
import Foundation
import Testing

/// SPEC.md P-5's overdue notification, posted in front of Eagle Boards and
/// behind it, and the style Settings › Timers shows for it.
@Suite("The overdue notification")
struct OverdueNotificationTests {
    @Test func inFrontItGoesAwayAfterTenSeconds() {
        #expect(OverdueNotification.removedAfter(appIsActive: true) == .seconds(10))
    }

    @Test func behindAnotherAppSystemSettingsDecides() {
        #expect(OverdueNotification.removedAfter(appIsActive: false) == nil)
    }

    @Test func theFooterSaysWhatHappensInFrontAndBehind() {
        #expect(OverdueNotification.settingsFooter
                == "Eagle Boards posts a notification once when a room goes overdue. With Eagle Boards in front, it goes "
                    + "away after 10 seconds; behind another app, the Alerts style keeps it on screen until you close it.")
    }

    // MARK: - Which boards are announced

    let config = Config.standard
    let clock = Date(timeIntervalSince1970: 1_790_118_300)

    private func board(_ first: String, room: String, _ status: BoardStatus, _ boardType: BoardType = .finalBoard,
                       minutesAgo: Int) -> Scout {
        var youth = Scout(fields: [
            "Type": "SCOUT", "ID": "SCOUT:Doe:\(first)", "First": first, "Last": "Doe", "UnitName": "Troop1234",
            "BoardType": boardType.rawValue, "Status": status.rawValue,
        ])
        youth.room = room
        youth.lastUpdateTime = Timestamp.recordStamp(for: clock.addingTimeInterval(TimeInterval(-minutesAgo * 60)))
        return youth
    }

    private func check(_ announced: Set<String>?, _ youth: [Scout], minutesLater: Int = 0)
        -> (announced: Set<String>, posts: [OverdueNotification.Post]) {
        OverdueNotification.check(announced: announced, youth: youth, config: config,
                                  now: clock.addingTimeInterval(TimeInterval(minutesLater * 60)))
    }

    /// As the rooms read aloud: opening an event, or opening it again after a
    /// relaunch, does not post one for every room already over.
    @Test func theFirstLookOnlyRecords() {
        let youth = [board("Jane", room: "101", .inProgress, minutesAgo: 50)]
        let first = check(nil, youth)
        #expect(first.posts.isEmpty, "a room already overdue when the event opens is not announced")
        #expect(first.announced == [RoomTimerSpeech.key(for: youth[0])])
        #expect(check(first.announced, youth, minutesLater: 1).posts.isEmpty, "nor at the next look")
    }

    @Test func aBoardGoingOverdueIsAnnouncedOnce() {
        let youth = [board("Jane", room: "101", .inProgress, minutesAgo: 40), board("Bill", room: "102", .seated, minutesAgo: 10)]
        let start = check(nil, youth)
        #expect(check(start.announced, youth, minutesLater: 4).posts.isEmpty, "running long is not overdue")
        let overdue = check(start.announced, youth, minutesLater: 5)
        #expect(overdue.posts == [OverdueNotification.Post(
            id: RoomTimerSpeech.key(for: youth[0]), title: "Room 101 is overdue", body: "Jane Doe's review has run 45 minutes.")])
        #expect(check(overdue.announced, youth, minutesLater: 6).posts.isEmpty, "still overdue: not posted again")
        let convening = check(overdue.announced, youth, minutesLater: 20)
        #expect(convening.posts.map(\.body) == ["Bill Doe's board has been convening for 30 minutes."])
    }

    @Test func onlySittingBoardsAreTimed() {
        let youth = [board("Jane", room: "101", .completed, minutesAgo: 10), board("Bill", room: "", .registered, minutesAgo: 10)]
        let start = check(nil, youth)
        #expect(check(start.announced, youth, minutesLater: 120).posts.isEmpty)
    }

    @Test(arguments: [
        (OverdueNotification.Style.notAsked, "Not asked yet"),
        (.off, "Off"),
        (.notShown, "None"),
        (.banners, "Banners"),
        (.alerts, "Alerts"),
    ])
    func eachStyleIsNamedAsSystemSettingsNamesIt(style: OverdueNotification.Style, label: String) {
        #expect(style.label == label)
    }

    @Test func alertsNeedNoNoteAndNoTripToSystemSettings() {
        #expect(OverdueNotification.Style.alerts.note == nil)
        #expect(!OverdueNotification.Style.alerts.canChangeInSystemSettings)
    }

    @Test func bannersGoAwayUntilSetToAlerts() {
        #expect(OverdueNotification.Style.banners.note
                == "Overdue notifications go away on their own until Eagle Boards is set to Alerts in System Settings › Notifications.")
        #expect(OverdueNotification.Style.banners.canChangeInSystemSettings)
    }

    @Test func noneShowsNothingOnScreen() {
        #expect(OverdueNotification.Style.notShown.note
                == "Overdue notifications do not show on screen until Eagle Boards is set to Alerts in System Settings › Notifications.")
        #expect(OverdueNotification.Style.notShown.canChangeInSystemSettings)
    }

    @Test func offIsSaidTheSameWay() {
        #expect(OverdueNotification.Style.off.note
                == "Notifications are off for Eagle Boards, so overdue notifications do not show until they are allowed, "
                    + "with the Alerts style, in System Settings › Notifications.")
        #expect(OverdueNotification.Style.off.canChangeInSystemSettings)
    }

    /// System Settings does not list Eagle Boards before macOS has asked, so
    /// there is no button to take the operator there.
    @Test func beforeMacOSAsksThereIsNothingToChange() {
        #expect(OverdueNotification.Style.notAsked.note
                == "macOS asks whether to allow notifications once the first board is seated. Overdue notifications "
                    + "stay on screen if Eagle Boards is then set to Alerts in System Settings › Notifications.")
        #expect(!OverdueNotification.Style.notAsked.canChangeInSystemSettings)
    }
}
