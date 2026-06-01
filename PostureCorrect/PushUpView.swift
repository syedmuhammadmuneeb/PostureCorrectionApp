//
//  PushUpView.swift
//  PostureCorrect
//
//  Camera placement: SIDE-ON — phone level with the user's chest/shoulder,
//  ~1.5–2 m away. Full body (wrist → elbow → shoulder → hip → knee) visible.
//
//  ─────────────────────────────────────────────────────────────────────────
//  PUSH-UP ANGLES  (biomechanically correct)
//  ─────────────────────────────────────────────────────────────────────────
//
//  1. Elbow angle (shoulder → elbow → wrist)
//     Start (high plank): ~160°–180° (arms nearly straight)
//     Bottom (chest near floor): 70°–110° — the key depth check
//     < 70°  = elbows flared / going too deep
//     > 110° = not going low enough
//
//  2. Hip angle (shoulder → hip → knee)
//     Should stay ~155°–180° throughout — body in a straight line.
//     < 155° = hips sagging toward the floor
//     > 180° = hips piked up
//
//  3. Spine angle (deviation of shoulder→hip line from horizontal)
//     Body parallel to floor = ~0°. Should stay ≤ 20°.
//     > 20°  = back arching or hips rotating
//
//  ─────────────────────────────────────────────────────────────────────────
//  REP STATE MACHINE (three-gate)
//  ─────────────────────────────────────────────────────────────────────────
//  Gate 1: elbowAngle < descentTrigger (155°) → rep starts
//  Gate 2: elbowAngle ≤ bottomMax (110°) for 3 frames → bottom confirmed
//  Gate 3: elbowAngle ≥ topMin (150°) for 3 frames → evaluate & count
//
//  Form errors (spine, hip, elbow) are latched with decay counters.
//  A rep only counts if ALL three error latches are clear at Gate 3.
//

import SwiftUI
import AVFoundation
import Vision
import Combine
import AVKit

// MARK: - PUSH-UP ISSUE
enum PushupIssue: String {
    case correct      = "✅ Perfect Push-up"
    case ready        = "🧍 Ready Position"
    case notLowEnough = "❌ Go Lower"
    case backSagging  = "❌ Keep Back Straight"
    case hipsTooHigh  = "❌ Lower Your Hips"
    case detecting    = "🔍 Detecting..."
    case notVisible   = "📷 Full Body Not Visible"
}

// MARK: - PUSH-UP PHASE
enum PushupPhase { case high, descending, bottom, ascending }

// MARK: - REP RECORD
struct PushupRepRecord: Identifiable {
    let id        = UUID()
    let repNumber: Int
    let score:     Int
    let isGood:    Bool
    let timestamp: Date
}

// MARK: - PUSH-UP RESULT
struct PushupResult {
    var issue: PushupIssue = .detecting
    var postureScore: Int  = 100
    var elbowAngle: Double = 180
    var hipAngle:   Double = 180
    var spineAngle: Double = 0
    var trackedLeftSide: Bool = true
    var elbowOk = true
    var hipOk   = true
    var spineOk = true
    var formIsValid: Bool { elbowOk && hipOk && spineOk }
}

