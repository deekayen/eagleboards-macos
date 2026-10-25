import Darwin
import Foundation
import SystemConfiguration

/// One IPv4 network this Mac is on: an item of Settings › General's Network
/// menu, and an address a sign-in tablet on that network can open.
public struct SignInNetwork: Hashable, Sendable, Identifiable {
    /// BSD name, such as `en0`. The choice is saved by this, not by the
    /// address, which DHCP can change.
    public let interface: String
    /// What System Settings › Network calls it ("Wi-Fi", "Ethernet"), or nil
    /// for a VPN or a bridge it does not list.
    public let kind: String?
    public let ipv4: String
    public let isWiFi: Bool

    public init(interface: String, kind: String?, ipv4: String, isWiFi: Bool = false) {
        self.interface = interface
        self.kind = kind
        self.ipv4 = ipv4
        self.isWiFi = isWiFi
    }

    public var id: String { "\(interface) \(ipv4)" }

    /// "Wi-Fi (en0)", or the BSD name alone when System Settings does not
    /// list the interface.
    public var name: String { Self.name(interface, kind: kind) }

    /// "Wi-Fi (en0), 192.168.1.20".
    public var label: String { "\(name), \(ipv4)" }

    static func name(_ interface: String, kind: String?) -> String {
        kind.map { "\($0) (\(interface))" } ?? interface
    }
}

extension Array where Element == SignInNetwork {
    /// The default network: Wi-Fi, or else the first in this order. Nil
    /// when the Mac is on none, and the station serves 127.0.0.1 alone.
    public var preferred: SignInNetwork? {
        first(where: \.isWiFi) ?? first
    }

