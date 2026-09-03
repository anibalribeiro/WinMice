import Combine
import Foundation
import ServiceManagement

/// How a middle-click starts and stops autoscrolling.
enum ScrollMode: Hashable, CaseIterable, Identifiable {
    /// Scroll while the middle button is held; stop on release.
    case holdToScroll
    /// Hold the middle button briefly to latch scrolling; stop on the next click.
    case holdToStart

    var id: Self { self }
}

/// Persisted preferences, and the single source of truth for both the event pipeline and the
/// settings window. Properties read through to `UserDefaults` so there is no second copy of the
/// state to keep in sync, and every write notifies observers.
@MainActor
final class AppSettings: ObservableObject {
    static let markerSizes = [28, 32, 40, 48]
    static let holdToStartDelayRange = 50...1000
    static let holdToStartDelayStep = 25
    static let scrollSpeedRange = 25...300
    static let scrollSpeedStep = 25

    /// Called after any change so the app can reconfigure live behavior.
    var onChange: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let darkMode = Preference("darkMode", default: false)
        static let holdToLockMode = Preference("holdToLockMode", default: false)
        static let holdToStartDelayMs = Preference("holdToStartDelayMs", default: 200)
        static let scrollSpeedPercent = Preference("scrollSpeedPercent", default: 100)
        static let reverseScrollDirectionVertical = Preference("reverseScrollDirectionVertical", default: false)
        static let reverseScrollDirectionHorizontal = Preference("reverseScrollDirectionHorizontal", default: false)
        static let markerSize = Preference("markerSize", default: 32)
        static let sideButtonsEnabled = Preference("sideButtonsEnabled", default: true)
        static let navigationMethod = Preference("navigationMethod", default: NavigationMethod.swipe)
        static let backButton = Preference("backButtonNumber", default: NavigationDirection.back.defaultButton)
        static let forwardButton = Preference("forwardButtonNumber", default: NavigationDirection.forward.defaultButton)
        /// Superseded by the two button numbers above; still read so existing installs keep their choice.
        static let swapSideButtons = Preference("swapSideButtons", default: false)
        static let triggerOnMouseDown = Preference("triggerOnMouseDown", default: true)
        static let menuBarIconHidden = Preference("menuBarIconHidden", default: false)

