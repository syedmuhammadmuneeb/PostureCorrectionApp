//
//  PushUpView.swift
//  PostureCorrect
//
//  Camera placement: SIDE-ON — phone on the floor to your left or right,
//  ~1.5–2 m away, lens at shoulder/hip height. Full body must be visible.
//
//  ─────────────────────────────────────────────────────────────────────────
//  BIOMECHANICALLY CORRECT PUSH-UP ANGLES  (Vision side-on, floor camera)
//  ─────────────────────────────────────────────────────────────────────────
//
//  1. Elbow angle  (shoulder → elbow → wrist)
//     • Top (arms extended):        150°–180°
//     • Bottom excellent:            80°–100°
//     • Bottom acceptable:           70°–110°
//     • Depth threshold:            ≤ 72°   (4 consecutive frames — based on observed ~58° bottom)
//     • Excellent depth:              ≤ 65°
//     • Minimum descent to record a rep event: ≤ 100°
//     • Descent trigger: < 145°
//
//  2. Hip angle  (shoulder → hip → knee)
//     • Excellent:   170°–180°
//     • Acceptable:  155°–170°  (was 165° — too strict for side-on camera)
//     • Poor:        < 155°
//     • Sagging fail: < 145°
//
//  3. Plank alignment score  (0–100, higher = straighter body)
//     • Perfect plank:   100  (hip exactly on shoulder–ankle line)
//     • Good form:       ≥ 85 (standing, bottom, ascending)
//     • Descending:      ≥ 80 (slight shift allowed)
//     • Visible sag/pike: < 80
//     • Extreme:          0   (hip ≥30% of body length off the line)
//     • spineSagging = true → hip below line (sagging); false → piking
//
//  4. Neck angle  (ear → shoulder → hip)
//     • Excellent:   170°–180°
//     • Acceptable:  160°–170°
//     • Poor:        < 160°
//
//  ─────────────────────────────────────────────────────────────────────────
//  REP COUNTING — STRICT FORM-GATED STATE MACHINE
//  ─────────────────────────────────────────────────────────────────────────
//
//  A rep is counted ONLY when ALL of the following are satisfied:
//    1. Elbow reached ≤ 110° for ≥ 3 consecutive smoothed frames (depth)
//    2. Arms returned to ≥ 150° for ≥ 2 consecutive smoothed frames (top)
//    3. Zero hip form errors (hipAngle < 165°) for ≥ 3 frames during the rep
//    4. Zero spine form errors (spineAngle > 35°) for ≥ 3 frames during the rep
//    5. Zero neck form errors (neckAngle < 155°) for ≥ 3 frames during the rep
//       (neck is advisory only when ear joint confidence < 0.15 — skipped)
//
//  Anti-jitter:
//    • 8-frame angle smoother on all rep-counting angles
//    • 6-frame overlay buffer keeps skeleton locked to body
//    • validDepthFrames uses += only; never hard-resets mid-rep
//    • minElbowAngle anchors the true bottom
//    • validStandingFrames resets immediately when elbow drops below elbowUpMin
//    • notVisibleFrames: 8 frames before surfacing "not visible"
//    • stableIssueFrames: 3 frames before changing the issue label
//

import SwiftUI
import AVFoundation
import Vision
import Combine
import AVKit

// MARK: - PUSHUP ISSUE
enum PushUpIssue: String {
    case correct       = "✅ Perfect Push-Up"
    case ready         = "🧍 Get Into Push-Up Position"
    case hipsTooLow    = "❌ Raise Your Hips"
    case hipsTooHigh   = "❌ Lower Your Hips"
    case backSagging   = "❌ Keep Body Straight"
    case neckBad       = "❌ Keep Head Neutral"
    case notDeepEnough = "❌ Go Lower"
    case detecting     = "🔍 Detecting..."
    case notVisible    = "📷 Full Body Not Visible"
    case improperDepth = "⚠️ Go Deeper Next Time"
}

// MARK: - PUSHUP PHASE
enum PushUpPhase { case standing, descending, bottom, ascending }

// MARK: - PUSHUP RESULT
struct PushUpResult {
    var issue: PushUpIssue  = .detecting
    var postureScore: Int   = 100
    var elbowAngle:  Double = 180
    var hipAngle:    Double = 180
    var spineAngle:  Double = 0         // plank alignment score 0–100
    var spineSagging: Bool  = false     // true = hip below plank line (sag); false = piking
    var neckAngle:   Double = 175       // ear → shoulder → hip
    var neckTracked: Bool   = false     // false when ear joint not visible
    var trackedLeftSide: Bool = true
    var elbowOk:  Bool = true
    var hipOk:    Bool = true
    var spineOk:  Bool = true
    var neckOk:   Bool = true
}

