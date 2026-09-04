import AppKit
import Combine
import Foundation
import Preferences

/// Lets the settings window map a mouse button by pressing it. While listening, the session event
/// tap plus local and global `NSEvent` monitors all feed presses in, so whatever button the user
/// presses is captured — not only the default back/forward pair.
@MainActor
final class ButtonRecorder: ObservableObject {
    /// The direction currently waiting for a press, or `nil` when nothing is being recorded.
    @Published private(set) var listeningFor: NavigationDirection?

    /// Set by the app to apply a captured button.
    var onRecord: ((NavigationDirection, Int) -> Void)?

    /// Listening swallows presses system-wide, so it gives up on its own rather than leaving the
    /// mouse half-captured if the user walks away mid-mapping.
    private static let timeout: TimeInterval = 15

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var timeoutWorkItem: DispatchWorkItem?

    func listen(for direction: NavigationDirection) {
        listeningFor = direction
        installMonitors()
    }

    func cancel() {
        tearDownMonitors()
        listeningFor = nil
    }

    /// Returns `true` when the press was consumed as a mapping and should not reach any app.
    func record(_ button: Int64) -> Bool {
        guard let direction = listeningFor, AppSettings.isAssignable(Int(button)) else { return false }
        tearDownMonitors()
        listeningFor = nil
        onRecord?(direction, Int(button))
        return true
    }

    private func installMonitors() {
        tearDownMonitors()

        // Local: swallow the press inside the settings window so it does not click UI underneath.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.record(Int64(event.buttonNumber)) ? nil : event
        }

        // Global: still learn the button if the event tap handled it outside this app, or if focus
        // is elsewhere when the user presses.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            _ = self?.record(Int64(event.buttonNumber))
        }

        let timeout = DispatchWorkItem { [weak self] in
            self?.cancel()
        }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout, execute: timeout)
    }

    private func tearDownMonitors() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }
}
