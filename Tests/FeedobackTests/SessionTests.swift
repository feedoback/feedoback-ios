import XCTest
@testable import Feedoback

final class SessionTests: XCTestCase {
    private var defaults: MemoryDefaults!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        defaults = MemoryDefaults()
        StubProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: configuration)
    }

    private func screen() -> FeedobackScreenContext {
        FeedobackScreenContext(
            route: "cart", title: "Cart", bundleId: "com.acme.shop",
            appVersion: "2.8.1", buildNumber: "4213", osVersion: "18.2",
            deviceModel: "iPhone 16 Pro", locale: "en-GB", timezone: "Europe/London",
            viewport: FeedobackViewport(width: 393, height: 852),
            scale: 3, orientation: .portrait)
    }

    private func makeSession(
        store: FeedobackStore? = nil,
        metadata: @escaping @Sendable () -> [String: FeedobackValue] = { [:] }
    ) -> (FeedobackSession, FeedobackStore) {
        let store = store ?? FeedobackStore(defaults: defaults)
        let transport = FeedobackTransport(
            host: URL(string: "https://feedoback.test")!,
            projectKey: "pk_test",
            identity: FeedobackClientIdentity(
                bundleId: "com.acme.shop", installId: "install-1", sdkVersion: "0.1.0"),
            session: session)
        let context = screen()
        return (
            FeedobackSession(
                transport: transport, store: store, context: { context },
                metadata: { metadata() },
                log: FeedobackLog(level: .silent)),
            store
        )
    }

    private func answer(_ status: Int, _ json: String) {
        StubProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }
    }

    // MARK: - Sending

    func testSendsWhatTheVisitorWrote() async {
        answer(201, #"{"threadId":"t_1"}"#)
        let (session, store) = makeSession()

        let outcome = await session.send(FeedobackDraft(body: "The cart total is wrong"))

        XCTAssertEqual(outcome, .sent(threadId: "t_1"))
        let queued = await store.queued()
        XCTAssertTrue(queued.isEmpty, "nothing to keep once it arrived")
    }

    func testRefusesToSendAnEmptyForm() async {
        let (session, _) = makeSession()
        let outcome = await session.send(FeedobackDraft(body: "   "))

        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(StubProtocol.seen.isEmpty, "and does not bother the server with it")
    }

    /// A rating with no words is still feedback.
    func testARatingOnItsOwnIsWorthSending() async {
        answer(201, #"{"threadId":"t_1"}"#)
        let (session, _) = makeSession()

        let outcome = await session.send(FeedobackDraft(body: "", rating: 4))
        XCTAssertEqual(outcome, .sent(threadId: "t_1"))
    }

    func testCarriesTheIdentityTheAppDeclared() async throws {
        answer(201, #"{"threadId":"t_1"}"#)
        let (session, store) = makeSession()
        await store.setVisitor(FeedobackVisitor(id: "u_1", name: "Ada"))

        _ = await session.send(FeedobackDraft(body: "Hello"))

        let body = try XCTUnwrap(StubProtocol.body())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let visitor = try XCTUnwrap(object["visitor"] as? [String: Any])
        XCTAssertEqual(visitor["id"] as? String, "u_1")
    }

    /// The only way to answer someone the app never named.
    func testAnAddressTypedIntoTheSheetBecomesTheVisitorsOwn() async throws {
        answer(201, #"{"threadId":"t_1"}"#)
        let (session, _) = makeSession()

        _ = await session.send(FeedobackDraft(body: "Hello", email: " ada@example.com "))

        let body = try XCTUnwrap(StubProtocol.body())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let visitor = try XCTUnwrap(object["visitor"] as? [String: Any])
        XCTAssertEqual(visitor["email"] as? String, "ada@example.com")
    }

    func testDoesNotOverwriteAnAddressTheAppAlreadyGave() async throws {
        answer(201, #"{"threadId":"t_1"}"#)
        let (session, store) = makeSession()
        await store.setVisitor(FeedobackVisitor(id: "u_1", email: "real@example.com"))

        _ = await session.send(FeedobackDraft(body: "Hi", email: "typed@example.com"))

        let body = try XCTUnwrap(StubProtocol.body())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let visitor = try XCTUnwrap(object["visitor"] as? [String: Any])
        XCTAssertEqual(visitor["email"] as? String, "real@example.com")
    }

    // MARK: - What the app attached

    func testCarriesTheContextTheAppAttached() async throws {
        answer(201, #"{"threadId":"t_1"}"#)
        let (session, _) = makeSession(metadata: { ["plan": .string("pro"), "seats": .number(12)] })

        _ = await session.send(FeedobackDraft(body: "Hello"))

        let body = try XCTUnwrap(StubProtocol.body())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let metadata = try XCTUnwrap(object["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["plan"] as? String, "pro")
        XCTAssertEqual(metadata["seats"] as? Double, 12)
    }

    /// An app that attached nothing sends no key at all, rather than an empty
    /// object the dashboard would then have to render as a block with no rows.
    func testSendsNoContextKeyWhenTheAppAttachedNothing() async throws {
        answer(201, #"{"threadId":"t_1"}"#)
        let (session, _) = makeSession()

        _ = await session.send(FeedobackDraft(body: "Hello"))

        let body = try XCTUnwrap(StubProtocol.body())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(object["metadata"])
    }

    // MARK: - When it cannot get through

    func testKeepsWhatTheNetworkWouldNotTake() async {
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let (session, store) = makeSession()

        let outcome = await session.send(FeedobackDraft(body: "Written in a tunnel"))

        XCTAssertEqual(outcome, .queued)
        let queued = await store.queued()
        XCTAssertEqual(queued.first?.request.body, "Written in a tunnel")
    }

    /// A refusal will keep being a refusal. Retrying it on every launch would
    /// only cost the device battery.
    func testDoesNotKeepSomethingTheServerWillNeverTake() async {
        answer(403, #"{"error":"Not allowed","reason":"visitor-not-identified"}"#)
        let (session, store) = makeSession()

        let outcome = await session.send(FeedobackDraft(body: "Hello"))

        XCTAssertEqual(outcome, .refused(.visitorNotIdentified))
        let queued = await store.queued()
        XCTAssertTrue(queued.isEmpty)
    }

    /// The words matter more than the picture.
    func testSendsTheMessageEvenWhenTheScreenshotWillNotUpload() async throws {
        var call = 0
        StubProtocol.handler = { request in
            call += 1
            // The ticket request fails; the thread itself goes through.
            let status = call == 1 ? 500 : 201
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"threadId":"t_1"}"#.utf8))
        }
        let (session, _) = makeSession()

        let outcome = await session.send(
            FeedobackDraft(body: "Look at this", screenshot: Data(repeating: 1, count: 128)))

        XCTAssertEqual(outcome, .sent(threadId: "t_1"))
        let body = try XCTUnwrap(StubProtocol.bodies.last)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(object["attachments"], "no picture, but the message arrived")
    }

    // MARK: - The queue, later

    /// Stamped when the visitor finished writing, not when it finally went:
    /// feedback written on the pro plan does not arrive marked free because
    /// they downgraded while it sat in a tunnel.
    func testAQueuedThreadArrivesWithTheContextItWasWrittenUnder() async throws {
        let plan = Mutable("pro")
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let (session, _) = makeSession(metadata: { ["plan": .string(plan.value)] })
        _ = await session.send(FeedobackDraft(body: "Written on pro"))

        plan.value = "free"
        answer(201, #"{"threadId":"t_1"}"#)
        let sent = await session.flushQueue()

        XCTAssertEqual(sent, 1)
        let body = try XCTUnwrap(StubProtocol.bodies.last)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let metadata = try XCTUnwrap(object["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["plan"] as? String, "pro")
    }

    func testSendsWhatItKeptOnceThereIsANetworkAgain() async {
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let (session, store) = makeSession()
        _ = await session.send(FeedobackDraft(body: "One"))
        _ = await session.send(FeedobackDraft(body: "Two"))

        answer(201, #"{"threadId":"t_1"}"#)
        let sent = await session.flushQueue()

        XCTAssertEqual(sent, 2)
        let left = await store.queued()
        XCTAssertTrue(left.isEmpty)
    }

    /// Still no network: stop rather than fire a burst of doomed requests.
    func testStopsFlushingTheMomentItCannotGetThrough() async {
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let (session, store) = makeSession()
        _ = await session.send(FeedobackDraft(body: "One"))
        _ = await session.send(FeedobackDraft(body: "Two"))
        StubProtocol.reset()
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        let sent = await session.flushQueue()

        XCTAssertEqual(sent, 0)
        XCTAssertEqual(StubProtocol.seen.count, 1, "one attempt, not one per queued thread")
        let left = await store.queued()
        XCTAssertEqual(left.count, 2, "and nothing was thrown away")
    }

    func testThrowsAwayWhatTheServerRefusesRatherThanRetryingForever() async {
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let (session, store) = makeSession()
        _ = await session.send(FeedobackDraft(body: "Doomed"))

        answer(403, #"{"error":"Not allowed","reason":"app-not-allowed"}"#)
        let sent = await session.flushQueue()

        XCTAssertEqual(sent, 0)
        let left = await store.queued()
        XCTAssertTrue(left.isEmpty)
    }

    /// The identity travels with the thread, not with whoever is signed in now.
    func testAQueuedThreadArrivesUnderWhoWroteIt() async throws {
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let (session, store) = makeSession()
        await store.setVisitor(FeedobackVisitor(id: "u_first"))
        _ = await session.send(FeedobackDraft(body: "Mine"))

        // Somebody else signs in before the network comes back.
        await store.reset()
        await store.setVisitor(FeedobackVisitor(id: "u_second"))
        StubProtocol.reset()
        answer(201, #"{"threadId":"t_1"}"#)
        _ = await session.flushQueue()

        let body = try XCTUnwrap(StubProtocol.body())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let visitor = try XCTUnwrap(object["visitor"] as? [String: Any])
        XCTAssertEqual(visitor["id"] as? String, "u_first")
    }
}
