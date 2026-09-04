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

    func testReverseVerticalLeavesHorizontalAlone() throws {
        var reversed = ScrollEngine()
        reversed.reverseVertical = true
        var plain = ScrollEngine()
        let drag = CGVector(dx: far, dy: -far)

        let reversedDelta = try XCTUnwrap(reversed.tick(offset: drag))
        let plainDelta = try XCTUnwrap(plain.tick(offset: drag))

        XCTAssertEqual(reversedDelta.horizontal, plainDelta.horizontal)
        XCTAssertEqual(reversedDelta.vertical, -plainDelta.vertical)
    }

    func testReverseHorizontalScrollsLeftWhenDraggingRight() {
        var engine = ScrollEngine()
        engine.reverseHorizontal = true

        let delta = engine.tick(offset: CGVector(dx: far, dy: 0))

        XCTAssertGreaterThan(delta?.horizontal ?? 0, 0)
    }

    func testReverseHorizontalLeavesVerticalAlone() throws {
        var reversed = ScrollEngine()
        reversed.reverseHorizontal = true
        var plain = ScrollEngine()
        let drag = CGVector(dx: far, dy: -far)

        let reversedDelta = try XCTUnwrap(reversed.tick(offset: drag))
        let plainDelta = try XCTUnwrap(plain.tick(offset: drag))

        XCTAssertEqual(reversedDelta.vertical, plainDelta.vertical)
        XCTAssertEqual(reversedDelta.horizontal, -plainDelta.horizontal)
    }

    func testReversingBothAxesFlipsBoth() throws {
        var reversed = ScrollEngine()
        reversed.reverseVertical = true
        reversed.reverseHorizontal = true
        var plain = ScrollEngine()
        let drag = CGVector(dx: far, dy: -far)

        let reversedDelta = try XCTUnwrap(reversed.tick(offset: drag))
        let plainDelta = try XCTUnwrap(plain.tick(offset: drag))

        XCTAssertEqual(reversedDelta.vertical, -plainDelta.vertical)
        XCTAssertEqual(reversedDelta.horizontal, -plainDelta.horizontal)
    }

    /// Reversing must flip the delta before the fractional remainder is added, not after. Flipping
    /// the sum instead alternates the carryover's sign every tick, which stalls a slow drag at zero.
    func testReversedSlowDragAccumulatesAcrossTicks() {
        var engine = ScrollEngine()
        engine.reverseVertical = true
        // Just past the dead zone one tick is worth well under a pixel, so nothing scrolls until
        // the remainder adds up over several ticks.
        let crawl = CGVector(dx: 0, dy: -(engine.deadZone + 3))
        XCTAssertNil(engine.tick(offset: crawl))

        var total: Int32 = 0
        for _ in 0..<60 {
            total += engine.tick(offset: crawl)?.vertical ?? 0
        }

        XCTAssertGreaterThan(total, 0)
    }

    func testOffsetInsideDeadZoneScrollsNothing() {
        var engine = ScrollEngine()

        XCTAssertNil(engine.tick(offset: CGVector(dx: 0, dy: engine.deadZone - 1)))
    }

    /// The Speed preference advertises a faster scroll, not just a shorter ramp. With a fixed
    /// per-tick ceiling, every setting above the default collapses to the same top speed over
    /// most of the screen, which makes the slider do nothing where users actually drag.
    func testHigherSpeedScrollsFasterFarFromTheAnchor() {
        let far = CGVector(dx: 0, dy: -400)

        var normal = ScrollEngine()
        normal.speed = ScrollEngine.baseSpeed
        var fast = ScrollEngine()
        fast.speed = ScrollEngine.baseSpeed * 3

        guard let normalStep = normal.tick(offset: far), let fastStep = fast.tick(offset: far) else {
            return XCTFail("both engines should scroll 400 points from the anchor")
        }

        XCTAssertGreaterThan(abs(fastStep.vertical), abs(normalStep.vertical))
    }

    /// The ceiling still has to exist, or a pointer flung at the edge of a large display
    /// scrolls hundreds of pixels in a single 16 ms tick.
    func testSpeedIsStillCappedAtTheFarEdge() {
        var engine = ScrollEngine()
        engine.speed = ScrollEngine.baseSpeed

        guard let step = engine.tick(offset: CGVector(dx: 0, dy: -4000)) else {
            return XCTFail("a distant pointer should scroll")
        }

        XCTAssertEqual(abs(step.vertical), 130)
    }
}
