import XCTest
@testable import Feedoback

/// The dictionary a bridge hands over, turned into a configuration.
///
/// React Native and Flutter both arrive with one of these, so this is the one
/// place either can get it wrong. Nothing here invents a default: an absent or
/// unrecognised key leaves the SDK's own in place, which is the one a plain
/// Swift app gets.
final class ConfigurationTests: XCTestCase {
    func testTakesAProjectKeyAndLeavesEverythingElseAlone() throws {
        let configuration = try XCTUnwrap(FeedobackConfiguration(options: ["projectKey": "pk_1"]))
        let defaults = FeedobackConfiguration(projectKey: "pk_1")

        XCTAssertEqual(configuration.projectKey, "pk_1")
        XCTAssertEqual(configuration.host, defaults.host)
        XCTAssertEqual(configuration.theme, defaults.theme)
        XCTAssertEqual(configuration.categories, defaults.categories)
        XCTAssertEqual(configuration.screenshots, defaults.screenshots)
        XCTAssertEqual(configuration.logLevel, defaults.logLevel)
        XCTAssertEqual(configuration.launcher.enabled, defaults.launcher.enabled)
    }

    func testCarriesEveryOptionABridgeCanSend() throws {
        let configuration = try XCTUnwrap(FeedobackConfiguration(options: [
            "projectKey": "pk_1",
            "host": "https://feedback.acme.com",
            "theme": "dark",
            "categories": ["bug", "idea"],
            "screenshots": "off",
            "logLevel": "debug",
        ]))

        XCTAssertEqual(configuration.host.absoluteString, "https://feedback.acme.com")
        XCTAssertEqual(configuration.theme, .dark)
        XCTAssertEqual(configuration.categories, [.bug, .idea])
        XCTAssertEqual(configuration.screenshots, .off)
        XCTAssertEqual(configuration.logLevel, .debug)
    }

    /// The whole configuration hangs off it, so there is nothing to fall back
    /// to and nothing worth starting.
    func testRefusesToBuildWithoutAProjectKey() {
        XCTAssertNil(FeedobackConfiguration(options: [:]))
        XCTAssertNil(FeedobackConfiguration(options: ["projectKey": "   "]))
        XCTAssertNil(FeedobackConfiguration(options: ["projectKey": 42]))
    }

    func testFallsBackRatherThanGuessingAtANameItDoesNotKnow() throws {
        let configuration = try XCTUnwrap(FeedobackConfiguration(options: [
            "projectKey": "pk_1", "theme": "midnight", "screenshots": 3,
        ]))

        XCTAssertEqual(configuration.theme, .system)
        XCTAssertEqual(configuration.screenshots, .automatic)
    }

    func testKeepsACategoryListFreeOfRepeatsAndOfNamesItDoesNotKnow() throws {
        let configuration = try XCTUnwrap(FeedobackConfiguration(options: [
            "projectKey": "pk_1", "categories": ["bug", "bug", "support", 4],
        ]))

        XCTAssertEqual(configuration.categories, [.bug])
    }

    /// A list with nothing usable in it is a list the app did not mean, so the
    /// SDK's own default survives rather than the sheet offering nothing.
    func testFallsBackWhenACategoryListComesToNothing() throws {
        let configuration = try XCTUnwrap(FeedobackConfiguration(options: [
            "projectKey": "pk_1", "categories": ["support"],
        ]))

        XCTAssertEqual(configuration.categories, [.feedback])
    }

    func testReadsTheLauncherCornersAndAll() throws {
        let configuration = try XCTUnwrap(FeedobackConfiguration(options: [
            "projectKey": "pk_1",
            "launcher": [
                "enabled": true,
                "corner": "bottom-start",
                "style": "labelled",
                "draggable": false,
                "hidesWithKeyboard": false,
                "offset": ["x": 20.0, "y": 30.0],
            ],
        ]))

        let launcher = configuration.launcher
        XCTAssertTrue(launcher.enabled)
        XCTAssertEqual(launcher.corner, .bottomLeading)
        XCTAssertEqual(launcher.style, .labelled)
        XCTAssertFalse(launcher.draggable)
        XCTAssertFalse(launcher.hidesWithKeyboard)
        XCTAssertEqual(launcher.offset, CGSize(width: 20, height: 30))
    }

    /// Start and end, not left and right: the launcher sits on the reading
    /// edge, and an Arabic app puts that on the other side.
    func testReadsTheFourCornersABridgeNames() throws {
        func corner(_ name: String) throws -> FeedobackLauncherCorner {
            try XCTUnwrap(FeedobackConfiguration(options: [
                "projectKey": "pk_1", "launcher": ["corner": name],
            ])).launcher.corner
        }

        XCTAssertEqual(try corner("top-start"), .topLeading)
        XCTAssertEqual(try corner("top-end"), .topTrailing)
        XCTAssertEqual(try corner("bottom-start"), .bottomLeading)
        XCTAssertEqual(try corner("bottom-end"), .bottomTrailing)
    }

    /// Half an offset would put the button somewhere nobody asked for on the
    /// other axis.
    func testKeepsItsOwnOffsetWhenOnlyOneNumberArrived() throws {
        let configuration = try XCTUnwrap(FeedobackConfiguration(options: [
            "projectKey": "pk_1", "launcher": ["offset": ["x": 20.0]],
        ]))

        XCTAssertEqual(configuration.launcher.offset, FeedobackLauncherOptions().offset)
    }

    func testLeavesTheLauncherOffWhenTheAppDidNotAskForOne() throws {
        let configuration = try XCTUnwrap(FeedobackConfiguration(options: ["projectKey": "pk_1"]))
        XCTAssertFalse(configuration.launcher.enabled)
    }
}
