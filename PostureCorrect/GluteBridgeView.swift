//
//  GluteBridgeView.swift
//  PostureCorrect
//
//  Camera: SIDE-ON, PORTRAIT, floor/hip level, 1.2–2 m away.
//  Full body shoulder→hip→knee→ankle must fill ~70% of frame height.
//
//  KEY DETECTION IMPROVEMENT:
//  Vision's pose model is trained on upright people. When you lie flat,
//  orientation guessing becomes unreliable. This view tries all four
//  orientations every frame and picks the one with the best total joint
//  confidence — so detection works regardless of how the phone is propped.
//

import SwiftUI
import AVFoundation
import Vision
import Combine
import AVKit

// MARK: - GLUTE BRIDGE ISSUE
enum GluteBridgeIssue: String {
    case correct        = "✅ Perfect Bridge"
    case ready          = "🧍 Lie Down & Begin"
    case hipsTooLow     = "❌ Push Hips Higher"
    case hipsTooHigh    = "❌ Don't Hyperextend"
    case kneeTooWide    = "❌ Move Feet Closer"
    case kneeTooClose   = "❌ Move Feet Further"
    case backArched     = "❌ Keep Back Neutral"
    case shoulderLifted = "❌ Keep Shoulders Down"
    case detecting      = "🔍 Detecting..."
    case notVisible     = "📷 Full Body Not Visible"
}

// MARK: - GLUTE BRIDGE PHASE
enum GluteBridgePhase { case flat, ascending, top, descending }

// MARK: - REP RECORD
struct GluteBridgeRepRecord: Identifiable {
    let id         = UUID()
    let repNumber:  Int
    let score:      Int
    let isGood:     Bool
    let timestamp:  Date
}

// MARK: - GLUTE BRIDGE RESULT
struct GluteBridgeResult {
    var issue: GluteBridgeIssue = .detecting
    var postureScore: Int       = 100
    var hipAngle:     Double    = 160
    var kneeAngle:    Double    = 90
    var spineAngle:   Double    = 0
    var shoulderRise: Double    = 0
    var trackedLeftSide: Bool   = true
    var hipOk:      Bool = true
    var kneeOk:     Bool = true
    var spineOk:    Bool = true
    var shoulderOk: Bool = true
    var formIsValid: Bool { hipOk && kneeOk && spineOk && shoulderOk }
}

