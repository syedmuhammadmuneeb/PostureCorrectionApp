//
//  WatchConnectivityManager.swift
//  PostureCorrect (iOS target)
//

import Foundation
import WatchConnectivity
import Combine

final class WatchConnectivityManager: NSObject, WCSessionDelegate, ObservableObject {

    static let shared = WatchConnectivityManager()

    @Published var isWatchReachable = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else {
            print("❌ WCSession NOT supported on this device")
            return
        }
        print("✅ WCSession is supported — activating...")
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendFormAlert(exercise: String, issue: String) {
        let state = WCSession.default.activationState

        print("📡 sendFormAlert called — exercise: \(exercise), issue: \(issue)")
        print("   activationState: \(state.rawValue) (2=activated)")
        print("   isReachable: \(WCSession.default.isReachable)")
        print("   isPaired: \(WCSession.default.isPaired)")
        print("   isWatchAppInstalled: \(WCSession.default.isWatchAppInstalled)")

        guard state == .activated else {
            print("❌ Session not activated — cannot send")
            return
        }

        guard WCSession.default.isPaired else {
            print("❌ No watch paired")
            return
        }

        guard WCSession.default.isWatchAppInstalled else {
            print("❌ Watch app not installed")
            return
        }

        let message: [String: Any] = [
            "exercise":  exercise,
            "issue":     issue,
            "timestamp": Date().timeIntervalSince1970
        ]

        if WCSession.default.isReachable {
            print("✅ Watch is reachable — sending via sendMessage")
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("❌ sendMessage error: \(error.localizedDescription)")
                print("   Falling back to transferUserInfo...")
                WCSession.default.transferUserInfo(message)
            }
        } else {
            print("⚠️ Watch not reachable — sending via transferUserInfo")
            WCSession.default.transferUserInfo(message)
        }
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession,
                 activationDidCompleteWith state: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
        if let error = error {
            print("❌ WCSession activation error: \(error.localizedDescription)")
        } else {
            print("✅ WCSession activated successfully")
            print("   isPaired: \(session.isPaired)")
            print("   isWatchAppInstalled: \(session.isWatchAppInstalled)")
            print("   isReachable: \(session.isReachable)")
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchReachable = session.isReachable
        }
        print("📡 Reachability changed: \(session.isReachable)")
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        print("⚠️ WCSession became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("⚠️ WCSession deactivated — reactivating...")
        WCSession.default.activate()
    }
}
