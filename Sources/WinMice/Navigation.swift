import ApplicationServices
import Preferences
import SwipeGesturePoster

extension NavigationDirection {
    var swipeDirection: SwipeNavigationDirection {
        switch self {
        case .back: .back
        case .forward: .forward
        }
    }
}

/// Back/forward navigation via clean-room swipe posting or keyboard shortcuts.
@MainActor
final class NavigationController {
    var enabled = true
    var method: NavigationMethod = .swipe
    var triggerOnMouseDown = true
    var buttons: [NavigationDirection: Int64] = NavigationDirection.allCases
        .reduce(into: [:]) { buttons, direction in
            buttons[direction] = Int64(direction.defaultButton)
        }

    private let keyboardSource = CGEventSource(stateID: .hidSystemState)

    /// Checked in a fixed order rather than by searching the dictionary, whose iteration order
    /// varies with the process's hash seed. `SideButtons.resolve` rules out one button driving both
    /// directions, so the order only decides what happens if that guarantee is ever broken — and
    /// back comes first to match the tie-break `resolve` uses, so the two agree even then.
    func direction(for buttonNumber: Int64) -> NavigationDirection? {
        if buttons[.back] == buttonNumber { return .back }
        if buttons[.forward] == buttonNumber { return .forward }
        return nil
    }

    func perform(_ direction: NavigationDirection) {
        switch method {
        case .swipe:
            SwipeGesturePoster.perform(direction.swipeDirection)
        case .keyboard:
            performKeyboard(direction)
        }
    }

    private func performKeyboard(_ direction: NavigationDirection) {
        let keyCode: CGKeyCode = direction == .back ? 0x21 : 0x1E
        // Command and nothing else: whatever the user happens to be holding would otherwise ride
        // along and turn this into a different shortcut.
        let flags: CGEventFlags = .maskCommand

        if let keyDown = CGEvent(keyboardEventSource: keyboardSource, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = flags
            keyDown.post(tap: CGEventTapLocation.cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: keyboardSource, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = flags
            keyUp.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }
}
