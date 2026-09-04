/// Remembers what the event tap did with each button press so the matching release can be
/// decided from that record rather than from whatever the current settings happen to say.
///
/// Re-deriving the release decision is what leaks unmatched events: a press delivered to the app
/// under the pointer whose release is swallowed leaves that app holding a button down forever,
/// and the reverse hands it a release it never asked for. Both are reachable by toggling a
/// setting, remapping a button, or clicking fast enough to cross a replay guard window.

/// What the tap did, or should do, with one half of a click.
public enum ButtonAction: Equatable {
    /// Hand the event on to the app under the pointer.
    case passThrough
    /// Keep the event; the app under the pointer never sees it.
    case swallow
}

public struct ButtonGate {
    private var pressed: [Int64: ButtonAction] = [:]

    public init() {}

    public mutating func press(button: Int64, action: ButtonAction) -> ButtonAction {
        pressed[button] = action
        return action
    }

    public mutating func release(button: Int64, fallback: ButtonAction) -> ButtonAction {
        pressed.removeValue(forKey: button) ?? fallback
    }

    public mutating func reset() {
        pressed.removeAll()
    }
}
