#if canImport(UIKit)
import UIKit
import XCTest
@testable import Feedoback

/// The accent is the owner's and can be anything. What is derived from it has
/// to stay readable, which is not something to eyeball once and hope.
final class ThemeTests: XCTestCase {
    func testReadsAHexColour() {
        let colour = FeedobackPalette.color(from: "#0f6e56")
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        colour?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(red, 15 / 255, accuracy: 0.001)
        XCTAssertEqual(green, 110 / 255, accuracy: 0.001)
        XCTAssertEqual(blue, 86 / 255, accuracy: 0.001)
    }

    func testFallsBackRatherThanDrawingNothing() {
        XCTAssertNil(FeedobackPalette.color(from: "not a colour"))
        XCTAssertNil(FeedobackPalette.color(from: "#abc"))
        // An unreadable value still gives a launcher somebody can see.
        XCTAssertNotNil(FeedobackPalette.accent("nonsense"))
    }

    /// Picked by contrast rather than chosen once, so a pale brand colour does
    /// not ship white text on a pale button.
    func testTextOnTheAccentIsAlwaysReadable() {
        let accents = ["#0f6e56", "#ffffff", "#000000", "#ffe600", "#1d4ed8", "#f5f5f5", "#7c3aed"]

        for hex in accents {
            let accent = FeedobackPalette.accent(hex)
            let text = FeedobackPalette.onAccent(accent)
            let ratio = FeedobackPalette.contrast(accent, text)
            XCTAssertGreaterThanOrEqual(
                ratio, 4.5, "\(hex) needs AA for the word on the launcher, got \(ratio)")
        }
    }

    func testAPaleAccentTakesInkAndADarkOneTakesWhite() {
        XCTAssertEqual(FeedobackPalette.onAccent(FeedobackPalette.accent("#ffe600")).cgColor.alpha, 1)
        XCTAssertLessThan(
            FeedobackPalette.luminance(of: FeedobackPalette.onAccent(FeedobackPalette.accent("#ffe600"))),
            0.5, "ink on a pale accent")
        XCTAssertGreaterThan(
            FeedobackPalette.luminance(of: FeedobackPalette.onAccent(FeedobackPalette.accent("#0f6e56"))),
            0.5, "white on a dark one")
    }

    /// `.system` leaves the device in charge, which is what almost every app
    /// wants and what a dashboard must never override.
    func testSystemLeavesTheDeviceInCharge() {
        XCTAssertEqual(FeedobackTheme.system.interfaceStyle, .unspecified)
        XCTAssertEqual(FeedobackTheme.light.interfaceStyle, .light)
        XCTAssertEqual(FeedobackTheme.dark.interfaceStyle, .dark)
    }
}
#endif
