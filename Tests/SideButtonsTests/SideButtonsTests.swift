import SideButtons
import XCTest

final class SideButtonsTests: XCTestCase {
    func testUnsetMappingUsesDefaults() {
        let mapping = SideButtons.resolve(storedBack: nil, storedForward: nil, legacySwap: false)

        XCTAssertEqual(mapping, SideButtonMapping(back: 3, forward: 4))
    }

    /// The `swapSideButtons` flag predates per-direction button numbers, so an install that set it
    /// and never mapped a button by hand has to keep the swapped pair.
    func testLegacySwapWithNothingStoredSwapsTheDefaults() {
        let mapping = SideButtons.resolve(storedBack: nil, storedForward: nil, legacySwap: true)

        XCTAssertEqual(mapping, SideButtonMapping(back: 4, forward: 3))
    }

    /// The flag only ever applied to a direction the user had never mapped. A stored value this
    /// build reserves is not the same thing as no value at all: it falls back to the direction's
    /// own default, with the swap ignored. Here back is mapped to 21 by hand and forward holds a
    /// button an intermediate build allowed, so forward must land on its own default of 4 rather
    /// than the swapped 3.
    func testLegacySwapDoesNotApplyToStoredButUnusableValues() {
        let mapping = SideButtons.resolve(storedBack: 21, storedForward: 2, legacySwap: true)

        XCTAssertEqual(mapping, SideButtonMapping(back: 21, forward: 4))
    }

    func testStoredButtonsAreKept() {
        let mapping = SideButtons.resolve(storedBack: 7, storedForward: 9, legacySwap: false)

        XCTAssertEqual(mapping, SideButtonMapping(back: 7, forward: 9))
    }

    func testReservedStoredButtonFallsBackToADefault() {
        // The middle button belongs to autoscroll, so a build that once allowed it must not win.
        let mapping = SideButtons.resolve(storedBack: 2, storedForward: nil, legacySwap: false)

        XCTAssertNotEqual(mapping.back, 2)
        XCTAssertTrue(SideButtons.isAssignable(mapping.back))
    }

    /// The regression this type exists for. An older build allowed the middle button for forward,
    /// and back was mapped to 4 by hand. Resolving each direction on its own sent the unusable
    /// forward value back to *its* default — which is 4, the button back already occupies. Both
    /// directions then answered to button 4, and which one fired was decided by the dictionary
    /// lookup in `NavigationController`, i.e. by the process's hash seed.
    func testReservedForwardButtonDoesNotCollideWithAMappedBackButton() {
        let mapping = SideButtons.resolve(storedBack: 4, storedForward: 2, legacySwap: false)

        XCTAssertEqual(mapping.back, 4, "an explicitly mapped button must be honored")
        XCTAssertNotEqual(mapping.forward, mapping.back)
        XCTAssertTrue(SideButtons.isAssignable(mapping.forward))
    }

    func testReservedBackButtonDoesNotCollideWithAMappedForwardButton() {
        let mapping = SideButtons.resolve(storedBack: 0, storedForward: 3, legacySwap: false)

        XCTAssertEqual(mapping.forward, 3, "an explicitly mapped button must be honored")
        XCTAssertNotEqual(mapping.back, mapping.forward)
        XCTAssertTrue(SideButtons.isAssignable(mapping.back))
    }

    /// Nothing in the app can write this, since `assign` trades places instead of mapping a button
    /// twice, but a hand-edited defaults domain can.
    /// Back keeps the button, so the outcome does not depend on which direction is read first.
    /// `NavigationController.direction(for:)` checks back first for the same reason.
    func testTwoStoredButtonsThatMatchResolveInFavorOfBack() {
        let mapping = SideButtons.resolve(storedBack: 6, storedForward: 6, legacySwap: false)

        XCTAssertEqual(mapping.back, 6)
        XCTAssertNotEqual(mapping.forward, 6)
        XCTAssertTrue(SideButtons.isAssignable(mapping.forward))
    }

    /// `fallback` steps aside to the other default when the preferred one is taken, which only
    /// yields a free button while the two defaults differ.
    func testTheTwoDefaultsDiffer() {
        XCTAssertNotEqual(SideButtons.defaultBack, SideButtons.defaultForward)
        XCTAssertTrue(SideButtons.isAssignable(SideButtons.defaultBack))
        XCTAssertTrue(SideButtons.isAssignable(SideButtons.defaultForward))
    }

    /// The invariant the whole type owes its callers: whatever is stored, one button never drives
    /// both directions, and every button it hands back is one the tap is allowed to claim.
    func testEveryCombinationResolvesToTwoDistinctAssignableButtons() {
        let candidates: [Int?] = [nil, -1, 0, 1, 2, 3, 4, 5, 31, 32, 99]

        for back in candidates {
            for forward in candidates {
                for legacySwap in [false, true] {
                    let mapping = SideButtons.resolve(
                        storedBack: back,
                        storedForward: forward,
                        legacySwap: legacySwap
                    )
                    let inputs = "back: \(back as Int?), forward: \(forward as Int?), swap: \(legacySwap)"

                    XCTAssertNotEqual(mapping.back, mapping.forward, "collision for \(inputs)")
                    XCTAssertTrue(SideButtons.isAssignable(mapping.back), "unassignable back for \(inputs)")
                    XCTAssertTrue(SideButtons.isAssignable(mapping.forward), "unassignable forward for \(inputs)")
                }
            }
        }
    }
}