        static let all: [String] = [
            darkMode.key,
            holdToLockMode.key,
            holdToStartDelayMs.key,
            scrollSpeedPercent.key,
            reverseScrollDirectionVertical.key,
            reverseScrollDirectionHorizontal.key,
            markerSize.key,
            sideButtonsEnabled.key,
            navigationMethod.key,
            backButton.key,
            forwardButton.key,
            swapSideButtons.key,
            triggerOnMouseDown.key,
            menuBarIconHidden.key
        ]
    }

    var darkMode: Bool {
        get { defaults[Key.darkMode] }
        set { write(newValue, to: Key.darkMode) }
    }

    /// Stored as the original `holdToLockMode` flag so existing installs keep their choice.
    var scrollMode: ScrollMode {
        get { defaults[Key.holdToLockMode] ? .holdToStart : .holdToScroll }
        set { write(newValue == .holdToStart, to: Key.holdToLockMode) }
    }

    var holdToStartDelayMs: Int {
        get { Self.clampHoldToStartDelay(defaults[Key.holdToStartDelayMs]) }
        set { write(Self.clampHoldToStartDelay(newValue), to: Key.holdToStartDelayMs) }
    }

    var scrollSpeedPercent: Int {
        get { Self.clamp(defaults[Key.scrollSpeedPercent], to: Self.scrollSpeedRange, step: Self.scrollSpeedStep) }
        set { write(Self.clamp(newValue, to: Self.scrollSpeedRange, step: Self.scrollSpeedStep), to: Key.scrollSpeedPercent) }
    }

    var reverseScrollDirectionVertical: Bool {
        get { defaults[Key.reverseScrollDirectionVertical] }
        set { write(newValue, to: Key.reverseScrollDirectionVertical) }
    }

    var reverseScrollDirectionHorizontal: Bool {
        get { defaults[Key.reverseScrollDirectionHorizontal] }
        set { write(newValue, to: Key.reverseScrollDirectionHorizontal) }
    }

    var markerSize: Int {
        get { Self.nearestMarkerSize(defaults[Key.markerSize]) }
        set { write(Self.nearestMarkerSize(newValue), to: Key.markerSize) }
    }

    var sideButtonsEnabled: Bool {
        get { defaults[Key.sideButtonsEnabled] }
        set { write(newValue, to: Key.sideButtonsEnabled) }
    }

    var navigationMethod: NavigationMethod {
        get { defaults[Key.navigationMethod] }
        set { write(newValue, to: Key.navigationMethod) }
    }

    var backButton: Int {
        get { button(Key.backButton, swappedTo: NavigationDirection.forward.defaultButton) }
        set { write(newValue, to: Key.backButton) }
    }

    var forwardButton: Int {
        get { button(Key.forwardButton, swappedTo: NavigationDirection.back.defaultButton) }
        set { write(newValue, to: Key.forwardButton) }
    }

    subscript(button direction: NavigationDirection) -> Int {
        get {
            switch direction {
            case .back: backButton
            case .forward: forwardButton
            }
        }
        set {
            switch direction {
            case .back: backButton = newValue
            case .forward: forwardButton = newValue
            }
        }
    }

    /// Maps a button to a direction. A button already used by the other direction trades places
    /// rather than ending up mapped twice.
    func assign(_ button: Int, to direction: NavigationDirection) {
        guard Self.isAssignable(button) else { return }
        let opposite = direction.opposite
        if self[button: opposite] == button {
            self[button: opposite] = self[button: direction]
        }
        self[button: direction] = button
    }

    /// Any mouse button the event tap can see and does not already own. Left and right (0 and 1)
    /// stay reserved so Set / Cancel clicks and the menu bar keep working, and the middle button
    /// (2) belongs to autoscroll — mapping it would leave a scroll latched with no way to end it.
    nonisolated static func isAssignable(_ button: Int) -> Bool {
        (3...31).contains(button)
    }

    private func button(_ preference: Preference<Int>, swappedTo swapped: Int) -> Int {
        let stored = defaults.hasValue(for: preference)
            ? defaults[preference]
            : (defaults[Key.swapSideButtons] ? swapped : preference.defaultValue)
        // A button an older build let through but this one reserves falls back to the default, so
        // the mapping settings shows is always the one actually in effect.
        return Self.isAssignable(stored) ? stored : preference.defaultValue
    }

    var triggerOnMouseDown: Bool {
        get { defaults[Key.triggerOnMouseDown] }
        set { write(newValue, to: Key.triggerOnMouseDown) }
    }

    var menuBarIconHidden: Bool {
        get { defaults[Key.menuBarIconHidden] }
        set { write(newValue, to: Key.menuBarIconHidden) }
    }

    /// Hold duration before `holdToStart` engages scrolling.
    var holdToStartDelay: TimeInterval {
        TimeInterval(holdToStartDelayMs) / 1000
    }

    /// Login items are owned by the system, so `SMAppService` stays the source of truth.
    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        objectWillChange.send()
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        onChange?()
    }

    /// Clears every stored preference. The login item belongs to the system, so it is left alone.
    func restoreDefaults() {
        objectWillChange.send()
        for key in Key.all {
            defaults.removeObject(forKey: key)
        }
        onChange?()
    }

    static func clampHoldToStartDelay(_ milliseconds: Int) -> Int {
        clamp(milliseconds, to: holdToStartDelayRange, step: holdToStartDelayStep)
    }

    /// Snaps to the nearest step, then into range. Rounding rather than truncating keeps a slider
    /// from always drifting toward its lower bound.
    static func clamp(_ value: Int, to range: ClosedRange<Int>, step: Int) -> Int {
        let stepped = Int((Double(value) / Double(step)).rounded()) * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    static func nearestMarkerSize(_ size: Int) -> Int {
        markerSizes.min { abs($0 - size) < abs($1 - size) } ?? 32
    }

    private func write<Value: PreferenceRepresentable>(_ value: Value, to preference: Preference<Value>) {
        objectWillChange.send()
        defaults[preference] = value
        onChange?()
    }
}