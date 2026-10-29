import CoreGraphics

/// Finds which of our own windows, if any, is frontmost under a screen point.
///
/// The window server lookups are passed in so the walk can be exercised without real windows.
public enum WindowHitTest {
    /// What a window number under the point turned out to be.
    public enum Candidate: Equatable, Sendable {
        /// Belongs to another process.
        case foreign
        /// Ours, and it takes mouse events.
        case own
        /// Ours, but click-through (such as the scroll indicator), so look beneath it.
        case ownClickThrough
    }

    /// Converts Core Graphics screen coordinates (origin top left of the primary screen) to Cocoa
    /// screen coordinates (origin bottom left of the primary screen).
    public static func cocoaPoint(fromCoreGraphics point: CGPoint, primaryScreenMaxY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }

    /// - Parameters:
    ///   - windowNumberBelow: The frontmost window number under the point below the given one
    ///     (`0` meaning the top of the stack), or `0` or less when there is none.
    ///   - classify: What the given window number is.
    /// - Returns: The number of our frontmost window that takes mouse events, or `nil` when another
    ///   process's window, or nothing, is in front of it.
    public static func frontmostOwnWindow(
        windowNumberBelow: (Int) -> Int,
        classify: (Int) -> Candidate
    ) -> Int? {
        var below = 0
        while true {
            let number = windowNumberBelow(below)
            guard number > 0, number != below else { return nil }
            switch classify(number) {
            case .foreign: return nil
            case .own: return number
            case .ownClickThrough: below = number
            }
        }
    }
}
