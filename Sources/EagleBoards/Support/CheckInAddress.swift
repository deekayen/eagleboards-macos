import EagleBoardsCore
import Foundation
import SystemConfiguration

/// One address a sign-in tablet can open, as the Sign-In Code window, the
/// toolbar popover and the toolbar's summary offer it.
struct CheckInAddress: Hashable, Identifiable {
    /// The network it is on.
    let network: SignInNetwork
    let url: URL
    var id: URL { url }
    var host: String { url.host() ?? "" }

    /// The Network picker's choice, kept so the projector's window and the
    /// popover draw the same code.
    static let chosenHostKey = "signInCodeHost"
}

extension [CheckInAddress] {
    /// The address chosen in the Network picker, or the default (Wi-Fi, then
    /// the likeliest venue network) when none is chosen or the chosen one is
    /// gone.
    func chosen(_ host: String) -> CheckInAddress? {
        let preferred = map(\.network).preferred
        return first { $0.host == host } ?? first { $0.network == preferred }
    }
}

/// Calls `onChange` on the main queue whenever an interface's IPv4 address
/// comes, goes or changes, so the sign-in station can follow the network it
/// serves. It is made once, by the app's model, and lives as long as the app.
@MainActor
final class NetworkWatcher {
    private let onChange: @MainActor () -> Void
    private var store: SCDynamicStore?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        var context = SCDynamicStoreContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "Eagle Boards" as CFString, { _, _, info in
            guard let info else { return }
            let watcher = Unmanaged<NetworkWatcher>.fromOpaque(info).takeUnretainedValue()
            // The store calls back on the main queue, set below.
            MainActor.assumeIsolated { watcher.onChange() }
        }, &context) else { return }
        let anyInterfaceIPv4 = SCDynamicStoreKeyCreateNetworkInterfaceEntity(
            nil, kSCDynamicStoreDomainState, kSCCompAnyRegex, kSCEntNetIPv4)
        SCDynamicStoreSetNotificationKeys(store, nil, [anyInterfaceIPv4] as CFArray)
        SCDynamicStoreSetDispatchQueue(store, .main)
        self.store = store
    }
}
