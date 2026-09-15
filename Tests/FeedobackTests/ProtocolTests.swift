import XCTest
@testable import Feedoback

/// The SDK against the fixtures in `packages/protocol/fixtures`.
///
/// Those files are the only thing this end and the server both read. Decoding
/// every response and encoding a request that matches theirs is what stops the
/// two drifting: a field added on one side fails here rather than in the wild.
final class ProtocolTests: XCTestCase {
    /// Found from this file, so the test needs no resource bundle and no copy
    /// of the fixtures that could go stale.
    ///
    /// Two places, because this package is developed beside the server and
    /// published on its own. In development the fixtures are the ones the
    /// server reads, a directory up; in the published repository they are
    /// copied in, so anyone who clones it can run these tests.
    private func fixture(_ name: String) throws -> Data {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // FeedobackTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // the package

        let shared = package
            .deletingLastPathComponent()  // packages
            .appendingPathComponent("protocol")
            .appendingPathComponent("fixtures")
            .appendingPathComponent(name)
        let copied = package
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)

        let url = FileManager.default.fileExists(atPath: shared.path) ? shared : copied
        return try Data(contentsOf: url)
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - What the server answers

    func testDecodesAnEnabledConfig() throws {
        let config = try JSONDecoder.feedoback.decode(
            FeedobackConfigResponse.self, from: try fixture("config.ios.json"))

        XCTAssertEqual(config.projectName, "Acme Shop")
        XCTAssertTrue(config.enabled)
        XCTAssertNil(config.reason)
        XCTAssertEqual(config.appearance.color, "#0f6e56")
        XCTAssertEqual(config.appearance.label, "Feedback")
        XCTAssertTrue(config.appearance.rating)
    }

    /// An app is offered one way in. The picker and the recorder have no native
    /// equivalent yet, and the server reduces them before answering.
    func testAnAppIsOfferedOneWayIn() throws {
        let config = try JSONDecoder.feedoback.decode(
            FeedobackConfigResponse.self, from: try fixture("config.ios.json"))

        XCTAssertFalse(config.appearance.actions.point)
        XCTAssertFalse(config.appearance.actions.record)
        XCTAssertTrue(config.appearance.actions.feedback)
    }

    /// Light and dark is the device's call, so the server does not send it.
    /// If it ever starts, this fails and someone decides on purpose.
    func testTheServerNeverTellsAnAppWhichThemeToBe() throws {
        let raw = try json(try fixture("config.ios.json"))
        let appearance = try XCTUnwrap(raw["appearance"] as? [String: Any])
        XCTAssertNil(appearance["theme"])

        let web = try json(try fixture("config.web.json"))
        let webAppearance = try XCTUnwrap(web["appearance"] as? [String: Any])
        XCTAssertNotNil(webAppearance["theme"], "the web widget still gets one")
    }

