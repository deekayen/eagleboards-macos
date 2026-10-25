import Darwin
import Foundation
import SystemConfiguration

/// The addresses a sign-in tablet on the same network could use to reach
/// this Mac.
enum NetworkAddresses {
    struct Address: Hashable, Identifiable {
        /// BSD name, e.g. `en0`.
        let interface: String
        let ipv4: String
        var id: String { "\(interface) \(ipv4)" }

        /// Wi-Fi and Ethernet are `en*`. Anything else is usually a VPN,
        /// a virtual machine's bridge, or a phone's hotspot link.
        var isLikelyVenueNetwork: Bool { interface.hasPrefix("en") }
    }

    /// Every active IPv4 address except loopback, venue-network ones first.
    static func current() -> [Address] {
        var interfaceList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceList) == 0, let first = interfaceList else { return [] }
        defer { freeifaddrs(interfaceList) }

        var found: [Address] = []
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
            let numericHost = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let address = Address(interface: String(cString: entry.pointee.ifa_name), ipv4: numericHost)
            if !address.ipv4.hasPrefix("169.254.") && !found.contains(address) {
                found.append(address)
            }
        }
        return found.sorted { lhs, rhs in
            if lhs.isLikelyVenueNetwork != rhs.isLikelyVenueNetwork {
                return lhs.isLikelyVenueNetwork
            }
            return lhs.interface < rhs.interface
        }
    }

    /// What System Settings › Network calls each interface ("Wi-Fi",
    /// "Ethernet"), by BSD name. A VPN or a bridge it does not list is left
    /// out, to go by its BSD name.
    static func displayNames() -> [String: String] {
        var names: [String: String] = [:]
        for interface in SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? [] {
            if let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?,
               let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? {
                names[bsdName] = name
            }
        }
        return names
    }
}

/// One address a sign-in tablet can open, as the Sign-In Code window, the
/// toolbar popover and the toolbar's summary offer it.
struct CheckInAddress: Hashable, Identifiable {
    /// The interface it is on, as System Settings names it, or its BSD name.
    let network: String
    let url: URL
    var id: URL { url }
    var host: String { url.host() ?? "" }

    /// The Network picker's choice, kept so the projector's window and the
    /// popover draw the same code.
    static let chosenHostKey = "signInCodeHost"
}

extension [CheckInAddress] {
    /// The address chosen in the Network picker, or the first (the likeliest
    /// venue network) when none is chosen or the chosen one is gone.
    func chosen(_ host: String) -> CheckInAddress? {
        first { $0.host == host } ?? first
    }
}
