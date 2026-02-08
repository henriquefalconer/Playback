import SwiftUI

struct LoadingStateContentView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .tint(.white)

                Text("Loading timeline...")
                    .font(.title3)
                    .foregroundColor(.white)

                Text("Press ESC to close")
                    .font(.footnote)
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(.top, 8)
            }
        }
    }
}
