import EagleBoardsCore
import Foundation
import Testing

/// Which network the sign-in station serves, and how Settings › General
/// names each one. Every address here is made up.
@Suite("Sign-in network")
struct SignInNetworkTests {
    let ethernet = SignInNetwork(interface: "en7", kind: "Ethernet", ipv4: "10.0.0.5")
    let wifi = SignInNetwork(interface: "en0", kind: "Wi-Fi", ipv4: "192.168.1.20", isWiFi: true)
    let vpn = SignInNetwork(interface: "utun3", kind: nil, ipv4: "10.8.0.2")

    @Test func eachNetworkIsNamedByKindAndBSDNameWithItsAddress() {
        #expect(wifi.label == "Wi-Fi (en0), 192.168.1.20")
        #expect(ethernet.label == "Ethernet (en7), 10.0.0.5")
        #expect(vpn.label == "utun3, 10.8.0.2", "System Settings does not list a VPN, so it goes by its BSD name")
        #expect(SignInListening.everyNetworkLabel == "Every Network")
    }

    @Test func theDefaultIsWiFiThenTheFirstAddressThenThisMacAlone() {
        let onWiFi = SignInListening(choice: nil, among: [ethernet, wifi, vpn])
        #expect(onWiFi.host == "192.168.1.20", "Wi-Fi, though Ethernet comes first")
        #expect(onWiFi.network == wifi && onWiFi.problem == nil)

        let noWiFi = SignInListening(choice: nil, among: [ethernet, vpn])
        #expect(noWiFi.host == "10.0.0.5", "the first address in the order given")

        let none = SignInListening(choice: nil, among: [])
        #expect(none.host == "127.0.0.1" && none.network == nil && none.problem == nil)
        #expect(!none.isEveryNetwork && none.selection == "")

        #expect(SignInListening(choice: "", among: [ethernet, wifi]).host == "192.168.1.20", "empty is no choice")
    }

