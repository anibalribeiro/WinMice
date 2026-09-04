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
        let crawl = CGVector(dx: 0, dy: -15)
        XCTAssertNil(engine.tick(offset: crawl))

        var total: Int32 = 0
        for _ in 0..<60 {
            total += engine.tick(offset: crawl)?.vertical ?? 0
        }

        XCTAssertGreaterThan(total, 0)
    }

    /// The dead zone's actual size is what decides whether the first few millimetres feel precise,
    /// so it needs asserting directly — a test that reads engine.deadZone to build its own input
    /// holds for any value and cannot fail.
    func testDeadZoneIsTwelvePoints() {
        XCTAssertEqual(ScrollEngine().deadZone, 12)
    }

    func testJustInsideTheDeadZoneScrollsNothing() {
        var engine = ScrollEngine()
        XCTAssertNil(engine.tick(offset: CGVector(dx: 0, dy: 11)))
    }

    func testJustOutsideTheDeadZoneEventuallyScrolls() {
        var engine = ScrollEngine()
        var scrolled = false
        for _ in 0..<60 where engine.tick(offset: CGVector(dx: 0, dy: -15)) != nil {
            scrolled = true
        }
        XCTAssertTrue(scrolled)
    }

    /// The README promises a response "slightly faster than linear". Doubling the excess past the
    /// dead zone (not the raw pointer distance) pins that without restating pow(), so flattening
    /// acceleration to 1.0 fails here — a 50 vs 100 comparison still passes when linear because
    /// the 12-pt offset inflates the ratio.
    func testResponseIsFasterThanLinear() {
        var engine = ScrollEngine()
        let near = magnitude(&engine, past: 52)
        engine.reset()
        let far = magnitude(&engine, past: 92)

        XCTAssertGreaterThan(far, 2 * near)
    }

    /// The dead zone is radial on purpose: measuring each axis on its own makes the still area a
    /// square, so a diagonal drag just past the corner would scroll nothing.
    func testDeadZoneIsRadialNotPerAxis() {
        var engine = ScrollEngine()
        // (11, 11) is inside a square dead zone on both axes but outside a radius of 12.
        var vertical: Int32 = 0
        for _ in 0..<60 {
            if let step = engine.tick(offset: CGVector(dx: 11, dy: 11)) {
                vertical += step.vertical
            }
        }
        XCTAssertGreaterThan(vertical, 0)
    }

    /// reset() exists so a fraction of a pixel owed from the last autoscroll does not leak into the
    /// next one. Making it a no-op used to leave the suite green.
    func testResetClearsTheCarriedSubPixelRemainder() {
        var used = ScrollEngine()
        for _ in 0..<5 { _ = used.tick(offset: CGVector(dx: 0, dy: -15)) }
        used.reset()

        var fresh = ScrollEngine()

        for tick in 0..<10 {
            XCTAssertEqual(
                used.tick(offset: CGVector(dx: 0, dy: -15))?.vertical,
                fresh.tick(offset: CGVector(dx: 0, dy: -15))?.vertical,
                "tick \(tick) differs, so reset() left a remainder behind"
            )
        }
    }

    /// Returning to the anchor must clear the remainder too, or a stale fraction survives a pause.
    /// One tick after the pause is still sub-pixel either way; comparing a run of ticks exposes
    /// the phase shift the leftover remainder causes.
    func testReturningToTheAnchorClearsTheRemainder() {
        var engine = ScrollEngine()
        for _ in 0..<5 { _ = engine.tick(offset: CGVector(dx: 0, dy: -15)) }
        XCTAssertNil(engine.tick(offset: .zero))

        var fresh = ScrollEngine()

        for tick in 0..<10 {
            XCTAssertEqual(
                engine.tick(offset: CGVector(dx: 0, dy: -15))?.vertical,
                fresh.tick(offset: CGVector(dx: 0, dy: -15))?.vertical,
                "tick \(tick) differs, so returning to the anchor left a remainder behind"
            )
        }
    }

    /// The horizontal axis accumulates sub-pixels exactly like the vertical one, and its reversal
    /// interacts with the carryover the same way. Only the vertical path was covered.
    func testHorizontalSlowDragAccumulatesAcrossTicks() {
        var engine = ScrollEngine()
        var horizontal: Int32 = 0
        for _ in 0..<60 {
            if let step = engine.tick(offset: CGVector(dx: 15, dy: 0)) {
                horizontal += step.horizontal
            }
        }
        XCTAssertLessThan(horizontal, 0)
    }

    func testReversedHorizontalSlowDragAccumulatesAcrossTicks() {
        var reversed = ScrollEngine()
        reversed.reverseHorizontal = true
        var plain = ScrollEngine()
        let crawl = CGVector(dx: 15, dy: 0)

        var reversedTotal: Int32 = 0
        var plainTotal: Int32 = 0
        for _ in 0..<60 {
            reversedTotal += reversed.tick(offset: crawl)?.horizontal ?? 0
            plainTotal += plain.tick(offset: crawl)?.horizontal ?? 0
        }
        XCTAssertGreaterThan(reversedTotal, 0)
        // Folding remainder inside the reverse factor is a no-op when reverse is on (the outer
        // sign is +1) and instead stalls the unreversed path. Matching the two totals pins that
        // the carryover lives in output-sign space on both paths.
        XCTAssertEqual(reversedTotal, -plainTotal)
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

    /// scrollSpeedPercent comes from UserDefaults, so it can be stale from an older build or
    /// hand-edited. A negative or non-finite speed used to reach Int32(), which traps and takes
    /// the whole app down on the next scroll tick.
    func testHostileSpeedValuesDoNotTrap() {
        for hostile in [-1, 0, 100_000_000] {
            var engine = ScrollEngine()
            engine.speed = CGFloat(hostile)
            _ = engine.tick(offset: CGVector(dx: 0, dy: -700))
        }

        var nanEngine = ScrollEngine()
        nanEngine.speed = .nan
        _ = nanEngine.tick(offset: CGVector(dx: 0, dy: -700))
    }

    /// A speed the UI cannot express must be pulled into range rather than honored, so a corrupt
    /// preference cannot invert scrolling or fling the view.
    func testSpeedIsClampedIntoRangeOnAssignment() {
        var engine = ScrollEngine()

        engine.speed = -5
        XCTAssertEqual(engine.speed, ScrollEngine.minSpeed)

        engine.speed = 1_000
        XCTAssertEqual(engine.speed, ScrollEngine.maxSpeed)
    }

    /// A non-finite offset must stop scrolling rather than crash.
    func testNonFiniteOffsetDoesNotTrap() {
        var engine = ScrollEngine()
        XCTAssertNil(engine.tick(offset: CGVector(dx: CGFloat.nan, dy: CGFloat.nan)))
        XCTAssertNil(engine.tick(offset: CGVector(dx: 0, dy: CGFloat.infinity)))
    }

    /// Accumulates whole steps over enough ticks to measure the curve's magnitude at a distance,
    /// which single-tick assertions cannot do below 1 px per tick.
    private func magnitude(_ engine: inout ScrollEngine, past distance: CGFloat) -> Double {
        var total: Int32 = 0
        let ticks = 100
        for _ in 0..<ticks {
            total += engine.tick(offset: CGVector(dx: 0, dy: -distance))?.vertical ?? 0
        }
        return Double(-total) / Double(ticks)
    }
}
