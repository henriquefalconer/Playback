import SwiftUI

struct EmptyStateView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "video.slash")
                    .font(.system(size: 64))
                    .foregroundColor(.gray)

                VStack(spacing: 12) {
                    Text("No recordings yet")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Text("Start recording from the menu bar")
                        .font(.body)
                        .foregroundColor(.gray)
                }

                Button(action: {
                    NSApp.activate(ignoringOtherApps: true)
                    if let menuBarWindow = NSApp.windows.first(where: { $0.className.contains("MenuBarExtra") }) {
                        menuBarWindow.makeKeyAndOrderFront(nil)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "menubar.rectangle")
                        Text("Open Menu Bar")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Text("Press ESC to close")
                    .font(.footnote)
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(.top, 8)
            }
        }
    }
}
