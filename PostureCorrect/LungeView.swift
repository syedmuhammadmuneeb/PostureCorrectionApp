//
//  LungeView.swift
//  PostureCorrect
//
//  Camera placement: FRONT-FACING — phone 2 m in front of the user.
//  Both legs must be fully visible (hip → knee → ankle on both sides).
//
//  ─────────────────────────────────────────────────────────────────────────
//  BIOMECHANICALLY CORRECT LUNGE ANGLES
//  ─────────────────────────────────────────────────────────────────────────
//
//  1. Front knee (hip → knee → ankle of stepping leg)
//     At the bottom of the lunge the front knee should be directly above
//     the ankle (not past the toes) and bent to ~90°.
//     • Ideal at bottom:  80°–105°
//     • Too straight:    > 105° = not going deep enough
//     • Too bent:        < 80°  = going too far forward
//
//  2. Back knee (hip → knee → ankle of trailing leg)
//     Back knee should drop toward (but not slam into) the floor.
//     • Ideal at bottom:  70°–110°
//     • Too straight:    > 110° = back leg not lowering enough
//
//  3. Torso angle (mid-shoulder → mid-hip from horizontal)
//     Perfectly vertical torso = ~90° in our atan2 formula.
//     Should stay 65°–115° (±25° from vertical).
//     • Outside range = torso leaning forward or backward
//
//  4. Hip level (left vs right hip y-coordinate difference)
//     Hips should stay even throughout — not tilting left or right.
//     • Threshold: ≤ 6% of frame height difference
//
//  ─────────────────────────────────────────────────────────────────────────
//  REP STATE MACHINE  (three-gate)
//  ─────────────────────────────────────────────────────────────────────────
//  Gate 1: frontKnee < descentTrigger (150°)     → rep starts
//  Gate 2: frontKnee ≤ frontKneeBottomMax (105°) for 3 frames → bottom
//  Gate 3: frontKnee > returnTrigger (148°)      for 3 frames → evaluate
//

import SwiftUI
import AVFoundation
import Vision
import Combine
import AVKit

// MARK: - LUNGE ISSUE
enum LungeIssue: String {
    case correct      = "✅ Perfect Lunge"
    case ready        = "🧍 Step Forward to Begin"
    case frontKneeBad = "❌ Front Knee: Aim for 90°"
    case backKneeBad  = "❌ Drop Back Knee Lower"
    case torsoLeaning = "❌ Keep Torso Upright"
    case hipDrop      = "❌ Keep Hips Level"
    case detecting    = "🔍 Detecting..."
    case notVisible   = "📷 Full Body Not Visible"
}

// MARK: - LUNGE PHASE
enum LungePhase { case standing, descending, bottom, ascending }

// MARK: - LUNGE REP RECORD
struct LungeRepRecord: Identifiable {
    let id        = UUID()
    let repNumber: Int
    let score:     Int
    let isGood:    Bool
    let timestamp: Date
}

// MARK: - LUNGE RESULT
struct LungeResult {
    var issue: LungeIssue  = .detecting
    var postureScore: Int  = 100
    var frontKneeAngle: Double = 180
    var backKneeAngle:  Double = 180
    var torsoAngle:     Double = 90
    var leftLegForward: Bool   = true
    var frontKneeOk: Bool = true
    var backKneeOk:  Bool = true
    var torsoOk:     Bool = true
    var hipLevelOk:  Bool = true
    var formIsValid: Bool { frontKneeOk && backKneeOk && torsoOk && hipLevelOk }
}

