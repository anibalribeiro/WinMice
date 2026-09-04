import Combine
import Foundation
import ServiceManagement
import SideButtons

/// How a middle-click starts and stops autoscrolling.
public enum ScrollMode: Hashable, CaseIterable, Identifiable {
    /// Scroll while the middle button is held; stop on release.
    case holdToScroll
    /// Hold the middle button briefly to latch scrolling; stop on the next click.
    case holdToStart

    public var id: Self { self }
}

/// Persisted preferences, and the single source of truth for both the event pipeline and the
/// settings window. Properties read through to `UserDefaults` so there is no second copy of the
/// state to keep in sync, and every write notifies observers.
@MainActor
public final class AppSettings: ObservableObject {
    public static let markerSizes = [28, 32, 40, 48]
    public static let holdToStartDelayRange = 50...1000
    public static let holdToStartDelayStep = 25
    public static let scrollSpeedRange = 25...300
    public static let scrollSpeedStep = 25

    /// Called after any change so the app can reconfigure live behavior.
    public var onChange: (() -> Void)?

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Instance properties rather than statics: `Mirror` cannot see static members, and
    /// reflecting over these is what keeps `restoreDefaults()` honest. Adding a preference here
    /// adds it to the reset automatically, so the two cannot drift apart.
    private struct Keys {
        let darkMode = Preference("darkMode", default: false)
        let holdToLockMode = Preference("holdToLockMode", default: false)
        let holdToStartDelayMs = Preference("holdToStartDelayMs", default: 200)
        let scrollSpeedPercent = Preference("scrollSpeedPercent", default: 100)
        let reverseScrollDirectionVertical = Preference("reverseScrollDirectionVertical", default: false)
        let reverseScrollDirectionHorizontal = Preference("reverseScrollDirectionHorizontal", default: false)
        let markerSize = Preference("markerSize", default: 32)
        let sideButtonsEnabled = Preference("sideButtonsEnabled", default: true)
        let navigationMethod = Preference("navigationMethod", default: NavigationMethod.swipe)
        let backButton = Preference("backButtonNumber", default: NavigationDirection.back.defaultButton)
        let forwardButton = Preference("forwardButtonNumber", default: NavigationDirection.forward.defaultButton)
        /// Superseded by the two button numbers above; still read so existing installs keep their choice.
        let swapSideButtons = Preference("swapSideButtons", default: false)
        let triggerOnMouseDown = Preference("triggerOnMouseDown", default: true)
        let menuBarIconHidden = Preference("menuBarIconHidden", default: false)

        var all: [String] {
            Mirror(reflecting: self).children.compactMap { ($0.value as? AnyPreference)?.key }
        }
    }

    private let keys = Keys()

    public var darkMode: Bool {
        get { defaults[keys.darkMode] }
        set { write(newValue, to: keys.darkMode) }
    }

    /// Stored as the original `holdToLockMode` flag so existing installs keep their choice.
    public var scrollMode: ScrollMode {
        get { defaults[keys.holdToLockMode] ? .holdToStart : .holdToScroll }
        set { write(newValue == .holdToStart, to: keys.holdToLockMode) }
    }

    public var holdToStartDelayMs: Int {
        get { Self.clampHoldToStartDelay(defaults[keys.holdToStartDelayMs]) }
        set { write(Self.clampHoldToStartDelay(newValue), to: keys.holdToStartDelayMs) }
    }

    public var scrollSpeedPercent: Int {
        get { Self.clamp(defaults[keys.scrollSpeedPercent], to: Self.scrollSpeedRange, step: Self.scrollSpeedStep) }
        set { write(Self.clamp(newValue, to: Self.scrollSpeedRange, step: Self.scrollSpeedStep), to: keys.scrollSpeedPercent) }
    }

    public var reverseScrollDirectionVertical: Bool {
        get { defaults[keys.reverseScrollDirectionVertical] }
        set { write(newValue, to: keys.reverseScrollDirectionVertical) }
    }