    func testDecodesADormantConfigWithItsReason() throws {
        let config = try JSONDecoder.feedoback.decode(
            FeedobackConfigResponse.self, from: try fixture("config.ios.dormant.json"))

        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.reason, .visitorNotIdentified)
        XCTAssertTrue(config.reason!.advice.contains("identify()"))
    }

    /// Every refusal the server can send has to decode, or an SDK update would
    /// be needed before a project could turn something on.
    func testEveryRefusalDecodes() throws {
        let reasons = [
            "not-an-app", "mobile-not-enabled", "app-not-allowed",
            "visitor-not-identified", "visitor-not-verified", "visitor-not-listed",
        ]
        for reason in reasons {
            let decoded = FeedobackRefusal(rawValue: reason)
            XCTAssertNotNil(decoded, "\(reason) should decode")
            XCTAssertFalse(decoded!.advice.isEmpty)
        }
    }

    // MARK: - What the SDK sends

    func testDecodesTheThreadFixtureItIsMeantToProduce() throws {
        let request = try JSONDecoder.feedoback.decode(
            FeedobackThreadRequest.self, from: try fixture("thread.ios.json"))

        XCTAssertEqual(request.category, .bug)
        XCTAssertEqual(request.pageContext.route, "cart")
        XCTAssertEqual(request.pageContext.bundleId, "com.acme.shop")
        XCTAssertEqual(request.pageContext.deviceModel, "iPhone 16 Pro")
        XCTAssertEqual(request.pageContext.viewport, FeedobackViewport(width: 393, height: 852))
        XCTAssertEqual(request.pageContext.scale, 3)
        XCTAssertEqual(request.pageContext.orientation, .portrait)
        XCTAssertEqual(request.pageContext.network, .wifi)
        XCTAssertEqual(request.visitor?.id, "u_8412")
        XCTAssertEqual(request.visitor?.userHash?.count, 64)
        XCTAssertEqual(request.metadata?["plan"], .string("pro"))
        XCTAssertEqual(request.metadata?["seats"], .number(12))
        XCTAssertEqual(request.metadata?["trial"], .bool(false))
        XCTAssertEqual(request.attachments?.first?.contentType, "image/jpeg")
    }

    /// The other direction, which is the one that matters: what this SDK
    /// encodes has to be the same object the server's schema accepts.
    func testEncodesBackToTheSameObject() throws {
        let data = try fixture("thread.ios.json")
        let request = try JSONDecoder.feedoback.decode(FeedobackThreadRequest.self, from: data)
        let encoded = try JSONEncoder.feedoback.encode(request)

        let ours = try json(encoded)
        let theirs = try json(data)

        // `rating: null` in the fixture is the same as leaving it out, which is
        // what the encoder does, so compare on the keys that carry a value.
        XCTAssertEqual(
            NSDictionary(dictionary: ours),
            NSDictionary(dictionary: theirs.filter { $0.value is NSNull == false }))
    }

    func testAndroidFixtureDecodesToo() throws {
        // The Android SDK writes this one; decoding it here is what keeps the
        // two from describing the same screen in two different shapes.
        let request = try JSONDecoder.feedoback.decode(
            FeedobackThreadRequest.self, from: try fixture("thread.android.json"))

        XCTAssertEqual(request.pageContext.platform, "android")
        XCTAssertEqual(request.rating, 4)
        XCTAssertEqual(request.pageContext.route, "checkout/payment")
    }

    func testOmitsWhatWasNotSetRatherThanSendingNull() throws {
        let request = FeedobackThreadRequest(
            category: .feedback,
            body: "Short and plain",
            pageContext: FeedobackScreenContext(
                route: "home", title: "Home", bundleId: "com.acme.app",
                appVersion: "1.0", buildNumber: "1", osVersion: "18.0",
                deviceModel: "iPhone", locale: "en", timezone: "UTC",
                viewport: FeedobackViewport(width: 390, height: 844),
                scale: 3, orientation: .portrait))

        let encoded = try json(try JSONEncoder.feedoback.encode(request))

        XCTAssertNil(encoded["rating"])
        XCTAssertNil(encoded["visitor"])
        XCTAssertNil(encoded["metadata"])
        XCTAssertNil(encoded["attachments"])
        // And the context leaves out the network it could not read.
        let context = try XCTUnwrap(encoded["pageContext"] as? [String: Any])
        XCTAssertNil(context["network"])
        XCTAssertEqual(context["platform"] as? String, "ios")
    }

    func testVisitorNamesSomebodyOnlyWithAnIdOrAnEmail() {
        XCTAssertTrue(FeedobackVisitor(id: "u_1").isNamed)
        XCTAssertTrue(FeedobackVisitor(email: "ada@example.com").isNamed)
        XCTAssertFalse(FeedobackVisitor(name: "Ada").isNamed)
        XCTAssertFalse(FeedobackVisitor().isNamed)
        XCTAssertFalse(FeedobackVisitor(id: "").isNamed)
    }
}