// MARK: - CAMERA VIEW
struct PushupCameraView: View {
    @StateObject private var viewModel = PushupViewModel()
    @State private var showGoalSheet   = false
    @State private var showStatsSheet  = false

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.session).ignoresSafeArea()

            PushupSkeletonOverlay(
                bodyPoints: viewModel.bodyPoints,
                result:     viewModel.postureResult
            ).ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if viewModel.showFormAlert {
                    PushupAlertBanner(message: viewModel.formAlertMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4), value: viewModel.showFormAlert)
                }
                Spacer()
                bottomPanel
            }

            // Bad rep flash
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

            // Good rep green flash
            if viewModel.showGoodRepFlash {
                Color.green.opacity(0.2).ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .onAppear    { viewModel.start() }
        .onDisappear { viewModel.stop()  }
        .sheet(isPresented: $showGoalSheet)  { PushupGoalSheet(viewModel: viewModel) }
        .sheet(isPresented: $showStatsSheet) { PushupStatsSheet(viewModel: viewModel) }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Push-up AI").font(.title2.bold()).foregroundColor(.white)
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
                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.postureResult.postureScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 58, height: 58).rotationEffect(.degrees(-90))
                Text("\(viewModel.postureResult.postureScore)").font(.headline.bold()).foregroundColor(.white)
            }
        }
        .padding().background(.black.opacity(0.65)).cornerRadius(20).padding()
    }

    // MARK: - Bottom panel
    private var bottomPanel: some View {
        VStack(spacing: 14) {
            Text(viewModel.badRepMessage ?? viewModel.postureResult.issue.rawValue)
                .font(.title2.bold())
                .foregroundColor(viewModel.badRepMessage != nil ? .orange : .white)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.2), value: viewModel.badRepMessage)

            HStack(spacing: 10) {
                PushupAngleCard(title: "Elbow", angle: viewModel.postureResult.elbowAngle,
                                isOk: viewModel.postureResult.elbowOk, idealRange: "70°-110°")
                PushupAngleCard(title: "Hip",   angle: viewModel.postureResult.hipAngle,
                                isOk: viewModel.postureResult.hipOk,   idealRange: "155°-180°")
                PushupAngleCard(title: "Back",  angle: viewModel.postureResult.spineAngle,
                                isOk: viewModel.postureResult.spineOk, idealRange: "0°-20°")
            }

            if viewModel.targetReps > 0 {
                PushupProgressBarView(
                    currentSet:  viewModel.currentSet,
                    totalSets:   viewModel.targetSets,
                    repsInSet:   viewModel.repsInCurrentSet,
                    targetReps:  viewModel.targetReps
                )
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
        let s = viewModel.postureResult.postureScore
        if s >= 80 { return .green }
        if s >= 55 { return .yellow }
        return .red
    }
}

// MARK: - SUPPORTING VIEWS

struct PushupProgressBarView: View {
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
                    RoundedRectangle(cornerRadius: 6).fill(Color.blue)
                        .frame(width: geo.size.width * CGFloat(min(repsInSet, targetReps)) / CGFloat(max(targetReps, 1)),
                               height: 10)
                        .animation(.spring(response: 0.3), value: repsInSet)
                }
            }.frame(height: 10)
        }.padding(.horizontal, 4)
    }
}