// MARK: - LUNGE CAMERA VIEW
struct LungeCameraView: View {
    @StateObject private var viewModel = LungeViewModel()
    @State private var showGoalSheet   = false
    @State private var showStatsSheet  = false

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.session).ignoresSafeArea()
            LungeSkeletonOverlay(bodyPoints: viewModel.bodyPoints,
                                 result: viewModel.lungeResult).ignoresSafeArea()
            VStack {
                topBar; Spacer()
                if viewModel.showFormAlert {
                    LungeFormAlertBanner(message: viewModel.formAlertMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4), value: viewModel.showFormAlert)
                }
                Spacer(); bottomPanel
            }
            if viewModel.showBadRepFlash {
                Color.red.opacity(0.25).ignoresSafeArea().allowsHitTesting(false)
                VStack {
                    Spacer()
                    Text("⚠️ Rep Not Counted\n\(viewModel.badRepReason)")
                        .font(.title3.bold()).foregroundColor(.white)
                        .multilineTextAlignment(.center).padding()
                        .background(Color.red.opacity(0.85)).cornerRadius(16)
                        .padding(.bottom, 220)
                }
            }
            if viewModel.showGoodRepFlash {
                Color.green.opacity(0.2).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .onAppear    { viewModel.start() }
        .onDisappear { viewModel.stop()  }
        .sheet(isPresented: $showGoalSheet)  { LungeGoalSheet(viewModel: viewModel) }
        .sheet(isPresented: $showStatsSheet) { LungeStatsSheet(viewModel: viewModel) }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lunge AI").font(.title2.bold()).foregroundColor(.white)
                Text(viewModel.sessionTimeString)
                    .font(.caption.monospacedDigit()).foregroundColor(.green)
            }
            Spacer()
            Button { showStatsSheet = true } label: {
                Image(systemName: "chart.bar.fill").font(.title2).foregroundColor(.white)
                    .padding(10).background(Color.white.opacity(0.2)).clipShape(Circle())
            }
            Button { showGoalSheet = true } label: {
                Image(systemName: "target").font(.title2).foregroundColor(.white)
                    .padding(10).background(Color.white.opacity(0.2)).clipShape(Circle())
            }
            Button { viewModel.switchCamera() } label: {
                Image(systemName: "camera.rotate").font(.title2).foregroundColor(.white)
                    .padding(10).background(Color.white.opacity(0.2)).clipShape(Circle())
            }
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 5).frame(width: 58, height: 58)
                Circle().trim(from: 0, to: CGFloat(viewModel.lungeResult.postureScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 58, height: 58).rotationEffect(.degrees(-90))
                Text("\(viewModel.lungeResult.postureScore)").font(.headline.bold()).foregroundColor(.white)
            }
        }
        .padding().background(.black.opacity(0.65)).cornerRadius(20).padding()
    }

    // MARK: - Bottom panel
    private var bottomPanel: some View {
        VStack(spacing: 14) {
            Text(viewModel.badRepMessage ?? viewModel.lungeResult.issue.rawValue)
                .font(.title2.bold())
                .foregroundColor(viewModel.badRepMessage != nil ? .orange : .white)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.2), value: viewModel.badRepMessage)

            HStack(spacing: 8) {
                LungeAngleCard(title: "Front Knee",
                               angle: viewModel.lungeResult.frontKneeAngle,
                               isOk:  viewModel.lungeResult.frontKneeOk,
                               idealRange: "80°-105°")
                LungeAngleCard(title: "Back Knee",
                               angle: viewModel.lungeResult.backKneeAngle,
                               isOk:  viewModel.lungeResult.backKneeOk,
                               idealRange: "70°-110°")
                LungeAngleCard(title: "Torso",
                               angle: viewModel.lungeResult.torsoAngle,
                               isOk:  viewModel.lungeResult.torsoOk,
                               idealRange: "65°-115°")
            }

            if viewModel.targetReps > 0 {
                LungeProgressBarView(currentSet: viewModel.currentSet,
                                     totalSets: viewModel.targetSets,
                                     repsInSet: viewModel.repsInCurrentSet,
                                     targetReps: viewModel.targetReps)
            }

            HStack(spacing: 36) {
                VStack(spacing: 2) {
                    Text("\(viewModel.repsInCurrentSet)")
                        .font(.system(size: 48, weight: .bold)).foregroundColor(.white)
                    Text(viewModel.targetReps > 0
                         ? "SET \(viewModel.currentSet)/\(viewModel.targetSets)"
                         : "REPS")
                        .font(.caption).foregroundColor(.white.opacity(0.7))
                }
                VStack(spacing: 2) {
                    Text(viewModel.phaseText).font(.title3.bold()).foregroundColor(viewModel.phaseColor)
                    Text("PHASE").font(.caption).foregroundColor(.white.opacity(0.7))
                }
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Text("✅\(viewModel.goodReps)").foregroundColor(.green).bold()
                        Text("❌\(viewModel.badReps)").foregroundColor(.red).bold()
                    }.font(.subheadline)
                    Text("QUALITY").font(.caption).foregroundColor(.white.opacity(0.7))
                }
                Button { viewModel.resetSession() } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.counterclockwise").font(.title2).foregroundColor(.white)
                        Text("RESET").font(.caption).foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
        .padding().background(.black.opacity(0.75)).cornerRadius(22).padding()
    }

    private var scoreColor: Color {
        let s = viewModel.lungeResult.postureScore
        if s >= 80 { return .green }
        if s >= 55 { return .yellow }
        return .red
    }
}

// MARK: - SUPPORTING VIEWS

struct LungeProgressBarView: View {
    let currentSet: Int; let totalSets: Int; let repsInSet: Int; let targetReps: Int
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Set \(currentSet) of \(totalSets)").font(.caption).foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(repsInSet)/\(targetReps) reps").font(.caption.bold()).foregroundColor(.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.15)).frame(height: 10)
                    RoundedRectangle(cornerRadius: 6).fill(Color.orange)
                        .frame(width: geo.size.width * CGFloat(min(repsInSet, targetReps)) / CGFloat(max(targetReps, 1)),
                               height: 10)
                        .animation(.spring(response: 0.3), value: repsInSet)
                }
            }.frame(height: 10)
        }.padding(.horizontal, 4)
    }
}

