import Sparkle

/// Thin wrapper over Sparkle's standard updater.
///
/// Sparkle owns all update state: `automaticallyChecksForUpdates` reads and writes straight
/// through to `SPUUpdater`, which persists it in `UserDefaults` under `SUEnableAutomaticChecks`.
/// It is deliberately not mirrored into `AppSettings` — Sparkle's own first-launch permission
/// prompt writes the same value, so a second copy would drift.
@MainActor
final class UpdateController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true schedules the first check itself. Because Info.plist omits
        // SUEnableAutomaticChecks, Sparkle asks the user for permission before checking.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// User-initiated check. Always reports an outcome, even when already up to date.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            guard newValue != controller.updater.automaticallyChecksForUpdates else { return }
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }
}
