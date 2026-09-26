import AppKit
import SwiftUI

/// Ways to support the app's author, the same list as the author's GitHub
/// FUNDING.yml. Offered in the Help menu and the About window, never on the
/// operator's screens.
enum SupportLink: CaseIterable, Identifiable {
    case githubSponsors
    case koFi
    case liberapay
    case payPal
    case venmo
    case buyMeACoffee

    var id: Self { self }

    var title: String {
        switch self {
        case .githubSponsors: "GitHub Sponsors"
        case .koFi: "Ko-fi"
        case .liberapay: "Liberapay"
        case .payPal: "PayPal"
        case .venmo: "Venmo"
        case .buyMeACoffee: "Buy Me a Coffee"
        }
    }

    var url: URL {
        switch self {
        case .githubSponsors: URL(string: "https://github.com/sponsors/deekayen")!
        case .koFi: URL(string: "https://ko-fi.com/deekayen")!
        case .liberapay: URL(string: "https://liberapay.com/deekayen")!
        case .payPal: URL(string: "https://paypal.me/deekayen")!
        case .venmo: URL(string: "https://venmo.com/drdnorman")!
        case .buyMeACoffee: URL(string: "https://buymeacoff.ee/deekayen")!
        }
    }
}

/// The Help menu's Donate submenu.
struct DonateMenu: View {
    var body: some View {
        Menu("Donate") {
            ForEach(SupportLink.allCases) { link in
                Button(link.title) { NSWorkspace.shared.open(link.url) }
            }
        }
    }
}

enum AboutPanel {
    /// The standard About window, with a line on supporting the app and a
    /// link for each way to do it.
    @MainActor
    static func show() {
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let credits = NSMutableAttributedString(
            string: "Free to use. If it helps your district's board nights, you can support its development:\n",
            attributes: [.font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: centered]
        )
        for (index, link) in SupportLink.allCases.enumerated() {
            if index > 0 {
                credits.append(NSAttributedString(
                    string: " · ",
                    attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: centered]
                ))
            }
            credits.append(NSAttributedString(
                string: link.title,
                attributes: [.font: body, .link: link.url, .paragraphStyle: centered]
            ))
        }
        NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApplication.shared.activate()
    }
}
