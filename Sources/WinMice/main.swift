@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import ButtonGate
import Preferences
import ScrollEngine

@MainActor
private final class WinMiceApp: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// What became of a middle-button press the tap swallowed.
    private enum MiddlePress {
        /// Still undecided: replayed as an ordinary click if the press ends without scrolling.
        case pending(CGEvent)
        /// Spent on scrolling, so only its release is left to swallow.
        case consumed
    }

    private let settings = AppSettings()
    private let permissions = PermissionsMonitor()
    private let indicator = ScrollIndicatorWindow()
    private let navigation = NavigationController()
    private let recorder = ButtonRecorder()
    private let updater = UpdateController()

    private var statusItem: NSStatusItem?
    private var menu: NSMenu!
    private var settingsController: SettingsWindowController!

    private var eventTap: EventTap!
    private var healthTimer: DispatchSourceTimer?
    private var accessibilityPromptedThisRun = false
    /// Global monitor used only while hold-to-start scrolling is latched, so the event tap does
    /// not need to listen for left/right clicks (which would break the menu bar icon).
    private var stopClickMonitor: Any?
    private var stopClickLocalMonitor: Any?

    private var scroll = ScrollEngine()
    private var scrollTimer: DispatchSourceTimer?
    private var anchor: CGPoint?
    private var isActive = false
    private var sawMiddleButtonDown = false
    private var armedScrollStart: DispatchWorkItem?
    /// Button whose release still has to be swallowed after it was captured as a mapping.
    private var recordedButton: Int64?
    private var middlePress: MiddlePress?
    private var lastMiddleReplay: Date?
    /// Mapped navigation buttons currently held down, so their release can be swallowed too.
    private var heldNavigationButtons: Set<Int64> = []
    /// Latches each press's tap decision so the matching release follows it instead of
    /// re-deriving from whatever the settings and replay window happen to say at that moment.
    private var buttonGate = ButtonGate()

    private static let middleButton: Int64 = 2
    private static let scrollTick = DispatchTimeInterval.milliseconds(16)
    /// Stamped on the middle clicks WinMice replays so the tap recognizes its own work coming back
    /// around instead of treating it as a fresh press.
    private static let eventSignature: Int64 = 0x57_49_4E_4D
    /// Backstop for the signature. If a replayed click ever lost its mark, treating presses this
    /// soon after a replay as ordinary clicks is what keeps it from replaying itself forever.
    private static let replayGuardWindow: TimeInterval = 0.2
    /// Hold-to-scroll waits about a frame before engaging, which is short enough to feel immediate
    /// and long enough that an ordinary middle click passes through without the indicator blinking.
    private static let holdToScrollDelay: TimeInterval = 0.02

    private var holdToStart: Bool { settings.scrollMode == .holdToStart }
    private var holdToStartDelay: TimeInterval { settings.holdToStartDelay }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        eventTap = EventTap(eventsOfInterest: [.otherMouseDown, .otherMouseUp]) { [weak self] type, event in
            guard let self else { return Unmanaged.passUnretained(event) }
            return handleEvent(type: type, event: event)
        }
        eventTap.onDisabled = { [weak self] in
            self?.resetEventState()
        }

        settings.onChange = { [weak self] in
            self?.applySettings()
        }
        recorder.onRecord = { [weak self] direction, button in
            self?.settings.assign(button, to: direction)
        }
        settingsController = SettingsWindowController(
            settings: settings,
            permissions: permissions,
            recorder: recorder,
            updater: updater
        )
        updater.onPendingUpdateChange = { [weak self] in
            guard let self else { return }
            if self.updater.pendingUpdateVersion != nil {
                self.installStatusItem()
            } else if self.settings.menuBarIconHidden {
                self.removeStatusItem()
            } else {
                self.applyStatusItemAppearance()
            }
        }

        configureMainMenu()
        configureMenu()
        applySettings()
        observeSystemEvents()
        // Prompt after the run loop is spinning; asking during didFinishLaunching often swallows
        // the system dialogs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.requestPermissions()
        }
        eventTap.install()
        startHealthTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopScrolling()
        healthTimer?.cancel()
        healthTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        eventTap.tearDown()
    }

    // MARK: - Menu bar

    /// AppKit only honors ⌘W / ⌘Q (and ⌘,) from the application main menu — the status-item
    /// menu's key equivalents do nothing while the settings window is key.
    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(AppInfo.name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(NSMenuItem(
            title: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))

        NSApp.mainMenu = mainMenu
    }

    private func configureMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Check for updates")
        menu.addItem(updateItem)

        let supportItem = NSMenuItem(title: "Buy me a coffee…", action: #selector(openSupportLink), keyEquivalent: "")
        supportItem.target = self
        supportItem.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Buy me a coffee")
        menu.addItem(supportItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        self.menu = menu
    }

    private func installStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = statusItem?.button {
                button.target = self
                button.action = #selector(statusBarButtonClicked(_:))
                // mouseDown is more reliable than mouseUp for status items, especially alongside an
                // event tap that also sees mouse events.
                button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            }
        }
        applyStatusItemAppearance()
    }

    /// Badge and tooltip when a scheduled update is waiting. A pending update keeps the item
    /// installed even if the user hid it; this is only a no-op when there is no status item yet.
    private func applyStatusItemAppearance() {
        guard let button = statusItem?.button else { return }
        let pending = updater.pendingUpdateVersion
        button.image = Self.menuBarIcon(updatePending: pending != nil)
        button.image?.isTemplate = true
        if let pending {
            button.toolTip = "Update \(pending) available"
        } else {
            button.toolTip = nil
        }
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    /// Classic middle-button autoscroll glyph for the menu bar (template image).
    private static func menuBarIcon(updatePending: Bool = false) -> NSImage {
        let pointSize: CGFloat = 18
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            let inset = rect.insetBy(dx: 1.25, dy: 1.25)
            let circle = NSBezierPath(ovalIn: inset)
            circle.lineWidth = 1.4
            NSColor.black.setStroke()
            circle.stroke()

            let cx = inset.midX
            let cy = inset.midY
            let triangleWidth = inset.width * 0.36
            let triangleHeight = inset.height * 0.18
            let gap = inset.height * 0.07
            let dotRadius = inset.width * 0.07

            NSColor.black.setFill()

            let upTip = NSPoint(x: cx, y: cy + gap + triangleHeight + dotRadius + 0.5)
            let up = NSBezierPath()
            up.move(to: upTip)
            up.line(to: NSPoint(x: upTip.x - triangleWidth / 2, y: upTip.y - triangleHeight))
            up.line(to: NSPoint(x: upTip.x + triangleWidth / 2, y: upTip.y - triangleHeight))
            up.close()
            up.fill()

            NSBezierPath(ovalIn: NSRect(
                x: cx - dotRadius,
                y: cy - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )).fill()

            let downTip = NSPoint(x: cx, y: cy - gap - triangleHeight - dotRadius - 0.5)
            let down = NSBezierPath()
            down.move(to: downTip)
            down.line(to: NSPoint(x: downTip.x - triangleWidth / 2, y: downTip.y + triangleHeight))
            down.line(to: NSPoint(x: downTip.x + triangleWidth / 2, y: downTip.y + triangleHeight))
            down.close()
            down.fill()

            if updatePending {
                let diameter: CGFloat = 5
                NSBezierPath(ovalIn: NSRect(
                    x: rect.maxX - diameter - 0.5,
                    y: rect.maxY - diameter - 0.5,
                    width: diameter,
                    height: diameter
                )).fill()
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseDown
            || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            sender.highlight(true)
            let location = NSPoint(x: 0, y: sender.bounds.height + 4)
            menu.popUp(positioning: nil, at: location, in: sender)
            sender.highlight(false)
        } else {
            showSettings()
        }
    }

    @objc private func showSettings() {
        checkHealth()
        settingsController.show()
    }

    @objc private func openSupportLink() {
        NSWorkspace.shared.open(AppInfo.supportURL)
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) {
            return updater.canCheckForUpdates
        }
        return true
    }

    /// Reopening from Finder or Spotlight is the only way back once the icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if settings.menuBarIconHidden {
            settings.menuBarIconHidden = false
        }
        if !flag {
            showSettings()
        }
        return true
    }

    private func applySettings() {
        indicator.configure(darkMode: settings.darkMode, size: CGFloat(settings.markerSize))
        scroll.speed = ScrollEngine.baseSpeed * CGFloat(settings.scrollSpeedPercent) / 100
        scroll.reverseVertical = settings.reverseScrollDirectionVertical
        scroll.reverseHorizontal = settings.reverseScrollDirectionHorizontal

        navigation.enabled = settings.sideButtonsEnabled
        navigation.method = settings.navigationMethod
        navigation.triggerOnMouseDown = settings.triggerOnMouseDown
        navigation.buttons = NavigationDirection.allCases.reduce(into: [:]) { buttons, direction in
            buttons[direction] = Int64(settings[button: direction])
        }

        if settings.menuBarIconHidden && updater.pendingUpdateVersion == nil {
            removeStatusItem()
        } else {
            installStatusItem()
        }
    }

    // MARK: - Permissions and health

    /// Ask for Accessibility. A modifying event tap is authorized via this grant on modern macOS.
    @objc private func requestPermissions() {
        if !AXIsProcessTrusted(), !accessibilityPromptedThisRun {
            accessibilityPromptedThisRun = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, !AXIsProcessTrusted() else { return }
                self.permissions.request()
            }
        }
        checkHealth()
    }

    /// One timer covers waiting for the grant and watching a live tap for the silent death macOS
    /// inflicts on it. Everything it calls is a local check, so the interval costs nothing
    /// measurable while idle.
    private func startHealthTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(2), leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.checkHealth()
        }
        healthTimer = timer
        timer.resume()
    }

    @objc private func checkHealth() {
        if !AXIsProcessTrusted(), !accessibilityPromptedThisRun {
            accessibilityPromptedThisRun = true
            permissions.request()
        }
        eventTap.verify()
        permissions.refresh()
    }

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name: Notification.Name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ] {
            workspace.addObserver(self, selector: #selector(systemDidResume), name: name, object: nil)
        }
        for name: Notification.Name in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ] {
            workspace.addObserver(self, selector: #selector(systemWillSuspend), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkHealth),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// A latched scroll cannot survive the machine going away, because the click that would have
    /// ended it is never coming.
    @objc private func systemWillSuspend() {
        resetEventState()
    }

    /// Sleep, screen lock, fast user switching and display changes all tear event taps down without
    /// telling anyone, so a resume rebuilds rather than trusting the handle we still hold.
    @objc private func systemDidResume() {
        resetEventState()
        eventTap.rebuild()
        permissions.refresh()
    }

    /// Drops everything that was waiting on an event stream we are no longer sure of. Releases seen
    /// before the tap went away will never arrive, so nothing may stay latched on one.
    private func resetEventState() {
        stopScrolling()
        heldNavigationButtons.removeAll()
        buttonGate.reset()
        recordedButton = nil
        middlePress = nil
    }

    // MARK: - Event handling

    /// Runs on the main thread with system-wide input delivery held up behind it, so everything it
    /// touches has to be a local, non-blocking call.
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // A middle click WinMice is replaying, on its way back out to the app under the pointer.
        if event.getIntegerValueField(.eventSourceUserData) == Self.eventSignature {
            return Unmanaged.passUnretained(event)
        }

        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        let isDown = type == .otherMouseDown

        if consumeForRecording(isDown: isDown, button: button) { return nil }

        if !isDown, heldNavigationButtons.contains(button) {
            // The press was swallowed under the mapping in force at the time. Honor that record
            // rather than the current mapping, which may have changed while the button was held.
            return handleNavigationButton(navigation.direction(for: button), button: button, isDown: isDown)
        }

        if navigation.enabled, let direction = navigation.direction(for: button) {
            return handleNavigationButton(direction, button: button, isDown: isDown)
        }

        guard button == Self.middleButton else { return Unmanaged.passUnretained(event) }
        return handleMiddleButton(isDown: isDown, event: event)
    }

    /// Both halves of a mapped click are swallowed. Letting one through leaves the app under the
    /// pointer with an unmatched press or release, and browsers that act on buttons 4 and 5
    /// themselves would navigate a second time on top of the swipe WinMice just sent.
    private func handleNavigationButton(
        _ direction: NavigationDirection?,
        button: Int64,
        isDown: Bool
    ) -> Unmanaged<CGEvent>? {
        // The event never reaches the monitors that normally end a latched scroll, so end it here.
        stopScrolling()

        if isDown {
            heldNavigationButtons.insert(button)
            if let direction, navigation.triggerOnMouseDown {
                navigation.perform(direction)
            }
        } else if heldNavigationButtons.remove(button) != nil, !navigation.triggerOnMouseDown {
            // Step 9: toggling the feature off mid-hold must not navigate.
            if let direction, navigation.enabled {
                navigation.perform(direction)
            }
        }
        return nil
    }

    /// The middle button is always swallowed here and handed back later, if at all. Letting the
    /// press through as it happens means every scroll also leaves a middle click under the pointer,
    /// which in a browser opens a tab each time you finish scrolling. Holding it back costs nothing
    /// — a middle click that turns out to be just a click is replayed on release, which is when
    /// apps act on it anyway.
    private func handleMiddleButton(isDown: Bool, event: CGEvent) -> Unmanaged<CGEvent>? {
        if isDown {
            // Latched here rather than re-checked on release: the guard is a 200 ms window, so a
            // press inside it released after it would otherwise be handed to the app with its
            // release swallowed.
            guard buttonGate.press(button: Self.middleButton, action: isReplayEcho() ? .passThrough : .swallow) == .swallow else {
                return Unmanaged.passUnretained(event)
            }
            if isActive {
                // Hold-to-start has latched, so this press is the one that ends it.
                stopScrolling()
                middlePress = .consumed
                return nil
            }
            middlePress = event.copy().map(MiddlePress.pending)
            armScrollStart(anchor: currentPointerLocation(), target: event.location)
            return nil
        }

        guard buttonGate.release(button: Self.middleButton, fallback: .swallow) == .swallow else {
            return Unmanaged.passUnretained(event)
        }
        let press = middlePress
        middlePress = nil
        // Hold-to-scroll ends on release; hold-to-start stays latched until the next press.
        if !holdToStart {
            stopScrolling()
        } else {
            cancelArmedScrollStart()
        }
        if case .pending(let down) = press {
            replayMiddleClick(down: down, up: event)
        }
        return nil
    }

    /// Marks the swallowed press as spent, so releasing the button no longer replays it as a click.
    private func claimMiddlePress() {
        if case .pending = middlePress {
            middlePress = .consumed
        }
    }

    private func isReplayEcho() -> Bool {
        guard let lastMiddleReplay else { return false }
        return Date().timeIntervalSince(lastMiddleReplay) < Self.replayGuardWindow
    }

    private func replayMiddleClick(down: CGEvent, up: CGEvent) {
        guard let up = up.copy() else { return }
        lastMiddleReplay = Date()
        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: Self.eventSignature)
        }
        // Posted after the callback returns, both to keep the tap quick and to stay clear of
        // injecting into the stream the window server is still handing us.
        DispatchQueue.main.async {
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }

    /// Feeds a press to the settings window while it is waiting to learn a button, and keeps both
    /// halves of that click from reaching any app. Presses it cannot map — the middle button, which
    /// autoscroll owns — are swallowed too, so nothing fires while the user is aiming at a button.
    private func consumeForRecording(isDown: Bool, button: Int64) -> Bool {
        guard recorder.listeningFor != nil || recordedButton == button else { return false }

        if isDown {
            recordedButton = button
            _ = recorder.record(button)
            return true
        }
        if recordedButton == button {
            recordedButton = nil
            return true
        }
        return false
    }

    // MARK: - Autoscroll

    /// Both modes wait before scrolling, and only the wait differs: hold-to-start waits for the
    /// user's latch delay, hold-to-scroll for a single frame. The anchor stays where the button
    /// went down either way, so the wait costs no accuracy.
    private func armScrollStart(anchor: CGPoint, target: CGPoint) {
        cancelArmedScrollStart()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            armedScrollStart = nil
            startScrolling(anchor: anchor, target: target)
        }
        armedScrollStart = work
        let delay = holdToStart ? holdToStartDelay : Self.holdToScrollDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelArmedScrollStart() {
        armedScrollStart?.cancel()
        armedScrollStart = nil
    }

    private func startScrolling(anchor: CGPoint, target: CGPoint) {
        guard eventTap.isInstalled, !isActive else { return }

        self.anchor = anchor
        isActive = true
        sawMiddleButtonDown = false
        scroll.reset()
        indicator.show(at: anchor)
        if holdToStart {
            // Reaching the latch is what spends the press in this mode.
            claimMiddlePress()
            startStopClickMonitor()
        }

        scrollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: Self.scrollTick, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.emitScrollTick()
        }
        scrollTimer = timer
        timer.resume()

        // Raising the window talks to another process over the Accessibility API and can stall for
        // as long as that process takes to answer, so it never runs inline with the event.
        WindowRaiser.raiseWindow(at: target)
    }

    private func stopScrolling() {
        cancelArmedScrollStart()
        guard isActive else { return }

        stopStopClickMonitor()
        scrollTimer?.cancel()
        scrollTimer = nil
        anchor = nil
        sawMiddleButtonDown = false
        isActive = false
        scroll.reset()
        indicator.hide()
    }

    private func startStopClickMonitor() {
        stopStopClickMonitor()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        stopClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in
                self?.stopScrolling()
            }
        }
        stopClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.stopScrolling()
            }
            return event
        }
    }

    private func stopStopClickMonitor() {
        if let stopClickMonitor {
            NSEvent.removeMonitor(stopClickMonitor)
            self.stopClickMonitor = nil
        }
        if let stopClickLocalMonitor {
            NSEvent.removeMonitor(stopClickLocalMonitor)
            self.stopClickLocalMonitor = nil
        }
    }

    private func emitScrollTick() {
        guard isActive, let anchor else { return }
        guard !shouldEndOnButtonRelease() else {
            stopScrolling()
            return
        }

        let pointer = currentPointerLocation()
        let offset = CGVector(dx: pointer.x - anchor.x, dy: pointer.y - anchor.y)
        guard let delta = scroll.tick(offset: offset) else { return }

        // The press moved something, so it was a scroll rather than a click.
        claimMiddlePress()

        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: delta.vertical,
            wheel2: delta.horizontal,
            wheel3: 0
        ) else {
            return
        }

        scrollEvent.post(tap: .cgSessionEventTap)
    }

    /// Hold-to-scroll ends on the middle button's release. If that release never reaches the tap —
    /// because the system disabled it mid-press, which it does for secure input fields among other
    /// things — the physical button state is the only thing left that can end the scroll.
    ///
    /// Only a state that has read as pressed at least once is allowed to end anything. The tap
    /// deletes the press on its way past, so a source that counts deleted events reports the button
    /// as up for the whole scroll; waiting to see it down first means a source that cannot see it
    /// simply never votes, rather than cutting every scroll short.
    private func shouldEndOnButtonRelease() -> Bool {
        guard !holdToStart else { return false }
        let isDown = CGEventSource.buttonState(.hidSystemState, button: .center)
            || CGEventSource.buttonState(.combinedSessionState, button: .center)
        if isDown {
            sawMiddleButtonDown = true
            return false
        }
        return sawMiddleButtonDown
    }

    private func currentPointerLocation() -> CGPoint {
        NSEvent.mouseLocation
    }
}

let app = NSApplication.shared
private let delegate = WinMiceApp()
app.delegate = delegate
app.run()
