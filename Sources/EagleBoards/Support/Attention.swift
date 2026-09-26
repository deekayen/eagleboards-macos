import AppKit
import EagleBoardsCore
import UserNotifications

/// Getting the operator's attention when the window is not in front: the
/// number waiting on the Dock icon, and a notification when a room passes its
/// red time.
@MainActor
final class Attention {
    /// Boards already notified about, by youth and step, so each one is
    /// announced once.
    private var announced: Set<String> = []
    private var askedPermission = false

    /// Notifications need a real app bundle; `swift run` has none.
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func showWaiting(_ count: Int) {
        NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    /// Asked once a board is seated, when the timers start to matter, rather
    /// than the moment the app opens.
    func askPermissionIfNeeded() {
        guard canNotify, !askedPermission else { return }
        askedPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Announce each board that has just gone past its red time, if the
    /// operator is working in another app. One in front of them already
    /// shows red in the sidebar.
    func checkRooms(in night: EventNight, now: Date) {
        for youth in night.scouts where youth.status == .seated || youth.status == .inProgress {
            guard let minutes = youth.minutesSinceLastUpdate(now: now),
                  RoomTimer.state(status: youth.status, boardType: youth.boardType, minutes: minutes, config: night.config) == .overdue
            else { continue }
            let key = "\(youth.id)|\(youth.statusText)|\(youth.lastUpdateTime)"
            guard announced.insert(key).inserted, canNotify, !NSApplication.shared.isActive else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Room \(youth.room) is past its red time"
            content.body = youth.status == .seated
                ? "\(youth.fullName)'s board has been convening for \(minutes) minutes."
                : "\(youth.fullName)'s review has run \(minutes) minutes."
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
        }
    }

    func forgetNight() {
        announced = []
        showWaiting(0)
    }
}
