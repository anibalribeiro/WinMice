import XCTest
@testable import ButtonGate

final class ButtonGateTests: XCTestCase {
    /// The bug this type exists to prevent: a press passed through to the app and a release
    /// swallowed, leaving the app holding a button down that never comes up.
    func testAReleaseFollowsWhateverItsPressDid() {
        var gate = ButtonGate()

        XCTAssertEqual(gate.press(button: 2, action: .passThrough), .passThrough)
        XCTAssertEqual(gate.release(button: 2, fallback: .swallow), .passThrough)
    }

    func testASwallowedPressGetsASwallowedRelease() {
        var gate = ButtonGate()

        XCTAssertEqual(gate.press(button: 2, action: .swallow), .swallow)
        XCTAssertEqual(gate.release(button: 2, fallback: .passThrough), .swallow)
    }

    /// Each button is tracked on its own: a side button held while the middle button is
    /// clicked must not inherit the middle button's decision.
    func testButtonsAreTrackedIndependently() {
        var gate = ButtonGate()

        _ = gate.press(button: 2, action: .passThrough)
        _ = gate.press(button: 3, action: .swallow)

        XCTAssertEqual(gate.release(button: 3, fallback: .passThrough), .swallow)
        XCTAssertEqual(gate.release(button: 2, fallback: .swallow), .passThrough)
    }

    /// A release whose press was never seen — the feature was toggled on mid-hold, or the tap
    /// was rebuilt — has no recorded decision, so the caller's fallback applies.
    func testAnUnmatchedReleaseUsesTheFallback() {
        var gate = ButtonGate()

        XCTAssertEqual(gate.release(button: 4, fallback: .passThrough), .passThrough)
        XCTAssertEqual(gate.release(button: 5, fallback: .swallow), .swallow)
    }

    /// The record is consumed, so a second release of the same button does not reuse it.
    func testARecordIsConsumedByItsRelease() {
        var gate = ButtonGate()

        _ = gate.press(button: 2, action: .passThrough)
        XCTAssertEqual(gate.release(button: 2, fallback: .swallow), .passThrough)
        XCTAssertEqual(gate.release(button: 2, fallback: .swallow), .swallow)
    }

    /// Sleep, screen lock, and a tap rebuild all mean the releases we are waiting on are never
    /// coming, so nothing may stay recorded across one.
    func testResetDropsEveryRecord() {
        var gate = ButtonGate()

        _ = gate.press(button: 2, action: .passThrough)
        gate.reset()

        XCTAssertEqual(gate.release(button: 2, fallback: .swallow), .swallow)
    }
}
