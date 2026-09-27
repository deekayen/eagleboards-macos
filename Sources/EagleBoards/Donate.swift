import AppKit
import SwiftUI

/// Ways to support the app's author, the same list as the author's GitHub
/// FUNDING.yml. Offered in the Help menu, the About window and the Donate
/// button at the foot of the scheduler's sidebar (SPEC.md D-17); never in the
/// queue, the rooms or the inspector.
enum SupportLink: CaseIterable, Identifiable {
    case githubSponsors
    case koFi
    case liberapay
    case payPal
    case venmo
    case buyMeACoffee

    var id: Self { self }

    /// Venmo's Pay screen with the note filled in, for the popover's QR code
    /// (SPEC.md D-17).
    static let venmoPay = URL(string: "https://venmo.com/u/drdnorman?txn=pay&note=Eagle%20Boards")!

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

/// The Donate button at the foot of the scheduler's sidebar (SPEC.md D-17):
/// a popover with the links, like the Support card in the other versions'
/// Settings.
struct DonateButton: View {
    @State private var showsLinks = false

    var body: some View {
        Button {
            showsLinks.toggle()
        } label: {
            Label("Donate", systemImage: "heart")
        }
        .buttonStyle(.borderless)
        .help("Ways to support Eagle Boards")
        .popover(isPresented: $showsLinks, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Support this project")
                    .font(.headline)
                Text("Eagle Boards is free, and built and kept up by a volunteer. If it helps your board events, you can chip in through any of these.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(SupportLink.allCases) { link in
                        Button {
                            NSWorkspace.shared.open(link.url)
                        } label: {
                            Text(link.title).frame(maxWidth: .infinity)
                        }
                        .help(link.url.absoluteString)
                    }
                }
                .padding(.top, 4)
                // Dark on white whatever the appearance, so a phone camera can read it.
                HStack(spacing: 12) {
                    QRCodeImage(text: SupportLink.venmoPay.absoluteString)
                        .frame(width: 116, height: 116)
                        .padding(8)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("QR code to pay with Venmo")
                    Text("Or scan this with your phone to pay with Venmo.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }
            .padding(16)
            .frame(width: 320)
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
            string: "Free to use. If it helps your district's board events, you can support its development:\n",
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
