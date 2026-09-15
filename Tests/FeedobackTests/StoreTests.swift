import XCTest
@testable import Feedoback

/// Stands in for UserDefaults, so a test never writes into the machine running it.
final class MemoryDefaults: FeedobackDefaults {
    private var values: [String: Any] = [:]

    func data(forKey key: String) -> Data? { values[key] as? Data }
    func string(forKey key: String) -> String? { values[key] as? String }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
}

final class StoreTests: XCTestCase {
    private var defaults: MemoryDefaults!
    private var clock: Mutable<Date>!

    override func setUp() {
        super.setUp()
        defaults = MemoryDefaults()
        clock = Mutable(Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func store() -> FeedobackStore {
        let clock = self.clock!
        return FeedobackStore(defaults: defaults, now: { clock.value })
    }

    private func thread(_ body: String, visitor: FeedobackVisitor? = nil) -> FeedobackThreadRequest {
        FeedobackThreadRequest(
            category: .feedback,
            body: body,
            pageContext: FeedobackScreenContext(
                route: "home", title: "Home", bundleId: "com.acme.app",
                appVersion: "1.0", buildNumber: "1", osVersion: "18.0",
                deviceModel: "iPhone", locale: "en", timezone: "UTC",
                viewport: FeedobackViewport(width: 390, height: 844),
                scale: 3, orientation: .portrait),
            visitor: visitor)
    }

    // MARK: - The install

    func testMintsAnInstallIdOnceAndKeepsIt() async {
        let first = await store().installId()
        let second = await store().installId()

        XCTAssertEqual(first, second)
        XCTAssertNotNil(UUID(uuidString: first), "a random id, not a fingerprint")
    }

    func testTwoInstallsAreNotTheSame() async {
        let a = await FeedobackStore(defaults: MemoryDefaults()).installId()
        let b = await FeedobackStore(defaults: MemoryDefaults()).installId()
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Identity

    func testRemembersWhoTheAppNamed() async {
        let store = self.store()
        await store.setVisitor(FeedobackVisitor(id: "u_1", email: "ada@example.com", name: "Ada"))

        // A second launch reads the same thing back.
        let read = await FeedobackStore(defaults: defaults).visitor()
        XCTAssertEqual(read?.id, "u_1")
        XCTAssertEqual(read?.name, "Ada")
    }

    /// A name on its own names nobody, so there is nothing worth keeping.
    func testKeepsNothingForAVisitorThatNamesNobody() async {
        let store = self.store()
        await store.setVisitor(FeedobackVisitor(name: "Ada"))
        let read = await store.visitor()
        XCTAssertNil(read)
    }

    func testSignOutForgetsThePersonButNotTheDevice() async {
        let store = self.store()
        let install = await store.installId()
        await store.setVisitor(FeedobackVisitor(id: "u_1"))

        await store.reset()

        let visitor = await store.visitor()
        XCTAssertNil(visitor)
        let after = await store.installId()
        XCTAssertEqual(after, install, "the same device, identifying nobody")
    }

    // MARK: - The queue

    func testKeepsWhatCouldNotBeSent() async {
        let store = self.store()
        await store.enqueue(thread("Written in a tunnel"))

        let queued = await store.queued()
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.first?.request.body, "Written in a tunnel")
    }

    /// The identity is stamped in before it is queued and read back as it was
    /// written, so a thread never goes out attributed to whoever signed in next.
    func testAQueuedThreadKeepsTheIdentityItWasWrittenWith() async {
        let store = self.store()
        await store.enqueue(thread("Mine", visitor: FeedobackVisitor(id: "u_first")))

        await store.setVisitor(FeedobackVisitor(id: "u_second"))
        await store.reset()

        let queued = await store.queued()
        XCTAssertEqual(queued.first?.request.visitor?.id, "u_first")
    }

    func testDropsTheOldestOncePastTheCap() async {
        let store = self.store()
        for index in 0..<(FeedobackStore.maxQueuedThreads + 5) {
            await store.enqueue(thread("message \(index)"))
        }

        let queued = await store.queued()
        XCTAssertEqual(queued.count, FeedobackStore.maxQueuedThreads)
        XCTAssertEqual(queued.first?.request.body, "message 5")
        XCTAssertEqual(queued.last?.request.body, "message 24")
    }

    /// A week-old complaint is not worth sending, and is worth not keeping.
    func testForgetsWhatWentStale() async {
        let store = self.store()
        await store.enqueue(thread("Ancient"))

        clock.value = clock.value.addingTimeInterval(FeedobackStore.maxQueueAge + 60)
        let queued = await store.queued()

        XCTAssertTrue(queued.isEmpty)
    }

    func testRemovesOneOnceItHasGone() async {
        let store = self.store()
        await store.enqueue(thread("First"))
        await store.enqueue(thread("Second"))

        let queued = await store.queued()
        await store.remove(queued[0])

        let left = await store.queued()
        XCTAssertEqual(left.map(\.request.body), ["Second"])
    }

    func testSurvivesRubbishInStorage() async {
        defaults.set(Data("not json".utf8), forKey: "com.feedoback.queue")
        defaults.set(Data("not json".utf8), forKey: "com.feedoback.visitor")

        let store = self.store()
        let queued = await store.queued()
        let visitor = await store.visitor()

        XCTAssertTrue(queued.isEmpty)
        XCTAssertNil(visitor)
    }
}