// MARK: - CAMERA VIEW  (compact GluteBridge-style UI)
struct PushupCameraView: View {
    @StateObject private var viewModel = PushUpViewModel()
    @State private var showGoalSheet   = false
    @State private var showStatsSheet  = false

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.session).ignoresSafeArea()

            PushUpSkeletonOverlay(
                bodyPoints: viewModel.bodyPoints,
                result:     viewModel.postureResult
            ).ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if viewModel.showFormAlert {
                    PushUpFormAlertBanner(message: viewModel.formAlertMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4), value: viewModel.showFormAlert)
                }
                Spacer()
                bottomPanel
            }

            // Good rep flash
            if viewModel.showGoodRepFlash {
                Color.green.opacity(0.22).ignoresSafeArea().allowsHitTesting(false)
            }

            // Bad rep flash overlay — matches GluteBridge style
            if viewModel.badRepMessage != nil {
                Color.red.opacity(0.25).ignoresSafeArea().allowsHitTesting(false)
                VStack {
                    Spacer()
                    Text(viewModel.badRepMessage ?? "")
                        .font(.title3.bold()).foregroundColor(.white)
                        .multilineTextAlignment(.center).padding()
                        .background(Color.red.opacity(0.85)).cornerRadius(16)
                        .padding(.bottom, 220)
                }
            }
        }
        .onAppear    { viewModel.start() }
        .onDisappear { viewModel.stop()  }
        .sheet(isPresented: $showGoalSheet)  { PushUpGoalSheet(viewModel: viewModel) }
        .sheet(isPresented: $showStatsSheet) { PushUpStatsSheet(viewModel: viewModel) }
    }

    // MARK: - Top bar (minimal floating pill — matches GluteBridge)
    private var topBar: some View {
        HStack(spacing: 8) {
            // Session timer pill
            Text(viewModel.sessionTimeString)
                .font(.caption.monospacedDigit().bold())
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.5)).cornerRadius(20)

            Spacer()

            // Score ring (40 px, compact)
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 3).frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.postureResult.postureScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 40, height: 40).rotationEffect(.degrees(-90))
                Text("\(viewModel.postureResult.postureScore)")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            }

            // Action buttons — single frosted pill
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

    // MARK: - Bottom panel (compact — matches GluteBridge layout exactly)
    private var bottomPanel: some View {
        VStack(spacing: 10) {

            // Issue label + phase pill on same row
            HStack {
                Text(viewModel.postureResult.issue.rawValue)
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
                PushUpAngleChip(label: "Elbow", angle: viewModel.postureResult.elbowAngle, isOk: viewModel.postureResult.elbowOk)
                PushUpAngleChip(label: "Hip",   angle: viewModel.postureResult.hipAngle,   isOk: viewModel.postureResult.hipOk)
                PushUpAngleChip(label: "Back",  angle: viewModel.postureResult.spineAngle, isOk: viewModel.postureResult.spineOk, unit: "")
                if viewModel.postureResult.neckTracked {
                    PushUpAngleChip(label: "Neck", angle: viewModel.postureResult.neckAngle, isOk: viewModel.postureResult.neckOk)
                }
            }

            // Progress bar (only when goal is set)
            if viewModel.targetReps > 0 {
                PushUpProgressBar(
                    currentSet: viewModel.currentSet,
                    totalSets:  viewModel.targetSets,
                    repsInSet:  viewModel.repsInCurrentSet,
                    targetReps: viewModel.targetReps
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
        let s = viewModel.postureResult.postureScore
        if s >= 80 { return .green }
        if s >= 55 { return .yellow }
        return .red
    }
}

// MARK: - FORM ALERT BANNER
struct PushUpFormAlertBanner: View {
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

// MARK: - ANGLE CHIP  (replaces PushUpAngleCard — matches GluteBridgeAngleChip)
struct PushUpAngleChip: View {
    let label: String
    let angle: Double
    let isOk:  Bool
    var unit:  String = "°"

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(isOk ? Color.green : Color.red).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(.white.opacity(0.6))
            Text("\(Int(angle))\(unit)").font(.system(size: 12, weight: .bold)).foregroundColor(isOk ? .green : .red)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(isOk ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - PROGRESS BAR
struct PushUpProgressBar: View {
    let currentSet: Int; let totalSets: Int; let repsInSet: Int; let targetReps: Int
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Set \(currentSet) of \(totalSets)")
                    .font(.caption).foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(repsInSet)/\(targetReps) reps")
                    .font(.caption.bold()).foregroundColor(.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.15)).frame(height: 10)
                    RoundedRectangle(cornerRadius: 6).fill(Color.blue)
                        .frame(
                            width: geo.size.width * CGFloat(min(repsInSet, targetReps)) / CGFloat(max(targetReps, 1)),
                            height: 10
                        )
                        .animation(.spring(response: 0.3), value: repsInSet)
                }
            }.frame(height: 10)
        }.padding(.horizontal, 4)
    }
}

