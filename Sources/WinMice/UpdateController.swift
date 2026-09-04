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
    /// Sparkle's own first-launch/second-launch permission prompt writes
    /// `automaticallyChecksForUpdates` directly on `SPUUpdater`
    /// (`updatePermissionRequestFinishedWithResponse:`), bypassing the setter below entirely.
    /// KVO is the only way to notice that write and republish it to SwiftUI — Sparkle documents
    /// the property as KVO-compliant and main-thread-only, which is what makes the
    /// `MainActor.assumeIsolated` in the handler below sound.
    private var automaticChecksObservation: NSKeyValueObservation?

    init() {
        // startingUpdater: true schedules the first check itself. Because Info.plist omits
        // SUEnableAutomaticChecks, Sparkle asks the user for permission before checking.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticChecksObservation = controller.updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.objectWillChange.send()
            }
        }
    }

    /// User-initiated check. Always reports an outcome, even when already up to date.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    /// Pass-through. Notification is driven by the KVO observation set up in `init`,
    /// not from here, so writes made by Sparkle itself are published too.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