    public var reverseScrollDirectionHorizontal: Bool {
        get { defaults[keys.reverseScrollDirectionHorizontal] }
        set { write(newValue, to: keys.reverseScrollDirectionHorizontal) }
    }

    public var markerSize: Int {
        get { Self.nearestMarkerSize(defaults[keys.markerSize]) }
        set { write(Self.nearestMarkerSize(newValue), to: keys.markerSize) }
    }

    public var sideButtonsEnabled: Bool {
        get { defaults[keys.sideButtonsEnabled] }
        set { write(newValue, to: keys.sideButtonsEnabled) }
    }

    public var navigationMethod: NavigationMethod {
        get { defaults[keys.navigationMethod] }
        set { write(newValue, to: keys.navigationMethod) }
    }

    /// Private because the setters take a button without validating it. `assign(_:to:)` is the way
    /// in: it rejects buttons the tap cannot claim and keeps the two directions on separate ones.
    private var backButton: Int {
        get { sideButtons.back }
        set { write(newValue, to: keys.backButton) }
    }

    private var forwardButton: Int {
        get { sideButtons.forward }
        set { write(newValue, to: keys.forwardButton) }
    }

    /// Resolved as a pair, so neither direction can fall back onto the button the other uses.
    private var sideButtons: SideButtonMapping {
        SideButtons.resolve(
            storedBack: stored(keys.backButton),
            storedForward: stored(keys.forwardButton),
            legacySwap: defaults[keys.swapSideButtons]
        )
    }

    private func stored(_ preference: Preference<Int>) -> Int? {
        defaults.hasValue(for: preference) ? defaults[preference] : nil
    }

    public subscript(button direction: NavigationDirection) -> Int {
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
    public func assign(_ button: Int, to direction: NavigationDirection) {
        guard Self.isAssignable(button) else { return }
        let opposite = direction.opposite
        if self[button: opposite] == button {
            self[button: opposite] = self[button: direction]
        }
        self[button: direction] = button
    }

    public nonisolated static func isAssignable(_ button: Int) -> Bool {
        SideButtons.isAssignable(button)
    }

    public var triggerOnMouseDown: Bool {
        get { defaults[keys.triggerOnMouseDown] }
        set { write(newValue, to: keys.triggerOnMouseDown) }
    }

    public var menuBarIconHidden: Bool {
        get { defaults[keys.menuBarIconHidden] }
        set { write(newValue, to: keys.menuBarIconHidden) }
    }

    /// Hold duration before `holdToStart` engages scrolling.
    public var holdToStartDelay: TimeInterval {
        TimeInterval(holdToStartDelayMs) / 1000
    }

    /// Login items are owned by the system, so `SMAppService` stays the source of truth.
    public var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setLaunchAtLogin(_ enabled: Bool) throws {
        objectWillChange.send()
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        onChange?()
    }

    /// Clears every stored preference WinMice owns. The login item belongs to the system, and
    /// Sparkle's consent lives in the same domain, so both are left alone.
    public func restoreDefaults() {
        objectWillChange.send()
        for key in keys.all {
            defaults.removeObject(forKey: key)
        }
        onChange?()
    }

    static func clampHoldToStartDelay(_ milliseconds: Int) -> Int {
        clamp(milliseconds, to: holdToStartDelayRange, step: holdToStartDelayStep)
    }

    /// Clamps into range before snapping to the step. Snapping first overflows on a value near
    /// Int.max, and these values come from UserDefaults, so they can be anything.
    static func clamp(_ value: Int, to range: ClosedRange<Int>, step: Int) -> Int {
        let bounded = min(max(value, range.lowerBound), range.upperBound)
        let stepped = Int((Double(bounded) / Double(step)).rounded()) * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    static func nearestMarkerSize(_ size: Int) -> Int {
        let bounded = min(max(size, markerSizes[0]), markerSizes[markerSizes.count - 1])
        return markerSizes.min { abs($0 - bounded) < abs($1 - bounded) } ?? 32
    }

    private func write<Value: PreferenceRepresentable>(_ value: Value, to preference: Preference<Value>) {
        objectWillChange.send()
        defaults[preference] = value
        onChange?()
    }
}
