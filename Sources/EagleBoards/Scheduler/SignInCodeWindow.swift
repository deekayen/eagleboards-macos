import EagleBoardsCore
import SwiftUI

/// The sign-in address as a large QR code, in a window of its own: drag it
/// to a second display or a projector by the door, or make it full screen.
/// It grows with the window.
struct SignInCodeWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let url = model.checkInURLs.first {
                VStack(spacing: 20) {
                    Text("Sign in for Eagle Boards")
                        .font(.largeTitle.bold())
                    QRCodeImage(text: url.absoluteString)
                        .padding(16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("QR code for \(url.absoluteString)")
                    Text(url.absoluteString)
                        .font(.title.monospaced())
                        .textSelection(.enabled)
                    Text("Scan the code with the tablet's camera, or type the address into its browser. "
                        + "The tablet must be on the same Wi-Fi.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
            } else {
                ContentUnavailableView {
                    Label(unavailableTitle, systemImage: "qrcode")
                } description: {
                    Text(unavailableDetail)
                }
            }
        }
        .frame(minWidth: 360, idealWidth: 560, maxWidth: .infinity, minHeight: 420, idealHeight: 680, maxHeight: .infinity)
    }

    private var unavailableTitle: String {
        switch model.serverState {
        case .running: "Not on a Network"
        case .starting: "Starting the Sign-In Station"
        case .stopped, .failed: "The Sign-In Station Is Not Running"
        }
    }

    private var unavailableDetail: String {
        switch model.serverState {
        case .running: "Join the venue's Wi-Fi so a tablet can reach the sign-in page."
        case .starting: "The code appears in a moment."
        case .stopped: "It starts when an event is open."
        case .failed(let message): message
        }
    }
}
