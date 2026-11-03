import Foundation

/// Keeps the Mac awake while the sign-in station serves, and lets go on every
/// way the station can end, a failed start included. `begin` and `end` are
/// the calls that start and finish the system's activity; `processActivity`
/// supplies the real ones, and a test supplies counters.
public final class KeepAwake {
    private let begin: () -> NSObjectProtocol
    private let end: (NSObjectProtocol) -> Void
    private var activity: NSObjectProtocol?

    public init(begin: @escaping () -> NSObjectProtocol, end: @escaping (NSObjectProtocol) -> Void) {
        self.begin = begin
        self.end = end
    }

    /// Holds off idle system sleep through `ProcessInfo`; the display may
    /// still sleep.
    public static func processActivity(reason: String) -> KeepAwake {
        KeepAwake(
            begin: {
                ProcessInfo.processInfo.beginActivity(
                    options: [.idleSystemSleepDisabled, .userInitiated], reason: reason)
            },
            end: { ProcessInfo.processInfo.endActivity($0) })
    }

    /// Whether an activity is open.
    public var isHeld: Bool { activity != nil }

    /// Begin the activity unless one is already open, so a second call does
    /// not leave an activity nothing will end.
    public func hold() {
        guard activity == nil else { return }
        activity = begin()
    }

    /// End the activity, if one is open.
    public func release() {
        guard let held = activity else { return }
        activity = nil
        end(held)
    }
}
