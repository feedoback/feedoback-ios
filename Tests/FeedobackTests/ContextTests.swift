import XCTest
@testable import Feedoback

/// The bounds mirror `customContextSchema` on the server. A value the SDK lets
/// through and the server refuses costs the visitor the whole thread, so these
/// are the numbers from lib/widget/visitor.ts and not round ones.
final class ContextTests: XCTestCase {
    func testKeepsWhatTheServerWouldTake() {
        let bounded = FeedobackCustomContext.bounded([
            "plan": .string("pro"),
            "seats": .number(12),
            "trial": .bool(false),
            "invitedBy": .null,
        ])

        XCTAssertEqual(bounded.count, 4)
        XCTAssertEqual(bounded["plan"], .string("pro"))
        XCTAssertEqual(bounded["seats"], .number(12))
        XCTAssertEqual(bounded["trial"], .bool(false))
        XCTAssertEqual(bounded["invitedBy"], .null)
    }

    func testDropsAKeyLongerThanTheServerAllows() {
        let long = String(repeating: "k", count: FeedobackCustomContext.maxKeyLength + 1)
        let bounded = FeedobackCustomContext.bounded([long: .string("x"), "plan": .string("pro")])

        XCTAssertNil(bounded[long])
        XCTAssertEqual(bounded["plan"], .string("pro"), "and keeps the rest")
    }

    func testDropsAnEmptyKey() {
        XCTAssertTrue(FeedobackCustomContext.bounded(["": .string("x")]).isEmpty)
    }

    func testTrimsALongValueRatherThanDroppingIt() {
        let long = String(repeating: "a", count: FeedobackCustomContext.maxValueLength + 50)
        let bounded = FeedobackCustomContext.bounded(["note": .string(long)])

        XCTAssertEqual(bounded["note"], .string(String(repeating: "a", count: 500)))
    }

    /// Zod counts UTF-16 units, so 300 emoji are 600 to the server. Cutting by
    /// character and measuring the way the server measures is what stops a
    /// truncation landing in the middle of a surrogate pair.
    func testTrimsByWhatTheServerCounts() {
        let bounded = FeedobackCustomContext.bounded(["note": .string(String(repeating: "😀", count: 300))])
        guard case .string(let kept)? = bounded["note"] else { return XCTFail("kept nothing") }

        XCTAssertEqual(kept.utf16.count, FeedobackCustomContext.maxValueLength)
        XCTAssertEqual(kept.count, 250, "whole emoji, never half of one")
        XCTAssertEqual(kept, String(repeating: "😀", count: 250))
    }

    func testDropsANumberThatIsNotFinite() {
        let bounded = FeedobackCustomContext.bounded(["ratio": .number(.infinity), "seats": .number(12)])

        XCTAssertNil(bounded["ratio"])
        XCTAssertEqual(bounded["seats"], .number(12))
    }

    func testKeepsTheFirstThirtyKeysInASettledOrder() {
        var context: [String: FeedobackValue] = [:]
        for index in 0..<50 { context[String(format: "k%02d", index)] = .number(Double(index)) }

        let bounded = FeedobackCustomContext.bounded(context)

        XCTAssertEqual(bounded.count, FeedobackCustomContext.maxKeys)
        XCTAssertEqual(bounded["k00"], .number(0))
        XCTAssertEqual(bounded["k29"], .number(29))
        XCTAssertNil(bounded["k30"], "and the same thirty on every launch")
    }
}
