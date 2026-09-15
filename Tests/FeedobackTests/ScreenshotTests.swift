#if canImport(UIKit)
import UIKit
import XCTest
@testable import Feedoback

/// Redaction without a view to mark.
///
/// Flutter draws its whole interface into one view, so a rectangle is the only
/// thing its SDK can say. These run on a simulator because the type they cover
/// only exists where UIKit does.
@MainActor
final class ScreenshotTests: XCTestCase {
    override func tearDown() {
        FeedobackScreenshot.setRedactedRegions([])
        super.tearDown()
    }

    func testKeepsTheRegionsItWasGiven() {
        FeedobackScreenshot.setRedactedRegions([
            CGRect(x: 10, y: 20, width: 100, height: 40),
            CGRect(x: 0, y: 0, width: 50, height: 50),
        ])

        XCTAssertEqual(FeedobackScreenshot.redactedRegions.count, 2)
    }

    /// A widget that has not been laid out yet reports a zero rectangle, and
    /// filling one paints nothing while still costing a pass over the bitmap.
    func testDropsARegionWithNothingInIt() {
        FeedobackScreenshot.setRedactedRegions([
            CGRect(x: 10, y: 20, width: 0, height: 40),
            CGRect(x: 10, y: 20, width: 100, height: 0),
            CGRect(x: 10, y: 20, width: 100, height: 40),
        ])

        XCTAssertEqual(
            FeedobackScreenshot.redactedRegions,
            [CGRect(x: 10, y: 20, width: 100, height: 40)])
    }

    /// Replacing rather than adding: a set that could only grow would keep
    /// painting over a place nothing sensitive has been for ten screens.
    func testReplacesWhatWasMarkedBefore() {
        FeedobackScreenshot.setRedactedRegions([CGRect(x: 0, y: 0, width: 10, height: 10)])
        FeedobackScreenshot.setRedactedRegions([CGRect(x: 50, y: 50, width: 20, height: 20)])

        XCTAssertEqual(
            FeedobackScreenshot.redactedRegions,
            [CGRect(x: 50, y: 50, width: 20, height: 20)])
    }

    func testAnEmptyListMarksNothing() {
        FeedobackScreenshot.setRedactedRegions([CGRect(x: 0, y: 0, width: 10, height: 10)])
        FeedobackScreenshot.setRedactedRegions([])

        XCTAssertTrue(FeedobackScreenshot.redactedRegions.isEmpty)
    }

    /// A secure field is still found on its own; regions are in addition to
    /// the walk, never instead of it.
    func testStillFindsASecureFieldWithNoRegionsMarked() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        field.isSecureTextEntry = true
        root.addSubview(field)

        XCTAssertEqual(FeedobackScreenshot.sensitiveViews(in: root), [field])
    }
}
#endif
