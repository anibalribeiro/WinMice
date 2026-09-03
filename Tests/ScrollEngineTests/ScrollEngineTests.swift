import CoreGraphics
import ScrollEngine
import XCTest

/// Wheel deltas follow CoreGraphics conventions: positive `wheel1` scrolls up and positive `wheel2`
/// scrolls left, so "scrolls down" below means a negative vertical delta and "scrolls right" means a
/// negative horizontal one.
final class ScrollEngineTests: XCTestCase {
    /// Far enough past the dead zone that a single tick produces whole pixels on either axis.
    private let far: CGFloat = 200

    func testDraggingDownScrollsDown() {
        var engine = ScrollEngine()

        let delta = engine.tick(offset: CGVector(dx: 0, dy: -far))

        XCTAssertLessThan(delta?.vertical ?? 0, 0)
    }

    func testDraggingUpScrollsUp() {
        var engine = ScrollEngine()

        let delta = engine.tick(offset: CGVector(dx: 0, dy: far))

        XCTAssertGreaterThan(delta?.vertical ?? 0, 0)
    }

    func testDraggingRightScrollsRight() {
        var engine = ScrollEngine()

        let delta = engine.tick(offset: CGVector(dx: far, dy: 0))

        XCTAssertLessThan(delta?.horizontal ?? 0, 0)
    }

    func testDraggingLeftScrollsLeft() {
        var engine = ScrollEngine()

        let delta = engine.tick(offset: CGVector(dx: -far, dy: 0))

        XCTAssertGreaterThan(delta?.horizontal ?? 0, 0)
    }

    func testReverseVerticalScrollsUpWhenDraggingDown() {
        var engine = ScrollEngine()
        engine.reverseVertical = true

        let delta = engine.tick(offset: CGVector(dx: 0, dy: -far))

        XCTAssertGreaterThan(delta?.vertical ?? 0, 0)
    }

    func testReverseVerticalLeavesHorizontalAlone() {
        var reversed = ScrollEngine()
        reversed.reverseVertical = true
        var plain = ScrollEngine()
        let drag = CGVector(dx: far, dy: -far)

        let reversedDelta = reversed.tick(offset: drag)
        let plainDelta = plain.tick(offset: drag)

        XCTAssertEqual(reversedDelta?.horizontal, plainDelta?.horizontal)
        XCTAssertEqual(reversedDelta?.vertical, plainDelta.map { -$0.vertical })
    }

    func testOffsetInsideDeadZoneScrollsNothing() {
        var engine = ScrollEngine()

        XCTAssertNil(engine.tick(offset: CGVector(dx: 0, dy: engine.deadZone - 1)))
    }
}
