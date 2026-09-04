import Combine
import Sparkle

/// Thin wrapper over Sparkle's standard updater.
///
/// Sparkle owns all update state: `automaticallyChecksForUpdates` reads and writes straight
/// through to `SPUUpdater`, which persists it in `UserDefaults` under `SUEnableAutomaticChecks`.
/// It is deliberately not mirrored into `AppSettings` — Sparkle's own first-launch permission
/// prompt writes the same value, so a second copy would drift.
@MainActor
final class UpdateController: NSObject, ObservableObject, @MainActor SPUStandardUserDriverDelegate {
    /// IUO so `self` can be passed as `userDriverDelegate`. Sparkle holds that delegate weakly
    /// (`SPUStandardUpdaterController.h`), so this object must outlive the controller — it does,
    /// because `WinMiceApp` owns the wrapper.
    private var controller: SPUStandardUpdaterController!
    /// Sparkle's own first-launch/second-launch permission prompt writes
    /// `automaticallyChecksForUpdates` directly on `SPUUpdater`
    /// (`updatePermissionRequestFinishedWithResponse:`), bypassing the setter below entirely.
    /// KVO is the only way to notice that write and republish it to SwiftUI — Sparkle documents
    /// the property as KVO-compliant and main-thread-only, which is what makes the
    /// `MainActor.assumeIsolated` in the handler below sound.
    private var automaticChecksObservation: NSKeyValueObservation?

    /// Display version of a scheduled update waiting for attention. Nil when nothing is pending
    /// or the check was user-initiated (Sparkle always presents those itself).
    @Published private(set) var pendingUpdateVersion: String? {
        didSet {
            guard oldValue != pendingUpdateVersion else { return }
            onPendingUpdateChange?()
        }
    }

    /// AppKit hook so the menu bar item can mark itself without importing Combine.
    var onPendingUpdateChange: (() -> Void)?

    override init() {
        super.init()
        // startingUpdater: true schedules the first check itself. Because Info.plist omits
        // SUEnableAutomaticChecks, Sparkle asks the user for permission before checking.
        // Must be assigned after super.init so `self` can be the user-driver delegate.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
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

    /// Pass-through of `SPUUpdater.canCheckForUpdates`, which Sparkle documents as the property
    /// to use for menu item validation.
    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    /// Pass-through. Notification is driven by the KVO observation set up in `init`,
    /// not from here, so writes made by Sparkle itself are published too.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// `SPUStandardUserDriverDelegate.h`: optional, default `NO`. Returning `YES` is what
    /// silences Sparkle's background-app warning and opts into the gentle-reminder callbacks.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Called before Sparkle shows an update. User-initiated checks always have
    /// `state.userInitiated == YES` and Sparkle always handles those; we only publish a
    /// pending version for scheduled checks so the menu bar can mark itself.
    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !state.userInitiated {
            pendingUpdateVersion = update.displayVersionString
        }
    }

    /// Sparkle's documented place to dismiss indicators introduced in
    /// `standardUserDriverWillHandleShowingUpdate`.
    func standardUserDriverWillFinishUpdateSession() {
        pendingUpdateVersion = nil
    }
}
