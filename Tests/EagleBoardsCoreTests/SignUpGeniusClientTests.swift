import EagleBoardsCore
import Foundation
import Testing

/// Answers SignUpGenius requests from canned JSON, so the client's parsing is
/// tested without the network or a key. Everything here is made up.
final class StubbedSignUpGenius: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var bodies: [String: String] = [:]
    nonisolated(unsafe) static var requestedURLs: [URL] = []
    /// What a request with no canned body is answered with.
    nonisolated(unsafe) static var refusal = 401
    /// When set, every request fails with it, as with no network.
    nonisolated(unsafe) static var failure: URLError?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.requestedURLs.append(url)
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let body = Self.bodies.first { url.path.contains($0.key) }?.value
        let response = HTTPURLResponse(url: url, statusCode: body == nil ? Self.refusal : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "{}").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubbedSignUpGenius.self]
        return URLSession(configuration: configuration)
    }
}

@Suite("SignUpGenius client", .serialized)
struct SignUpGeniusClientTests {
    @Test func findsTheEagleBoardSignUpCoveringTodayEvenOnItsFirstDay() async throws {
        StubbedSignUpGenius.bodies = [
            "created/active": """
                {"data": [
                  {"signupid": 111, "title": "Spring Campout", "startdatestring": "2026-09-01 08:00:00", "enddatestring": "2026-09-30 17:00:00"},
                  {"signupid": 222, "title": "Eagle Board of Review - September", "startdatestring": "2026-09-22 18:30:00", "enddatestring": "2026-09-22 21:00:00"}
                ]}
                """,
        ]
        let client = SignUpGeniusClient(apiKey: "test-key", session: StubbedSignUpGenius.session)
        let signup = try await client.findActiveSignup(today: "2026-09-22")
        #expect(signup.id == "222")
        #expect(signup.title.contains("Eagle Board"))
        #expect(StubbedSignUpGenius.requestedURLs.last?.query == "user_key=test-key")

        await #expect(throws: EventError.self) { try await client.findActiveSignup(today: "2026-09-23") }
    }

    @Test func readsFilledSlotsAndTheirCustomAnswers() async throws {
        StubbedSignUpGenius.bodies = [
            "report/filled/222": """
                {"data": {"signup": [
                  {"startdatestring": "2026-09-22 19:00:00", "firstname": "jan", "lastname": "doe", "item": "Eagle Board of Review",
                   "email": "jan@example.org", "customfields": [{"value": "Troop 1776"}, {"value": 7705550100}, {"value": "lee leader"}]},
                  {"startdatestring": "2026-09-22 19:00:00", "firstname": "Morgan", "lastname": "Member", "item": "Adult Board Member",
                   "email": "morgan@example.org"}
                ]}}
                """,
        ]
        let client = SignUpGeniusClient(apiKey: "test-key", session: StubbedSignUpGenius.session)
        let entries = try await client.filledSlots(signupID: "222")
        #expect(entries.count == 2)
        #expect(entries[0].unitText == "Troop 1776")
        #expect(entries[0].phoneText == "7705550100", "a number in the JSON reads as its digits")
        #expect(entries[0].leaderText == "lee leader")
        #expect(!entries[0].isAdultSlot)
        #expect(entries[1].isAdultSlot)
        #expect(entries[1].customAnswers.isEmpty)
    }

