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
                .onAppear {
                    // Connect playback controller to timeline store for segment preloading
                    playbackController.timelineStore = timelineStore

                    // Activate app and bring window to front BEFORE toggling fullscreen
                    NSApp.activate(ignoringOtherApps: true)

                    if let window = NSApp.windows.first(where: { $0.title.contains("ContentView") || $0.level == .normal }) {
                        window.makeKeyAndOrderFront(nil)
                        fullscreenManager.configureFullscreenPresentation()
                        window.toggleFullScreen(nil)
                    } else {
                        #if DEBUG
                        print("[Playback] ERROR: Could not find timeline window")
                        #endif
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
                }
                .onDisappear {
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
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clean up stale signal file from previous run (if app crashed or was force-quit)
        let signalPath = Paths.timelineOpenSignalPath
        if FileManager.default.fileExists(atPath: signalPath.path) {
            try? FileManager.default.removeItem(at: signalPath)
        }

        try? Paths.ensureDirectoriesExist()

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }

        Task {
            await ensureServicesRunning()
        }
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
        } catch HotkeyError.accessibilityPermissionDenied {
            #if DEBUG
            print("[Playback] Accessibility permission denied. Global hotkey will not work.")
            #endif
            showPermissionAlert()
        } catch {
            #if DEBUG
            print("[Playback] Failed to register global hotkey: \(error)")
            #endif
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
            #if DEBUG
            print("[Playback] Error creating signal file: \(error)")
            #endif
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

        #if DEBUG
        print("[Playback] Configured fullscreen presentation options")
        #endif
    }

    func restoreNormalPresentation() {
        NSApp.presentationOptions = previousPresentationOptions

        #if DEBUG
        print("[Playback] Restored normal presentation options")
        #endif
    }
}