// MARK: - SKELETON OVERLAY
// Draws the full side-on chain:
//   arm:  shoulder → elbow → wrist
//   body: shoulder → hip → knee → ankle
//   neck: ear → shoulder (when ear is visible)
// Each segment coloured green/red by its specific form check.
// Body points are smoothed over 6 frames so they stay locked on the body.
struct PushUpSkeletonOverlay: View {
    let bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let result: PushUpResult

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let shoulder: VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftShoulder : .rightShoulder
                let elbow:    VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftElbow    : .rightElbow
                let wrist:    VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftWrist    : .rightWrist
                let hip:      VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftHip      : .rightHip
                let knee:     VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftKnee     : .rightKnee
                let ankle:    VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftAnkle    : .rightAnkle
                let ear:      VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftEar      : .rightEar

                // Arm
                drawLine(shoulder, elbow, geo, ok: result.elbowOk)
                drawLine(elbow,    wrist, geo, ok: result.elbowOk)
                // Body
                drawLine(shoulder, hip,   geo, ok: result.spineOk)
                drawLine(hip,      knee,  geo, ok: result.hipOk)
                drawLine(knee,     ankle, geo, ok: result.hipOk)
                // Neck (only when ear visible)
                if result.neckTracked {
                    drawLine(ear, shoulder, geo, ok: result.neckOk)
                }

                let joints: [VNHumanBodyPoseObservation.JointName] = result.neckTracked
                    ? [shoulder, elbow, wrist, hip, knee, ankle, ear]
                    : [shoulder, elbow, wrist, hip, knee, ankle]

                ForEach(joints, id: \.self) { joint in
                    if let pt = bodyPoints[joint] {
                        Circle()
                            .fill(dotColor(for: joint,
                                          shoulder: shoulder, elbow: elbow, wrist: wrist,
                                          hip: hip, knee: knee, ankle: ankle, ear: ear))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                            .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                    }
                }
            }
        }
    }

    private func dotColor(
        for joint: VNHumanBodyPoseObservation.JointName,
        shoulder: VNHumanBodyPoseObservation.JointName,
        elbow:    VNHumanBodyPoseObservation.JointName,
        wrist:    VNHumanBodyPoseObservation.JointName,
        hip:      VNHumanBodyPoseObservation.JointName,
        knee:     VNHumanBodyPoseObservation.JointName,
        ankle:    VNHumanBodyPoseObservation.JointName,
        ear:      VNHumanBodyPoseObservation.JointName
    ) -> Color {
        switch joint {
        case elbow, wrist:   return result.elbowOk ? .green : .red
        case shoulder:       return (result.spineOk && result.neckOk) ? .green : .red
        case hip:            return result.hipOk   ? .green : .red
        case knee, ankle:    return result.hipOk   ? .green : .red
        case ear:            return result.neckOk  ? .green : .red
        default:             return .white
        }
    }

    @ViewBuilder
    private func drawLine(
        _ j1: VNHumanBodyPoseObservation.JointName,
        _ j2: VNHumanBodyPoseObservation.JointName,
        _ geo: GeometryProxy,
        ok: Bool
    ) -> some View {
        if let p1 = bodyPoints[j1], let p2 = bodyPoints[j2] {
            Path { path in
                path.move(to:    CGPoint(x: p1.x * geo.size.width, y: p1.y * geo.size.height))
                path.addLine(to: CGPoint(x: p2.x * geo.size.width, y: p2.y * geo.size.height))
            }
            .stroke(ok ? Color.green : Color.red, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
    }
}

// MARK: - GOAL SHEET
struct PushUpGoalSheet: View {
    @ObservedObject var viewModel: PushUpViewModel
    @Environment(\.dismiss) var dismiss
    @State private var sets    = 3
    @State private var reps    = 10
    @State private var restSec = 60

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
                        viewModel.setGoal(sets: sets, reps: reps, restSeconds: restSec); dismiss()
                    }.foregroundColor(.blue).bold()
                    Button("Clear Goal") { viewModel.clearGoal(); dismiss() }.foregroundColor(.red)
                }
            }
            .navigationTitle("Set Goal")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - STATS SHEET
