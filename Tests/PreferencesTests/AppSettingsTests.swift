import XCTest
@testable import Preferences

@MainActor
final class AppSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    override func setUp() {
        super.setUp()
        // A private suite, so a test run never touches the developer's real preferences.
        suiteName = "cz.anibalribeiro.winmice.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// The values the README documents. A default that disagrees with the docs is a real bug,
    /// and until now it lived in three places with nothing comparing them.
    func testShippedDefaultsMatchTheDocumentedValues() {
        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.darkMode)
        XCTAssertEqual(settings.scrollMode, .holdToScroll)
        XCTAssertEqual(settings.holdToStartDelayMs, 200)
        XCTAssertEqual(settings.scrollSpeedPercent, 100)
        XCTAssertFalse(settings.reverseScrollDirectionVertical)
        XCTAssertFalse(settings.reverseScrollDirectionHorizontal)
        XCTAssertEqual(settings.markerSize, 32)
        XCTAssertTrue(settings.sideButtonsEnabled)
        XCTAssertEqual(settings.navigationMethod, .swipe)
        XCTAssertEqual(settings[button: .back], 3)
        XCTAssertEqual(settings[button: .forward], 4)
        XCTAssertTrue(settings.triggerOnMouseDown)
        XCTAssertFalse(settings.menuBarIconHidden)
    }

    /// The bug this task exists to prevent: a preference that Restore Defaults silently skips
    /// because someone added it to the type but not to the reset list.
    func testRestoreDefaultsResetsEveryPreference() {
        let settings = AppSettings(defaults: defaults)

        settings.darkMode = true
        settings.scrollMode = .holdToStart
        settings.holdToStartDelayMs = 500
        settings.scrollSpeedPercent = 250
        settings.reverseScrollDirectionVertical = true
        settings.reverseScrollDirectionHorizontal = true
        settings.markerSize = 48
        settings.sideButtonsEnabled = false
        settings.navigationMethod = .keyboard
        settings.assign(6, to: .back)
        settings.assign(7, to: .forward)
        settings.triggerOnMouseDown = false
        settings.menuBarIconHidden = true

        settings.restoreDefaults()

        XCTAssertFalse(settings.darkMode)
        XCTAssertEqual(settings.scrollMode, .holdToScroll)
        XCTAssertEqual(settings.holdToStartDelayMs, 200)
        XCTAssertEqual(settings.scrollSpeedPercent, 100)
        XCTAssertFalse(settings.reverseScrollDirectionVertical)
        XCTAssertFalse(settings.reverseScrollDirectionHorizontal)
        XCTAssertEqual(settings.markerSize, 32)
        XCTAssertTrue(settings.sideButtonsEnabled)
        XCTAssertEqual(settings.navigationMethod, .swipe)
        XCTAssertEqual(settings[button: .back], 3)
        XCTAssertEqual(settings[button: .forward], 4)
        XCTAssertTrue(settings.triggerOnMouseDown)
        XCTAssertFalse(settings.menuBarIconHidden)
    }

    /// Restore Defaults must leave the keys it does not own alone. Sparkle's consent lives in
    /// the same domain, and wiping it would re-trigger the permission prompt.
    func testRestoreDefaultsLeavesForeignKeysAlone() {
        defaults.set(true, forKey: "SUEnableAutomaticChecks")

        AppSettings(defaults: defaults).restoreDefaults()

        XCTAssertEqual(defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool, true)
    }

    /// These come from UserDefaults, so they can be stale from an older build or hand-edited.
    /// A value the slider cannot express must be pulled into range on read.
    func testOutOfRangePersistedValuesAreClampedOnRead() {
        defaults.set(9_000, forKey: "scrollSpeedPercent")
        defaults.set(1, forKey: "holdToStartDelayMs")
        defaults.set(999, forKey: "markerSize")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.scrollSpeedPercent, 300)
        XCTAssertEqual(settings.holdToStartDelayMs, 50)
        XCTAssertEqual(settings.markerSize, 48)
    }

    /// A negative or enormous stored value used to reach an Int multiplication that overflows
    /// and traps, which would crash the app during startup with no way to recover from inside it.
    func testExtremePersistedValuesDoNotTrap() {
        defaults.set(Int.min, forKey: "scrollSpeedPercent")
        defaults.set(Int.max, forKey: "holdToStartDelayMs")
        defaults.set(Int.min, forKey: "markerSize")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.scrollSpeedPercent, 25)
        XCTAssertEqual(settings.holdToStartDelayMs, 1_000)
        XCTAssertEqual(settings.markerSize, 28)
    }

    /// Mapping a button already bound to the other direction swaps the two rather than leaving
    /// both directions on one button, which would capture it twice.
    func testAssigningAMappedButtonSwapsTheTwoDirections() {
        let settings = AppSettings(defaults: defaults)

        settings.assign(4, to: .back)

        XCTAssertEqual(settings[button: .back], 4)
        XCTAssertEqual(settings[button: .forward], 3)
    }

    /// Left, right, and middle are refused: the first two keep Set and Cancel clickable and the
    /// middle button belongs to autoscroll.
    func testReservedButtonsAreRefused() {
        let settings = AppSettings(defaults: defaults)

        for reserved in [0, 1, 2] {
            settings.assign(reserved, to: .back)
            XCTAssertEqual(settings[button: .back], 3, "button \(reserved) should not be assignable")
        }
    }
}
