import XCTest
@testable import Feedoback

/// Answers a request without a network, so these tests are about what the SDK
/// sends and how it reads what comes back — not about reaching a server.
final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var seen: [URLRequest] = []
    /// URLSession turns `httpBody` into a stream before a protocol sees the
    /// request, and a stream reads once — so it is captured here, in order.
    nonisolated(unsafe) static var bodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// What was posted with the nth request.
    static func body(_ index: Int = 0) -> Data? {
        bodies.indices.contains(index) ? bodies[index] : nil
    }

    static func reset() {
        handler = nil
        seen = []
        bodies = []
    }

    override func startLoading() {
        StubProtocol.seen.append(request)
        StubProtocol.bodies.append(
            request.httpBody ?? request.httpBodyStream.map(StubProtocol.drain) ?? Data())
        guard let handler = StubProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class TransportTests: XCTestCase {
    private let host = URL(string: "https://feedoback.test")!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        StubProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: configuration)
    }

    private func transport(bundleId: String = "com.acme.shop") -> FeedobackTransport {
        FeedobackTransport(
            host: host,
            projectKey: "pk_test",
            identity: FeedobackClientIdentity(
                bundleId: bundleId, installId: "install-1", sdkVersion: "0.1.0"),
            session: session)
    }

    private func answer(_ status: Int, _ json: String, headers: [String: String] = [:]) {
        StubProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            return (response, Data(json.utf8))
        }
    }

    private var configJSON: String {
        """
        {"projectName":"Acme","enabled":true,
         "appearance":{"color":"#0f6e56","size":"medium","position":"bottom-right",
         "rating":true,"welcome":"Hi","label":"Feedback","icon":"",
         "actions":{"point":false,"record":false,"feedback":true},
         "bubble":true,"bubbleSeconds":0}}
        """
    }

    // MARK: - Declaring itself

    /// A native client sends no Origin, so this is what the gate reads instead.
    func testEveryRequestDeclaresTheAppAndTheInstall() async throws {
        answer(200, configJSON)
        _ = try await transport().config(for: nil)

        let request = try XCTUnwrap(StubProtocol.seen.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: FeedobackHeader.platform), "ios")
        XCTAssertEqual(request.value(forHTTPHeaderField: FeedobackHeader.app), "com.acme.shop")
        XCTAssertEqual(request.value(forHTTPHeaderField: FeedobackHeader.install), "install-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: FeedobackHeader.sdk), "ios/0.1.0")
    }

    func testAsksTheProjectItWasGiven() async throws {
        answer(200, configJSON)
        _ = try await transport().config(for: nil)

        let url = try XCTUnwrap(StubProtocol.seen.first?.url)
        XCTAssertEqual(url.path, "/api/widget/pk_test/config")
    }

    func testCarriesTheIdentityTheAppDeclared() async throws {
        answer(200, configJSON)
        _ = try await transport().config(
            for: FeedobackVisitor(id: "u_1", email: "ada@example.com", name: "Ada", userHash: "abc"))

        let url = try XCTUnwrap(StubProtocol.seen.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
        XCTAssertEqual(byName["id"], "u_1")
        XCTAssertEqual(byName["email"], "ada@example.com")
        XCTAssertEqual(byName["hash"], "abc")
    }

    func testSendsNoQueryAtAllForAnAnonymousVisitor() async throws {
        answer(200, configJSON)
        _ = try await transport().config(for: FeedobackVisitor())

        XCTAssertNil(StubProtocol.seen.first?.url?.query)
    }

    // MARK: - Reading the answer

    func testReadsADormantConfigAsAnAnswerRatherThanAFailure() async throws {
        answer(200, """
            {"projectName":"Acme","enabled":false,"reason":"mobile-not-enabled",
             "appearance":{"color":"#0f6e56","size":"medium","position":"bottom-right",
             "rating":true,"welcome":"","label":"Feedback","icon":"",
             "actions":{"point":false,"record":false,"feedback":true},
             "bubble":false,"bubbleSeconds":0}}
            """)

        let config = try await transport().config(for: nil)

        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.reason, .mobileNotEnabled)
    }

    func testTellsAnUnknownProjectApartFromARefusal() async {
        answer(404, #"{"error":"unknown-project"}"#)
        await assertThrows(.unknownProject) { try await self.transport().config(for: nil) }

        answer(403, #"{"error":"Not allowed","reason":"app-not-allowed"}"#)
        await assertThrows(.refused(.appNotAllowed)) { try await self.transport().config(for: nil) }
    }

    /// A refusal the SDK does not recognise is still a refusal; it just has
    /// nothing useful to print.
    func testARefusalWithNoReasonIsStillARefusal() async {
        answer(403, #"{"error":"Not allowed"}"#)
        await assertThrows(.refused(nil)) { try await self.transport().config(for: nil) }
    }

    func testReadsHowLongToWaitWhenItIsToldToSlowDown() async {
        answer(429, #"{"error":"Too many requests"}"#, headers: ["Retry-After": "30"])
        await assertThrows(.rateLimited(retryAfter: 30)) {
            try await self.transport().config(for: nil)
        }
    }

    /// Nothing reached the server, so the words are worth keeping for later.
    func testAnUnreachableServerIsItsOwnKindOfFailure() async {
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await assertThrows(.unreachable) { try await self.transport().config(for: nil) }
    }

    // MARK: - Opening a thread

    func testPostsTheThreadAsJSON() async throws {
        answer(201, #"{"threadId":"t_1"}"#)

        let request = FeedobackThreadRequest(
            category: .bug,
            body: "Cart total is wrong",
            pageContext: FeedobackScreenContext(
                route: "cart", title: "Cart", bundleId: "com.acme.shop",
                appVersion: "2.8.1", buildNumber: "4213", osVersion: "18.2",
                deviceModel: "iPhone 16 Pro", locale: "en-GB", timezone: "Europe/London",
                viewport: FeedobackViewport(width: 393, height: 852),
                scale: 3, orientation: .portrait))

        let id = try await transport().createThread(request)
        XCTAssertEqual(id, "t_1")

        let sent = try XCTUnwrap(StubProtocol.seen.first)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(StubProtocol.body())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["category"] as? String, "bug")
        let context = try XCTUnwrap(object["pageContext"] as? [String: Any])
        XCTAssertEqual(context["platform"] as? String, "ios")
        XCTAssertEqual(context["route"] as? String, "cart")
    }

    // MARK: - Uploading

    func testAsksForATicketThenPutsTheBytesThroughTheApp() async throws {
        var call = 0
        StubProtocol.handler = { request in
            call += 1
            let json = call == 1
                ? #"{"uploadUrl":"/api/uploads/screenshots/abc.jpeg","storageKey":"screenshots/abc.jpeg"}"#
                : "{}"
            let response = HTTPURLResponse(
                url: request.url!, statusCode: call == 1 ? 201 : 200,
                httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let attachment = try await transport().upload(
            Data(repeating: 7, count: 1024), kind: "screenshot", contentType: "image/jpeg")

        XCTAssertEqual(attachment.storageKey, "screenshots/abc.jpeg")
        XCTAssertEqual(attachment.sizeBytes, 1024)
        XCTAssertEqual(StubProtocol.seen.count, 2)
        // The bytes go to the app's own route, never straight to storage.
        XCTAssertEqual(StubProtocol.seen[1].httpMethod, "PUT")
        XCTAssertEqual(StubProtocol.seen[1].url?.host, "feedoback.test")
        XCTAssertEqual(StubProtocol.seen[1].url?.path, "/api/uploads/screenshots/abc.jpeg")
    }

    // MARK: - Helpers

    private func assertThrows(
        _ expected: FeedobackTransportError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ work: () async throws -> Void
    ) async {
        do {
            try await work()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as FeedobackTransportError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected \(expected), got \(error)", file: file, line: line)
        }
    }
}
