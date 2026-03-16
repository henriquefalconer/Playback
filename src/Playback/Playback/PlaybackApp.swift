import SwiftUI
import AppKit
import Combine
import os

extension Notification.Name {
    static let openTimeline = Notification.Name("com.falconer.Playback.openTimeline")
    static let openSettings = Notification.Name("com.falconer.Playback.openSettings")
}

@main
struct PlaybackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var timelineStore = TimelineStore()
    @StateObject private var playbackController = PlaybackController()
    @StateObject private var signalManager = SignalFileManagerWrapper()
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var hotkeyManager = GlobalHotkeyManagerWrapper()
    @StateObject private var fullscreenManager = FullscreenManagerWrapper()
    @State private var timelineOpenTime: Date?
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "timeline") {
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
                    hotkeyManager.registerHotkey {
                        NSApp.activate(ignoringOtherApps: true)
                        if let window = NSApp.windows.first(where: { $0.level == .normal }) {
                            window.makeKeyAndOrderFront(nil)
                            if !window.styleMask.contains(.fullScreen) {
                                window.toggleFullScreen(nil)
                            }
                        }
                    }
                    timelineOpenTime = openTime
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
                .onReceive(NotificationCenter.default.publisher(for: .openTimeline)) { _ in
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "timeline")
                }
                .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
        }
        .windowStyle(.hiddenTitleBar)

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
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let menuBarViewModel = MenuBarViewModel()
    private var iconObserver: AnyCancellable?

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

        Task {
            await ensureServicesRunning()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else {
            Log.menuBar.error("Failed to create status bar button")
            return
        }

        // Set initial icon
        updateStatusBarIcon()

        // Observe recording state changes to update icon
        iconObserver = menuBarViewModel.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusBarIcon()
            }

        // Left-click action
        button.action = #selector(statusBarButtonClicked(_:))
        button.target = self
        // Send action on both left and right click
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        Log.menuBar.info("Custom status bar item created with right-click support")
    }

    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        let iconName = menuBarViewModel.recordingState.iconName
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Playback") {
            image.isTemplate = true
            button.image = image
        }
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            Log.menuBar.info("Right-click on tray icon — showing context menu")
            showRightClickMenu()
        } else {
            Log.menuBar.info("Left-click on tray icon — showing popover")
            togglePopover()
        }
    }

    private func togglePopover() {
        if let popover = popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        let menuBarView = MenuBarView(viewModel: menuBarViewModel)
            .environmentObject(ConfigManager.shared)

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 240, height: 220)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: menuBarView)

        self.popover = popover

        if let button = statusItem?.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showRightClickMenu() {
        let menu = NSMenu()

        let openTimelineItem = NSMenuItem(
            title: "Open Timeline",
            action: #selector(openTimelineFromMenu),
            keyEquivalent: ""
        )
        openTimelineItem.target = self
        openTimelineItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Open Timeline")
        menu.addItem(openTimelineItem)

        if let button = statusItem?.button {
            // Position menu below the status bar button
            statusItem?.menu = menu
            button.performClick(nil)
            // Clear menu so left-click still works as popover
            statusItem?.menu = nil
        }
    }

    @objc private func openTimelineFromMenu() {
        Log.menuBar.info("Open Timeline clicked (right-click menu)")
        NotificationCenter.default.post(name: .openTimeline, object: nil)
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

    func registerHotkey(callback: @escaping () -> Void) {
        do {
            let (keyCode, modifiers) = GlobalHotkeyManager.optionShiftSpace
            try manager.register(keyCode: keyCode, modifiers: modifiers, callback: callback)
            Log.session.info("Accessibility permission: granted")
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
            alert.informativeText = "Playback needs Accessibility permission to register the global hotkey (Option+Shift+Space).\n\nYou can grant this permission in System Settings > Privacy & Security > Accessibility."
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
