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
                    NSApp.windows.first?.toggleFullScreen(nil)
                    signalManager.createSignal()
                    hotkeyManager.registerHotkey {
                        NSApp.activate(ignoringOtherApps: true)
                        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "timeline" }) {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
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
            print("[Playback] Accessibility permission denied. Global hotkey will not work.")
            showPermissionAlert()
        } catch {
            print("[Playback] Failed to register global hotkey: \(error)")
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
            print("[Playback] Error creating signal file: \(error)")
        }
    }

    deinit {
        manager.removeSignalFile()
    }
}