    @Test func aRejectedKeySaysSoWithoutRepeatingIt() async throws {
        StubbedSignUpGenius.bodies = [:]
        StubbedSignUpGenius.refusal = 401
        let client = SignUpGeniusClient(apiKey: "secret-looking-key", session: StubbedSignUpGenius.session)
        do {
            _ = try await client.findActiveSignup(today: "2026-09-22")
            Issue.record("expected a refusal")
        } catch {
            #expect(error.localizedDescription
                == "SignUpGenius didn't accept the API key. Check the key in Settings › SignUpGenius, and then import again.")
            #expect(!error.localizedDescription.contains("secret-looking-key"))
        }
    }

    /// Only a 401 or 403 blames the key: an outage would otherwise send the
    /// operator to Settings to change a key that works. No status number is
    /// shown, as in the Windows version.
    @Test func anOutageDoesNotBlameTheKey() async throws {
        StubbedSignUpGenius.bodies = [:]
        StubbedSignUpGenius.refusal = 503
        defer { StubbedSignUpGenius.refusal = 401 }
        let client = SignUpGeniusClient(apiKey: "test-key", session: StubbedSignUpGenius.session)
        do {
            _ = try await client.findActiveSignup(today: "2026-09-22")
            Issue.record("expected a refusal")
        } catch {
            #expect(error.localizedDescription == "SignUpGenius couldn't send the sign-ups just now. Try the import again later.")
            #expect(!error.localizedDescription.contains("API key") && !error.localizedDescription.contains("503"))
        }
    }

    /// No answer at all keeps the system's reason, the only clue there is
    /// with no log, and says what to do. The key stays out of it.
    @Test func noAnswerSaysToCheckTheConnection() async throws {
        StubbedSignUpGenius.failure = URLError(.notConnectedToInternet)
        defer { StubbedSignUpGenius.failure = nil }
        let client = SignUpGeniusClient(apiKey: "secret-looking-key", session: StubbedSignUpGenius.session)
        do {
            _ = try await client.findActiveSignup(today: "2026-09-22")
            Issue.record("expected a refusal")
        } catch {
            let text = error.localizedDescription
            let opening = "Couldn't reach SignUpGenius: ", ending = " Check the internet connection, and then import again."
            #expect(text.hasPrefix(opening) && text.hasSuffix(ending))
            let reason = text.dropFirst(opening.count).dropLast(ending.count)
            #expect(reason.count > 1 && reason.last.map { ".!?".contains($0) } == true && !reason.hasSuffix(".."),
                    "the system's reason, ended once")
            #expect(!text.contains("secret-looking-key"))
        }
    }

    @Test(arguments: [(401, true), (403, true), (404, false), (429, false), (500, false)])
    func onlyARefusedKeyIsTheKeysFault(status: Int, blamesTheKey: Bool) {
        #expect(SignUpGeniusClient.problem(forStatus: status).contains("API key") == blamesTheKey)
        #expect(!SignUpGeniusClient.problem(forStatus: status).contains("\(status)"))
    }

    @Test func anAnswerThatIsNotTheSignUpsSaysSo() async throws {
        StubbedSignUpGenius.bodies = ["created/active": "<html>Down for maintenance</html>"]
        let client = SignUpGeniusClient(apiKey: "test-key", session: StubbedSignUpGenius.session)
        await #expect(throws: EventError("SignUpGenius sent the sign-ups in a form Eagle Boards doesn't recognize.")) {
            try await client.findActiveSignup(today: "2026-09-22")
        }
    }

    /// No sign-up covering the day names it as the Mac writes dates.
    @Test func noSignUpForTheDayNamesTheDay() async throws {
        StubbedSignUpGenius.bodies = ["created/active": #"{"data": []}"#]
        let client = SignUpGeniusClient(apiKey: "test-key", session: StubbedSignUpGenius.session)
        await #expect(throws: EventError("SignUpGenius has no active Eagle board sign-up covering \(Timestamp.shownDate("2026-09-22")).")) {
            try await client.findActiveSignup(today: "2026-09-22")
        }
    }
}

/// The real API, when CI has the `SUG_KEY` secret. It checks that the key is
/// accepted and the answer still parses; it prints nothing it receives.
@Suite("SignUpGenius live API")
struct SignUpGeniusLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SUG_KEY"]?.isEmpty == false))
    func theKeyIsAcceptedAndTheAnswerParses() async throws {
        let key = ProcessInfo.processInfo.environment["SUG_KEY"] ?? ""
        let client = SignUpGeniusClient(apiKey: key)
        do {
            let signup = try await client.findActiveSignup(today: Timestamp.dayStamp(for: Date()))
            _ = try await client.filledSlots(signupID: signup.id)
        } catch let refusal as EventError where refusal.message.contains("no active Eagle board sign-up") {
            // The key works and the list parsed; there is simply no board event today.
        }
    }
}
