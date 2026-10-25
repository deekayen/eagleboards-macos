import Foundation

/// SPEC.md P-5's notification when a room goes overdue, posted whether or not
/// Eagle Boards is in front. In front it goes away on its own, as the owner
/// asked on 2026-10-25: the one exception to D-14, since the room card shows
/// the alarm clock there. Behind another app, the style chosen for Eagle
/// Boards in System Settings › Notifications decides whether it stays, and
/// no app can set that style.
public enum OverdueNotification {
    /// One notification to post, identified by `RoomTimerSpeech.key`.
    public struct Post: Equatable, Sendable {
        public let id: String
        public let title: String
        public let body: String

        public init(id: String, title: String, body: String) {
            self.id = id
            self.title = title
            self.body = body
        }
    }

    /// The boards that have gone overdue since the last look, and every board
    /// announced so far, so each is announced once. Nil `announced` is the
    /// first look after an event opens: it only records, as
    /// `RoomTimerSpeech.check` does, so a room already overdue then is not
    /// announced as if it had just gone over.
    public static func check(announced: Set<String>?, youth: [Scout], config: Config, now: Date)
        -> (announced: Set<String>, posts: [Post]) {
        var seen = announced ?? []
        var posts: [Post] = []
        for youth in youth where youth.status == .seated || youth.status == .inProgress {
            guard let minutes = youth.minutesSinceLastUpdate(now: now),
                  RoomTimer.state(status: youth.status, boardType: youth.boardType, minutes: minutes, config: config) == .overdue
            else { continue }
            let key = RoomTimerSpeech.key(for: youth)
            guard seen.insert(key).inserted, announced != nil else { continue }
            posts.append(Post(
                id: key,
                title: "Room \(youth.room) is overdue",
                body: youth.status == .seated
                    ? "\(youth.shownFullName)'s board has been convening for \(Count.minutes(minutes))."
                    : "\(youth.shownFullName)'s review has run \(Count.minutes(minutes))."))
        }
        return (seen, posts)
    }

    /// How long one posted while Eagle Boards is in front stays, on screen and
    /// in Notification Center. Nil behind another app, where the style in
    /// System Settings decides.
    public static func removedAfter(appIsActive: Bool) -> Duration? {
        appIsActive ? .seconds(10) : nil
    }

    /// Under the style in Settings › Timers, whatever it is.
    public static let settingsFooter = "Eagle Boards posts a notification once when a room goes overdue. With Eagle "
        + "Boards in front, it goes away after 10 seconds; behind another app, the Alerts style keeps it on screen "
        + "until you close it."

    /// Eagle Boards' notification style in System Settings › Notifications.
    public enum Style: Equatable, Sendable {
        /// macOS has not asked yet; it asks once the first board is seated.
        case notAsked
        /// Notifications are not allowed.
        case off
        /// Allowed, with the None style: Notification Center only.
        case notShown
        case banners
        case alerts

        /// As System Settings names it.
        public var label: String {
            switch self {
            case .notAsked: "Not asked yet"
            case .off: "Off"
            case .notShown: "None"
            case .banners: "Banners"
            case .alerts: "Alerts"
            }
        }

        /// What the operator needs to know when an overdue notification will
        /// not stay on screen behind another app. Nil for Alerts.
        public var note: String? {
            switch self {
            case .notAsked:
                "macOS asks whether to allow notifications once the first board is seated. Overdue notifications "
                    + "stay on screen if Eagle Boards is then set to Alerts in System Settings › Notifications."
            case .off:
                "Notifications are off for Eagle Boards, so overdue notifications do not show until they are "
                    + "allowed, with the Alerts style, in System Settings › Notifications."
            case .notShown:
                "Overdue notifications do not show on screen until Eagle Boards is set to Alerts in "
                    + "System Settings › Notifications."
            case .banners:
                "Overdue notifications go away on their own until Eagle Boards is set to Alerts in "
                    + "System Settings › Notifications."
            case .alerts:
                nil
            }
        }

        /// System Settings lists Eagle Boards under Notifications only once
        /// macOS has asked, so before that there is nothing there to change.
        public var canChangeInSystemSettings: Bool {
            note != nil && self != .notAsked
        }
    }
}
