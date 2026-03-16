import SwiftUI
import AppKit
import Combine
import os

extension Notification.Name {
    static let openTimeline = Notification.Name("com.falconer.Playback.openTimeline")
}

@main
struct PlaybackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var timelineStore = TimelineStore()
    @StateObject private var playbackController = PlaybackController()
    @StateObject private var signalManager = SignalFileManagerWrapper()
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var menuBarViewModel = MenuBarViewModel()
    @StateObject private var hotkeyManager = GlobalHotkeyManagerWrapper()
    @StateObject private var fullscreenManager = FullscreenManagerWrapper()
    @State private var timelineOpenTime: Date?
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: menuBarViewModel)
                .environmentObject(configManager)
                .onReceive(NotificationCenter.default.publisher(for: .openTimeline)) { _ in
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "timeline")
                }
        } label: {
            Image(systemName: menuBarViewModel.recordingState.iconName)
                .foregroundColor(menuBarViewModel.recordingState == .recording ? .red : .primary)
        }

        WindowGroup(id: "timeline") {
            ContentView()
                .environmentObject(timelineStore)
                .environmentObject(playbackController)
                .onAppear {
                    let openTime = Date()
                    // Connect playback controller to timeline store for segment preloading
                    playbackController.timelineStore = timelineStore

                    // Activate app and bring window to front BEFORE toggling fullscreen
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
    private var localRightClickMonitor: Any?
    private var globalRightClickMonitor: Any?
    private var statusBarButtonFrame: NSRect = .zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clean up stale signal file from previous run (if app crashed or was force-quit)
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

        setupStatusBarRightClickMenu()

        Task {
            await ensureServicesRunning()
        }
    }

    private func setupStatusBarRightClickMenu() {
        // Delay to allow MenuBarExtra to render and create its NSStatusItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.installRightClickMonitor()
        }
    }

    private func installRightClickMonitor() {
        // Find and cache the status bar button window frame
        if let statusWindow = NSApp.windows.first(where: {
            String(describing: type(of: $0)).contains("NSStatusBarWindow")
        }) {
            statusBarButtonFrame = statusWindow.frame
            Log.menuBar.info("Found status bar window at frame=\(statusWindow.frame.debugDescription, privacy: .public)")
        }

        // Local monitor: catches events when app is active (e.g. during MenuBarExtra interaction)
        localRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard self != nil else { return event }

            if let window = event.window,
               String(describing: type(of: window)).contains("NSStatusBarWindow") {
                Log.menuBar.info("Right-click menu shown on tray icon (local)")
                self?.showRightClickMenu(at: event)
                return nil
            }
            return event
        }

        // Global monitor: catches events when app is NOT active (normal state for menu bar apps)
        globalRightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self = self else { return }

            // Re-find the status bar window frame (it can move if menu bar items change)
            if let statusWindow = NSApp.windows.first(where: {
                String(describing: type(of: $0)).contains("NSStatusBarWindow")
            }) {
                self.statusBarButtonFrame = statusWindow.frame
            }

            // Check if click is within the status bar button's screen frame
            let clickLocation = NSEvent.mouseLocation
            if self.statusBarButtonFrame.contains(clickLocation) {
                Log.menuBar.info("Right-click menu shown on tray icon (global)")
                DispatchQueue.main.async {
                    self.showRightClickMenuAtStatusBar()
                }
            }
        }

        Log.menuBar.info("Right-click monitors installed on status bar button")
    }

    private func makeRightClickMenu() -> NSMenu {
        let menu = NSMenu()

        let openTimelineItem = NSMenuItem(
            title: "Open Timeline",
            action: #selector(openTimelineFromRightClick),
            keyEquivalent: ""
        )
        openTimelineItem.target = self
        openTimelineItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Open Timeline")
        menu.addItem(openTimelineItem)

        return menu
    }

    private func showRightClickMenu(at event: NSEvent) {
        let menu = makeRightClickMenu()
        if let window = event.window {
            menu.popUp(positioning: nil, at: event.locationInWindow, in: window.contentView)
        }
    }

    private func showRightClickMenuAtStatusBar() {
        let menu = makeRightClickMenu()
        if let statusWindow = NSApp.windows.first(where: {
            String(describing: type(of: $0)).contains("NSStatusBarWindow")
        }) {
            // Show menu at the bottom-left of the status bar button
            let menuLocation = NSPoint(x: 0, y: 0)
            menu.popUp(positioning: nil, at: menuLocation, in: statusWindow.contentView)
        }
    }

    @objc private func openTimelineFromRightClick() {
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
