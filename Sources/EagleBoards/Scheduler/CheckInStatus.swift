import CoreImage.CIFilterBuiltins
import EagleBoardsCore
import SwiftUI

/// The toolbar's report on the sign-in station, and where to point a tablet.
struct CheckInStatusButton: View {
    @Environment(AppModel.self) private var model
    @AppStorage(CheckInAddress.chosenHostKey) private var chosenHost = ""
    @State private var showingDetails = false

    var body: some View {
        Button {
            showingDetails.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 9, height: 9)
                if servedEventNote != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                Text(summary)
            }
        }
        .help(servedEventNote.map { "Where the sign-in tablets connect. They sign people in \($0), the open event, not today." }
            ?? "Where the sign-in tablets connect")
        .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
            CheckInDetails()
                .environment(model)
        }
    }

    private var indicatorColor: Color {
        switch model.serverState {
        case .running: .green
        case .starting: .yellow
        case .stopped: .secondary
        case .failed: .red
        }
    }

    /// Said only while serving: a stopped or failed station signs nobody in.
    private var servedEventNote: String? {
        model.isServing ? model.servedEventNote : nil
    }

    private var summary: String {
        switch model.serverState {
        case .running:
            (model.checkInAddresses.chosen(chosenHost).map { "Sign-in: \($0.host):\($0.url.port ?? 0)" } ?? "Sign-in: this Mac only")
                + (servedEventNote.map { " \($0)" } ?? "")
        case .starting: "Starting sign-in…"
        case .stopped: "Sign-in stopped"
        case .failed: "Sign-in not running"
        }
    }
}

struct CheckInDetails: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(CheckInAddress.chosenHostKey) private var chosenHost = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.serverState {
            case .running(let port):
                let addresses = model.checkInAddresses
                if let primary = addresses.chosen(chosenHost) {
                    Text("Open this on the sign-in tablet" + (model.servedEventNote.map { " \($0)" } ?? ""))
                        .font(.headline)
                    if addresses.count > 1 {
                        NetworkPicker(addresses: addresses, chosenHost: $chosenHost)
                    }
                    HStack(alignment: .top, spacing: 16) {
                        // Dark on white whatever the appearance, so a camera can read it.
                        QRCodeImage(text: primary.url.absoluteString)
                            .frame(width: 150, height: 150)
                            .padding(12)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("QR code for \(primary.url.absoluteString)")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(primary.url.absoluteString)
                                .font(.title3.monospaced())
                                .textSelection(.enabled)
                            Text("Scan the code with the tablet's camera, or type the address into its browser. "
                                + "The tablet must be on the same network as this Mac.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: 280, alignment: .leading)
                    }
                } else {
                    Label("This Mac is not on a network", systemImage: "wifi.slash")
                        .font(.headline)
                    Text("Join the venue's Wi-Fi so a tablet can reach the sign-in page. It is open on this Mac at http://127.0.0.1:\(port)/.")
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Open Sign-In Page Here") {
                        if let url = model.localSignInURL { NSWorkspace.shared.open(url) }
                    }
                    Button("Show Code in a Window") { openWindow(id: WindowID.signInCode) }
                        .help("A large code to put on a second display or a projector by the door")
                    Spacer()
                    Text("Only the sign-in pages are on the network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                NoticeLabel("The sign-in station is not running", systemImage: "exclamationmark.triangle.fill", tint: .red)
                    .font(.headline)
                // To copy into a message or a search.
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack {
                    Button("Try Again") { model.startServer() }
                    // The failure may say to choose another port there.
                    SettingsLink { Text("Open Settings…") }
                }
            case .starting:
                ProgressView("Starting the sign-in station…")
            case .stopped:
                Text("The sign-in station starts when an event is open.")
            }
        }
        .padding(16)
        .frame(width: 504)
    }
}

/// The networks this Mac is on, to choose the one the sign-in tablet is on.
/// The choice is kept, so the Sign-In Code window and the toolbar popover
/// draw the same code.
struct NetworkPicker: View {
    let addresses: [CheckInAddress]
    @Binding var chosenHost: String

    var body: some View {
        Picker("Network", selection: Binding(
            get: { addresses.chosen(chosenHost)?.host ?? "" },
            set: { chosenHost = $0 }
        )) {
            ForEach(addresses) { address in
                Text("\(address.network) (\(address.host))").tag(address.host)
            }
        }
        .fixedSize()
    }
}

/// A QR code, drawn crisp at any size.
struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(.secondary)
        }
    }

    /// One pixel per module. Core Image leaves one module of white around
    /// the code; four more clear the standard's four-module quiet zone, so
    /// a camera reads it on any background.
    private static func render(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let padded = output.extent.insetBy(dx: -4, dy: -4)
        let onWhite = output.composited(over: CIImage(color: .white).cropped(to: padded))
        return CIContext().createCGImage(onWhite, from: padded)
    }
}
