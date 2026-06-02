//
//  SquatViewModel+Store.swift
//  PostureCorrect
//
//  Created by Syed Muhammad Muneeb on 01/06/26.
//

import Foundation
//
//  SquatViewModel+Store.swift
//  PostureCorrect
//
//  Drop this file into the project alongside SquatView.swift.
//  It extends SquatViewModel with a single method that persists the session
//  summary to LastExerciseStore so the Coach tab can display it.
//  No changes to SquatView.swift are needed — just call saveToStore() from
//  the existing stop() method, OR call it from SquatCameraView.onDisappear.
//
//  ── Recommended integration ──────────────────────────────────────────────────
//  In SquatCameraView.body, change:
//      .onDisappear { viewModel.stop() }
//  to:
//      .onDisappear { viewModel.stopAndSave() }
//

import Foundation

extension SquatViewModel {

    /// Stops the camera session and saves the session summary to
    /// LastExerciseStore so the Coach tab reflects the last workout.
    func stopAndSave() {
        stop()
        saveToStore()
    }

    func saveToStore() {
        // Build feedback items from repHistory + known error patterns
        var feedbackItems: [PCLastFeedbackItem] = []

        // Good reps first
        let goodCount = repHistory.filter { $0.isGood }.count
        if goodCount > 0 {
            feedbackItems.append(PCLastFeedbackItem(
                isGood: true,
                title: "\(goodCount) rep\(goodCount == 1 ? "" : "s") with perfect form",
                timestamp: Date()
            ))
        }

        // Collect unique error messages from bad reps
        // We derive them from the rep records' score (0 = bad rep)
        let badReps = repHistory.filter { !$0.isGood }
        if !badReps.isEmpty {
            // Use the issues we can infer — SquatViewModel tracks these booleans
            // per rep but resets them; the best we can do from history is count.
            feedbackItems.append(PCLastFeedbackItem(
                isGood: false,
                title: "\(badReps.count) rep\(badReps.count == 1 ? "" : "s") with form errors",
                timestamp: Date()
            ))
        }

        // Add the most-recently-seen live issue as specific feedback
        if postureResult.issue != .correct &&
           postureResult.issue != .ready &&
           postureResult.issue != .detecting &&
           postureResult.issue != .notVisible {
            feedbackItems.append(PCLastFeedbackItem(
                isGood: false,
                title: postureResult.issue.rawValue
                    .replacingOccurrences(of: "❌ ", with: "")
                    .replacingOccurrences(of: "⚠️ ", with: ""),
                timestamp: Date()
            ))
        }

        if feedbackItems.isEmpty {
            feedbackItems.append(PCLastFeedbackItem(
                isGood: true,
                title: "No issues detected",
                timestamp: Date()
            ))
        }

        LastExerciseStore.shared.record(
            exerciseName:  "Squats",
            icon:          "figure.strengthtraining.functional",
            iconColor:     "orange",
            formScore:     averageScore > 0 ? averageScore : postureResult.postureScore,
            goodReps:      self.goodReps,
            badReps:       self.badReps,
            totalReps:     totalRepsAllTime,
            sessionTime:   sessionTimeString,
            feedbackItems: feedbackItems
        )
    }
}