struct PushUpStatsSheet: View {
    @ObservedObject var viewModel: PushUpViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        PushUpStatCard(title: "Total Reps", value: "\(viewModel.totalRepsAllTime)", color: .blue)
                        PushUpStatCard(title: "Good Reps",  value: "\(viewModel.goodReps)",         color: .green)
                        PushUpStatCard(title: "Bad Reps",   value: "\(viewModel.badReps)",          color: .red)
                    }
                    HStack(spacing: 12) {
                        PushUpStatCard(title: "Avg Score",    value: "\(viewModel.averageScore)",   color: .yellow)
                        PushUpStatCard(title: "Best Score",   value: "\(viewModel.bestRepScore)",   color: .orange)
                        PushUpStatCard(title: "Session Time", value: viewModel.sessionTimeString,   color: .cyan)
                    }

                    if !viewModel.repHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Rep History").font(.headline).padding(.horizontal)
                            ForEach(viewModel.repHistory.reversed()) { rep in
                                HStack {
                                    Text("Rep \(rep.repNumber)").font(.subheadline)
                                    Spacer()
                                    Text("Score: \(rep.score)")
                                        .font(.subheadline.bold())
                                        .foregroundColor(rep.isGood ? .green : .red)
                                    Text(rep.isGood ? "✅" : "❌")
                                }
                                .padding(.horizontal).padding(.vertical, 6)
                                .background(Color(.systemGray6)).cornerRadius(10).padding(.horizontal)
                            }
                        }
                    } else {
                        Text("No reps recorded yet.\nStart pushing! 💪")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary).padding(.top, 40)
                    }
                }.padding(.vertical)
            }
            .navigationTitle("Session Stats")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct PushUpStatCard: View {
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

// MARK: - VIEW MODEL
final class PushUpViewModel: NSObject, ObservableObject,
                              AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    @Published var bodyPoints:     [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var postureResult   = PushUpResult()
    @Published var currentPhase: PushUpPhase = .standing
    @Published var phaseText       = "Up"
    @Published var phaseColor: Color = .white
    @Published var cameraPosition: AVCaptureDevice.Position = .back

    @Published var showFormAlert     = false
    @Published var formAlertMessage  = ""
    @Published var showGoodRepFlash  = false
    @Published var badRepMessage: String? = nil

    // Analytics
    @Published var repHistory:      [RepRecord] = []
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

    // Session timer
    @Published var sessionTimeString = "00:00"
    private var sessionStartDate: Date?
    private var sessionTimer: Timer?

    @Published var reps = 0

    // ── Smoothing buffers ────────────────────────────────────────────────────
    // 6-frame overlay buffer → skeleton stays locked to body at all times
    private var pointsBuffer: [[VNHumanBodyPoseObservation.JointName: CGPoint]] = []
    // 8-frame angle buffer → stable angle readings for all rep logic
    private var frameBuffer:  [PushUpResult] = []

    // ── Rep-counting state ───────────────────────────────────────────────────
    private var lastElbowAngle      = 180.0
    private var minElbowAngle       = 180.0   // true minimum seen this rep
    private var pushUpStarted       = false
    private var depthReached        = false
    private var bottomReached       = false
    private var validDepthFrames    = 0       // counts up only; never hard-reset mid-rep
    private var validBottomFrames   = 0
    private var validStandingFrames = 0

    // ── Debounce / noise ─────────────────────────────────────────────────────
    private var stableIssueFrames  = 0
    private var notVisibleFrames   = 0
    private var lastIssue: PushUpIssue = .detecting
    private var alertTimer: Timer?

    // ── Per-rep form error accumulators ─────────────────────────────────────
    // Each counter decays by 1 per frame when form is good (never hard-resets),
    // so a single clean frame cannot erase accumulated errors.
    private var hipErrorFrames    = 0
    private var spineErrorFrames  = 0
    private var neckErrorFrames   = 0
    private var hadHipError       = false
    private var hadSpineError     = false
    private var hadNeckError      = false

    // ── Watch / notification throttle ───────────────────────────────────────
    private var lastNotifTime: [String: Date] = [:]
    private let notifCooldown: TimeInterval   = 5.0

    private let speechSynth      = AVSpeechSynthesizer()
    private var lastSpeechTime:  Date = .distantPast
    private var lastSpokenIssue: PushUpIssue = .detecting

    // ════════════════════════════════════════════════════════════════════════
    // THRESHOLDS
    // ════════════════════════════════════════════════════════════════════════

    private let elbowDescentTrigger: Double = 145
    private let elbowMinimumDescent: Double = 100
    private let elbowDepthMax:       Double = 72
    private let elbowDepthExcellent: Double = 65
    private let elbowUpMin:          Double = 150

    private let hipExcellentMin:  Double = 170
    private let hipAcceptableMin: Double = 155
    private let hipSaggingFail:   Double = 145

    private let spineIdealMax: Double = 35
    private let uprightGuard:  Double = 60

    private let neckAcceptableMin: Double = 160
    private let neckErrorMin:      Double = 155

    private let depthFramesRequired:    Int = 4
    private let standingFramesRequired: Int = 2

    // MARK: - Lifecycle
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            DispatchQueue.global(qos: .userInitiated).async { self.setupCamera() }
        }
        startSessionTimer()
        fireWatchNotification(title: "🏋️ Push-Up Started", body: "Get into position and begin.")
    }

    func stop() {
        session.stopRunning()
        sessionTimer?.invalidate()
    }

    func resetSession() {
        DispatchQueue.main.async {
            self.reps = 0; self.repsInCurrentSet = 0; self.currentSet = 1
            self.goodReps = 0; self.badReps = 0; self.totalRepsAllTime = 0
            self.averageScore = 0; self.bestRepScore = 0; self.repHistory = []
            self.currentPhase = .standing; self.phaseText = "Up"; self.phaseColor = .white
        }
        resetPushUpState()
    }

    private func resetPushUpState() {
        pushUpStarted = false; depthReached = false; bottomReached = false
        validDepthFrames = 0; validBottomFrames = 0; validStandingFrames = 0
        lastElbowAngle = 180; minElbowAngle = 180
        hipErrorFrames = 0; spineErrorFrames = 0; neckErrorFrames = 0
        hadHipError = false; hadSpineError = false; hadNeckError = false
        frameBuffer = []; pointsBuffer = []
        DispatchQueue.main.async {
            self.currentPhase = .standing; self.phaseText = "Up"; self.phaseColor = .white
        }
    }

    // MARK: - Goal
    func setGoal(sets: Int, reps: Int, restSeconds: Int) {
        DispatchQueue.main.async {
            self.targetSets = sets; self.targetReps = reps
            self.currentSet = 1; self.repsInCurrentSet = 0
        }
    }

    func clearGoal() {
        DispatchQueue.main.async {
            self.targetSets = 0; self.targetReps = 0
            self.currentSet = 1; self.repsInCurrentSet = 0
        }
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

    // MARK: - Camera setup
    private func setupCamera() {
        guard !session.isRunning else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        session.inputs.forEach { session.removeInput($0) }
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition),
            let input  = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { session.commitConfiguration(); return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "pushupVideoQueue"))
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        session.startRunning()
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

    // MARK: - Analyze frame
    private func analyzeFrame(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return }
            let points = try observation.recognizedPoints(.all)

            updateBodyPoints(points)

            let rawResult = analyzePushUpPosture(points)

            if rawResult.issue == .notVisible {
                notVisibleFrames += 1
                if notVisibleFrames >= 8 {
                    DispatchQueue.main.async { self.postureResult = rawResult }
                }
                return
            } else {
                notVisibleFrames = 0
            }

            var smoothed = smoothResult(rawResult)
            updatePhaseAndReps(smoothedResult: smoothed)

            if smoothed.issue == lastIssue { stableIssueFrames += 1 }
            else { stableIssueFrames = 0; lastIssue = smoothed.issue }
            if stableIssueFrames < 3 { smoothed.issue = postureResult.issue }

            updateFormAlert(result: smoothed)
            DispatchQueue.main.async { self.postureResult = smoothed }
        } catch {
            print("PushUp Vision error: \(error)")
        }
    }

    // MARK: - Posture analysis
    private func analyzePushUpPosture(
        _ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> PushUpResult {
        var result = PushUpResult()
        let useLeft = betterSide(points)
        result.trackedLeftSide = useLeft

        let shoulderKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder
        let elbowKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftElbow    : .rightElbow
        let wristKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftWrist    : .rightWrist
        let hipKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let kneeKey:     VNHumanBodyPoseObservation.JointName = useLeft ? .leftKnee     : .rightKnee
        let ankleKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftAnkle    : .rightAnkle
        let earKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftEar      : .rightEar

        let conf: Float = 0.15
        for joint in [shoulderKey, elbowKey, wristKey, hipKey, kneeKey] {
            guard let p = points[joint], p.confidence > conf else {
                result.issue = .notVisible; return result
            }
        }

        let shoulder = points[shoulderKey]!.location
        let elbow    = points[elbowKey]!.location
        let wrist    = points[wristKey]!.location
        let hip      = points[hipKey]!.location
        let knee     = points[kneeKey]!.location

        result.elbowAngle = calculateAngle(first: shoulder, middle: elbow, last: wrist)
        result.hipAngle   = calculateAngle(first: shoulder, middle: hip,   last: knee)

        let ankleConf = points[ankleKey]?.confidence ?? 0
        let anklePoint: CGPoint = ankleConf > 0.1
            ? points[ankleKey]!.location
            : CGPoint(x: knee.x + (knee.x - hip.x) * 0.6,
                      y: knee.y + (knee.y - hip.y) * 0.6)

        let refDX = anklePoint.x - shoulder.x
        let refDY = anklePoint.y - shoulder.y
        let refLen = sqrt(refDX * refDX + refDY * refDY)
        let crossZ   = refDX * (hip.y - shoulder.y) - refDY * (hip.x - shoulder.x)
        let perpDist = refLen > 0.001 ? Double(crossZ) / Double(refLen) : 0.0
        let clampedDev = max(-0.3, min(0.3, perpDist))
        let alignScore = 100.0 - (abs(clampedDev) / 0.3) * 100.0

        result.spineAngle   = alignScore
        result.spineSagging = perpDist < 0

        if let earPoint = points[earKey], earPoint.confidence > 0.15 {
            result.neckAngle   = calculateAngle(first: earPoint.location, middle: shoulder, last: hip)
            result.neckTracked = true
            result.neckOk      = result.neckAngle >= neckAcceptableMin
        } else {
            result.neckTracked = false
            result.neckOk      = true
        }

        let personIsUpright = result.elbowAngle >= 165 && result.hipAngle >= 165
        guard !personIsUpright else {
            result.elbowOk = true; result.hipOk = true; result.spineOk = true; result.neckOk = true
            result.issue = .ready; result.postureScore = 100
            return result
        }

        let spineThresh: Double = (currentPhase == .descending) ? 80.0 : 85.0
        result.spineOk = result.spineAngle >= spineThresh
        result.hipOk   = result.hipAngle >= hipAcceptableMin

        switch currentPhase {
        case .standing, .ascending:
            result.elbowOk = result.elbowAngle >= elbowUpMin
        case .descending:
            result.elbowOk = result.elbowAngle < elbowDescentTrigger
        case .bottom:
            result.elbowOk = result.elbowAngle <= elbowDepthMax
        }

        var score = 100
        if result.hipAngle < hipSaggingFail       { score -= 40 }
        else if result.hipAngle < hipAcceptableMin { score -= 25 }
        else if result.hipAngle < hipExcellentMin  { score -= 10 }
        if !result.spineOk { score -= 30 }
        if !result.elbowOk { score -= 20 }
        if result.neckTracked && !result.neckOk { score -= 15 }
        if currentPhase == .bottom || currentPhase == .descending {
            if result.elbowAngle <= elbowDepthExcellent   { score = min(100, score + 5) }
            else if result.elbowAngle > elbowDepthMax      { score -= 10 }
        }
        result.postureScore = max(score, 0)

        if !result.hipOk {
            result.issue = .hipsTooLow
        } else if !result.spineOk {
            result.issue = result.spineSagging ? .hipsTooLow : .backSagging
        } else if result.neckTracked && !result.neckOk {
            result.issue = .neckBad
        } else {
            result.issue = .correct
        }

        return result
    }

    // MARK: - Phase & rep counting state machine
    private func updatePhaseAndReps(smoothedResult: PushUpResult) {
        let elbowAngle = smoothedResult.elbowAngle
        let prev       = lastElbowAngle
        var nextPhase  = currentPhase
        var addRep     = false

        if currentPhase == .descending || currentPhase == .bottom || currentPhase == .ascending {
            if !smoothedResult.hipOk   { hipErrorFrames += 1   } else { hipErrorFrames   = max(0, hipErrorFrames - 1)   }
            if !smoothedResult.spineOk { spineErrorFrames += 1 } else { spineErrorFrames = max(0, spineErrorFrames - 1) }
            if smoothedResult.neckTracked {
                if smoothedResult.neckAngle < neckErrorMin { neckErrorFrames += 1 } else { neckErrorFrames = max(0, neckErrorFrames - 1) }
            }
            if hipErrorFrames   >= 3 { hadHipError   = true }
            if spineErrorFrames >= 3 { hadSpineError = true }
            if neckErrorFrames  >= 3 { hadNeckError  = true }
        }

        if elbowAngle < elbowDescentTrigger && prev > elbowAngle && !pushUpStarted {
            nextPhase     = .descending
            pushUpStarted = true
        }

        if elbowAngle < minElbowAngle { minElbowAngle = elbowAngle }

        if elbowAngle <= elbowDepthMax {
            validDepthFrames += 1
            if validDepthFrames >= depthFramesRequired { depthReached = true }
        } else if elbowAngle > (elbowDepthMax + 8) && !depthReached {
            validDepthFrames = 0
        }

        let startedRising = depthReached && elbowAngle > (minElbowAngle + 4)
        if startedRising && !bottomReached {
            validBottomFrames += 1
            if validBottomFrames >= 3 { nextPhase = .bottom; bottomReached = true }
        } else if !depthReached {
            validBottomFrames = 0
        }

        if bottomReached && elbowAngle > (prev + 2) && elbowAngle < elbowUpMin {
            nextPhase = .ascending
        }

        if elbowAngle < elbowUpMin { validStandingFrames = 0 }

        if pushUpStarted && elbowAngle >= elbowUpMin {
            validStandingFrames += 1
            if validStandingFrames >= standingFramesRequired {
                let hadRealDescent = minElbowAngle <= elbowMinimumDescent
                if hadRealDescent {
                    if depthReached {
                        let formWasGood = !hadHipError && !hadSpineError && !hadNeckError
                        if formWasGood {
                            addRep = true
                            triggerGoodRepFeedback(score: smoothedResult.postureScore)
                        } else {
                            triggerBadRepFeedback()
                        }
                    } else {
                        triggerBadRepFeedback()
                    }
                }
                nextPhase = .standing
                pushUpStarted = false; depthReached = false; bottomReached = false
                validStandingFrames = 0; validBottomFrames = 0
                validDepthFrames    = 0; minElbowAngle     = 180
                hipErrorFrames  = 0; spineErrorFrames  = 0; neckErrorFrames = 0
                hadHipError     = false; hadSpineError = false; hadNeckError  = false
            }
        }

        lastElbowAngle = elbowAngle
        let scoreSnapshot = smoothedResult.postureScore

        DispatchQueue.main.async {
            if addRep {
                self.reps             += 1
                self.repsInCurrentSet += 1
                self.totalRepsAllTime += 1
                self.speakRepCount(self.repsInCurrentSet)

                if self.targetReps > 0 && self.repsInCurrentSet >= self.targetReps {
                    if self.currentSet < self.targetSets {
                        self.speakText("Set \(self.currentSet) complete!")
                        self.currentSet       += 1
                        self.repsInCurrentSet  = 0
                        self.fireWatchNotification(
                            title: "✅ Set Complete",
                            body:  "Rest, then start set \(self.currentSet)."
                        )
                    } else {
                        self.speakText("Workout complete! Great job!")
                        self.fireWatchNotification(
                            title: "🎉 Workout Complete!",
                            body:  "You finished all \(self.targetSets) sets."
                        )
                    }
                }

                let record = RepRecord(
                    repNumber: self.totalRepsAllTime,
                    score:     scoreSnapshot,
                    isGood:    true,
                    timestamp: Date()
                )
                self.repHistory.append(record)
                self.updateScoreStats()
            }

            self.currentPhase = nextPhase
            switch nextPhase {
            case .standing:   self.phaseText = "Up";          self.phaseColor = .white
            case .descending: self.phaseText = "Going Down";  self.phaseColor = .yellow
            case .bottom:     self.phaseText = "Deep ✅";     self.phaseColor = .green
            case .ascending:  self.phaseText = "Coming Up";   self.phaseColor = .blue
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

    // MARK: - Feedback
    private func triggerGoodRepFeedback(score: Int) {
        DispatchQueue.main.async {
            self.showGoodRepFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.showGoodRepFlash = false }
        }
    }

    private func triggerBadRepFeedback() {
        var reasons: [String] = []
        if hadSpineError { reasons.append("Keep body straight") }
        if hadHipError   { reasons.append("Hips sagging") }
        if hadNeckError  { reasons.append("Head dropping") }
        if !depthReached { reasons.append("Go lower") }
        if reasons.isEmpty { reasons.append("Check your form") }
        let message = "⚠️ Rep Not Counted\n" + reasons.joined(separator: " • ")

        if hadSpineError      { speakText("Keep your body straight") }
        else if hadHipError   { speakText("Keep your hips up") }
        else if hadNeckError  { speakText("Keep your head neutral") }
        else                  { speakText("Go lower next time") }

        fireWatchNotification(title: "❌ Bad Rep!", body: reasons.joined(separator: " • "))

        DispatchQueue.main.async {
            self.badRepMessage = message
            let record = RepRecord(
                repNumber: self.totalRepsAllTime + 1,
                score:     0,
                isGood:    false,
                timestamp: Date()
            )
            self.repHistory.append(record)
            self.totalRepsAllTime += 1
            self.badReps          += 1
            self.updateScoreStats()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.badRepMessage = nil }
        }
    }

    private func speakFormCue(result: PushUpResult) {
        guard currentPhase == .descending || currentPhase == .bottom else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSpeechTime) > 3.0 else { return }
        var cue: String? = nil
        if !result.spineOk                           { cue = "Keep your body straight" }
        else if !result.hipOk                        { cue = "Keep your hips up" }
        else if result.neckTracked && !result.neckOk { cue = "Keep your head neutral" }
        else if !result.elbowOk && currentPhase == .descending { cue = "Go lower" }
        guard let text = cue, result.issue != lastSpokenIssue else { return }
        lastSpokenIssue = result.issue
        lastSpeechTime  = now
        let u = AVSpeechUtterance(string: text); u.rate = 0.5; u.volume = 0.9
        DispatchQueue.main.async { self.speechSynth.speak(u) }
    }

    private func updateFormAlert(result: PushUpResult) {
        guard currentPhase == .descending || currentPhase == .bottom else {
            DispatchQueue.main.async { self.showFormAlert = false }
            return
        }
        var message: String? = nil
        if !result.spineOk                           { message = "Keep Your Body Straight!" }
        else if !result.hipOk                        { message = "Raise Your Hips — They're Sagging!" }
        else if result.neckTracked && !result.neckOk { message = "Keep Your Head Neutral!" }

        if let msg = message {
            fireWatchNotification(title: "⚠️ Fix Your Form", body: msg)
            speakFormCue(result: result)
        }

        DispatchQueue.main.async {
            if let msg = message {
                self.formAlertMessage = msg
                self.showFormAlert    = true
                self.alertTimer?.invalidate()
                self.alertTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    DispatchQueue.main.async { self.showFormAlert = false }
                }
            } else {
                self.showFormAlert = false
            }
        }
    }

    // MARK: - Watch notification
    func fireWatchNotification(title: String, body: String) {
        let now = Date()
        if let last = lastNotifTime[title], now.timeIntervalSince(last) < notifCooldown { return }
        lastNotifTime[title] = now
        NotificationManager.shared.send(title: title, body: body)
        WatchConnectivityManager.shared.sendFormAlert(exercise: "Push-Up", issue: "\(title): \(body)")
    }

    // MARK: - Helpers
    private func betterSide(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        let lS = points[.leftShoulder]?.confidence  ?? 0
        let lE = points[.leftElbow]?.confidence     ?? 0
        let lW = points[.leftWrist]?.confidence     ?? 0
        let lH = points[.leftHip]?.confidence       ?? 0
        let lK = points[.leftKnee]?.confidence      ?? 0
        let rS = points[.rightShoulder]?.confidence ?? 0
        let rE = points[.rightElbow]?.confidence    ?? 0
        let rW = points[.rightWrist]?.confidence    ?? 0
        let rH = points[.rightHip]?.confidence      ?? 0
        let rK = points[.rightKnee]?.confidence     ?? 0
        let leftTotal:  Float = lS + lE + lW + lH + lK
        let rightTotal: Float = rS + rE + rW + rH + rK
        return leftTotal >= rightTotal
    }

    private func updateBodyPoints(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        var mapped: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (joint, point) in points where point.confidence > 0.3 {
            mapped[joint] = CGPoint(x: point.location.x, y: 1 - point.location.y)
        }
        pointsBuffer.append(mapped)
        if pointsBuffer.count > 6 { pointsBuffer.removeFirst() }

        var smoothed: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        let allJoints = Set(pointsBuffer.flatMap { $0.keys })
        for joint in allJoints {
            let positions = pointsBuffer.compactMap { $0[joint] }
            guard !positions.isEmpty else { continue }
            let n = CGFloat(positions.count)
            smoothed[joint] = CGPoint(
                x: positions.map(\.x).reduce(0, +) / n,
                y: positions.map(\.y).reduce(0, +) / n
            )
        }
        DispatchQueue.main.async { self.bodyPoints = smoothed }
    }

    private func calculateAngle(first: CGPoint, middle: CGPoint, last: CGPoint) -> Double {
        let a = atan2(first.y  - middle.y, first.x  - middle.x)
        let b = atan2(last.y   - middle.y, last.x   - middle.x)
        var angle = abs((a - b) * 180 / .pi)
        if angle > 180 { angle = 360 - angle }
        return angle
    }

    private func smoothResult(_ result: PushUpResult) -> PushUpResult {
        frameBuffer.append(result)
        if frameBuffer.count > 8 { frameBuffer.removeFirst() }
        let n = Double(frameBuffer.count)
        var s = result
        s.elbowAngle   = frameBuffer.map(\.elbowAngle).reduce(0,  +) / n
        s.hipAngle     = frameBuffer.map(\.hipAngle).reduce(0,    +) / n
        s.spineAngle   = frameBuffer.map(\.spineAngle).reduce(0,  +) / n
        s.neckAngle    = frameBuffer.map(\.neckAngle).reduce(0,   +) / n
        s.postureScore = Int(Double(frameBuffer.map(\.postureScore).reduce(0, +)) / n)
        s.trackedLeftSide = result.trackedLeftSide
        s.neckTracked     = result.neckTracked
        let saggingCount = frameBuffer.filter { $0.spineSagging }.count
        s.spineSagging = saggingCount > frameBuffer.count / 2
        return s
    }

    // MARK: - Speech
    private func speakRepCount(_ count: Int) {
        let u = AVSpeechUtterance(string: "\(count)")
        u.rate = 0.55; u.volume = 1.0
        DispatchQueue.main.async { self.speechSynth.speak(u) }
    }

    private func speakText(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = 0.5; u.volume = 1.0
        DispatchQueue.main.async { self.speechSynth.speak(u) }
    }
}