struct LungeFormAlertBanner: View {
    let message: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(message).font(.subheadline.bold()).foregroundColor(.white)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Color.black.opacity(0.85)).cornerRadius(30)
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.orange, lineWidth: 1.5))
        .shadow(color: .orange.opacity(0.4), radius: 8).padding(.horizontal)
    }
}

struct LungeAngleCard: View {
    let title: String; let angle: Double; let isOk: Bool; let idealRange: String
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundColor(.white.opacity(0.7))
            Text("\(Int(angle))°").font(.headline.bold()).foregroundColor(isOk ? .green : .red)
            Text(idealRange).font(.caption2).foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(isOk ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
        .cornerRadius(12)
    }
}

struct LungeGoalSheet: View {
    @ObservedObject var viewModel: LungeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var sets = 3; @State private var reps = 10; @State private var restSec = 60
    var body: some View {
        NavigationView {
            Form {
                Section("Workout Goal") {
                    Stepper("Sets: \(sets)", value: $sets, in: 1...10)
                    Stepper("Reps per set: \(reps)", value: $reps, in: 1...30)
                }
                Section("Rest Timer") {
                    Stepper("Rest: \(restSec)s", value: $restSec, in: 10...180, step: 10)
                }
                Section {
                    Button("Start Workout") { viewModel.setGoal(sets: sets, reps: reps, restSeconds: restSec); dismiss() }
                        .foregroundColor(.green).bold()
                    Button("Clear Goal") { viewModel.clearGoal(); dismiss() }.foregroundColor(.red)
                }
            }
            .navigationTitle("Set Goal")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct LungeStatsSheet: View {
    @ObservedObject var viewModel: LungeViewModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        LungeStatCard(title: "Total Reps", value: "\(viewModel.totalRepsAllTime)", color: .orange)
                        LungeStatCard(title: "Good Reps",  value: "\(viewModel.goodReps)",         color: .green)
                        LungeStatCard(title: "Bad Reps",   value: "\(viewModel.badReps)",          color: .red)
                    }
                    HStack(spacing: 12) {
                        LungeStatCard(title: "Avg Score",    value: "\(viewModel.averageScore)",  color: .yellow)
                        LungeStatCard(title: "Best Score",   value: "\(viewModel.bestRepScore)",  color: .mint)
                        LungeStatCard(title: "Session Time", value: viewModel.sessionTimeString, color: .cyan)
                    }
                    if !viewModel.repHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Rep Score History").font(.headline).padding(.horizontal)
                            LungeRepScoreGraph(records: viewModel.repHistory).frame(height: 180).padding(.horizontal)
                        }
                        .padding(.vertical, 10).background(Color(.systemGray6)).cornerRadius(16).padding(.horizontal)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Rep History").font(.headline).padding(.horizontal)
                            ForEach(viewModel.repHistory.reversed()) { rep in
                                HStack {
                                    Text("Rep \(rep.repNumber)").font(.subheadline)
                                    Spacer()
                                    Text("Score: \(rep.score)").font(.subheadline.bold())
                                        .foregroundColor(rep.isGood ? .green : .red)
                                    Text(rep.isGood ? "✅" : "❌")
                                }
                                .padding(.horizontal).padding(.vertical, 6)
                                .background(Color(.systemGray6)).cornerRadius(10).padding(.horizontal)
                            }
                        }
                    } else {
                        Text("No reps recorded yet.\nStart lunging! 🦵")
                            .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.top, 40)
                    }
                }.padding(.vertical)
            }
            .navigationTitle("Session Stats")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct LungeStatCard: View {
    let title: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundColor(color)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Color(.systemGray6)).cornerRadius(12)
    }
}

