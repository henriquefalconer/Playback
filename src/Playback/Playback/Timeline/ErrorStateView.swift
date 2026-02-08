import SwiftUI
import AppKit

enum ErrorType {
    case databaseError(String)
    case videoFileMissing(String)
    case segmentLoadingFailure(String)
    case permissionDenied
    case multipleConsecutiveFailures(Int)
}

struct ErrorStateView: View {
    let errorType: ErrorType

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: iconName)
                    .font(.system(size: 64))
                    .foregroundColor(.red)

                VStack(spacing: 12) {
                    Text(errorTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                actionButton

                Text("Press ESC to close")
                    .font(.footnote)
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(.top, 8)
            }
        }
    }

    private var iconName: String {
        switch errorType {
        case .databaseError:
            return "exclamationmark.triangle.fill"
        case .videoFileMissing:
            return "film.slash"
        case .segmentLoadingFailure:
            return "xmark.circle.fill"
        case .permissionDenied:
            return "lock.shield.fill"
        case .multipleConsecutiveFailures:
            return "exclamationmark.arrow.circlepath"
        }
    }

    private var errorTitle: String {
        switch errorType {
        case .databaseError:
            return "Database Error"
        case .videoFileMissing:
            return "Video File Missing"
        case .segmentLoadingFailure:
            return "Segment Loading Failed"
        case .permissionDenied:
            return "Permission Denied"
        case .multipleConsecutiveFailures:
            return "Multiple Loading Failures"
        }
    }

    private var errorMessage: String {
        switch errorType {
        case .databaseError(let message):
            return "Failed to load recordings database. \(message)"
        case .videoFileMissing(let filename):
            return "Video file '\(filename)' is missing or corrupted. The recording may have been moved or deleted."
        case .segmentLoadingFailure(let message):
            return "Failed to load video segment. \(message)"
        case .permissionDenied:
            return "Playback needs Screen Recording permission to display recorded videos. Please grant permission in System Settings."
        case .multipleConsecutiveFailures(let count):
            return "Failed to load \(count) consecutive video segments. There may be an issue with your recordings or video files."
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch errorType {
        case .permissionDenied:
            Button(action: openSystemSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                    Text("Open System Settings")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

        case .databaseError:
            Button(action: retryLoading) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

        default:
            EmptyView()
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func retryLoading() {
        NotificationCenter.default.post(name: NSNotification.Name("RetryLoadingTimeline"), object: nil)
    }
}
