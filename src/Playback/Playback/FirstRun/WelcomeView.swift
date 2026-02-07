// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI

struct WelcomeView: View {
    @ObservedObject var coordinator: FirstRunCoordinator

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "record.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.red)

            Text("Welcome to Playback")
                .font(.system(size: 32, weight: .bold))

            Text("Your Personal Screen Recording Timeline")
                .font(.title3)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "clock.fill", text: "Continuous screen recording")
                FeatureRow(icon: "film.fill", text: "Efficient video compression")
                FeatureRow(icon: "magnifyingglass", text: "Timeline-based playback")
                FeatureRow(icon: "lock.fill", text: "100% local - no cloud, no network")
            }
            .padding(.top, 20)

            Spacer()

            Text("Let's get you set up. This will only take a few minutes.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.blue)
            Text(text)
                .font(.body)
        }
    }
}
