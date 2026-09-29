import EagleBoardsCore
import Foundation
import Testing

/// Answers SignUpGenius requests from canned JSON, so the client's parsing is
/// tested without the network or a key. Everything here is made up.
final class StubbedSignUpGenius: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var bodies: [String: String] = [:]
    nonisolated(unsafe) static var requestedURLs: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.requestedURLs.append(url)
        let body = Self.bodies.first { url.path.contains($0.key) }?.value
        let response = HTTPURLResponse(url: url, statusCode: body == nil ? 401 : 200, httpVersion: nil, headerFields: nil)!
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
        let client = SignUpGeniusClient(apiKey: "secret-looking-key", session: StubbedSignUpGenius.session)
        do {
            _ = try await client.findActiveSignup(today: "2026-09-22")
            Issue.record("expected a refusal")
        } catch {
            #expect(error.localizedDescription.contains("HTTP 401"))
            #expect(!error.localizedDescription.contains("secret-looking-key"))
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
