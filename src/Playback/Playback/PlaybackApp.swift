import SwiftUI

@main
struct PlaybackApp: App {
    @StateObject private var timelineStore = TimelineStore()
    @StateObject private var playbackController = PlaybackController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(timelineStore)
                .environmentObject(playbackController)
                .onAppear {
                    NSApp.windows.first?.toggleFullScreen(nil)
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
