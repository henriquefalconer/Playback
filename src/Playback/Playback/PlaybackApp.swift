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

@main
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
                .onAppear {
                    let openTime = Date()
                    playbackController.timelineStore = timelineStore
                    NSApp.activate(ignoringOtherApps: true)

                    if let window = NSApp.windows.first(where: { $0.title.contains("ContentView") || $0.level == .normal }) {
                        Log.session.info("Timeline window opened — size=\(window.frame.width, privacy: .public)x\(window.frame.height, privacy: .public)")
                        window.makeKeyAndOrderFront(nil)
                        fullscreenManager.configureFullscreenPresentation()
                        window.toggleFullScreen(nil)
                    } else {
                        Log.playback.error("Could not find timeline window")
                    }

                    signalManager.createSignal()
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
            (NSApp.delegate as? AppDelegate)?.rebuildStatusItem()
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

        Task {
            await ensureServicesRunning()
        }

        // Opening the app by hand (Finder/Dock) means the user wants the rewind view;
        // login-item launches stay in the background (menu bar only).
        if !launchedAsLoginItem {
            DispatchQueue.main.async {
                Self.openTimeline()
            }
        }
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
