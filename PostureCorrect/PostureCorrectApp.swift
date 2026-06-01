//
//  PostureCorrectApp.swift
//  PostureCorrect
//
//  Created by Syed Muhammad Muneeb on 18/05/26.
//

import SwiftUI

@main
struct PostureCorrectApp: App {
    init() {
            // 1. Register notification delegate first
            _ = NotificationManager.shared
     
            // 2. Request notification permission
            NotificationManager.shared.requestPermission()
     
            // 3. Activate WatchConnectivity session at launch
            //    Must be done here — not lazily — so the session is ready
            //    before the first exercise starts
            _ = WatchConnectivityManager.shared
        }
    // Activate WatchConnectivity at launch
    private let watchManager = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
