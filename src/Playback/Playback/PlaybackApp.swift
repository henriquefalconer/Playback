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

                    // Configure fullscreen presentation options before entering fullscreen
                    fullscreenManager.configureFullscreenPresentation()

                    NSApp.windows.first?.toggleFullScreen(nil)
                    signalManager.createSignal()
                    processMonitor.startMonitoring()
                    hotkeyManager.registerHotkey {
                        NSApp.activate(ignoringOtherApps: true)
                        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "timeline" }) {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                }
                .onDisappear {
                    processMonitor.stopMonitoring()
                    fullscreenManager.restoreNormalPresentation()
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !FirstRunCoordinator.hasCompletedFirstRun {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showFirstRunWindow()
            }
        } else {
            Task {
                await self.ensureServicesRunning()
            }
        }
    }

    private func ensureServicesRunning() async {
        let agentManager = LaunchAgentManager.shared
        let configManager = ConfigManager.shared

        do {
            try agentManager.installAgent(.processing)
            try agentManager.loadAgent(.processing)
            try agentManager.startAgent(.processing)

            try agentManager.installAgent(.cleanup)
            try agentManager.loadAgent(.cleanup)

            if configManager.config.recordingEnabled {
                try agentManager.installAgent(.recording)
                try agentManager.loadAgent(.recording)
                try agentManager.startAgent(.recording)
            } else {
                try? agentManager.stopAgent(.recording)
            }

            if Paths.isDevelopment {
                print("[ServiceLifecycle] All services ensured running")
            }
        } catch {
            if Paths.isDevelopment {
                print("[ServiceLifecycle] Error ensuring services: \(error)")
            }
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