struct LungeRepScoreGraph: View {
    let records: [LungeRepRecord]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width; let h = geo.size.height
            let barW = max(8, min(28, w / CGFloat(records.count) - 4))
            ZStack(alignment: .bottom) {
                ForEach([0, 25, 50, 75, 100], id: \.self) { val in
                    let y = h * (1 - CGFloat(val) / 100)
                    Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                }
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(records) { rep in
                        VStack(spacing: 2) {
                            Text("\(rep.score)").font(.system(size: 8)).foregroundColor(.white.opacity(0.7))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(rep.isGood ? Color.green : Color.red)
                                .frame(width: barW, height: max(4, h * CGFloat(rep.score) / 100 - 16))
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

// MARK: - SKELETON OVERLAY
struct LungeSkeletonOverlay: View {
    let bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let result: LungeResult

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Torso
                drawLine(.leftShoulder,  .rightShoulder, geo, ok: result.torsoOk)
                drawLine(.leftShoulder,  .leftHip,       geo, ok: result.torsoOk)
                drawLine(.rightShoulder, .rightHip,      geo, ok: result.torsoOk)
                drawLine(.leftHip,       .rightHip,      geo, ok: result.hipLevelOk)

                // Front leg
                let fH: VNHumanBodyPoseObservation.JointName  = result.leftLegForward ? .leftHip   : .rightHip
                let fK: VNHumanBodyPoseObservation.JointName  = result.leftLegForward ? .leftKnee  : .rightKnee
                let fA: VNHumanBodyPoseObservation.JointName  = result.leftLegForward ? .leftAnkle : .rightAnkle
                drawLine(fH, fK, geo, ok: result.frontKneeOk)
                drawLine(fK, fA, geo, ok: result.frontKneeOk)

                // Back leg
                let bH: VNHumanBodyPoseObservation.JointName  = result.leftLegForward ? .rightHip   : .leftHip
                let bK: VNHumanBodyPoseObservation.JointName  = result.leftLegForward ? .rightKnee  : .leftKnee
                let bA: VNHumanBodyPoseObservation.JointName  = result.leftLegForward ? .rightAnkle : .leftAnkle
                drawLine(bH, bK, geo, ok: result.backKneeOk)
                drawLine(bK, bA, geo, ok: result.backKneeOk)

                // Joint dots
                let joints: [VNHumanBodyPoseObservation.JointName] = [
                    .leftShoulder, .rightShoulder, .leftHip, .rightHip,
                    fK, fA, bK, bA
                ]
                ForEach(joints, id: \.self) { joint in
                    if let pt = bodyPoints[joint] {
                        Circle().fill(dotColor(for: joint, fK: fK, fA: fA, bK: bK, bA: bA))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                            .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                    }
                }
            }
        }
    }

    private func dotColor(for joint: VNHumanBodyPoseObservation.JointName,
                          fK: VNHumanBodyPoseObservation.JointName,
                          fA: VNHumanBodyPoseObservation.JointName,
                          bK: VNHumanBodyPoseObservation.JointName,
                          bA: VNHumanBodyPoseObservation.JointName) -> Color {
        if joint == .leftShoulder || joint == .rightShoulder { return result.torsoOk    ? .green : .red }
        if joint == .leftHip      || joint == .rightHip      { return result.hipLevelOk ? .green : .red }
        if joint == fK            || joint == fA             { return result.frontKneeOk ? .green : .red }
        if joint == bK            || joint == bA             { return result.backKneeOk  ? .green : .red }
        return .white
    }

    @ViewBuilder
    private func drawLine(_ j1: VNHumanBodyPoseObservation.JointName,
                          _ j2: VNHumanBodyPoseObservation.JointName,
                          _ geo: GeometryProxy, ok: Bool) -> some View {
        if let p1 = bodyPoints[j1], let p2 = bodyPoints[j2] {
            Path { path in
                path.move(to: CGPoint(x: p1.x * geo.size.width, y: p1.y * geo.size.height))
                path.addLine(to: CGPoint(x: p2.x * geo.size.width, y: p2.y * geo.size.height))
            }
            .stroke(ok ? Color.green : Color.red, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
    }
}

// MARK: - VIEW MODEL
final class LungeViewModel: NSObject, ObservableObject,
                             AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    @Published var bodyPoints:  [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var lungeResult  = LungeResult()
    @Published var phaseText    = "Standing"
    @Published var phaseColor: Color = .white
    @Published var cameraPosition: AVCaptureDevice.Position = .back

    @Published var showFormAlert    = false
    @Published var formAlertMessage = ""
    @Published var showBadRepFlash  = false
    @Published var badRepReason     = ""
    @Published var showGoodRepFlash = false
    @Published var badRepMessage: String? = nil

    // Analytics
    @Published var repHistory:       [LungeRepRecord] = []
    @Published var goodReps          = 0
    @Published var badReps           = 0
    @Published var totalRepsAllTime  = 0
    @Published var averageScore      = 0
    @Published var bestRepScore      = 0

    // Sets / Goal
    @Published var targetSets       = 0
    @Published var targetReps       = 0
    @Published var currentSet       = 1
    @Published var repsInCurrentSet = 0

    // Rest timer
    @Published var isResting        = false
    @Published var restSecondsLeft  = 0
    private var restDuration        = 60
    private var restTimer: Timer?

    // Session timer
    @Published var sessionTimeString = "00:00"
    private var sessionStartDate: Date?
    private var sessionTimer: Timer?

    @Published var reps = 0

    // ── Thresholds ────────────────────────────────────────────────────────────
    private let frontKneeBottomMin: Double = 80
    private let frontKneeBottomMax: Double = 105
    private let backKneeBottomMin:  Double = 70
    private let backKneeBottomMax:  Double = 110
    private let torsoMin:           Double = 65
    private let torsoMax:           Double = 115
    private let hipDropFraction:    Double = 0.06
    private let minConfidence:      Float  = 0.35
    private let descentTrigger:     Double = 150
    private let returnTrigger:      Double = 148
    private let framesForBottom:    Int    = 3
    private let framesForReturn:    Int    = 3
    private let errorLatch:         Int    = 3

    // ── Smoothing ─────────────────────────────────────────────────────────────
    private var angleBuffer: [(frontKnee: Double, backKnee: Double, torso: Double)] = []
    private let bufferSize = 6

    // ── Rep state ─────────────────────────────────────────────────────────────
    private var repInProgress   = false
    private var bottomReached   = false
    private var framesAtBottom  = 0
    private var framesAtReturn  = 0
    private var currentPhase: LungePhase = .standing

    private var torsoErrFrames   = 0; private var hadTorsoError   = false
    private var frontErrFrames   = 0; private var hadFrontError   = false
    private var backErrFrames    = 0; private var hadBackError    = false
    private var hipDropErrFrames = 0; private var hadHipDropError = false

    // ── Debounce ──────────────────────────────────────────────────────────────
    private var stableIssueFrames = 0
    private var lastIssue: LungeIssue = .detecting
    private var alertTimer: Timer?

    // Speech
    private let speechSynth    = AVSpeechSynthesizer()
    private var lastSpeechTime: Date = .distantPast

    // Watch notification throttle
    private var lastNotifTime: [String: Date] = [:]
    private let notifCooldown: TimeInterval   = 4.0

    // MARK: - Lifecycle
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            DispatchQueue.global(qos: .userInitiated).async { self.setupCamera() }
        }
        startSessionTimer()
        fireWatchNotification(title: "🦵 Lunge Started",
                              body:  "Step forward into position.")
    }

    func stop() {
        session.stopRunning()
        sessionTimer?.invalidate()
        restTimer?.invalidate()
    }

    private func startSessionTimer() {
        sessionStartDate = Date()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.sessionStartDate else { return }
            let e = Int(Date().timeIntervalSince(start))
            DispatchQueue.main.async {
                self.sessionTimeString = String(format: "%02d:%02d", e / 60, e % 60)
            }
        }
    }

