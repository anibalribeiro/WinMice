import CoreGraphics

/// Turns the pointer's distance from the autoscroll anchor into whole-pixel wheel deltas.
///
/// Three things decide how the scrolling feels:
///
/// - The dead zone is radial. Measuring each axis on its own makes the still area a square, so a
///   diagonal drag has to travel about 1.4× further than a straight one before anything moves.
/// - Fractional pixels carry over between ticks. Rounding each tick on its own throws away up to a
///   pixel every 16 ms, which is the difference between a smooth crawl and a stuttering one — and
///   below roughly 1 px per tick it rounds slow drags away to nothing at all.
/// - The response is slightly faster than linear, so the first few points past the dead zone stay
///   precise while the far end of the screen still scrolls quickly.
public struct ScrollEngine {
    /// Pixels scrolled per tick one point past the dead zone, before the user's speed preference.
    public static let baseSpeed: CGFloat = 0.10

    /// Pointer distance from the anchor, in points, that scrolls nothing.
    public var deadZone: CGFloat = 12
    /// Pixels scrolled per tick one point past the dead zone.
    public var speed = baseSpeed
    /// Inverts the vertical wheel delta, so dragging down scrolls up.
    public var reverseVertical = false
    /// Inverts the horizontal wheel delta, so dragging right scrolls left.
    public var reverseHorizontal = false
    /// Exponent on the distance past the dead zone. Above 1 this buys fine control near the anchor
    /// at the cost of a steeper ramp further out.
    public var acceleration: CGFloat = 1.35
    /// Ceiling for one tick, so a pointer flung at the edge of the screen stays controllable.
    public var maxDeltaPerTick: CGFloat = 130

    private var remainder = CGVector.zero

    public init() {}

    public mutating func reset() {
        remainder = .zero
    }

    /// - Parameter offset: Pointer position minus anchor, in AppKit coordinates (y grows upward).
    /// - Returns: Wheel deltas for this tick, or `nil` when there is nothing to scroll.
    public mutating func tick(offset: CGVector) -> (vertical: Int32, horizontal: Int32)? {
        let distance = (offset.dx * offset.dx + offset.dy * offset.dy).squareRoot()
        guard distance > deadZone else {
            reset()
            return nil
        }

        let magnitude = min(speed * pow(distance - deadZone, acceleration), maxDeltaPerTick)
        // Positive wheel1 scrolls up and positive wheel2 scrolls left, so the vertical offset maps
        // straight across and the horizontal one inverts. The reverse flags flip either axis on top
        // of that, before the remainder is added, so the carryover stays in the same sign
        // convention as the deltas it accumulates toward.
        let vertical = (reverseVertical ? -1 : 1) * magnitude * offset.dy / distance + remainder.dy
        let horizontal = (reverseHorizontal ? 1 : -1) * magnitude * offset.dx / distance + remainder.dx

        let steps = CGVector(dx: horizontal.rounded(.towardZero), dy: vertical.rounded(.towardZero))
        remainder = CGVector(dx: horizontal - steps.dx, dy: vertical - steps.dy)

        guard steps.dx != 0 || steps.dy != 0 else { return nil }
        return (vertical: Int32(steps.dy), horizontal: Int32(steps.dx))
    }
}
