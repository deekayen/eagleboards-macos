import AppKit
import EagleBoardsCore
import UserNotifications

/// Getting the operator's attention: the number waiting on the Dock icon, and
/// a notification when a room goes overdue (SPEC.md P-5), in front of Eagle
/// Boards or behind it.
@MainActor
final class Attention: NSObject, UNUserNotificationCenterDelegate {
    /// Boards already notified about, by youth and step, so each one is
    /// announced once. Nil until the first look after an event opens.
    private var announced: Set<String>?
    private var askedPermission = false

    /// Notifications need a real app bundle; `swift run` has none.
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    /// Without a delegate that says how, macOS shows nothing posted while the
    /// app is in front.
    override init() {
        super.init()
        if canNotify {
            UNUserNotificationCenter.current().delegate = self
        }
    }

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

    /// Announce each board that has just gone overdue. One posted while Eagle
    /// Boards is in front, where the room shows its alarm clock, is taken
    /// down again after a few seconds.
    func checkRooms(in event: BoardEvent, now: Date) {
        let check = OverdueNotification.check(announced: announced, youth: event.scouts, config: event.config, now: now)
        announced = check.announced
        guard canNotify else { return }
        for post in check.posts {
            let content = UNMutableNotificationContent()
            content.title = post.title
            content.body = post.body
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: post.id, content: content, trigger: nil))
            if let shown = OverdueNotification.removedAfter(appIsActive: NSApplication.shared.isActive) {
                Task {
                    try? await Task.sleep(for: shown)
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [post.id])
                }
            }
        }
    }

    func forgetEvent() {
        announced = nil
        showWaiting(0)
    }

    /// Shown in front of Eagle Boards too, as it would be behind it.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    // MARK: - The style in System Settings

    /// Eagle Boards' style in System Settings › Notifications, which decides
    /// whether a notification posted behind another app stays. Nil without
    /// an app bundle, which cannot notify.
    func notificationStyle() async -> OverdueNotification.Style? {
        guard canNotify else { return nil }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notAsked
        case .denied: return .off
        default:
            switch settings.alertStyle {
            case .alert: return .alerts
            case .banner: return .banners
            default: return .notShown
            }
        }
    }

    /// System Settings › Notifications, at Eagle Boards where macOS takes the
    /// `id`. The pane's older name, which System Settings still answers to
    /// (its `legacyBundleIdentifier`), works on macOS 14 and later alike.
    func openNotificationSettings() {
        var link = "x-apple.systempreferences:com.apple.preference.notifications"
        if let id = Bundle.main.bundleIdentifier {
            link += "?id=\(id)"
        }
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }
}
