//
//  LastExerciseStore.swift
//  PostureCorrect
//
//  Created by Syed Muhammad Muneeb on 01/06/26.
//

import Foundation
//
//  LastExerciseStore.swift
//  PostureCorrect
//
//  Single source of truth for the "last exercise" data that the Coach tab
//  displays.  Any ViewModel (SquatViewModel, PushupViewModel, …) calls
//  LastExerciseStore.shared.record(…) when a session ends or the user leaves.
//

import Foundation
import Combine

// MARK: - Feedback entry (one error row in Coach tab)
struct PCLastFeedbackItem: Identifiable {
    let id        = UUID()
    let isGood:    Bool          // true → green checkmark, false → orange warning
    let title:     String        // e.g. "Knees too forward"
    let timestamp: Date
}

// MARK: - Last-exercise snapshot
struct PCLastExercise {
    let exerciseName: String     // "Squats"
    let icon:         String     // SF Symbol
    let iconColor:    String     // Color name we'll resolve in the view
    let formScore:    Int        // average posture score 0-100
    let goodReps:     Int
    let badReps:      Int
    let totalReps:    Int
    let sessionTime:  String     // "04:32"
    let feedbackItems: [PCLastFeedbackItem]
    let recordedAt:   Date
}

// MARK: - Store
final class LastExerciseStore: ObservableObject {

    static let shared = LastExerciseStore()
    private init() {}

    @Published var last: PCLastExercise? = nil

    /// Call this from any ViewModel's stop() / onDisappear to persist results.
    func record(
        exerciseName: String,
        icon:         String,
        iconColor:    String,
        formScore:    Int,
        goodReps:     Int,
        badReps:      Int,
        totalReps:    Int,
        sessionTime:  String,
        feedbackItems: [PCLastFeedbackItem]
    ) {
        DispatchQueue.main.async {
            self.last = PCLastExercise(
                exerciseName:  exerciseName,
                icon:          icon,
                iconColor:     iconColor,
                formScore:     formScore,
                goodReps:      goodReps,
                badReps:       badReps,
                totalReps:     totalReps,
                sessionTime:   sessionTime,
                feedbackItems: feedbackItems,
                recordedAt:    Date()
            )
        }
    }
}
