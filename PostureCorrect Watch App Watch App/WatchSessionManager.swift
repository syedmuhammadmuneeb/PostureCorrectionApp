//
//  WatchSessionManager.swift
//  PostureCorrect Watch App
//

import Foundation
import WatchConnectivity
import WatchKit
import Combine

struct FormAlert: Identifiable {
    let id         = UUID()
    let exercise:  String
    let issue:     String
    let receivedAt: Date

    var timeAgo: String {
        let secs = Int(-receivedAt.timeIntervalSinceNow)
        if secs < 60 { return "\(secs)s ago" }
        return "\(secs / 60)m ago"
    }
}

final class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {

    static let shared = WatchSessionManager()

    @Published var latestAlert: FormAlert?
    @Published var isConnected = false
    @Published var showFlash   = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async {
            // Show connected as soon as the session is active —
            // isReachable fluctuates but activated means the iPhone is paired
            self.isConnected = (state == .activated)
        }
        if let error = error {
            print("WCSession activation error: \(error.localizedDescription)")
        }
    }

    // Handles instant sendMessage delivery (watch app is open)
    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }

    // Handles transferUserInfo delivery (watch app was in background)
    func session(_ session: WCSession,
                 didReceiveUserInfo userInfo: [String: Any]) {
        handleIncoming(userInfo)
    }

    // MARK: - Shared handler for both delivery paths
    private func handleIncoming(_ message: [String: Any]) {
        guard
            let exercise = message["exercise"] as? String,
            let issue    = message["issue"]    as? String
        else { return }

        DispatchQueue.main.async {
            self.latestAlert = FormAlert(
                exercise:   exercise,
                issue:      issue,
                receivedAt: Date()
            )
            self.fireHapticAndFlash(issue: issue)
        }
    }

    // MARK: - Haptic + visual flash
    private func fireHapticAndFlash(issue: String) {
        let lower = issue.lowercased()

        // Map the error type to the most appropriate haptic
        let hapticType: WKHapticType
        if lower.contains("back") || lower.contains("straight") || lower.contains("spine") {
            hapticType = .notification   // strong — spine errors are most critical
        } else if lower.contains("knee") || lower.contains("hip") {
            hapticType = .retry          // medium
        } else {
            hapticType = .failure        // sharp tap for other errors
        }

        WKInterfaceDevice.current().play(hapticType)

        // Red border flash on screen
        self.showFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.showFlash = false
        }
    }
}
