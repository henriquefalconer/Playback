import SwiftUI

@main
struct PlaybackApp: App {
    @StateObject private var timelineStore = TimelineStore()
    @StateObject private var playbackController = PlaybackController()
    @StateObject private var signalManager = SignalFileManagerWrapper()
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var menuBarViewModel = MenuBarViewModel()

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

/// Wrapper class to make SignalFileManager compatible with @StateObject
final class SignalFileManagerWrapper: ObservableObject {
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
