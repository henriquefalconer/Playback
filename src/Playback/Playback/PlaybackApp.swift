import SwiftUI

@main
struct PlaybackApp: App {
    @StateObject private var timelineStore = TimelineStore()
    @StateObject private var playbackController = PlaybackController()
    @StateObject private var signalManager = SignalFileManagerWrapper()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(timelineStore)
                .environmentObject(playbackController)
                .onAppear {
                    NSApp.windows.first?.toggleFullScreen(nil)
                    signalManager.createSignal()
                }
        }
        .windowStyle(.hiddenTitleBar)
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