// MARK: - GLUTE BRIDGE CAMERA VIEW
struct GluteBridgeCameraView: View {
    @StateObject private var viewModel = GluteBridgeViewModel()
    @State private var showGoalSheet   = false
    @State private var showStatsSheet  = false

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.session).ignoresSafeArea()

            GluteBridgeSkeletonOverlay(
                bodyPoints: viewModel.bodyPoints,
                result:     viewModel.bridgeResult
            ).ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if viewModel.showFormAlert {
                    GluteBridgeAlertBanner(message: viewModel.formAlertMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4), value: viewModel.showFormAlert)
                }
                Spacer()

                if viewModel.isResting {
                    GluteBridgeRestTimerView(secondsLeft: viewModel.restSecondsLeft)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(), value: viewModel.isResting)
                }

                bottomPanel
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
        }
        .onAppear    { viewModel.start() }
        .onDisappear { viewModel.stop()  }
        .sheet(isPresented: $showGoalSheet)  { GluteBridgeGoalSetupSheet(viewModel: viewModel) }
        .sheet(isPresented: $showStatsSheet) { GluteBridgeStatsSheet(viewModel: viewModel) }
    }

    // MARK: - Top controls (minimal floating pill)
    private var topBar: some View {
        HStack(spacing: 8) {
            // Session time
            Text(viewModel.sessionTimeString)
                .font(.caption.monospacedDigit().bold())
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.5)).cornerRadius(20)

            Spacer()

            // Score ring
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 3).frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.bridgeResult.postureScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 40, height: 40).rotationEffect(.degrees(-90))
                Text("\(viewModel.bridgeResult.postureScore)")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            }

            // Action buttons
            HStack(spacing: 4) {
                Button { showStatsSheet = true } label: {
                    Image(systemName: "chart.bar.fill").font(.subheadline).foregroundColor(.white)
                        .padding(8).background(Color.white.opacity(0.15)).clipShape(Circle())
                }
                Button { showGoalSheet = true } label: {
                    Image(systemName: "target").font(.subheadline).foregroundColor(.white)
                        .padding(8).background(Color.white.opacity(0.15)).clipShape(Circle())
                }
                Button { viewModel.switchCamera() } label: {
                    Image(systemName: "camera.rotate").font(.subheadline).foregroundColor(.white)
                        .padding(8).background(Color.white.opacity(0.15)).clipShape(Circle())
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(.black.opacity(0.5)).cornerRadius(24)
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    // MARK: - Bottom panel (compact)
    private var bottomPanel: some View {
        VStack(spacing: 10) {

            // Issue label + phase pill on same row
            HStack {
                Text(viewModel.bridgeResult.issue.rawValue)
                    .font(.subheadline.bold()).foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Text(viewModel.phaseText)
                    .font(.caption.bold())
                    .foregroundColor(viewModel.phaseColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(viewModel.phaseColor.opacity(0.15))
                    .cornerRadius(12)
            }

            // Angle chips — compact single row
            HStack(spacing: 6) {
                GluteBridgeAngleChip(label: "Hip",  angle: viewModel.bridgeResult.hipAngle,      isOk: viewModel.bridgeResult.hipOk)
                GluteBridgeAngleChip(label: "Knee", angle: viewModel.bridgeResult.kneeAngle,     isOk: viewModel.bridgeResult.kneeOk)
                GluteBridgeAngleChip(label: "Back", angle: viewModel.bridgeResult.spineAngle,    isOk: viewModel.bridgeResult.spineOk)
                GluteBridgeAngleChip(label: "Shld", angle: viewModel.bridgeResult.shoulderRise,  isOk: viewModel.bridgeResult.shoulderOk)
            }

            // Progress bar (only when goal is set)
            if viewModel.targetReps > 0 {
                GluteBridgeProgressBarView(
                    currentSet:  viewModel.currentSet,
                    totalSets:   viewModel.targetSets,
                    repsInSet:   viewModel.repsInCurrentSet,
                    targetReps:  viewModel.targetReps
                )
            }

            // Rep count row
            HStack(alignment: .center, spacing: 0) {
                // Rep number — dominant
                VStack(spacing: 0) {
                    Text("\(viewModel.repsInCurrentSet)")
                        .font(.system(size: 52, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(viewModel.targetReps > 0
                         ? "SET \(viewModel.currentSet) OF \(viewModel.targetSets)"
                         : "REPS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .kerning(1.2)
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 44)

                // Quality
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Label("\(viewModel.goodReps)", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Label("\(viewModel.badReps)", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                    .font(.subheadline.bold())
                    Text("QUALITY").font(.system(size: 10)).foregroundColor(.white.opacity(0.5)).kerning(1.2)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 44)

                // Reset
                Button { viewModel.resetSession() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title3).foregroundColor(.white.opacity(0.7))
                        Text("RESET").font(.system(size: 10)).foregroundColor(.white.opacity(0.4)).kerning(1.2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(.ultraThinMaterial.opacity(0.95))
        .background(Color.black.opacity(0.6))
        .cornerRadius(24)
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var scoreColor: Color {
        let s = viewModel.bridgeResult.postureScore
        if s >= 80 { return .green }
        if s >= 55 { return .yellow }
        return .red
    }
}

// MARK: - ALERT BANNER
struct GluteBridgeAlertBanner: View {
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

// MARK: - REST TIMER VIEW
struct GluteBridgeRestTimerView: View {
    let secondsLeft: Int
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer").foregroundColor(.cyan)
            Text("Rest: \(secondsLeft)s").font(.title3.bold()).foregroundColor(.white)
            Text("Next set coming up...").font(.caption).foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Color.black.opacity(0.85)).cornerRadius(30)
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(Color.cyan, lineWidth: 1.5))
        .shadow(color: .cyan.opacity(0.4), radius: 8).padding(.horizontal)
    }
}

// MARK: - PROGRESS BAR VIEW
struct GluteBridgeProgressBarView: View {
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
                    RoundedRectangle(cornerRadius: 6).fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(min(repsInSet, targetReps)) / CGFloat(max(targetReps, 1)),
                               height: 10)
                        .animation(.spring(response: 0.3), value: repsInSet)
                }
            }.frame(height: 10)
        }.padding(.horizontal, 4)
    }
}

// MARK: - ANGLE CHIP (compact inline chip)
struct GluteBridgeAngleChip: View {
    let label: String; let angle: Double; let isOk: Bool
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(isOk ? Color.green : Color.red).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(.white.opacity(0.6))
            Text("\(Int(angle))°").font(.system(size: 12, weight: .bold)).foregroundColor(isOk ? .green : .red)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(isOk ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - GOAL SETUP SHEET
struct GluteBridgeGoalSetupSheet: View {
    @ObservedObject var viewModel: GluteBridgeViewModel
    @Environment(\.dismiss) var dismiss
    @State private var sets    = 3
    @State private var reps    = 12
    @State private var restSec = 45

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
                    Button("Start Workout") {
                        viewModel.setGoal(sets: sets, reps: reps, restSeconds: restSec)
                        dismiss()
                    }.foregroundColor(.green).bold()
                    Button("Clear Goal") {
                        viewModel.clearGoal(); dismiss()
                    }.foregroundColor(.red)
                }
            }
            .navigationTitle("Set Goal")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - STATS SHEET
struct GluteBridgeStatsSheet: View {
    @ObservedObject var viewModel: GluteBridgeViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        GluteBridgeStatCard(title: "Total Reps", value: "\(viewModel.totalRepsAllTime)", color: .blue)
                        GluteBridgeStatCard(title: "Good Reps",  value: "\(viewModel.goodReps)",         color: .green)
                        GluteBridgeStatCard(title: "Bad Reps",   value: "\(viewModel.badReps)",          color: .red)
                    }
                    HStack(spacing: 12) {
                        GluteBridgeStatCard(title: "Avg Score",    value: "\(viewModel.averageScore)",   color: .yellow)
                        GluteBridgeStatCard(title: "Best Score",   value: "\(viewModel.bestRepScore)",   color: .orange)
                        GluteBridgeStatCard(title: "Session Time", value: viewModel.sessionTimeString,   color: .cyan)
                    }

                    if !viewModel.repHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Rep Score History").font(.headline).padding(.horizontal)
                            GluteBridgeRepScoreGraph(records: viewModel.repHistory)
                                .frame(height: 180).padding(.horizontal)
                        }
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6)).cornerRadius(16).padding(.horizontal)
                    }

                    if !viewModel.repHistory.isEmpty {
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
                        Text("No reps recorded yet.\nStart bridging! 🍑")
                            .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.top, 40)
                    }
                }.padding(.vertical)
            }
            .navigationTitle("Session Stats")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct GluteBridgeStatCard: View {
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

struct GluteBridgeRepScoreGraph: View {
    let records: [GluteBridgeRepRecord]
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
struct GluteBridgeSkeletonOverlay: View {
    let bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let result: GluteBridgeResult

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let usedSide = result.trackedLeftSide
                let shoulder: VNHumanBodyPoseObservation.JointName = usedSide ? .leftShoulder : .rightShoulder
                let hip:      VNHumanBodyPoseObservation.JointName = usedSide ? .leftHip      : .rightHip
                let knee:     VNHumanBodyPoseObservation.JointName = usedSide ? .leftKnee     : .rightKnee
                let ankle:    VNHumanBodyPoseObservation.JointName = usedSide ? .leftAnkle    : .rightAnkle

                drawLine(shoulder, hip,   geo, ok: result.spineOk)
                drawLine(hip,      knee,  geo, ok: result.hipOk)
                drawLine(knee,     ankle, geo, ok: result.kneeOk)

                ForEach([shoulder, hip, knee, ankle], id: \.self) { joint in
                    if let pt = bodyPoints[joint] {
                        Circle()
                            .fill(dotColor(for: joint, s: shoulder, h: hip, k: knee, a: ankle))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                            .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                    }
                }

                if let anklePt = bodyPoints[ankle] {
                    let y = anklePt.y * geo.size.height
                    Path { p in
                        p.move(to: .init(x: 0, y: y))
                        p.addLine(to: .init(x: geo.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                }
            }
        }
    }

    private func dotColor(for joint: VNHumanBodyPoseObservation.JointName,
                          s: VNHumanBodyPoseObservation.JointName,
                          h: VNHumanBodyPoseObservation.JointName,
                          k: VNHumanBodyPoseObservation.JointName,
                          a: VNHumanBodyPoseObservation.JointName) -> Color {
        if joint == s { return result.shoulderOk ? .green : .red }
        if joint == h { return result.hipOk      ? .green : .red }
        if joint == k { return result.kneeOk     ? .green : .red }
        if joint == a { return result.kneeOk     ? .green : .red }
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

// MARK: - GLUTE BRIDGE VIEW MODEL
final class GluteBridgeViewModel: NSObject, ObservableObject,
                                   AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    @Published var bodyPoints:      [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var bridgeResult     = GluteBridgeResult()
    @Published var reps             = 0
    @Published var phaseText        = "Lie Flat"
    @Published var phaseColor: Color = .white
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var detectionStatus  = "Real-Time Form Check"

    @Published var showFormAlert    = false
    @Published var formAlertMessage = ""
    @Published var showBadRepFlash  = false
    @Published var badRepReason     = ""

    // Analytics
    @Published var repHistory:      [GluteBridgeRepRecord] = []
    @Published var goodReps         = 0
    @Published var badReps          = 0
    @Published var totalRepsAllTime = 0
    @Published var averageScore     = 0
    @Published var bestRepScore     = 0

    // Sets / Goal
    @Published var targetSets        = 0
    @Published var targetReps        = 0
    @Published var currentSet        = 1
    @Published var repsInCurrentSet  = 0

    // Rest timer
    @Published var isResting         = false
    @Published var restSecondsLeft   = 0
    private var restDuration         = 45
    private var restTimer: Timer?

    // Session timer
    @Published var sessionTimeString = "00:00"
    private var sessionStartDate: Date?
    private var sessionTimer: Timer?

    // Speech
    private let speechSynth        = AVSpeechSynthesizer()
    private var lastSpokenIssue: GluteBridgeIssue = .detecting
    private var lastSpeechTime: Date = .distantPast

    // Watch notification throttle
    private var lastNotifTime: [String: Date] = [:]
    private let notifCooldown: TimeInterval   = 5.0

    // ── Thresholds ────────────────────────────────────────────────────────────
    private let bridgeTopHipMin: Double = 145
    private let bridgeTopHipMax: Double = 178
    private let flatHipMin:      Double = 115
    private let kneeMin:         Double = 70
    private let kneeMax:         Double = 120
    private let spineMax:        Double = 30
    private let shoulderRiseMax: Double = 0.07

    private let hipRiseRequired:  Double = 0.05
    private let flatThreshold:    Double = 0.03
    private let framesForTop:     Int = 3
    private let framesForFlat:    Int = 3
    private let errorLatch:       Int = 4
    private let baselineRequired: Int = 8

    // ── Orientation locking ───────────────────────────────────────────────────
    private var lockedOrientation: CGImagePropertyOrientation? = nil
    private var orientationSearchFrames = 0
    private let orientationLockFrames   = 10
    private var missingBodyFrames       = 0
    private let relockThreshold         = 30

    private let candidateOrientations: [CGImagePropertyOrientation] = [
        .right, .left, .up, .down
    ]

    // ── Smoothing (display only) ──────────────────────────────────────────────
    private var angleBuffer: [(hip: Double, knee: Double, spine: Double, shoulder: Double)] = []
    private let angleBufferSize = 5

    // ── Locked side ───────────────────────────────────────────────────────────
    private var lockedSide: Bool? = nil

    // ── Rep state ─────────────────────────────────────────────────────────────
    private var repInProgress    = false
    private var topReached       = false
    private var framesAtTop      = 0
    private var framesAtFlat     = 0
    private var hipYBaseline:      Double? = nil
    private var shoulderYBaseline: Double? = nil
    private var baselineCaptured   = false
    private var baselineFrames     = 0

    private var hipErrFrames:      Int = 0;  private var hadHipError      = false
    private var kneeErrFrames:     Int = 0;  private var hadKneeError     = false
    private var spineErrFrames:    Int = 0;  private var hadSpineError    = false
    private var shoulderErrFrames: Int = 0;  private var hadShoulderError = false

    private var stableIssueFrames = 0
    private var lastIssue: GluteBridgeIssue = .detecting
    private var alertTimer: Timer?
    private var currentPhase: GluteBridgePhase = .flat

    // MARK: - Lifecycle
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            DispatchQueue.global(qos: .userInitiated).async { self.setupCamera() }
        }
        startSessionTimer()
        fireWatchNotification(title: "🏋️ Ready for Glute Bridge!", body: "Lie flat and begin when calibrated.")
    }

    func stop() {
        session.stopRunning()
        sessionTimer?.invalidate()
        restTimer?.invalidate()
    }

    // MARK: - Session timer
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
            self.resetRepState()
            self.resetBaseline()
            self.lockedSide = nil
            self.lockedOrientation = nil
            self.orientationSearchFrames = 0
            self.missingBodyFrames = 0
            self.isResting = false; self.restTimer?.invalidate()
            self.sessionStartDate = Date()
            self.phaseText  = "Lie Flat"
            self.phaseColor = .white
        }
    }

    private func resetRepState() {
        repInProgress = false; topReached = false
        framesAtTop = 0; framesAtFlat = 0
        hipErrFrames = 0; hadHipError = false
        kneeErrFrames = 0; hadKneeError = false
        spineErrFrames = 0; hadSpineError = false
        shoulderErrFrames = 0; hadShoulderError = false
        currentPhase = .flat
    }

    private func resetBaseline() {
        hipYBaseline = nil; shoulderYBaseline = nil
        baselineCaptured = false; baselineFrames = 0
    }

    // MARK: - Rest timer
    private func startRestTimer() {
        restSecondsLeft = restDuration; isResting = true
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            DispatchQueue.main.async {
                self.restSecondsLeft -= 1
                if self.restSecondsLeft <= 0 {
                    t.invalidate(); self.isResting = false
                    self.resetRepState(); self.speakText("Go!")
                }
            }
        }
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
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "gluteBridgeQ"))
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
            DispatchQueue.main.async {
                self.cameraPosition = newPos
                self.lockedOrientation = nil
                self.orientationSearchFrames = 0
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        analyzeFrame(pixelBuffer: pixelBuffer)
    }

    // MARK: - Best-orientation detection
    private func bestOrientation(for pixelBuffer: CVPixelBuffer)
        -> (orientation: CGImagePropertyOrientation,
            points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint])? {

        var bestScore: Float = 0
        var bestResult: (CGImagePropertyOrientation, [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint])?

        let keysToScore: [VNHumanBodyPoseObservation.JointName] = [
            .leftShoulder, .rightShoulder,
            .leftHip,      .rightHip,
            .leftKnee,     .rightKnee,
            .leftAnkle,    .rightAnkle
        ]

        let orientations: [CGImagePropertyOrientation] = cameraPosition == .front
            ? [.leftMirrored, .rightMirrored, .upMirrored, .downMirrored]
            : candidateOrientations

        for orientation in orientations {
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                orientation: orientation)
            do {
                try handler.perform([request])
                guard let obs = request.results?.first,
                      let pts = try? obs.recognizedPoints(.all) else { continue }
                let score = keysToScore.reduce(Float(0)) { $0 + (pts[$1]?.confidence ?? 0) }
                if score > bestScore {
                    bestScore = score
                    bestResult = (orientation, pts)
                }
            } catch { continue }
        }
        guard let result = bestResult, bestScore > 0.4 else { return nil }
        return result
    }

    // MARK: - Analysis pipeline
    private func analyzeFrame(pixelBuffer: CVPixelBuffer) {
        guard !isResting else { return }

        let orientationToUse: CGImagePropertyOrientation
        var rawPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]

        if let locked = lockedOrientation {
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: locked)
            do {
                try handler.perform([request])
                guard let obs = request.results?.first,
                      let pts = try? obs.recognizedPoints(.all) else {
                    missingBodyFrames += 1
                    if missingBodyFrames >= relockThreshold {
                        lockedOrientation = nil
                        orientationSearchFrames = 0
                        missingBodyFrames = 0
                        DispatchQueue.main.async { self.detectionStatus = "Searching..." }
                    }
                    DispatchQueue.main.async { self.bridgeResult.issue = .notVisible }
                    return
                }
                orientationToUse = locked
                rawPoints = pts
                missingBodyFrames = 0
            } catch {
                DispatchQueue.main.async { self.bridgeResult.issue = .notVisible }
                return
            }
        } else {
            guard let best = bestOrientation(for: pixelBuffer) else {
                DispatchQueue.main.async {
                    self.bridgeResult.issue = .notVisible
                    self.detectionStatus = "Searching — lie flat & stay still"
                }
                return
            }
            orientationToUse = best.orientation
            rawPoints = best.points

            orientationSearchFrames += 1
            if orientationSearchFrames >= orientationLockFrames {
                lockedOrientation = orientationToUse
                orientationSearchFrames = 0
                DispatchQueue.main.async { self.detectionStatus = "Real-Time Form Check" }
            }
        }

        let useLeft: Bool
        if let locked = lockedSide {
            useLeft = locked
        } else {
            useLeft = betterSide(rawPoints)
        }

        var mapped: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (joint, point) in rawPoints where point.confidence > 0.15 {
            mapped[joint] = CGPoint(x: point.location.x, y: 1 - point.location.y)
        }

        guard let rawResult = extractAngles(from: rawPoints, useLeft: useLeft) else {
            DispatchQueue.main.async {
                self.bodyPoints = mapped
                self.bridgeResult.issue = .notVisible
            }
            return
        }

        updateBaseline(result: rawResult, rawPoints: rawPoints, useLeft: useLeft)
        updatePhaseAndReps(result: rawResult, rawPoints: rawPoints, useLeft: useLeft)

        var displayResult = rawResult
        let s = smoothForDisplay(rawResult)
        displayResult.hipAngle     = s.hip
        displayResult.kneeAngle    = s.knee
        displayResult.spineAngle   = s.spine
        displayResult.shoulderRise = s.shoulder

        evaluateForm(result: &displayResult)

        if displayResult.issue == lastIssue { stableIssueFrames += 1 }
        else { stableIssueFrames = 0; lastIssue = displayResult.issue }
        var published = displayResult
        if stableIssueFrames < 3 { published.issue = bridgeResult.issue }

        speakFormCue(result: published)
        updateFormAlert(result: published)

        DispatchQueue.main.async {
            self.bodyPoints   = mapped
            self.bridgeResult = published
        }
    }

    // MARK: - Angle extraction
    private func extractAngles(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
                                useLeft: Bool) -> GluteBridgeResult? {
        let shoulderKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder
        let hipKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let kneeKey:     VNHumanBodyPoseObservation.JointName = useLeft ? .leftKnee     : .rightKnee
        let ankleKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftAnkle    : .rightAnkle

        for j in [shoulderKey, hipKey, kneeKey, ankleKey] {
            guard let p = points[j], p.confidence > 0.15 else { return nil }
        }

        let shoulder = points[shoulderKey]!.location
        let hip      = points[hipKey]!.location
        let knee     = points[kneeKey]!.location
        let ankle    = points[ankleKey]!.location

        var result = GluteBridgeResult()
        result.trackedLeftSide = useLeft
        result.hipAngle   = calculateAngle(first: shoulder, middle: hip,  last: knee)
        result.kneeAngle  = calculateAngle(first: hip,      middle: knee, last: ankle)
        let spineRaw      = atan2(shoulder.y - hip.y, shoulder.x - hip.x) * 180 / .pi
        result.spineAngle = min(abs(spineRaw), 90)
        if let baseline = shoulderYBaseline {
            result.shoulderRise = max(0, shoulder.y - baseline) * 100
        }
        return result
    }

    // MARK: - Baseline capture
    private func updateBaseline(result: GluteBridgeResult,
                                rawPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
                                useLeft: Bool) {
        guard !baselineCaptured else { return }

        let hipKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let shoulderKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder

        guard let hipPt = rawPoints[hipKey], let shoulderPt = rawPoints[shoulderKey],
              hipPt.confidence > 0.15, shoulderPt.confidence > 0.15 else { return }

        let isFlat = result.spineAngle < 30 && result.hipAngle > flatHipMin

        if isFlat {
            baselineFrames += 1
            let w = 1.0 / Double(baselineFrames)
            hipYBaseline      = (hipYBaseline ?? hipPt.location.y) * (1 - w) + hipPt.location.y * w
            shoulderYBaseline = (shoulderYBaseline ?? shoulderPt.location.y) * (1 - w) + shoulderPt.location.y * w

            if baselineFrames >= baselineRequired {
                baselineCaptured = true
                lockedSide = useLeft
                DispatchQueue.main.async {
                    self.phaseText = "Ready ✅"; self.phaseColor = .green
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if self.currentPhase == .flat {
                            self.phaseText = "Lie Flat"; self.phaseColor = .white
                        }
                    }
                }
            }
        } else {
            baselineFrames = 0; hipYBaseline = nil; shoulderYBaseline = nil
        }
    }

    // MARK: - Form evaluation
    private func evaluateForm(result: inout GluteBridgeResult) {
        guard result.spineAngle < 50 else {
            result.hipOk = true; result.kneeOk = true
            result.spineOk = true; result.shoulderOk = true
            result.issue = .ready; result.postureScore = 100; return
        }

        let atTop = currentPhase == .top || currentPhase == .ascending

        result.hipOk = atTop
            ? (result.hipAngle >= bridgeTopHipMin && result.hipAngle <= bridgeTopHipMax)
            : true

        result.kneeOk = result.kneeAngle >= kneeMin && result.kneeAngle <= kneeMax

        result.spineOk = atTop ? result.spineAngle <= spineMax : true

        result.shoulderOk = result.shoulderRise <= (shoulderRiseMax * 100)

        var score = 100
        if !result.hipOk      { score -= 35 }
        if !result.kneeOk     { score -= 25 }
        if !result.spineOk    { score -= 25 }
        if !result.shoulderOk { score -= 15 }
        result.postureScore = max(score, 0)

        if !result.hipOk          { result.issue = result.hipAngle < bridgeTopHipMin ? .hipsTooLow : .hipsTooHigh }
        else if !result.spineOk   { result.issue = .backArched }
        else if !result.kneeOk    { result.issue = result.kneeAngle < kneeMin ? .kneeTooClose : .kneeTooWide }
        else if !result.shoulderOk { result.issue = .shoulderLifted }
        else                       { result.issue = .correct }
    }

    // MARK: - Rep state machine (original logic preserved exactly)
    private func updatePhaseAndReps(result: GluteBridgeResult,
                                    rawPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint],
                                    useLeft: Bool) {
        guard baselineCaptured, let hipBase = hipYBaseline else {
            DispatchQueue.main.async {
                self.phaseText = "Hold Still to Calibrate"
                self.phaseColor = .white.opacity(0.6)
            }
            return
        }

        let hipKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip : .rightHip
        guard let hipPt = rawPoints[hipKey], hipPt.confidence > 0.15 else { return }

        let hipRise = hipPt.location.y - hipBase

        var nextPhase = currentPhase
        var addRep    = false

        if repInProgress {
            hipErrFrames      = result.hipOk      ? max(0, hipErrFrames - 1)      : hipErrFrames + 1
            kneeErrFrames     = result.kneeOk     ? max(0, kneeErrFrames - 1)     : kneeErrFrames + 1
            spineErrFrames    = result.spineOk    ? max(0, spineErrFrames - 1)    : spineErrFrames + 1
            shoulderErrFrames = result.shoulderOk ? max(0, shoulderErrFrames - 1) : shoulderErrFrames + 1
            if hipErrFrames      >= errorLatch { hadHipError      = true }
            if kneeErrFrames     >= errorLatch { hadKneeError     = true }
            if spineErrFrames    >= errorLatch { hadSpineError    = true }
            if shoulderErrFrames >= errorLatch { hadShoulderError = true }
        }

        if !repInProgress && hipRise >= hipRiseRequired {
            repInProgress = true; framesAtTop = 0; framesAtFlat = 0
            nextPhase = .ascending
        }

        if repInProgress && hipRise >= hipRiseRequired && nextPhase != .top {
            nextPhase = .ascending
        }

        if repInProgress && result.hipAngle >= bridgeTopHipMin && hipRise >= hipRiseRequired * 0.5 {
            framesAtTop += 1
            if framesAtTop >= framesForTop { topReached = true; nextPhase = .top }
        } else if repInProgress && nextPhase != .top {
            framesAtTop = max(0, framesAtTop - 1)
        }

        if topReached && hipRise < hipRiseRequired && hipRise > flatThreshold {
            nextPhase = .descending
        }

        if repInProgress && hipRise <= flatThreshold {
            framesAtFlat += 1
            if framesAtFlat >= framesForFlat {
                let topWasReached = topReached
                let reasons = buildBadRepReasons(topWasReached: topWasReached)
                if topWasReached && !hadHipError && !hadSpineError {
                    addRep = true
                } else {
                    let r = reasons
                    DispatchQueue.main.async { self.triggerBadRepFeedback(reasons: r) }
                }
                resetRepState()
                nextPhase = .flat
            }
        } else if repInProgress {
            framesAtFlat = 0
        }

        currentPhase = nextPhase
        let scoreSnapshot = result.postureScore

        DispatchQueue.main.async {
            if addRep {
                self.reps += 1
                self.repsInCurrentSet += 1
                self.totalRepsAllTime += 1
                self.speakRepCount(self.repsInCurrentSet)

                if self.targetReps > 0 && self.repsInCurrentSet >= self.targetReps {
                    if self.currentSet < self.targetSets {
                        self.speakText("Set \(self.currentSet) complete! Rest now.")
                        self.fireWatchNotification(
                            title: "✅ Set \(self.currentSet) Done!",
                            body:  "Rest up, next set starting soon."
                        )
                        self.startRestTimer()
                        self.currentSet += 1
                        self.repsInCurrentSet = 0
                    } else {
                        self.speakText("Workout complete! Great job!")
                        self.fireWatchNotification(
                            title: "🎉 Workout Complete!",
                            body:  "You finished all \(self.targetSets) sets. Great job!"
                        )
                    }
                }

                let record = GluteBridgeRepRecord(
                    repNumber: self.totalRepsAllTime,
                    score: scoreSnapshot,
                    isGood: true,
                    timestamp: Date()
                )
                self.repHistory.append(record)
                self.updateScoreStats()
            }

            switch nextPhase {
            case .flat:       self.phaseText = "Lie Flat";       self.phaseColor = .white
            case .ascending:  self.phaseText = "Lifting Up";     self.phaseColor = .yellow
            case .top:        self.phaseText = "Full Bridge ✅"; self.phaseColor = .green
            case .descending: self.phaseText = "Lowering Down";  self.phaseColor = .blue
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

    private func buildBadRepReasons(topWasReached: Bool) -> String {
        var r: [String] = []
        if !topWasReached   { r.append("Didn't reach full extension") }
        if hadHipError      { r.append("Hips not high enough") }
        if hadSpineError    { r.append("Back arching") }
        if hadKneeError     { r.append("Foot placement off") }
        if hadShoulderError { r.append("Shoulders lifted") }
        return r.isEmpty ? "Check your form" : r.joined(separator: " • ")
    }

    private func triggerBadRepFeedback(reasons: String) {
        // Voice cue for bad rep
        if reasons.contains("Hips")        { speakText("Push your hips higher") }
        else if reasons.contains("arching") { speakText("Keep your back neutral") }
        else if reasons.contains("Foot")   { speakText("Check your foot placement") }
        else if reasons.contains("extension") { speakText("Reach full extension at the top") }
        else if reasons.contains("Shoulders") { speakText("Keep shoulders on the floor") }

        // Watch notification for bad rep
        fireWatchNotification(title: "❌ Rep Not Counted", body: reasons)

        // Record bad rep
        DispatchQueue.main.async {
            let record = GluteBridgeRepRecord(
                repNumber: self.totalRepsAllTime + 1,
                score: 0,
                isGood: false,
                timestamp: Date()
            )
            self.repHistory.append(record)
            self.totalRepsAllTime += 1
            self.updateScoreStats()
        }

        badRepReason = reasons; showBadRepFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.showBadRepFlash = false }
    }

    // MARK: - Voice cues
    private func speakFormCue(result: GluteBridgeResult) {
        guard currentPhase == .ascending || currentPhase == .top else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSpeechTime) > 3.0 else { return }
        var cue: String? = nil
        if !result.hipOk       { cue = result.hipAngle < bridgeTopHipMin ? "Push hips higher" : "Don't hyperextend" }
        else if !result.spineOk { cue = "Keep your back neutral" }
        else if !result.shoulderOk { cue = "Keep shoulders on the floor" }
        else if !result.kneeOk  { cue = result.kneeAngle < kneeMin ? "Move feet further away" : "Move feet closer" }
        if let text = cue, result.issue != lastSpokenIssue {
            lastSpokenIssue = result.issue; lastSpeechTime = now
            speakText(text)
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

    // MARK: - Form alert (fires watch notification for real-time errors)
    private func updateFormAlert(result: GluteBridgeResult) {
        guard currentPhase == .ascending || currentPhase == .top else {
            DispatchQueue.main.async { self.showFormAlert = false }; return
        }
        var message: String? = nil
        if !result.hipOk       { message = result.hipAngle < bridgeTopHipMin ? "Push Hips Higher!" : "Don't Hyperextend!" }
        else if !result.spineOk  { message = "Keep Back Neutral!" }
        else if !result.shoulderOk { message = "Keep Shoulders on the Floor!" }
        else if !result.kneeOk   { message = result.kneeAngle < kneeMin ? "Move Feet Further Away!" : "Move Feet Closer!" }

        if let msg = message {
            // Watch notification: real-time form error
            fireWatchNotification(title: "⚠️ Fix Your Form", body: msg)
        }

        DispatchQueue.main.async {
            if let msg = message {
                self.formAlertMessage = msg; self.showFormAlert = true
                self.alertTimer?.invalidate()
                self.alertTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    DispatchQueue.main.async { self.showFormAlert = false }
                }
            } else { self.showFormAlert = false }
        }
    }

    // MARK: - Watch notification (fires both local notification + WatchConnectivity)
    func fireWatchNotification(title: String, body: String) {
        let key = title
        let now = Date()
        if let last = lastNotifTime[key], now.timeIntervalSince(last) < notifCooldown { return }
        lastNotifTime[key] = now

        // 1. Local notification — shows on iPhone + mirrors to watch
        NotificationManager.shared.send(title: title, body: body)

        // 2. WatchConnectivity — direct message to watch app for instant haptic
        WatchConnectivityManager.shared.sendFormAlert(
            exercise: "Glute Bridge",
            issue:    "\(title): \(body)"
        )
    }

    // MARK: - Helpers
    private func betterSide(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        let lScore: Float = (points[.leftShoulder]?.confidence ?? 0)
                          + (points[.leftHip]?.confidence      ?? 0)
                          + (points[.leftKnee]?.confidence     ?? 0)
                          + (points[.leftAnkle]?.confidence    ?? 0)
        let rScore: Float = (points[.rightShoulder]?.confidence ?? 0)
                          + (points[.rightHip]?.confidence      ?? 0)
                          + (points[.rightKnee]?.confidence     ?? 0)
                          + (points[.rightAnkle]?.confidence    ?? 0)
        return lScore >= rScore
    }

    private func calculateAngle(first: CGPoint, middle: CGPoint, last: CGPoint) -> Double {
        let a = atan2(first.y - middle.y, first.x - middle.x)
        let b = atan2(last.y  - middle.y, last.x  - middle.x)
        var angle = abs((a - b) * 180 / .pi)
        if angle > 180 { angle = 360 - angle }
        return angle
    }

    private func smoothForDisplay(_ r: GluteBridgeResult)
        -> (hip: Double, knee: Double, spine: Double, shoulder: Double) {
        angleBuffer.append((r.hipAngle, r.kneeAngle, r.spineAngle, r.shoulderRise))
        if angleBuffer.count > angleBufferSize { angleBuffer.removeFirst() }
        let n = Double(angleBuffer.count)
        return (angleBuffer.map(\.hip).reduce(0,+)      / n,
                angleBuffer.map(\.knee).reduce(0,+)     / n,
                angleBuffer.map(\.spine).reduce(0,+)    / n,
                angleBuffer.map(\.shoulder).reduce(0,+) / n)
    }
}
