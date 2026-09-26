import CoreImage.CIFilterBuiltins
import EagleBoardsCore
import SwiftUI

/// The toolbar's report on the sign-in station, and where to point a tablet.
struct CheckInStatusButton: View {
    @Environment(AppModel.self) private var model
    @State private var showingDetails = false

    var body: some View {
        Button {
            showingDetails.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 9, height: 9)
                Text(summary)
            }
        }
        .help("Where the sign-in tablets connect")
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

    private var summary: String {
        switch model.serverState {
        case .running: model.checkInURLs.first.map { "Sign-in: \($0.host() ?? ""):\($0.port ?? 0)" } ?? "Sign-in: this Mac only"
        case .starting: "Starting sign-in…"
        case .stopped: "Sign-in stopped"
        case .failed: "Sign-in not running"
        }
    }
}

struct CheckInDetails: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.serverState {
            case .running(let port):
                let addresses = model.checkInURLs
                if let primary = addresses.first {
                    Text("Open this on the sign-in tablet").font(.headline)
                    HStack(alignment: .top, spacing: 16) {
                        QRCodeImage(text: primary.absoluteString)
                            .frame(width: 150, height: 150)
                            .accessibilityLabel("QR code for \(primary.absoluteString)")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(primary.absoluteString)
                                .font(.title3.monospaced())
                                .textSelection(.enabled)
                            Text("Scan the code with the tablet's camera, or type the address into its browser. "
                                + "The tablet must be on the same network as this Mac.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if addresses.count > 1 {
                                Text("Other addresses for this Mac:")
                                    .font(.callout.bold())
                                    .padding(.top, 4)
                                ForEach(addresses.dropFirst(), id: \.self) { url in
                                    Text(url.absoluteString).font(.callout.monospaced()).textSelection(.enabled)
                                }
                            }
                        }
                        .frame(width: 280, alignment: .leading)
                    }
                } else {
                    Label("This Mac is not on a network", systemImage: "wifi.slash")
                        .font(.headline)
                    Text("Join the venue's Wi-Fi so a tablet can reach the sign-in page. It is open on this Mac at http://127.0.0.1:\(port)/.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Open Sign-In Page Here") {
                        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(port)/")!)
                    }
                    Button("Show Code in a Window") { openWindow(id: WindowID.signInCode) }
                        .help("A large code to put on a second display or a projector by the door")
                    Spacer()
                    Text("Only the sign-in pages are on the network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .failed(let message):
                Label("The sign-in station is not running", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message).fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { model.startServer() }
            case .starting:
                ProgressView("Starting the sign-in station…")
            case .stopped:
                Text("The sign-in station starts when an event is open.")
            }
        }
        .padding(16)
        .frame(width: 480)
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

    private static func render(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
