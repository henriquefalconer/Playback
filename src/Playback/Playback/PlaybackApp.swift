import SwiftUI
import AppKit
import Combine
import os

extension Notification.Name {
    static let openTimeline = Notification.Name("com.falconer.Playback.openTimeline")
    static let openSettings = Notification.Name("com.falconer.Playback.openSettings")
}

/// Stores the SwiftUI openWindow action so it can be called from AppDelegate
enum WindowOpener {
    @MainActor static var openWindow: OpenWindowAction?
}

struct PlaybackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var timelineStore = TimelineStore()
    @StateObject private var playbackController = PlaybackController()
    @StateObject private var signalManager = SignalFileManagerWrapper()
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var fullscreenManager = FullscreenManagerWrapper()
    @State private var timelineOpenTime: Date?
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Store openWindow action for use by AppDelegate (evaluated on every body access)
        let _ = { WindowOpener.openWindow = openWindow }()

        Window("Playback", id: "timeline") {
            ContentView()
                .environmentObject(timelineStore)
                .environmentObject(playbackController)
                .environmentObject(fullscreenManager)
                .onAppear {
                    let openTime = Date()
                    playbackController.timelineStore = timelineStore
                    NSApp.activate(ignoringOtherApps: true)

                    let timelineWindow = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("timeline") == true })
                        ?? NSApp.windows.first(where: { $0.title.contains("ContentView") || $0.level == .normal })
                    if let window = timelineWindow {
                        Log.session.info("Timeline window opened — size=\(window.frame.width, privacy: .public)x\(window.frame.height, privacy: .public), fullscreen=\(window.styleMask.contains(.fullScreen), privacy: .public)")
                        window.makeKeyAndOrderFront(nil)
                        fullscreenManager.configureFullscreenPresentation()
                        fullscreenManager.enterFullscreen(window)
                    } else {
                        Log.playback.error("Could not find timeline window")
                    }

                    signalManager.createSignal()
                    // Stop recording (and the sharing indicator) while browsing history,
                    // so the menu bar and macOS sharing notice reflect that we're paused.
                    RecordingService.shared.pauseForTimeline()
                    timelineOpenTime = openTime

                    ProcessingService.shared.triggerProcessing(source: "timeline_open")
                }
                .onDisappear {
                    if let openTime = timelineOpenTime {
                        let duration = Date().timeIntervalSince(openTime)
                        Log.session.info("Timeline window closed — session_duration=\(String(format: "%.1f", duration), privacy: .public)s")
                        timelineOpenTime = nil
                    }
                    fullscreenManager.restoreNormalPresentation()
                    signalManager.removeSignal()
                    // Resume recording now that the timeline closed (unless the user
                    // disabled it or a system pause is still in effect).
                    RecordingService.shared.resumeFromTimeline()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(configManager)
                .onAppear {
                    Log.settings.info("Settings window opened")
                }
                .onDisappear {
                    Log.settings.info("Settings window closed")
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    let timelineOpen = NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue.contains("timeline") == true })
                    if !timelineOpen {
                        NotificationCenter.default.post(name: .openSettings, object: nil)
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// With @NSApplicationDelegateAdaptor, NSApp.delegate is SwiftUI's internal
    /// wrapper — casting it to AppDelegate always fails, so static members must
    /// reach the real instance through this reference.
    private static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private let menuBarViewModel = MenuBarViewModel()
    private var iconObserver: AnyCancellable?
    private var hotkeyManagerWrapper: GlobalHotkeyManagerWrapper?
    private var notificationObservers: [Any] = []

    /// Recording lives with the menu bar item, not the Dock icon: only the menu bar
    /// "Quit Playback" item (or a system logout/shutdown) may terminate the process.
    static var isQuitAuthorized = false

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Self.openTimeline()
        }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.isQuitAuthorized {
            Log.session.info("Terminating — quit authorized via menu bar")
            return .terminateNow
        }
        if isSystemInitiatedQuit() {
            Log.session.info("Terminating — system-initiated quit (logout/shutdown/restart)")
            return .terminateNow
        }

        // Quit from the Dock icon or Cmd+Q: close windows, drop the Dock icon,
        // and keep the menu bar item + recording alive.
        Log.session.info("Quit intercepted (Dock/Cmd+Q) — closing windows, recording continues")
        for window in NSApp.windows where window.isVisible {
            window.close()
        }
        Self.updateActivationPolicy()
        return .terminateCancel
    }

    /// Detects quit Apple events carrying a logout/restart/shutdown reason,
    /// so the app never blocks the user from logging out or shutting down.
    private func isSystemInitiatedQuit() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication),
              let reason = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) else {
            return false
        }
        let systemReasons = [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAERestart, kAEShowShutdownDialog, kAEShutDown]
        return systemReasons.map { OSType($0) }.contains(reason.enumCodeValue)
    }

    /// Show the Dock icon only while a timeline or settings window is visible;
    /// otherwise run as a menu-bar-only accessory app.
    static func updateActivationPolicy() {
        let hasVisibleWindows = NSApp.windows.contains { window in
            guard window.isVisible, let id = window.identifier?.rawValue else { return false }
            return id.contains("timeline") || id.contains("settings")
        }
        let policy: NSApplication.ActivationPolicy = hasVisibleWindows ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        if policy == .accessory {
            // Switching regular → accessory only takes effect reliably when inactive
            NSApp.deactivate()
        }
        NSApp.setActivationPolicy(policy)
        Log.session.info("Activation policy changed: \(policy == .regular ? "regular (Dock icon shown)" : "accessory (menu bar only)", privacy: .public)")

        if policy == .accessory {
            // AppKit quirk: the status item stops receiving real mouse clicks after a
            // regular → accessory transition. Recreating it restores click handling.
            shared?.rebuildStatusItem()
        }
    }

    func rebuildStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        setupStatusItem()
        Log.menuBar.info("Status bar item rebuilt after activation policy change")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // Clean up stale signal file from previous run
        let signalPath = Paths.timelineOpenSignalPath
        if FileManager.default.fileExists(atPath: signalPath.path) {
            do {
                try FileManager.default.removeItem(at: signalPath)
            } catch {
                Log.system.notice("Failed to remove stale signal file: \(error.localizedDescription)")
            }
        }

        do {
            try Paths.ensureDirectoriesExist()
        } catch {
            Log.system.fault("Failed to create data directories: \(error.localizedDescription)")
        }

        let screenCaptureGranted = CGPreflightScreenCaptureAccess()
        Log.session.info("Screen Recording permission: \(screenCaptureGranted ? "granted" : "denied", privacy: .public)")
        if !screenCaptureGranted {
            CGRequestScreenCaptureAccess()
        }

        setupStatusItem()
        setupNotificationObservers()
        registerGlobalHotkey()

        // `launchedAsLoginItem` reads the launch Apple event, only valid now — so
        // capture it before the (possibly async) index migration defers the rest.
        let asLoginItem = launchedAsLoginItem

        // Upgrade a pre-compaction OCR index if present. While the migration runs,
        // its native dialog is shown *instead of* the timeline, and recording + OCR
        // stay off (no write-lock/VACUUM contention); they start only when the user
        // clicks Open Playback. When nothing needs migrating, launch proceeds
        // immediately with no dialog.
        MigrationCoordinator.runIfNeeded(
            immediate: {
                Task { await self.ensureServicesRunning() }
                // Opening by hand (Finder/Dock) means the user wants the rewind
                // view; login-item launches stay in the background (menu bar only).
                if !asLoginItem {
                    Self.openTimeline()
                }
            },
            afterMigration: {
                // Explicit Open Playback click — start services and reveal the timeline.
                Task { await self.ensureServicesRunning() }
                Self.openTimeline()
            }
        )
    }

    /// True when this launch came from the SMAppService login item rather than user action.
    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication),
              let propData = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) else {
            return false
        }
        return propData.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    private func registerGlobalHotkey() {
        let hotkeyManager = GlobalHotkeyManagerWrapper()
        hotkeyManager.registerHotkey {
            Self.openTimeline()
        }
        self.hotkeyManagerWrapper = hotkeyManager
    }

    private func setupNotificationObservers() {
        let timelineObserver = NotificationCenter.default.addObserver(
            forName: .openTimeline, object: nil, queue: .main
        ) { _ in
            Self.openTimeline()
        }
        let settingsObserver = NotificationCenter.default.addObserver(
            forName: .openSettings, object: nil, queue: .main
        ) { _ in
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            WindowOpener.openWindow?(id: "settings")
        }
        // Drop back to accessory (no Dock icon) once the last timeline/settings window closes
        let windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.async {
                Self.updateActivationPolicy()
            }
        }
        notificationObservers = [timelineObserver, settingsObserver, windowCloseObserver]
    }

    static func openTimeline() {
        // If the timeline was minimized (Shift+ESC), restore it from the Dock: reuse
        // the live window so its state is kept and the didDeminiaturize observer puts
        // it back into fullscreen. Don't openWindow() here — that wouldn't deminiaturize.
        if let minimized = NSApp.windows.first(where: {
            $0.isMiniaturized && $0.identifier?.rawValue.contains("timeline") == true
        }) {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            minimized.deminiaturize(nil)
            Log.hotkey.info("Timeline restored from minimized state")
            return
        }
        if NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue.contains("timeline") == true }) {
            Log.hotkey.debug("Timeline already open — ignoring")
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        WindowOpener.openWindow?(id: "timeline")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard statusItem?.button != nil else {
            Log.menuBar.error("Failed to create status bar button")
            return
        }

        updateStatusBarIcon()

        // Observe recording state changes to update icon
        iconObserver = menuBarViewModel.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarIcon()
            }

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu

        Log.menuBar.info("Status bar item created with native menu")
    }

    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        let iconName = menuBarViewModel.recordingState.iconName
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Playback") {
            image.isTemplate = true
            button.image = image
        }
        button.toolTip = menuBarViewModel.recordingState.tooltip
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Record Screen toggle
        let recordItem = NSMenuItem(
            title: "Record Screen",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        recordItem.target = self
        recordItem.state = menuBarViewModel.isRecordingEnabled ? .on : .off
        recordItem.setAccessibilityIdentifier("menubar.recordToggle")
        menu.addItem(recordItem)

        menu.addItem(.separator())

        // Open Timeline
        let timelineItem = NSMenuItem(
            title: "Open Timeline",
            action: #selector(openTimelineFromMenu),
            keyEquivalent: ""
        )
        timelineItem.target = self
        timelineItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        timelineItem.setAccessibilityIdentifier("menubar.openTimelineButton")
        menu.addItem(timelineItem)

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.setAccessibilityIdentifier("menubar.settingsButton")
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // About
        let aboutItem = NSMenuItem(
            title: "About Playback",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.setAccessibilityIdentifier("menubar.aboutButton")
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Playback",
            action: #selector(quitFromMenu),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = .command
        quitItem.setAccessibilityIdentifier("menubar.quitButton")
        menu.addItem(quitItem)
    }

    // MARK: - Menu Actions

    @objc private func toggleRecording() {
        menuBarViewModel.isRecordingEnabled.toggle()
        menuBarViewModel.toggleRecording()
    }

    @objc private func openTimelineFromMenu() {
        Log.menuBar.info("Open Timeline clicked")
        NotificationCenter.default.post(name: .openTimeline, object: nil)
    }

    @objc private func openSettingsFromMenu() {
        Log.menuBar.info("Settings clicked")
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    @objc private func showAbout() {
        Log.menuBar.info("About Playback clicked")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel()
    }

    @objc private func quitFromMenu() {
        menuBarViewModel.quitPlayback()
    }

    private func ensureServicesRunning() async {
        let configManager = ConfigManager.shared
        let recordingService = RecordingService.shared
        let processingService = ProcessingService.shared

        await MainActor.run {
            if configManager.config.recordingEnabled {
                recordingService.start()
            } else {
                recordingService.stop()
            }
            processingService.start()

            let config = configManager.config
            Log.session.info("App launch complete — recording_enabled=\(config.recordingEnabled, privacy: .public), excluded_apps=\(config.excludedApps.count, privacy: .public), shortcut=\(config.timelineShortcut, privacy: .public), version=\(config.version, privacy: .public)")
        }
    }
}

final class GlobalHotkeyManagerWrapper: ObservableObject {
    let objectWillChange = PassthroughSubject<Void, Never>()
    private let manager = GlobalHotkeyManager.shared
    private var hotkeyCallback: (() -> Void)?
    private var configObserver: Any?

    func registerHotkey(callback: @escaping () -> Void) {
        self.hotkeyCallback = callback

        let shortcut = ConfigManager.shared.config.timelineShortcut
        registerShortcut(shortcut)

        configObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ConfigDidChange"), object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let newShortcut = ConfigManager.shared.config.timelineShortcut
            self.manager.unregister()
            self.registerShortcut(newShortcut)
        }
    }

    private func registerShortcut(_ shortcut: String) {
        guard let parsed = GlobalHotkeyManager.parse(shortcut: shortcut) else {
            Log.hotkey.error("Failed to parse shortcut string: \(shortcut)")
            return
        }

        do {
            try manager.register(keyCode: parsed.keyCode, modifiers: parsed.modifiers, callback: hotkeyCallback!)
            Log.session.info("Registered hotkey: \(shortcut)")
        } catch HotkeyError.accessibilityPermissionDenied {
            Log.session.info("Accessibility permission: denied")
            Log.playback.notice("Accessibility permission denied. Global hotkey will not work.")
            showPermissionAlert()
        } catch {
            Log.playback.error("Failed to register global hotkey: \(error.localizedDescription)")
        }
    }

    private func showPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Playback needs Accessibility permission to register the global hotkey.\n\nYou can grant this permission in System Settings > Privacy & Security > Accessibility."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

/// Wrapper class to make SignalFileManager compatible with @StateObject
final class SignalFileManagerWrapper: ObservableObject {
    let objectWillChange = PassthroughSubject<Void, Never>()
    private let manager = SignalFileManager()

    func createSignal() {
        do {
            try manager.createSignalFile()
        } catch {
            Log.playback.error("Error creating signal file: \(error.localizedDescription)")
        }
    }

    func removeSignal() {
        manager.removeSignalFile()
    }

    deinit {
        manager.removeSignalFile()
    }
}

/// Manages fullscreen presentation options for timeline window
final class FullscreenManagerWrapper: ObservableObject {
    let objectWillChange = PassthroughSubject<Void, Never>()
    private var previousPresentationOptions: NSApplication.PresentationOptions = []
    private var didEnterObserver: Any?
    private var willEnterObserver: Any?
    private var noopWatchdog: DispatchWorkItem?
    private var abortWatchdog: DispatchWorkItem?
    private var fullscreenAttempts = 0
    private var stickyActive = false
    private var stickyWork: DispatchWorkItem?

    /// Enter fullscreen and, for a few seconds, re-enter if the window reverts to
    /// windowed. Restoring a minimized window from the Dock lands the saved windowed
    /// frame a beat after the fullscreen enter — reverting it *without* a
    /// didExitFullScreen notification — so we poll the styleMask rather than listen.
    /// Close/minimize call `beginIntentionalExit()` first so the guard never fights a
    /// deliberate exit; the user can't leave fullscreen on their own (⌃⌘F is disabled,
    /// there's no title bar), so any windowed state here is spurious.
    func enterFullscreenSticky(_ window: NSWindow) {
        configureFullscreenPresentation()
        endSticky()
        stickyActive = true
        enterFullscreen(window)
        // First check well after the enter animation would finish, so we don't mistake
        // an in-progress transition for a revert and double-toggle.
        scheduleStickyCheck(window, delay: 1.8, remaining: 10)
    }

    private func scheduleStickyCheck(_ window: NSWindow, delay: TimeInterval, remaining: Int) {
        let work = DispatchWorkItem { [weak self, weak window] in
            guard let self, let window, self.stickyActive else { return }
            guard remaining > 0, window.isVisible, !window.isMiniaturized else { self.endSticky(); return }
            if window.styleMask.contains(.fullScreen) {
                // Holding fullscreen — keep watching briefly in case the settle is late.
                self.scheduleStickyCheck(window, delay: 0.5, remaining: remaining - 1)
            } else {
                Log.playback.info("Sticky guard re-entering fullscreen (revert caught)")
                self.enterFullscreen(window)
                self.scheduleStickyCheck(window, delay: 1.8, remaining: remaining - 1)
            }
        }
        stickyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Stop the sticky guard before a deliberate fullscreen exit (close / minimize).
    func beginIntentionalExit() {
        endSticky()
    }

    private func endSticky() {
        stickyActive = false
        stickyWork?.cancel()
        stickyWork = nil
    }

    /// Reliably drive the timeline window into native fullscreen.
    ///
    /// SwiftUI reuses the single "timeline" window across open/close, and toggling a
    /// freshly-reopened window is flaky in two distinct ways: `toggleFullScreen` can
    /// silently no-op (no transition at all), or a transition can start
    /// (`willEnterFullScreen`) yet abort before completing — both leave the window
    /// windowed (the intermittent "opens windowed" bug). Only `didEnterFullScreen`
    /// means success, so we watch for each failure mode separately and re-toggle:
    ///   • no `willEnter` shortly after a toggle → it no-op'd → retry (fast).
    ///   • `willEnter` but no `didEnter` → it aborted → retry (after the animation
    ///     window). A legit in-progress transition completes via `didEnter` first, so
    ///     we never double-toggle mid-animation.
    func enterFullscreen(_ window: NSWindow) {
        // Strip ⌃⌘F off the standard "Enter/Exit Full Screen" menu item so the user
        // can't toggle the timeline out of fullscreen. The local key monitor can't
        // stop this — the menu key-equivalent is handled before the monitor runs.
        disableFullscreenMenuShortcut()

        if window.styleMask.contains(.fullScreen) { return }

        clearObservers()
        fullscreenAttempts = 0
        willEnterObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main
        ) { [weak self, weak window] _ in
            guard let self, let window else { return }
            // Transition started — it won't no-op. Guard only against it aborting.
            self.noopWatchdog?.cancel()
            self.noopWatchdog = nil
            self.scheduleAbortWatchdog(window)
        }
        didEnterObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main
        ) { [weak self] _ in
            Log.playback.info("Timeline entered fullscreen (attempts=\(self?.fullscreenAttempts ?? -1, privacy: .public))")
            // The menu item flips to "Exit Full Screen" on entering — re-strip its shortcut.
            self?.disableFullscreenMenuShortcut()
            self?.clearObservers()
        }

        attemptFullscreen(window)
    }

    /// Clear the key equivalent on every standard `toggleFullScreen:` menu item so the
    /// native ⌃⌘F shortcut can't flip the timeline out of (or into) fullscreen.
    func disableFullscreenMenuShortcut() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let toggleSelector = NSSelectorFromString("toggleFullScreen:")
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if item.action == toggleSelector {
                    item.keyEquivalent = ""
                    item.keyEquivalentModifierMask = []
                }
                if let submenu = item.submenu { walk(submenu) }
            }
        }
        walk(mainMenu)
    }

    private func attemptFullscreen(_ window: NSWindow) {
        if window.styleMask.contains(.fullScreen) { clearObservers(); return }
        guard fullscreenAttempts < 6 else {
            Log.playback.error("Could not enter fullscreen after \(self.fullscreenAttempts, privacy: .public) attempts")
            clearObservers()
            return
        }
        fullscreenAttempts += 1

        window.toggleFullScreen(nil)

        // If willEnterFullScreen doesn't fire promptly, the toggle no-op'd — retry.
        let work = DispatchWorkItem { [weak self, weak window] in
            guard let self, let window else { return }
            self.attemptFullscreen(window)
        }
        noopWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func scheduleAbortWatchdog(_ window: NSWindow) {
        abortWatchdog?.cancel()
        // A successful enter fires didEnterFullScreen (clearing everything) well within
        // this window; if it hasn't, the transition aborted and we try again.
        let work = DispatchWorkItem { [weak self, weak window] in
            guard let self, let window else { return }
            if window.styleMask.contains(.fullScreen) { self.clearObservers(); return }
            self.attemptFullscreen(window)
        }
        abortWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    private func clearObservers() {
        noopWatchdog?.cancel()
        noopWatchdog = nil
        abortWatchdog?.cancel()
        abortWatchdog = nil
        if let obs = willEnterObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = didEnterObserver { NotificationCenter.default.removeObserver(obs) }
        willEnterObserver = nil
        didEnterObserver = nil
    }

    func configureFullscreenPresentation() {
        previousPresentationOptions = NSApp.presentationOptions

        let fullscreenOptions: NSApplication.PresentationOptions = [
            .autoHideMenuBar,
            .autoHideDock,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableHideApplication
        ]

        NSApp.presentationOptions = fullscreenOptions

        Log.playback.debug("Configured fullscreen presentation options")
    }

    func restoreNormalPresentation() {
        NSApp.presentationOptions = previousPresentationOptions

        Log.playback.debug("Restored normal presentation options")
    }
}
