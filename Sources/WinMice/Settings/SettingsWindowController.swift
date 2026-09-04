import AppKit
import Preferences
import SwiftUI

/// Hosts the settings UI. The window itself is the only AppKit state here: everything below is
/// SwiftUI reading from `AppSettings` and `PermissionsMonitor`, so there is nothing to push or
/// reload when values change elsewhere in the app.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let defaultContentSize = NSSize(width: 640, height: 680)
    private static let minContentSize = NSSize(width: 560, height: 540)
    /// Bumped when default size/layout changed so a saved frame doesn’t stick.
    private static let frameAutosaveName = "WinMiceSettingsWindow.v5"

    private let recorder: ButtonRecorder

    init(
        settings: AppSettings,
        permissions: PermissionsMonitor,
        recorder: ButtonRecorder,
        updater: UpdateController
    ) {
        self.recorder = recorder
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppInfo.name) Settings"
        // The sidebar supplies its own header, so the titlebar only carries the window buttons.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minContentSize
        window.contentViewController = NSHostingController(
            rootView: SettingsView(
                settings: settings,
                permissions: permissions,
                recorder: recorder,
                updater: updater
            )
        )
        window.appearance = NSAppearance(named: .aqua)
        // Assigning a content view controller resizes the window to fit, so restore our size after.
        window.setContentSize(Self.defaultContentSize)

        super.init(window: window)
        window.delegate = self

        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Promotes the accessory app to a regular one so the window can take focus, then shows it.
    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.collectionBehavior.insert(.moveToActiveSpace)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        recorder.cancel()
        NSApp.setActivationPolicy(.accessory)
    }
}
