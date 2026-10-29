import CoreGraphics
import WindowHitTest
import XCTest

final class WindowHitTestTests: XCTestCase {
    /// Simulates the window stack under the point, frontmost first.
    private func frontmostOwnWindow(in stack: [(Int, WindowHitTest.Candidate)]) -> Int? {
        WindowHitTest.frontmostOwnWindow(
            windowNumberBelow: { below in
                if below == 0 { return stack.first?.0 ?? 0 }
                guard let index = stack.firstIndex(where: { $0.0 == below }), index + 1 < stack.count else {
                    return 0
                }
                return stack[index + 1].0
            },
            classify: { number in stack.first(where: { $0.0 == number })!.1 }
        )
    }

    func testReturnsOwnWindowOnTop() {
        XCTAssertEqual(frontmostOwnWindow(in: [(7, .own), (3, .foreign)]), 7)
    }

    func testReturnsNilWhenForeignWindowIsOnTop() {
        XCTAssertNil(frontmostOwnWindow(in: [(3, .foreign), (7, .own)]))
    }

    func testLooksThroughClickThroughWindows() {
        XCTAssertEqual(frontmostOwnWindow(in: [(9, .ownClickThrough), (7, .own)]), 7)
    }

    func testReturnsNilWhenClickThroughWindowIsOverForeignWindow() {
        XCTAssertNil(frontmostOwnWindow(in: [(9, .ownClickThrough), (3, .foreign), (7, .own)]))
    }

    func testReturnsNilWhenNothingIsUnderThePoint() {
        XCTAssertNil(frontmostOwnWindow(in: []))
        XCTAssertNil(frontmostOwnWindow(in: [(9, .ownClickThrough)]))
    }

    func testStopsWhenLookupReturnsTheSameWindowAgain() {
        let result = WindowHitTest.frontmostOwnWindow(windowNumberBelow: { _ in 9 }, classify: { _ in .ownClickThrough })
        XCTAssertNil(result)
    }

    func testFlipsCoreGraphicsPointToCocoa() {
        let point = WindowHitTest.cocoaPoint(fromCoreGraphics: CGPoint(x: 120, y: 200), primaryScreenMaxY: 982)
        XCTAssertEqual(point, CGPoint(x: 120, y: 782))
    }
}
