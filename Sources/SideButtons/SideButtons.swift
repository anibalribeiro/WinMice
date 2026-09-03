/// Which mouse button drives each navigation direction.
public struct SideButtonMapping: Equatable, Sendable {
    public let back: Int
    public let forward: Int

    public init(back: Int, forward: Int) {
        self.back = back
        self.forward = forward
    }
}

public enum SideButtons {
    /// Button numbers each direction uses until the user maps another one. CoreGraphics numbers
    /// from zero, so the left, right, and middle buttons are 0 through 2 and the side buttons
    /// start at 3.
    public static let defaultBack = 3
    public static let defaultForward = 4

    /// Any mouse button the event tap can see and does not already own. Left and right stay
    /// reserved so Set / Cancel clicks and the menu bar keep working, and the middle button
    /// belongs to autoscroll — mapping it would leave a scroll latched with no way to end it.
    public static let assignable = 3...31

    public static func isAssignable(_ button: Int) -> Bool {
        assignable.contains(button)
    }

    /// - Parameters:
    ///   - storedBack: The stored back button, or `nil` when the user has never set one.
    ///   - storedForward: The stored forward button, or `nil` when the user has never set one.
    ///   - legacySwap: The superseded `swapSideButtons` flag, still honored so existing installs
    ///     keep the choice they made under it.
    /// Both directions resolve together because a fallback has to see what the other direction
    /// already occupies. Resolving them one at a time is what let a stored value the app no longer
    /// accepts fall back onto a button the other direction was using, leaving one button driving
    /// both — and leaving which one fired up to a dictionary lookup, i.e. to the hash seed.
    public static func resolve(
        storedBack: Int?,
        storedForward: Int?,
        legacySwap: Bool
    ) -> SideButtonMapping {
        let mappedBack = mapped(storedBack)
        var mappedForward = mapped(storedForward)
        // Two stored values that match cannot both stand. Back keeps the button and forward is
        // resolved as though it had none, so the result does not depend on which is read first.
        if mappedBack == mappedForward {
            mappedForward = nil
        }

        let back = mappedBack ?? fallback(
            preferred: preference(ownDefault: defaultBack, wasStored: storedBack != nil, legacySwap: legacySwap),
            taken: mappedForward
        )
        let forward = mappedForward ?? fallback(
            preferred: preference(ownDefault: defaultForward, wasStored: storedForward != nil, legacySwap: legacySwap),
            taken: back
        )
        return SideButtonMapping(back: back, forward: forward)
    }

    /// The button the user actually chose, or `nil` when they never chose one or chose one this
    /// build reserves — a value an older build let through, say.
    private static func mapped(_ stored: Int?) -> Int? {
        guard let stored, isAssignable(stored) else { return nil }
        return stored
    }

    /// The button a direction would use if nothing else were competing for it.
    ///
    /// The superseded flag swapped the pair, but only for a direction the user had never mapped.
    /// A stored value this build reserves is not the same as no value at all: it falls back to the
    /// direction's own default with the swap ignored, which is what it has always done.
    private static func preference(ownDefault: Int, wasStored: Bool, legacySwap: Bool) -> Int {
        legacySwap && !wasStored ? other(than: ownDefault) : ownDefault
    }

    /// Steps aside when the preferred button is already taken. Total because the two defaults
    /// differ, so the pair always holds one button that is not the taken one.
    private static func fallback(preferred: Int, taken: Int?) -> Int {
        preferred == taken ? other(than: preferred) : preferred
    }

    private static func other(than button: Int) -> Int {
        button == defaultBack ? defaultForward : defaultBack
    }
}
