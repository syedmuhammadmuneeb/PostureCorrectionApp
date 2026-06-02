//
//  PostureCorrectApp.swift
//  PostureCorrect
//

import SwiftUI

@main
struct PostureCorrectApp: App {

    init() {
        _ = NotificationManager.shared
        NotificationManager.shared.requestPermission()
        _ = WatchConnectivityManager.shared
    }

    var body: some Scene {
        WindowGroup {
            PCRootView()
        }
    }
}
