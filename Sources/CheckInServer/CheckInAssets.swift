import Foundation
import Hummingbird

/// The sign-in pages, read once from the app's resources.
///
/// Only the files listed here are ever served, by exact path, so a request
/// can never reach anything else on disk.
enum CheckInAssets {
    struct Page: Sendable {
        let path: String
        let contentType: String
        let body: Data

        func response() -> Response {
            Response(
                status: .ok,
                headers: [.contentType: contentType],
                body: .init(byteBuffer: ByteBuffer(bytes: body))
            )
        }
    }

    static let pages: [Page] = {
        let files: [(path: String, file: String, contentType: String)] = [
            ("/", "index.html", "text/html; charset=utf-8"),
            ("/youth_register", "youth_register.html", "text/html; charset=utf-8"),
            ("/adult_register", "adult_register.html", "text/html; charset=utf-8"),
            ("/checkin.css", "checkin.css", "text/css; charset=utf-8"),
            ("/checkin.js", "checkin.js", "text/javascript; charset=utf-8"),
        ]
        return files.map { entry in
            let body = (try? Data(contentsOf: directory.appending(path: entry.file))) ?? Data()
            return Page(path: entry.path, contentType: entry.contentType, body: body)
        }
    }()

    /// Where the pages are. Inside the built app, `scripts/build-app.sh` puts
    /// the resource bundle in `Contents/Resources`; under `swift test` it sits
    /// beside the test binary, where SwiftPM's own `Bundle.module` finds it.
    /// The app's copy is checked first because `Bundle.module` looks beside
    /// the executable and would stop the app if it were not there.
    static let directory: URL = {
        if let bundleURL = Bundle.main.url(forResource: "EagleBoards_CheckInServer", withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL),
           let pagesURL = bundle.url(forResource: "CheckIn", withExtension: nil) {
            return pagesURL
        }
        return Bundle.module.url(forResource: "CheckIn", withExtension: nil)!
    }()
}
