//
//  ContentView.swift
//  PostureCorrect Watch App Watch App
//
//  Created by Syed Muhammad Muneeb on 31/05/26.
//

import SwiftUI
import WatchConnectivity
import WatchKit

struct ContentView: View {
    @StateObject private var connector = WatchSessionManager.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(connector.isConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(connector.isConnected ? "iPhone Connected" : "Waiting for iPhone")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                if let alert = connector.latestAlert {
                    // Exercise name
                    Text(alert.exercise)
                        .font(.headline.bold())
                        .foregroundColor(.orange)

                    // Issue description
                    Text(alert.issue)
                        .font(.body)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    // Time since alert
                    Text(alert.timeAgo)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                } else {
                    Image(systemName: "figure.strengthtraining.functional")
                        .font(.system(size: 36))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Exercise to begin")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                }

                Spacer()
            }
            .padding()
        }
        // Flash red border on new alert
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.red.opacity(connector.showFlash ? 0.8 : 0), lineWidth: 3)
                .animation(.easeOut(duration: 0.6), value: connector.showFlash)
        )
    }
}
