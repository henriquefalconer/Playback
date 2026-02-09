import SwiftUI
import AppKit
import Combine

@main
struct PlaybackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var timelineStore = TimelineStore()
    @StateObject private var playbackController = PlaybackController()
    @StateObject private var signalManager = SignalFileManagerWrapper()
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var menuBarViewModel = MenuBarViewModel()
    @StateObject private var hotkeyManager = GlobalHotkeyManagerWrapper()
    @StateObject private var processMonitor = ProcessMonitor.shared
    @StateObject private var fullscreenManager = FullscreenManagerWrapper()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: menuBarViewModel)
                .environmentObject(configManager)
        } label: {
            Image(systemName: menuBarViewModel.recordingState.iconName)
                .foregroundColor(menuBarViewModel.recordingState == .recording ? .red : .primary)
        }

        WindowGroup(id: "timeline") {
            ContentView()
                .environmentObject(timelineStore)
                .environmentObject(playbackController)
                .environmentObject(processMonitor)
                .onAppear {
                    // Connect playback controller to timeline store for segment preloading
                    playbackController.timelineStore = timelineStore

                    // Activate app and bring window to front BEFORE toggling fullscreen
                    NSApp.activate(ignoringOtherApps: true)

                    // Find the timeline window
                    if let window = NSApp.windows.first(where: { $0.title.contains("ContentView") || $0.level == .normal }) {
                        print("[Playback] Found timeline window, activating and entering fullscreen")
                        window.makeKeyAndOrderFront(nil)

                        // Configure fullscreen presentation options before entering fullscreen
                        fullscreenManager.configureFullscreenPresentation()

                        // Enter fullscreen
                        window.toggleFullScreen(nil)
                    } else {
                        print("[Playback] ERROR: Could not find timeline window")
                    }

                    signalManager.createSignal()
                    processMonitor.startMonitoring()
                    hotkeyManager.registerHotkey {
                        NSApp.activate(ignoringOtherApps: true)
                        if let window = NSApp.windows.first(where: { $0.level == .normal }) {
                            window.makeKeyAndOrderFront(nil)
                            if !window.styleMask.contains(.fullScreen) {
                                window.toggleFullScreen(nil)
                            }
                        }
                    }
                }
                .onDisappear {
                    processMonitor.stopMonitoring()
                    fullscreenManager.restoreNormalPresentation()
                    signalManager.removeSignal()
                }
        }
        .windowStyle(.hiddenTitleBar)

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(configManager)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Welcome to Playback", id: "firstrun") {
            FirstRunWindowView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var firstRunWindow: NSWindow?

    override init() {
        super.init()

        // Listen for first-run completion to start services
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFirstRunComplete),
            name: NSNotification.Name("FirstRunComplete"),
            object: nil
        )
    }

    @objc private func handleFirstRunComplete() {
        print("[AppDelegate] First-run completed, starting services")
        Task {
            await self.ensureServicesRunning()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[AppDelegate] applicationDidFinishLaunching called")
        print("[AppDelegate] hasCompletedFirstRun=\(FirstRunCoordinator.hasCompletedFirstRun)")

        // Clean up stale signal file from previous run (if app crashed or was force-quit)
        let signalPath = Paths.timelineOpenSignalPath
        if FileManager.default.fileExists(atPath: signalPath.path) {
            print("[AppDelegate] Removing stale signal file from previous run")
            try? FileManager.default.removeItem(at: signalPath)
        }

        if !FirstRunCoordinator.hasCompletedFirstRun {
            print("[AppDelegate] Showing first run window")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showFirstRunWindow()
            }
        } else {
            print("[AppDelegate] First run already completed, ensuring services running")
            Task {
                await self.ensureServicesRunning()
            }
        }
    }

    private func ensureServicesRunning() async {
        print("[ServiceLifecycle] ensureServicesRunning() called")
        let agentManager = LaunchAgentManager.shared
        let configManager = ConfigManager.shared
        let recordingService = RecordingService.shared

        print("[ServiceLifecycle] Config loaded: recordingEnabled=\(configManager.config.recordingEnabled)")

        do {
            // Start Python processing service (LaunchAgent)
            try agentManager.installAgent(.processing)
            try agentManager.loadAgent(.processing)
            try agentManager.startAgent(.processing)

            // Install cleanup service (LaunchAgent)
            try agentManager.installAgent(.cleanup)
            try agentManager.loadAgent(.cleanup)

            // Start Swift recording service (in-app, uses app's Screen Recording permission)
            if configManager.config.recordingEnabled {
                print("[ServiceLifecycle] Recording is enabled, starting RecordingService")
                await MainActor.run {
                    recordingService.start()
                }
            } else {
                print("[ServiceLifecycle] Recording is disabled, stopping RecordingService")
                await MainActor.run {
                    recordingService.stop()
                }
            }

            print("[ServiceLifecycle] All services ensured running")
            print("[ServiceLifecycle] Recording service: \(recordingService.isRecording ? "started" : "stopped")")
        } catch {
            print("[ServiceLifecycle] Error ensuring services: \(error)")
        }
    }

    private func showFirstRunWindow() {
        let contentView = FirstRunWindowView()
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Playback"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrame(NSRect(x: 0, y: 0, width: 600, height: 500), display: true)
        window.center()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        self.firstRunWindow = window
    }
}

final class GlobalHotkeyManagerWrapper: ObservableObject {
    let objectWillChange = PassthroughSubject<Void, Never>()
    private let manager = GlobalHotkeyManager.shared

    func registerHotkey(callback: @escaping () -> Void) {
        do {
            let (keyCode, modifiers) = GlobalHotkeyManager.optionShiftSpace
            try manager.register(keyCode: keyCode, modifiers: modifiers, callback: callback)
        } catch HotkeyError.accessibilityPermissionDenied {
            if Paths.isDevelopment {
                print("[Playback] Accessibility permission denied. Global hotkey will not work.")
            }
            showPermissionAlert()
        } catch {
            if Paths.isDevelopment {
                print("[Playback] Failed to register global hotkey: \(error)")
            }
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
            if Paths.isDevelopment {
                print("[Playback] Error creating signal file: \(error)")
            }
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

        if Paths.isDevelopment {
            print("[Playback] Configured fullscreen presentation options")
        }
    }

    func restoreNormalPresentation() {
        NSApp.presentationOptions = previousPresentationOptions

        if Paths.isDevelopment {
            print("[Playback] Restored normal presentation options")
        }
    }
}