    // MARK: - Goal
    func setGoal(sets: Int, reps: Int, restSeconds: Int) {
        DispatchQueue.main.async {
            self.targetSets = sets; self.targetReps = reps
            self.restDuration = restSeconds
            self.currentSet = 1; self.repsInCurrentSet = 0
        }
    }

    func clearGoal() {
        DispatchQueue.main.async {
            self.targetSets = 0; self.targetReps = 0
            self.currentSet = 1; self.repsInCurrentSet = 0
        }
    }

    // MARK: - Reset
    func resetSession() {
        DispatchQueue.main.async {
            self.reps = 0; self.repsInCurrentSet = 0; self.currentSet = 1
            self.goodReps = 0; self.badReps = 0; self.totalRepsAllTime = 0
            self.averageScore = 0; self.bestRepScore = 0; self.repHistory = []
            self.angleBuffer.removeAll()
            self.isResting = false; self.restTimer?.invalidate()
            self.sessionStartDate = Date()
        }
        resetRepState()
        DispatchQueue.main.async { self.phaseText = "Standing"; self.phaseColor = .white }
    }

    private func resetRepState() {
        repInProgress = false; bottomReached = false
        framesAtBottom = 0; framesAtReturn = 0; currentPhase = .standing
        torsoErrFrames = 0;   hadTorsoError   = false
        frontErrFrames = 0;   hadFrontError   = false
        backErrFrames  = 0;   hadBackError    = false
        hipDropErrFrames = 0; hadHipDropError = false
    }