    @Test func theChosenInterfaceIsServedAtTheAddressItHasNow() {
        let chosen = SignInListening(choice: "en7", among: [wifi, ethernet])
        #expect(chosen.host == "10.0.0.5" && chosen.network == ethernet && chosen.problem == nil)
        #expect(chosen.selection == "en7")

        let renumbered = SignInNetwork(interface: "en7", kind: "Ethernet", ipv4: "10.0.0.77")
        #expect(SignInListening(choice: "en7", among: [wifi, renumbered]).host == "10.0.0.77",
                "saved by BSD name, so a new DHCP address is followed")
    }

    @Test func everyNetworkListensOnAllOfThem() {
        let every = SignInListening(choice: SignInListening.everyNetwork, among: [wifi, ethernet])
        #expect(every.host == "0.0.0.0" && every.isEveryNetwork)
        #expect(every.network == nil && every.problem == nil)
        #expect(every.selection == "all")
        #expect(SignInListening(choice: "all", among: []).host == "0.0.0.0", "with no network as well")
    }

    /// The saved interface has no address when the station starts: it goes
    /// on the default, and the sign-in status says so until that is fixed.
    @Test func aChosenNetworkWithNoAddressFallsBackAndSaysSo() {
        let gone = SignInListening(choice: "en7", among: [vpn, wifi], kinds: ["en7": "Ethernet", "en0": "Wi-Fi"])
        #expect(gone.host == "192.168.1.20" && gone.network == wifi)
        #expect(gone.unavailableChoice == "en7")
        #expect(gone.selection == "en7", "the menu shows what is saved, so choosing Wi-Fi there replaces it")
        #expect(gone.problem == "Ethernet (en7), chosen for sign-in in Settings › General, has no address. "
            + "Until it has one, or until you choose another network there, "
            + "the sign-in station is on Wi-Fi (en0), 192.168.1.20.")

        let alone = SignInListening(choice: "en7", among: [])
        #expect(alone.host == "127.0.0.1")
        #expect(alone.problem == "en7, chosen for sign-in in Settings › General, has no address. "
            + "Until it has one, or until you choose another network there, only this Mac can open the sign-in page.",
                "named by its BSD name when System Settings does not list it")

        #expect(SignInListening(choice: "en7", among: [ethernet]).unavailableChoice == nil, "back once it has an address")
    }

    @Test func theMenuHasEachInterfaceTheChoiceWithNoAddressAndEveryNetwork() {
        let menu = SignInListening(choice: nil, among: [wifi, ethernet]).menu(among: [wifi, ethernet])
        #expect(menu.map(\.label) == ["Wi-Fi (en0), 192.168.1.20", "Ethernet (en7), 10.0.0.5", "Every Network"])
        #expect(menu.map(\.tag) == ["en0", "en7", "all"])

        let gone = SignInListening(choice: "en7", among: [wifi, vpn], kinds: ["en7": "Ethernet"])
        #expect(gone.menu(among: [wifi, vpn]).map(\.label)
            == ["Wi-Fi (en0), 192.168.1.20", "utun3, 10.8.0.2", "Ethernet (en7), No Address", "Every Network"])
        #expect(gone.menu(among: [wifi, vpn]).map(\.tag).contains(gone.selection), "the selection is always an item")
    }

    /// One network, served, is no choice; anything else saved is shown so
    /// it can be changed.
    @Test func theMenuIsShownWhenThereIsAChoiceToSeeOrChange() {
        #expect(SignInListening(choice: nil, among: [wifi, ethernet]).showsMenu(among: [wifi, ethernet]))
        #expect(!SignInListening(choice: nil, among: [wifi]).showsMenu(among: [wifi]))
        #expect(!SignInListening(choice: "en0", among: [wifi]).showsMenu(among: [wifi]))
        #expect(!SignInListening(choice: nil, among: []).showsMenu(among: []))
        #expect(SignInListening(choice: "all", among: [wifi]).showsMenu(among: [wifi]),
                "Every Network saved at an earlier event can be turned back to the one network")
        #expect(!SignInListening(choice: "all", among: []).showsMenu(among: []))
        #expect(SignInListening(choice: "en7", among: [wifi]).showsMenu(among: [wifi]), "a chosen network with no address")
        #expect(SignInListening(choice: "en7", among: []).showsMenu(among: []))
    }

    /// The order `SignInNetwork.current()` returns, and so which address is
    /// first when the Mac has no Wi-Fi.
    @Test func addressesGoVenueNetworksFirstThenByNameKeepingEachInterfacesOrder() {
        let bridge = SignInNetwork(interface: "bridge100", kind: "Thunderbolt Bridge", ipv4: "192.168.2.1")
        let alias = SignInNetwork(interface: "en0", kind: "Wi-Fi", ipv4: "192.168.1.21", isWiFi: true)
        #expect([vpn, bridge, ethernet, alias, wifi].venueNetworksFirst == [alias, wifi, ethernet, bridge, vpn])
        #expect([vpn, ethernet].venueNetworksFirst.first == ethernet, "Ethernet before a VPN, whatever the order given")
        #expect([SignInNetwork]().venueNetworksFirst.isEmpty)
    }

    @Test func theMenuListsEachInterfaceOnce() {
        let alias = SignInNetwork(interface: "en0", kind: "Wi-Fi", ipv4: "192.168.1.21", isWiFi: true)
        #expect([wifi, alias, ethernet].oneEachInterface == [wifi, ethernet], "at its first address")
        #expect([ethernet, alias, wifi].preferred == alias, "the first Wi-Fi address")
        #expect([SignInNetwork]().preferred == nil)
    }
}

@Suite("Sign-in network setting")
struct SignInNetworkSettingTests {
    @Test func theSavedChoiceIsABSDNameAndTheVariableWins() {
        let suite = "eagleboards-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(LaunchSettings(environment: [:], defaults: defaults).signInNetwork == nil, "Wi-Fi by default")

        defaults.set("en7", forKey: LaunchSettings.Keys.signInNetwork)
        #expect(LaunchSettings(environment: [:], defaults: defaults).signInNetwork == "en7")
        #expect(LaunchSettings(environment: ["EAGLEBOARDS_NETWORK": "all"], defaults: defaults).signInNetwork == "all")
        #expect(LaunchSettings(environment: ["EAGLEBOARDS_NETWORK": ""], defaults: defaults).signInNetwork == "en7",
                "an empty variable is not a choice")
    }
}