struct PushupAlertBanner: View {
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

struct PushupAngleCard: View {
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

struct PushupGoalSheet: View {
    @ObservedObject var viewModel: PushupViewModel
    @Environment(\.dismiss) var dismiss
    @State private var sets = 3
    @State private var reps = 10
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
                        viewModel.setGoal(sets: sets, reps: reps, restSeconds: restSec)
                        dismiss()
                    }.foregroundColor(.green).bold()
                    Button("Clear Goal") { viewModel.clearGoal(); dismiss() }.foregroundColor(.red)
                }
            }
            .navigationTitle("Set Goal")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct PushupStatsSheet: View {
    @ObservedObject var viewModel: PushupViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        PushupStatCard(title: "Total Reps", value: "\(viewModel.totalRepsAllTime)", color: .blue)
                        PushupStatCard(title: "Good Reps",  value: "\(viewModel.goodReps)",         color: .green)
                        PushupStatCard(title: "Bad Reps",   value: "\(viewModel.badReps)",          color: .red)
                    }
                    HStack(spacing: 12) {
                        PushupStatCard(title: "Avg Score",    value: "\(viewModel.averageScore)",  color: .yellow)
                        PushupStatCard(title: "Best Score",   value: "\(viewModel.bestRepScore)",  color: .orange)
                        PushupStatCard(title: "Session Time", value: viewModel.sessionTimeString, color: .cyan)
                    }

                    if !viewModel.repHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Rep Score History").font(.headline).padding(.horizontal)
                            PushupRepScoreGraph(records: viewModel.repHistory).frame(height: 180).padding(.horizontal)
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
                        Text("No reps recorded yet.\nStart pushing! 💪")
                            .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.top, 40)
                    }
                }.padding(.vertical)
            }
            .navigationTitle("Session Stats")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct PushupStatCard: View {
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

struct PushupRepScoreGraph: View {
    let records: [PushupRepRecord]
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
struct PushupSkeletonOverlay: View {
    let bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let result: PushupResult

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let s: VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftShoulder : .rightShoulder
                let e: VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftElbow    : .rightElbow
                let w: VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftWrist    : .rightWrist
                let h: VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftHip      : .rightHip
                let k: VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftKnee     : .rightKnee

                drawLine(s, e, geo, ok: result.elbowOk)
                drawLine(e, w, geo, ok: result.elbowOk)
                drawLine(s, h, geo, ok: result.spineOk)
                drawLine(h, k, geo, ok: result.hipOk)

                ForEach([s, e, w, h, k], id: \.self) { joint in
                    if let pt = bodyPoints[joint] {
                        Circle().fill(dotColor(for: joint)).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                            .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                    }
                }
            }
        }
    }

    private func dotColor(for joint: VNHumanBodyPoseObservation.JointName) -> Color {
        switch joint {
        case .leftShoulder, .rightShoulder: return result.spineOk ? .green : .red
        case .leftElbow,    .rightElbow:    return result.elbowOk ? .green : .red
        case .leftWrist,    .rightWrist:    return result.elbowOk ? .green : .red
        case .leftHip,      .rightHip:      return result.hipOk   ? .green : .red
        case .leftKnee,     .rightKnee:     return result.hipOk   ? .green : .red
        default:                            return .white
        }
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
final class PushupViewModel: NSObject, ObservableObject,
                              AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    @Published var bodyPoints:    [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var postureResult  = PushupResult()
    @Published var currentPhase:  PushupPhase = .high
    @Published var phaseText      = "High Position"
    @Published var phaseColor: Color = .white
    @Published var cameraPosition: AVCaptureDevice.Position = .back

    @Published var showFormAlert    = false
    @Published var formAlertMessage = ""
    @Published var showBadRepFlash  = false
    @Published var badRepReason     = ""
    @Published var showGoodRepFlash = false
    @Published var badRepMessage: String? = nil

    // Analytics
    @Published var repHistory:       [PushupRepRecord] = []
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
    private let elbowDescentTrigger: Double = 155  // arm starts bending past this
    private let elbowBottomMax:      Double = 110  // must reach this depth
    private let elbowBottomIdealMin: Double = 70   // ideal bottom range
    private let elbowBottomIdealMax: Double = 110
    private let elbowTopMin:         Double = 150  // must return to this to close rep
    private let hipAngleMin:         Double = 155  // body straight lower bound
    private let hipAngleMax:         Double = 185  // body straight upper bound
    private let spineAngleMax:       Double = 20   // max torso tilt from horizontal

    // ── Smoothing ─────────────────────────────────────────────────────────────
    private var angleBuffer: [(elbow: Double, hip: Double, spine: Double)] = []
    private let bufferSize = 6

    // ── Rep state (three-gate) ────────────────────────────────────────────────
    private var repInProgress  = false
    private var bottomReached  = false
    private var minElbowSeen   = 180.0
    private var framesAtBottom = 0
    private var framesAtTop    = 0

    // Error accumulators — decay on clean frames so single noisy frames don't latch
    private var spineErrFrames = 0; private var hadSpineError = false
    private var hipErrFrames   = 0; private var hadHipError   = false
    private var elbowErrFrames = 0; private var hadElbowError = false

    // ── Debounce ──────────────────────────────────────────────────────────────
    private var stableIssueFrames = 0
    private var lastIssue: PushupIssue = .detecting
    private var alertTimer: Timer?

    // Speech
    private let speechSynth     = AVSpeechSynthesizer()
    private var lastSpokenIssue: PushupIssue = .detecting
    private var lastSpeechTime:  Date = .distantPast

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
        fireWatchNotification(title: "💪 Push-up Started",
                              body: "Get into high plank position.")
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
            self.repInProgress = false; self.bottomReached = false; self.minElbowSeen = 180
            self.framesAtBottom = 0; self.framesAtTop = 0
            self.spineErrFrames = 0; self.hipErrFrames = 0; self.elbowErrFrames = 0
            self.hadSpineError = false; self.hadHipError = false; self.hadElbowError = false
            self.currentPhase = .high; self.phaseText = "High Position"; self.phaseColor = .white
            self.isResting = false; self.restTimer?.invalidate()
            self.sessionStartDate = Date()
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
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "pushupVideoQueue"))
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
                DispatchQueue.main.async { self.postureResult.issue = .notVisible }; return
            }
            let s = smooth(result)
            result.elbowAngle = s.elbow; result.hipAngle = s.hip; result.spineAngle = s.spine
            evaluateForm(result: &result)
            updatePhaseAndReps(result: result)

            if result.issue == lastIssue { stableIssueFrames += 1 }
            else { stableIssueFrames = 0; lastIssue = result.issue }
            var published = result
            if stableIssueFrames < 3 { published.issue = postureResult.issue }

            // Form alert uses raw result (not debounced) for immediate feedback
            updateFormAlert(result: result)
            speakFormCue(result: result)
            DispatchQueue.main.async { self.postureResult = published }
        } catch { print("Pushup Vision error: \(error)") }
    }

    // MARK: - Angle extraction
    private func extractAngles(from pts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint])
        -> PushupResult? {
        let lSh: Float = pts[.leftShoulder]?.confidence ?? 0
        let lEl: Float = pts[.leftElbow]?.confidence    ?? 0
        let lWr: Float = pts[.leftWrist]?.confidence    ?? 0
        let lHp: Float = pts[.leftHip]?.confidence      ?? 0
        let lKn: Float = pts[.leftKnee]?.confidence     ?? 0
        let rSh: Float = pts[.rightShoulder]?.confidence ?? 0
        let rEl: Float = pts[.rightElbow]?.confidence    ?? 0
        let rWr: Float = pts[.rightWrist]?.confidence    ?? 0
        let rHp: Float = pts[.rightHip]?.confidence      ?? 0
        let rKn: Float = pts[.rightKnee]?.confidence     ?? 0
        let lC = lSh + lEl + lWr + lHp + lKn
        let rC = rSh + rEl + rWr + rHp + rKn
        let useLeft = lC >= rC

        let sK: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder
        let eK: VNHumanBodyPoseObservation.JointName = useLeft ? .leftElbow    : .rightElbow
        let wK: VNHumanBodyPoseObservation.JointName = useLeft ? .leftWrist    : .rightWrist
        let hK: VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let kK: VNHumanBodyPoseObservation.JointName = useLeft ? .leftKnee     : .rightKnee

        for j in [sK, eK, wK, hK, kK] {
            guard let p = pts[j], p.confidence > 0.4 else { return nil }
        }

        let sh = pts[sK]!.location; let el = pts[eK]!.location
        let wr = pts[wK]!.location; let hp = pts[hK]!.location; let kn = pts[kK]!.location

        var result = PushupResult(); result.trackedLeftSide = useLeft
        result.elbowAngle = calculateAngle(first: sh, middle: el, last: wr)
        result.hipAngle   = calculateAngle(first: sh, middle: hp, last: kn)
        let raw           = atan2(sh.y - hp.y, sh.x - hp.x) * 180 / .pi
        result.spineAngle = min(abs(raw), 90)
        return result
    }

    // MARK: - Form evaluation
    private func evaluateForm(result: inout PushupResult) {
        // If arms straight → person is in high plank / ready position
        guard result.elbowAngle < elbowDescentTrigger else {
            result.elbowOk = true; result.hipOk = true; result.spineOk = true
            result.issue = .ready; result.postureScore = 100; return
        }

        // Elbow: only check depth at the bottom; mid-rep is transitional
        let atBottom   = result.elbowAngle <= elbowBottomMax
        result.elbowOk = atBottom
            ? (result.elbowAngle >= elbowBottomIdealMin && result.elbowAngle <= elbowBottomIdealMax)
            : true

        // Hip and spine: checked throughout the entire rep
        result.hipOk   = result.hipAngle   >= hipAngleMin && result.hipAngle   <= hipAngleMax
        result.spineOk = result.spineAngle <= spineAngleMax

        var score = 100
        if !result.elbowOk { score -= 30 }
        if !result.hipOk   { score -= 35 }
        if !result.spineOk { score -= 35 }
        result.postureScore = max(score, 0)

        // Issue label: most critical first
        if !result.spineOk      { result.issue = .backSagging }
        else if !result.hipOk   { result.issue = .hipsTooHigh }
        else if !result.elbowOk { result.issue = .notLowEnough }
        else                    { result.issue = .correct }
    }

    // MARK: - Rep state machine
    private func updatePhaseAndReps(result: PushupResult) {
        let elbow = result.elbowAngle

        if repInProgress {
            if !result.spineOk { spineErrFrames += 1 } else { spineErrFrames = max(0, spineErrFrames - 1) }
            if !result.hipOk   { hipErrFrames   += 1 } else { hipErrFrames   = max(0, hipErrFrames   - 1) }
            if elbow <= elbowBottomMax && !result.elbowOk {
                elbowErrFrames += 1
            } else { elbowErrFrames = max(0, elbowErrFrames - 1) }
            if spineErrFrames >= 3 { hadSpineError = true }
            if hipErrFrames   >= 3 { hadHipError   = true }
            if elbowErrFrames >= 3 { hadElbowError = true }
            minElbowSeen = min(minElbowSeen, elbow)
        }

        var nextPhase = currentPhase; var addRep = false; var badRep = false

        // Gate 1: arm starts bending
        if !repInProgress && elbow < elbowDescentTrigger {
            repInProgress = true; minElbowSeen = elbow
            framesAtBottom = 0; framesAtTop = 0; nextPhase = .descending
        }

        // Gate 2: bottom reached
        if repInProgress && elbow <= elbowBottomMax {
            framesAtBottom += 1
            if framesAtBottom >= 3 { bottomReached = true; nextPhase = .bottom }
        } else if repInProgress { framesAtBottom = max(0, framesAtBottom - 1) }

        // Ascending
        if bottomReached && elbow > elbowBottomMax && elbow < elbowTopMin { nextPhase = .ascending }

        // Gate 3: arms return to top
        if repInProgress && elbow >= elbowTopMin {
            framesAtTop += 1
            if framesAtTop >= 3 {
                if bottomReached {
                    let goodForm = !hadSpineError && !hadHipError && !hadElbowError
                    if goodForm {
                        addRep = true
                        triggerGoodRepFeedback(score: result.postureScore)
                    } else { badRep = true }
                } else { badRep = true }
                repInProgress = false; bottomReached = false; minElbowSeen = 180
                framesAtBottom = 0; framesAtTop = 0
                spineErrFrames = 0; hipErrFrames = 0; elbowErrFrames = 0
                hadSpineError = false; hadHipError = false; hadElbowError = false
                nextPhase = .high
            }
        } else { if elbow < elbowTopMin { framesAtTop = 0 } }

        let scoreSnap = result.postureScore
        let reasons   = buildBadRepReasons()

        DispatchQueue.main.async {
            if addRep {
                self.reps += 1
                self.repsInCurrentSet += 1
                self.totalRepsAllTime += 1
                self.speakRepCount(self.repsInCurrentSet)

                if self.targetReps > 0 && self.repsInCurrentSet >= self.targetReps {
                    if self.currentSet < self.targetSets {
                        self.speakText("Set \(self.currentSet) complete! Rest now.")
                        self.startRestTimer()
                        self.currentSet += 1; self.repsInCurrentSet = 0
                    } else {
                        self.speakText("Workout complete! Great job!")
                        self.fireWatchNotification(
                            title: "🎉 Workout Complete!",
                            body:  "You finished all \(self.targetSets) sets!"
                        )
                    }
                }

                let record = PushupRepRecord(repNumber: self.totalRepsAllTime,
                                             score: scoreSnap, isGood: true, timestamp: Date())
                self.repHistory.append(record)
                self.updateScoreStats()
            }
            if badRep { self.triggerBadRepFeedback(reasons: reasons) }

            self.currentPhase = nextPhase
            switch nextPhase {
            case .high:       self.phaseText = "High Position";    self.phaseColor = .white
            case .descending: self.phaseText = "Going Down";       self.phaseColor = .yellow
            case .bottom:     self.phaseText = "Perfect Depth ✅"; self.phaseColor = .green
            case .ascending:  self.phaseText = "Pushing Up";       self.phaseColor = .blue
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
                    self.speakText("Go!")
                }
            }
        }
    }

    // MARK: - Feedback
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
            let record = PushupRepRecord(repNumber: self.totalRepsAllTime + 1,
                                         score: 0, isGood: false, timestamp: Date())
            self.repHistory.append(record)
            self.totalRepsAllTime += 1
            self.updateScoreStats()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.badRepMessage = nil }
        }
    }

    private func buildBadRepReasons() -> String {
        var r: [String] = []
        if hadSpineError  { r.append("Back not straight") }
        if hadHipError    { r.append("Hips sagging/high") }
        if hadElbowError  { r.append("Elbow angle off") }
        if !bottomReached { r.append("Go lower next time") }
        return r.isEmpty ? "Go lower next time" : r.joined(separator: " • ")
    }

    // MARK: - Form alert (live corrections, same as squats)
    private func updateFormAlert(result: PushupResult) {
        guard currentPhase == .descending || currentPhase == .bottom else {
            DispatchQueue.main.async { self.showFormAlert = false }; return
        }
        var message: String? = nil
        if !result.spineOk    { message = "Keep Your Back Straight!" }
        else if !result.hipOk { message = "Keep Hips Level!" }

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
    private func speakFormCue(result: PushupResult) {
        guard currentPhase == .descending || currentPhase == .bottom else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSpeechTime) > 3.0 else { return }
        var cue: String? = nil
        if !result.spineOk    { cue = "Keep your back straight" }
        else if !result.hipOk { cue = "Keep your hips level" }
        if let text = cue, result.issue != lastSpokenIssue {
            lastSpokenIssue = result.issue; lastSpeechTime = now
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
        WatchConnectivityManager.shared.sendFormAlert(exercise: "Push-up", issue: "\(title): \(body)")
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
        let a = atan2(first.y - middle.y, first.x - middle.x)
        let b = atan2(last.y  - middle.y, last.x  - middle.x)
        var angle = abs((a - b) * 180 / .pi)
        if angle > 180 { angle = 360 - angle }
        return angle
    }

    private func smooth(_ r: PushupResult) -> (elbow: Double, hip: Double, spine: Double) {
        angleBuffer.append((r.elbowAngle, r.hipAngle, r.spineAngle))
        if angleBuffer.count > bufferSize { angleBuffer.removeFirst() }
        let n = Double(angleBuffer.count)
        return (angleBuffer.map(\.elbow).reduce(0,+) / n,
                angleBuffer.map(\.hip).reduce(0,+)   / n,
                angleBuffer.map(\.spine).reduce(0,+) / n)
    }
}