    /// `en*` (Wi-Fi and Ethernet) first, then by BSD name, and an interface's
    /// addresses in the order given. Anything else is usually a VPN, a
    /// virtual machine's bridge, or a phone's hotspot link.
    public var venueNetworksFirst: [SignInNetwork] {
        enumerated().sorted { lhs, rhs in
            let lhsEn = lhs.element.interface.hasPrefix("en"), rhsEn = rhs.element.interface.hasPrefix("en")
            if lhsEn != rhsEn {
                return lhsEn
            }
            if lhs.element.interface != rhs.element.interface {
                return lhs.element.interface < rhs.element.interface
            }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    /// Each interface once, at its first address: the Network menu's items.
    public var oneEachInterface: [SignInNetwork] {
        var seen: Set<String> = []
        return filter { seen.insert($0.interface).inserted }
    }
}

/// Where the sign-in station listens: the network chosen in Settings ›
/// General, resolved to its address when the station starts, and 127.0.0.1
/// beside it, so this Mac's own browser still reaches the pages. Every
/// Network listens on all of them.
public struct SignInListening: Equatable, Sendable {
    /// Saved as the choice for Every Network, where a BSD name is otherwise
    /// saved. No interface is named this.
    public static let everyNetwork = "all"
    public static let everyNetworkLabel = "Every Network"
    public static let anyAddress = "0.0.0.0"
    public static let loopback = "127.0.0.1"

    /// The address the server listens on as well as 127.0.0.1: the
    /// network's, `anyAddress` for every network, or `loopback` itself when
    /// the Mac is on no network.
    public let host: String
    /// The network served. Nil for every network, or for none.
    public let network: SignInNetwork?
    /// The chosen interface, by BSD name, when it has no address and the
    /// station is on another. The Network menu keeps it as an item, so the
    /// menu shows what is saved and choosing any other item replaces it.
    public let unavailableChoice: String?
    /// Why the station is not on the network chosen. It stays in the
    /// sign-in status until that network has an address again or another is
    /// chosen (SPEC.md D-14).
    public let problem: String?
    private let unavailableName: String?

    public var isEveryNetwork: Bool { host == Self.anyAddress }

    /// The Network menu's item for this: Every Network, the chosen interface
    /// (with an address or not), or the default's. Empty when the Mac is on
    /// no network and none was chosen.
    public var selection: String {
        isEveryNetwork ? Self.everyNetwork : unavailableChoice ?? network?.interface ?? ""
    }

    /// One item of Settings › General's Network menu.
    public struct MenuItem: Hashable, Sendable, Identifiable {
        public let tag: String
        public let label: String
        public var id: String { tag }
    }

    /// Settings › General's Network menu: each interface once, at its first
    /// address; the chosen interface when it has no address ("Ethernet
    /// (en7), No Address"); and Every Network.
    public func menu(among networks: [SignInNetwork]) -> [MenuItem] {
        networks.oneEachInterface.map { MenuItem(tag: $0.interface, label: $0.label) }
            + (unavailableChoice.map { [MenuItem(tag: $0, label: "\(unavailableName ?? $0), No Address")] } ?? [])
            + [MenuItem(tag: Self.everyNetwork, label: Self.everyNetworkLabel)]
    }

    /// Whether Settings shows the Network menu. One network, served, is no
    /// choice. A saved choice other than it, Every Network or a network with
    /// no address, is shown so it can be seen and changed.
    public func showsMenu(among networks: [SignInNetwork]) -> Bool {
        let interfaces = networks.oneEachInterface.count
        return interfaces > 1 || unavailableChoice != nil || (isEveryNetwork && interfaces == 1)
    }

    /// - Parameters:
    ///   - choice: the saved BSD name, `everyNetwork`, or nil (or empty) for
    ///     the default, `preferred`.
    ///   - networks: this Mac's IPv4 addresses, as `SignInNetwork.current()`
    ///     orders them.
    ///   - kinds: System Settings' names by BSD name, to name a chosen
    ///     interface that has no address now.
    public init(choice: String?, among networks: [SignInNetwork], kinds: [String: String] = [:]) {
        let choice = choice ?? ""
        if choice == Self.everyNetwork {
            host = Self.anyAddress
            network = nil
            unavailableChoice = nil
            unavailableName = nil
            problem = nil
            return
        }
        let chosen = choice.isEmpty ? nil : networks.first { $0.interface == choice }
        let serving = chosen ?? networks.preferred
        host = serving?.ipv4 ?? Self.loopback
        network = serving
        if choice.isEmpty || chosen != nil {
            unavailableChoice = nil
            unavailableName = nil
            problem = nil
        } else {
            let name = SignInNetwork.name(choice, kind: kinds[choice])
            unavailableChoice = choice
            unavailableName = name
            problem = Self.unavailable(name, instead: serving)
        }
    }

    /// The chosen network has no address, and the station is on `instead`.
    public static func unavailable(_ chosen: String, instead: SignInNetwork?) -> String {
        "\(chosen), chosen for sign-in in Settings › General, has no address. "
            + "Until it has one, or until you choose another network there, "
            + (instead.map { "the sign-in station is on \($0.label)." }
                ?? "only this Mac can open the sign-in page.")
    }
}

extension SignInNetwork {
    /// Every active IPv4 address except loopback and link-local, `en*`
    /// (Wi-Fi and Ethernet) first, then by BSD name.
    public static func current() -> [SignInNetwork] {
        let system = systemInterfaces()
        var interfaceList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceList) == 0, let first = interfaceList else { return [] }
        defer { freeifaddrs(interfaceList) }

        var found: [SignInNetwork] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard let socketAddress = entry.pointee.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0
            else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(socketAddress, socklen_t(socketAddress.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let ipv4 = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let interface = String(cString: entry.pointee.ifa_name)
            let network = SignInNetwork(interface: interface, kind: system[interface]?.kind, ipv4: ipv4,
                                        isWiFi: system[interface]?.isWiFi ?? false)
            if !ipv4.hasPrefix("169.254.") && !found.contains(network) {
                found.append(network)
            }
        }
        return found.venueNetworksFirst
    }

    /// What System Settings › Network calls each interface, by BSD name,
    /// whether or not it has an address now.
    public static func kinds() -> [String: String] {
        systemInterfaces().mapValues(\.kind)
    }

    private static func systemInterfaces() -> [String: (kind: String, isWiFi: Bool)] {
        var found: [String: (kind: String, isWiFi: Bool)] = [:]
        for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            if let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?,
               let kind = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                let type = SCNetworkInterfaceGetInterfaceType(interface) as String?
                found[bsdName] = (kind, type == kSCNetworkInterfaceTypeIEEE80211 as String)
            }
        }
        return found
    }
}