    // MARK: - Camera
    private func setupCamera() {
        guard !session.isRunning else { return }
        session.beginConfiguration(); session.sessionPreset = .high
        session.inputs.forEach { session.removeInput($0) }
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition),
            let input  = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { session.commitConfiguration(); return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "lungeVideoQueue"))
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration(); session.startRunning()
    }

    func switchCamera() {
        DispatchQueue.global(qos: .userInitiated).async {
            let newPos: AVCaptureDevice.Position = self.cameraPosition == .front ? .back : .front
            self.session.beginConfiguration()
            if let old = self.session.inputs.first { self.session.removeInput(old) }
            guard
                let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPos),
                let inp = try? AVCaptureDeviceInput(device: dev),
                self.session.canAddInput(inp)
            else { self.session.commitConfiguration(); return }
            self.session.addInput(inp); self.session.commitConfiguration()
            DispatchQueue.main.async { self.cameraPosition = newPos }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let orientation: CGImagePropertyOrientation = cameraPosition == .front ? .leftMirrored : .right
        analyzeFrame(pixelBuffer: pixelBuffer, orientation: orientation)
    }

    // MARK: - Analysis pipeline
    private func analyzeFrame(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        guard !isResting else { return }
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        do {
            try handler.perform([request])
            guard let obs = request.results?.first else { return }
            let pts = try obs.recognizedPoints(.all)
            updateBodyPoints(pts)
            guard var result = extractAngles(from: pts) else {
                DispatchQueue.main.async { self.lungeResult.issue = .notVisible }; return
            }
            let s = smooth(result)
            result.frontKneeAngle = s.frontKnee
            result.backKneeAngle  = s.backKnee
            result.torsoAngle     = s.torso
            evaluateForm(result: &result, rawPoints: pts)
            updatePhaseAndReps(result: result)

            if result.issue == lastIssue { stableIssueFrames += 1 }
            else { stableIssueFrames = 0; lastIssue = result.issue }
            var published = result
            if stableIssueFrames < 3 { published.issue = lungeResult.issue }

            // Alert uses raw (non-debounced) result for immediate response
            updateFormAlert(result: result)
            speakFormCue(result: result)
            DispatchQueue.main.async { self.lungeResult = published }
        } catch { print("Lunge Vision error: \(error)") }
    }

    // MARK: - Angle extraction (original logic preserved exactly)
    private func extractAngles(
        from pts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> LungeResult? {
        let required: [VNHumanBodyPoseObservation.JointName] = [
            .leftHip, .rightHip, .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle, .leftShoulder, .rightShoulder
        ]
        for j in required {
            guard let p = pts[j], p.confidence > minConfidence else { return nil }
        }

        let lKnee     = pts[.leftKnee]!.location
        let rKnee     = pts[.rightKnee]!.location
        let lHip      = pts[.leftHip]!.location
        let rHip      = pts[.rightHip]!.location
        let lAnkle    = pts[.leftAnkle]!.location
        let rAnkle    = pts[.rightAnkle]!.location
        let lShoulder = pts[.leftShoulder]!.location
        let rShoulder = pts[.rightShoulder]!.location

        // In Vision coords y=0 is at the bottom of the image.
        // The forward knee is lower in the frame → smaller y value.
        let leftIsForward = lKnee.y < rKnee.y

        let frontHip   = leftIsForward ? lHip   : rHip
        let frontKnee  = leftIsForward ? lKnee  : rKnee
        let frontAnkle = leftIsForward ? lAnkle : rAnkle
        let backHip    = leftIsForward ? rHip   : lHip
        let backKnee   = leftIsForward ? rKnee  : lKnee
        let backAnkle  = leftIsForward ? rAnkle : lAnkle

        var result = LungeResult()
        result.leftLegForward = leftIsForward
        result.frontKneeAngle = calculateAngle(first: frontHip, middle: frontKnee, last: frontAnkle)
        result.backKneeAngle  = calculateAngle(first: backHip,  middle: backKnee,  last: backAnkle)

        let midShoulder = CGPoint(x: (lShoulder.x + rShoulder.x) / 2,
                                  y: (lShoulder.y + rShoulder.y) / 2)
        let midHip      = CGPoint(x: (lHip.x + rHip.x) / 2,
                                  y: (lHip.y + rHip.y) / 2)
        var torsoDeg = atan2(midShoulder.y - midHip.y,
                             midShoulder.x - midHip.x) * 180 / .pi
        if torsoDeg < 0 { torsoDeg += 180 }
        result.torsoAngle = torsoDeg
        return result
    }

    // MARK: - Form evaluation
    private func evaluateForm(result: inout LungeResult,
                              rawPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        let front = result.frontKneeAngle
        let back  = result.backKneeAngle
        let torso = result.torsoAngle

        guard front < descentTrigger || back < descentTrigger else {
            result.frontKneeOk = true; result.backKneeOk = true
            result.torsoOk = true; result.hipLevelOk = true
            result.issue = .ready; result.postureScore = 100; return
        }

        // Knee angles only penalised at the bottom where 90° is required
        let atBottom = front <= frontKneeBottomMax
        result.frontKneeOk = atBottom
            ? (front >= frontKneeBottomMin && front <= frontKneeBottomMax)
            : true
        result.backKneeOk = atBottom
            ? (back >= backKneeBottomMin && back <= backKneeBottomMax)
            : true

        // Torso checked throughout entire rep
        result.torsoOk = torso >= torsoMin && torso <= torsoMax

        // Hip level using raw y-coords (not smoothed)
        var hipLevelOk = true
        if let lHp = rawPoints[.leftHip], let rHp = rawPoints[.rightHip],
           lHp.confidence > minConfidence, rHp.confidence > minConfidence {
            hipLevelOk = abs(lHp.location.y - rHp.location.y) <= hipDropFraction
        }
        result.hipLevelOk = hipLevelOk

        var score = 100
        if !result.frontKneeOk { score -= 30 }
        if !result.backKneeOk  { score -= 25 }
        if !result.torsoOk     { score -= 25 }
        if !result.hipLevelOk  { score -= 20 }
        result.postureScore = max(score, 0)

        if !result.torsoOk         { result.issue = .torsoLeaning }
        else if !result.hipLevelOk { result.issue = .hipDrop }
        else if !result.backKneeOk { result.issue = .backKneeBad }
        else if !result.frontKneeOk { result.issue = .frontKneeBad }
        else                        { result.issue = .correct }
    }

    // MARK: - Rep state machine (original logic preserved exactly)
    private func updatePhaseAndReps(result: LungeResult) {
        let front = result.frontKneeAngle
        var nextPhase = currentPhase
        var addRep = false; var badRep = false

        if repInProgress {
            if !result.torsoOk    { torsoErrFrames   += 1 } else { torsoErrFrames   = max(0, torsoErrFrames   - 1) }
            if !result.hipLevelOk { hipDropErrFrames += 1 } else { hipDropErrFrames = max(0, hipDropErrFrames - 1) }
            let atBottom = front <= frontKneeBottomMax
            if atBottom {
                if !result.frontKneeOk { frontErrFrames += 1 } else { frontErrFrames = max(0, frontErrFrames - 1) }
                if !result.backKneeOk  { backErrFrames  += 1 } else { backErrFrames  = max(0, backErrFrames  - 1) }
            }
            if torsoErrFrames   >= errorLatch { hadTorsoError   = true }
            if hipDropErrFrames >= errorLatch { hadHipDropError = true }
            if frontErrFrames   >= errorLatch { hadFrontError   = true }
            if backErrFrames    >= errorLatch { hadBackError    = true }
        }

        // Gate 1
        if !repInProgress && front < descentTrigger {
            repInProgress = true; framesAtBottom = 0; framesAtReturn = 0; nextPhase = .descending
        }

        // Gate 2
        if repInProgress && front <= frontKneeBottomMax {
            framesAtBottom += 1
            if framesAtBottom >= framesForBottom { bottomReached = true; nextPhase = .bottom }
        } else if repInProgress && front > frontKneeBottomMax {
            framesAtBottom = 0
        }

        if bottomReached && front > frontKneeBottomMax && front < returnTrigger { nextPhase = .ascending }

        // Gate 3
        if repInProgress && front > returnTrigger {
            framesAtReturn += 1
            if framesAtReturn >= framesForReturn {
                if bottomReached {
                    let goodForm = !hadTorsoError && !hadFrontError && !hadBackError && !hadHipDropError
                    if goodForm {
                        addRep = true
                        triggerGoodRepFeedback(score: result.postureScore)
                    } else { badRep = true }
                } else { badRep = true }
                resetRepState(); nextPhase = .standing
            }
        } else if front <= returnTrigger { framesAtReturn = 0 }

        currentPhase = nextPhase
        let scoreSnap = result.postureScore
        let reasons   = buildBadRepReasons(bottomWasReached: bottomReached)

        DispatchQueue.main.async {
            if addRep {
                self.reps += 1; self.repsInCurrentSet += 1; self.totalRepsAllTime += 1
                self.speakRepCount(self.repsInCurrentSet)
                if self.targetReps > 0 && self.repsInCurrentSet >= self.targetReps {
                    if self.currentSet < self.targetSets {
                        self.speakText("Set \(self.currentSet) complete! Rest now.")
                        self.startRestTimer(); self.currentSet += 1; self.repsInCurrentSet = 0
                    } else {
                        self.speakText("Workout complete! Great job!")
                        self.fireWatchNotification(title: "🎉 Workout Complete!",
                                                   body: "You finished all \(self.targetSets) sets!")
                    }
                }
                let record = LungeRepRecord(repNumber: self.totalRepsAllTime,
                                            score: scoreSnap, isGood: true, timestamp: Date())
                self.repHistory.append(record); self.updateScoreStats()
            }
            if badRep { self.triggerBadRepFeedback(reasons: reasons) }
            self.currentPhase = nextPhase
            switch nextPhase {
            case .standing:   self.phaseText = "Standing";      self.phaseColor = .white
            case .descending: self.phaseText = "Stepping Down"; self.phaseColor = .yellow
            case .bottom:     self.phaseText = "Good Depth ✅"; self.phaseColor = .green
            case .ascending:  self.phaseText = "Stepping Up";   self.phaseColor = .blue
            }
        }
    }

    private func updateScoreStats() {
        goodReps = repHistory.filter { $0.isGood }.count
        badReps  = repHistory.filter { !$0.isGood }.count
        if !repHistory.isEmpty {
            averageScore = repHistory.map { $0.score }.reduce(0,+) / repHistory.count
            bestRepScore = repHistory.map { $0.score }.max() ?? 0
        }
    }

    private func startRestTimer() {
        restSecondsLeft = restDuration; isResting = true; restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            DispatchQueue.main.async {
                self.restSecondsLeft -= 1
                if self.restSecondsLeft <= 0 { t.invalidate(); self.isResting = false; self.speakText("Go!") }
            }
        }
    }

    private func triggerGoodRepFeedback(score: Int) {
        DispatchQueue.main.async {
            self.showGoodRepFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.showGoodRepFlash = false }
        }
    }

    private func triggerBadRepFeedback(reasons: String) {
        fireWatchNotification(title: "❌ Rep Not Counted", body: reasons)
        DispatchQueue.main.async {
            self.badRepMessage = "⚠️ \(reasons)"
            let record = LungeRepRecord(repNumber: self.totalRepsAllTime + 1,
                                        score: 0, isGood: false, timestamp: Date())
            self.repHistory.append(record); self.totalRepsAllTime += 1; self.updateScoreStats()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.badRepMessage = nil }
        }
    }

    private func buildBadRepReasons(bottomWasReached: Bool) -> String {
        var r: [String] = []
        if hadTorsoError   { r.append("Torso leaning") }
        if hadHipDropError { r.append("Hips not level") }
        if hadFrontError   { r.append("Front knee off") }
        if hadBackError    { r.append("Back knee not low enough") }
        if !bottomWasReached { r.append("Insufficient depth") }
        return r.isEmpty ? "Insufficient depth" : r.joined(separator: " • ")
    }

    // MARK: - Form alert (live, immediate — uses non-debounced result)
    private func updateFormAlert(result: LungeResult) {
        let active = currentPhase == .descending || currentPhase == .bottom
        guard active else {
            DispatchQueue.main.async { self.showFormAlert = false }; return
        }
        var message: String? = nil
        if !result.torsoOk         { message = "Keep Torso Upright!" }
        else if !result.hipLevelOk { message = "Keep Hips Level!" }
        else if !result.backKneeOk { message = "Drop Back Knee Lower!" }

        if let msg = message {
            fireWatchNotification(title: "⚠️ Fix Your Form", body: msg, key: msg)
        }

        DispatchQueue.main.async {
            if let msg = message {
                if self.formAlertMessage != msg {
                    self.formAlertMessage = msg
                    self.alertTimer?.invalidate()
                    self.alertTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                        DispatchQueue.main.async { self.showFormAlert = false }
                    }
                }
                self.showFormAlert = true
            } else {
                self.alertTimer?.invalidate()
                self.showFormAlert = false
            }
        }
    }

    // MARK: - Voice cues
    private func speakFormCue(result: LungeResult) {
        guard currentPhase == .descending || currentPhase == .bottom else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSpeechTime) > 3.0 else { return }
        var cue: String? = nil
        if !result.torsoOk         { cue = "Keep torso upright" }
        else if !result.hipLevelOk { cue = "Keep hips level" }
        else if !result.backKneeOk { cue = "Drop back knee lower" }
        if let text = cue {
            lastSpeechTime = now
            let u = AVSpeechUtterance(string: text); u.rate = 0.5; u.volume = 0.9
            DispatchQueue.main.async { self.speechSynth.speak(u) }
        }
    }

    private func speakRepCount(_ count: Int) {
        let u = AVSpeechUtterance(string: "\(count)"); u.rate = 0.55; u.volume = 1.0
        DispatchQueue.main.async { self.speechSynth.speak(u) }
    }

    private func speakText(_ text: String) {
        let u = AVSpeechUtterance(string: text); u.rate = 0.5; u.volume = 1.0
        DispatchQueue.main.async { self.speechSynth.speak(u) }
    }

    // MARK: - Watch notification
    func fireWatchNotification(title: String, body: String, key: String? = nil) {
        let throttleKey = key ?? title
        let now = Date()
        if let last = lastNotifTime[throttleKey], now.timeIntervalSince(last) < notifCooldown { return }
        lastNotifTime[throttleKey] = now
        NotificationManager.shared.send(title: title, body: body)
        WatchConnectivityManager.shared.sendFormAlert(exercise: "Lunge", issue: "\(title): \(body)")
    }

    // MARK: - Helpers
    private func updateBodyPoints(_ pts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        var mapped: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (j, p) in pts where p.confidence > 0.3 {
            mapped[j] = CGPoint(x: p.location.x, y: 1 - p.location.y)
        }
        DispatchQueue.main.async { self.bodyPoints = mapped }
    }

    private func calculateAngle(first: CGPoint, middle: CGPoint, last: CGPoint) -> Double {
        let a = atan2(first.y  - middle.y, first.x  - middle.x)
        let b = atan2(last.y   - middle.y, last.x   - middle.x)
        var angle = abs((a - b) * 180 / .pi)
        if angle > 180 { angle = 360 - angle }
        return angle
    }

    private func smooth(_ result: LungeResult) -> (frontKnee: Double, backKnee: Double, torso: Double) {
        angleBuffer.append((result.frontKneeAngle, result.backKneeAngle, result.torsoAngle))
        if angleBuffer.count > bufferSize { angleBuffer.removeFirst() }
        let n = Double(angleBuffer.count)
        return (
            angleBuffer.map(\.frontKnee).reduce(0, +) / n,
            angleBuffer.map(\.backKnee).reduce(0,  +) / n,
            angleBuffer.map(\.torso).reduce(0,    +) / n
        )
    }
}
