//
//  SquatView.swift
//  PostureCorrect
//
//  Camera placement: SIDE-ON — phone level with the user's hips, ~2 m away.
//  Logic from uploaded working code — preserved exactly.
//  Watch notifications added at all three key moments.
//

import SwiftUI
import AVFoundation
import Vision
import Combine
import AVKit

// MARK: - SQUAT ISSUE
enum SquatIssue: String {
    case correct         = "✅ Perfect Squat"
    case ready           = "🧍 Ready to Squat"
    case kneesNotDeep    = "❌ Go Lower"
    case backNotStraight = "❌ Keep Back Straight"
    case hipTooHigh      = "❌ Lower Your Hips"
    case kneesOverToes   = "❌ Knees Too Forward"
    case detecting       = "🔍 Detecting..."
    case notVisible      = "📷 Full Body Not Visible"
    case improperDepth   = "⚠️ Go Deeper Next Time"
}

// MARK: - SQUAT PHASE
enum SquatPhase { case standing, descending, bottom, ascending }

// MARK: - REP RECORD
struct RepRecord: Identifiable {
    let id        = UUID()
    let repNumber: Int
    let score:     Int
    let isGood:    Bool
    let timestamp: Date
}

// MARK: - SQUAT RESULT
struct SquatResult {
    var issue: SquatIssue = .detecting
    var postureScore: Int = 100
    var kneeAngle:      Double = 180
    var hipAngle:       Double = 180
    var spineAngle:     Double = 0
    var kneeToeOffset:  Double = 0
    var trackedLeftSide: Bool  = true
    var kneeOk:  Bool = true
    var hipOk:   Bool = true
    var spineOk: Bool = true
    var ankleOk: Bool = true
    var formIsValid: Bool { kneeOk && hipOk && spineOk && ankleOk }
}

// MARK: - CAMERA VIEW
struct SquatCameraView: View {
    @StateObject private var viewModel = SquatViewModel()
    @State private var showGoalSheet   = false
    @State private var showStatsSheet  = false

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.session).ignoresSafeArea()

            SquatSkeletonOverlay(
                bodyPoints: viewModel.bodyPoints,
                result:     viewModel.postureResult
            ).ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if viewModel.showFormAlert {
                    SquatFormAlertBanner(message: viewModel.formAlertMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4), value: viewModel.showFormAlert)
                }
                Spacer()

                if viewModel.isResting {
                    SquatRestTimerView(secondsLeft: viewModel.restSecondsLeft)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(), value: viewModel.isResting)
                }

                bottomPanel
            }

            if viewModel.showGoodRepFlash {
                Color.green.opacity(0.2).ignoresSafeArea().allowsHitTesting(false)
            }

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
        .sheet(isPresented: $showGoalSheet)  { SquatGoalSetupSheet(viewModel: viewModel) }
        .sheet(isPresented: $showStatsSheet) { SquatStatsSheet(viewModel: viewModel) }
    }

    // MARK: - Top bar (minimal floating pill)
    private var topBar: some View {
        HStack(spacing: 8) {
            Text(viewModel.sessionTimeString)
                .font(.caption.monospacedDigit().bold())
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.5)).cornerRadius(20)

            Spacer()

            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 3).frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.postureResult.postureScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 40, height: 40).rotationEffect(.degrees(-90))
                Text("\(viewModel.postureResult.postureScore)")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            }

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

            // Issue label + phase pill
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

            // Angle chips
            HStack(spacing: 6) {
                SquatAngleChip(label: "Knee",  angle: viewModel.postureResult.kneeAngle,  isOk: viewModel.postureResult.kneeOk)
                SquatAngleChip(label: "Hip",   angle: viewModel.postureResult.hipAngle,   isOk: viewModel.postureResult.hipOk)
                SquatAngleChip(label: "Back",  angle: viewModel.postureResult.spineAngle, isOk: viewModel.postureResult.spineOk)
                SquatAngleChip(label: "Ankle", angle: abs(viewModel.postureResult.kneeToeOffset * 100),
                               isOk: viewModel.postureResult.ankleOk, unit: "")
            }

            // Progress bar (only when goal is set)
            if viewModel.targetReps > 0 {
                SquatProgressBarView(
                    currentSet:  viewModel.currentSet,
                    totalSets:   viewModel.targetSets,
                    repsInSet:   viewModel.repsInCurrentSet,
                    targetReps:  viewModel.targetReps
                )
            }

            // Rep count row
            HStack(alignment: .center, spacing: 0) {
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

                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 44)

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

// MARK: - SUPPORTING VIEWS

struct SquatAngleChip: View {
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

struct SquatProgressBarView: View {
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

struct SquatRestTimerView: View {
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

struct SquatFormAlertBanner: View {
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

struct SquatGoalSetupSheet: View {
    @ObservedObject var viewModel: SquatViewModel
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

struct SquatStatsSheet: View {
    @ObservedObject var viewModel: SquatViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        SquatStatCard(title: "Total Reps", value: "\(viewModel.totalRepsAllTime)", color: .blue)
                        SquatStatCard(title: "Good Reps",  value: "\(viewModel.goodReps)",         color: .green)
                        SquatStatCard(title: "Bad Reps",   value: "\(viewModel.badReps)",          color: .red)
                    }
                    HStack(spacing: 12) {
                        SquatStatCard(title: "Avg Score",    value: "\(viewModel.averageScore)",   color: .yellow)
                        SquatStatCard(title: "Best Score",   value: "\(viewModel.bestRepScore)",   color: .orange)
                        SquatStatCard(title: "Session Time", value: viewModel.sessionTimeString,   color: .cyan)
                    }

                    if !viewModel.repHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Rep Score History").font(.headline).padding(.horizontal)
                            SquatRepScoreGraph(records: viewModel.repHistory)
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
                        Text("No reps recorded yet.\nStart squatting! 💪")
                            .multilineTextAlignment(.center).foregroundColor(.secondary).padding(.top, 40)
                    }
                }.padding(.vertical)
            }
            .navigationTitle("Session Stats")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct SquatStatCard: View {
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

struct SquatRepScoreGraph: View {
    let records: [RepRecord]
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
struct SquatSkeletonOverlay: View {
    let bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let result: SquatResult

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let shoulder: VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftShoulder : .rightShoulder
                let hip:      VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftHip      : .rightHip
                let knee:     VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftKnee     : .rightKnee
                let ankle:    VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftAnkle    : .rightAnkle

                drawLine(shoulder, hip,   geo, ok: result.spineOk)
                drawLine(hip,      knee,  geo, ok: result.hipOk)
                drawLine(knee,     ankle, geo, ok: result.ankleOk)

                ForEach([shoulder, hip, knee, ankle], id: \.self) { joint in
                    if let point = bodyPoints[joint] {
                        Circle().fill(dotColor(for: joint)).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                            .position(x: point.x * geo.size.width, y: point.y * geo.size.height)
                    }
                }
            }
        }
    }

    private func dotColor(for joint: VNHumanBodyPoseObservation.JointName) -> Color {
        switch joint {
        case .leftShoulder, .rightShoulder: return result.spineOk ? .green : .red
        case .leftHip,      .rightHip:      return result.hipOk   ? .green : .red
        case .leftKnee,     .rightKnee:     return result.kneeOk  ? .green : .red
        case .leftAnkle,    .rightAnkle:    return result.ankleOk ? .green : .red
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
final class SquatViewModel: NSObject, ObservableObject,
                             AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    @Published var bodyPoints:    [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    private var pointsBuffer:     [[VNHumanBodyPoseObservation.JointName: CGPoint]] = []
    @Published var postureResult  = SquatResult()
    @Published var currentPhase: SquatPhase = .standing
    @Published var phaseText      = "Standing"
    @Published var phaseColor: Color = .white
    @Published var cameraPosition: AVCaptureDevice.Position = .back

    @Published var showFormAlert    = false
    @Published var formAlertMessage = ""
    @Published var showGoodRepFlash = false
    @Published var badRepMessage: String? = nil

    // Analytics
    @Published var repHistory:       [RepRecord] = []
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

    private var frameBuffer:        [SquatResult] = []
    private var lastKneeAngle:      Double = 180
    private var bottomReached       = false
    private var depthReached        = false
    private var squatStarted        = false
    private var validBottomFrames   = 0
    private var minKneeAngle        = 180.0
    private var validDepthFrames    = 0
    private var validStandingFrames = 0
    private var stableIssueFrames   = 0
    private var notVisibleFrames    = 0
    private var lastIssue: SquatIssue = .detecting
    private var alertTimer: Timer?

    private var spineErrorFrames = 0
    private var ankleErrorFrames = 0
    private var hipErrorFrames   = 0
    private var hadSpineError    = false
    private var hadHipError      = false
    private var hadAnkleError    = false
    private var hadKneeError     = false

    private let speechSynth     = AVSpeechSynthesizer()
    private var lastSpokenIssue: SquatIssue = .detecting
    private var lastSpeechTime:  Date = .distantPast

    private var lastNotifTime: [String: Date] = [:]
    private let notifCooldown: TimeInterval   = 5.0

    // MARK: - Start / Stop
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            DispatchQueue.global(qos: .userInitiated).async { self.setupCamera() }
        }
        startSessionTimer()
        fireWatchNotification(title: "🏋️ Ready for Squat!", body: "Get into position and begin.")
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

    func resetSession() {
        DispatchQueue.main.async {
            self.reps = 0; self.repsInCurrentSet = 0; self.currentSet = 1
            self.goodReps = 0; self.badReps = 0; self.totalRepsAllTime = 0
            self.averageScore = 0; self.bestRepScore = 0; self.repHistory = []
            self.bottomReached = false; self.depthReached = false; self.squatStarted = false
            self.currentPhase = .standing; self.phaseText = "Standing"; self.phaseColor = .white
            self.validBottomFrames = 0; self.validStandingFrames = 0
            self.spineErrorFrames = 0; self.ankleErrorFrames = 0; self.hipErrorFrames = 0
            self.hadSpineError = false; self.hadHipError = false
            self.hadAnkleError = false; self.hadKneeError = false
            self.isResting = false; self.restTimer?.invalidate()
            self.sessionStartDate = Date()
        }
    }

    private func resetSquatState() {
        bottomReached = false; depthReached = false; squatStarted = false
        validBottomFrames = 0; validStandingFrames = 0; lastKneeAngle = 180
        spineErrorFrames = 0; ankleErrorFrames = 0; hipErrorFrames = 0
        hadSpineError = false; hadHipError = false; hadAnkleError = false; hadKneeError = false
        frameBuffer = []; pointsBuffer = []
        DispatchQueue.main.async {
            self.currentPhase = .standing; self.phaseText = "Standing"; self.phaseColor = .white
        }
    }

    // MARK: - Camera
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
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "squatVideoQueue"))
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
        guard !isResting else { return }
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return }
            let points = try observation.recognizedPoints(.all)

            updateBodyPoints(points)
            let rawResult = analyzeSquatPosture(points)

            if rawResult.issue == .notVisible {
                notVisibleFrames += 1
                if notVisibleFrames >= 8 { DispatchQueue.main.async { self.postureResult = rawResult } }
                return
            } else { notVisibleFrames = 0 }

            var smoothed = smoothResult(rawResult)
            updatePhaseAndReps(smoothedResult: smoothed)

            if smoothed.issue == lastIssue { stableIssueFrames += 1 }
            else { stableIssueFrames = 0; lastIssue = smoothed.issue }
            if stableIssueFrames < 3 { smoothed.issue = postureResult.issue }

            updateFormAlert(result: smoothed)
            DispatchQueue.main.async { self.postureResult = smoothed }
        } catch { print(error) }
    }

    private func speakFormCue(result: SquatResult) {
        guard currentPhase == .descending || currentPhase == .bottom else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSpeechTime) > 3.0 else { return }
        var cue: String? = nil
        if !result.spineOk      { cue = "Keep your back straight" }
        else if !result.ankleOk { cue = "Knees too far forward" }
        else if !result.hipOk   { cue = "Lower your hips" }
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

    private func updateFormAlert(result: SquatResult) {
        guard currentPhase == .descending || currentPhase == .bottom else {
            DispatchQueue.main.async { self.showFormAlert = false }
            return
        }
        var message: String? = nil
        if !result.spineOk      { message = "Keep Your Back Straight!" }
        else if !result.ankleOk { message = "Knees Too Far Forward!" }
        else if !result.hipOk   { message = "Lower Your Hips More!" }

        if let msg = message {
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

    // MARK: - Phase & rep logic (original logic preserved exactly)
    private func updatePhaseAndReps(smoothedResult: SquatResult) {
        let kneeAngle = smoothedResult.kneeAngle
        let prev      = lastKneeAngle
        var nextPhase = currentPhase
        var addRep    = false

        if currentPhase == .descending || currentPhase == .bottom || currentPhase == .ascending {
            if !smoothedResult.spineOk { spineErrorFrames += 1 } else { spineErrorFrames = 0 }
            if !smoothedResult.ankleOk { ankleErrorFrames += 1 } else { ankleErrorFrames = 0 }
            if !smoothedResult.hipOk   { hipErrorFrames   += 1 } else { hipErrorFrames   = 0 }
            if spineErrorFrames >= 3 { hadSpineError = true }
            if ankleErrorFrames >= 3 { hadAnkleError = true }
            if hipErrorFrames   >= 3 { hadHipError   = true }
            if !smoothedResult.kneeOk && currentPhase == .bottom { hadKneeError = true }
        }

        if kneeAngle < 145 && prev > kneeAngle && !depthReached {
            nextPhase = .descending; squatStarted = true
        }

        if kneeAngle < minKneeAngle { minKneeAngle = kneeAngle }

        if kneeAngle <= 90 {
            validDepthFrames += 1
            if validDepthFrames >= 5 { depthReached = true }
        } else { validDepthFrames = 0 }

        let startedRising = depthReached && kneeAngle > (minKneeAngle + 4)
        if startedRising && !bottomReached {
            validBottomFrames += 1
            if validBottomFrames >= 3 { nextPhase = .bottom; bottomReached = true }
        } else if !depthReached { validBottomFrames = 0 }

        if bottomReached && kneeAngle > (prev + 2) && kneeAngle < 152 { nextPhase = .ascending }

        if squatStarted && kneeAngle >= 152 {
            validStandingFrames += 1
            if validStandingFrames >= 2 {
                if depthReached {
                    let formWasGood = !hadAnkleError && !hadSpineError && !hadHipError
                    if formWasGood {
                        addRep = true
                        triggerGoodRepFeedback(score: smoothedResult.postureScore)
                    } else {
                        triggerBadRepFeedback()
                    }
                } else {
                    triggerBadRepFeedback()
                }
                nextPhase = .standing; bottomReached = false; depthReached = false
                squatStarted = false; validStandingFrames = 0; validBottomFrames = 0
                minKneeAngle = 180; validDepthFrames = 0
                spineErrorFrames = 0; ankleErrorFrames = 0; hipErrorFrames = 0
                hadSpineError = false; hadHipError = false; hadAnkleError = false; hadKneeError = false
            }
        } else { validStandingFrames = 0 }

        lastKneeAngle = kneeAngle
        let scoreSnapshot = smoothedResult.postureScore

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

                let record = RepRecord(repNumber: self.totalRepsAllTime,
                                       score: scoreSnapshot, isGood: true, timestamp: Date())
                self.repHistory.append(record)
                self.updateScoreStats()
            }

            self.currentPhase = nextPhase
            switch nextPhase {
            case .standing:   self.phaseText = "Standing";         self.phaseColor = .white
            case .descending: self.phaseText = "Going Down";       self.phaseColor = .yellow
            case .bottom:     self.phaseText = "Perfect Depth ✅"; self.phaseColor = .green
            case .ascending:  self.phaseText = "Coming Up";        self.phaseColor = .blue
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
        restSecondsLeft = restDuration; isResting = true
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            DispatchQueue.main.async {
                self.restSecondsLeft -= 1
                if self.restSecondsLeft <= 0 {
                    t.invalidate(); self.isResting = false
                    self.resetSquatState(); self.speakText("Go!")
                }
            }
        }
    }

    private func triggerGoodRepFeedback(score: Int) {
        DispatchQueue.main.async {
            self.showGoodRepFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.showGoodRepFlash = false }
        }
    }

    private func triggerBadRepFeedback() {
        var reasons: [String] = []
        if hadSpineError  { reasons.append("Back not straight") }
        if hadAnkleError  { reasons.append("Knees too forward") }
        if hadHipError    { reasons.append("Hips too high") }
        if reasons.isEmpty { reasons.append("Improper Depth") }
        let message = "⚠️ Rep Not Counted\n" + reasons.joined(separator: " • ")

        if hadSpineError       { speakText("Keep your back straight") }
        else if hadAnkleError  { speakText("Knees too far forward") }
        else if hadHipError    { speakText("Lower your hips") }
        else                   { speakText("Improper Depth") }

        fireWatchNotification(title: "❌ You Did It Wrong!", body: reasons.joined(separator: " • "))

        DispatchQueue.main.async {
            self.badRepMessage = message
            let record = RepRecord(repNumber: self.totalRepsAllTime + 1,
                                   score: 0, isGood: false, timestamp: Date())
            self.repHistory.append(record)
            self.totalRepsAllTime += 1
            self.updateScoreStats()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.badRepMessage = nil }
        }
    }

    func fireWatchNotification(title: String, body: String) {
        let key = "\(title)"
        let now = Date()
        if let last = lastNotifTime[key], now.timeIntervalSince(last) < notifCooldown { return }
        lastNotifTime[key] = now
        NotificationManager.shared.send(title: title, body: body)
        WatchConnectivityManager.shared.sendFormAlert(exercise: "Squat", issue: "\(title): \(body)")
    }

    // MARK: - Posture analysis (original logic preserved exactly)
    private func analyzeSquatPosture(
        _ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> SquatResult {
        var result = SquatResult()
        let useLeft = betterSide(points)
        result.trackedLeftSide = useLeft

        let shoulderKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder
        let hipKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let kneeKey:     VNHumanBodyPoseObservation.JointName = useLeft ? .leftKnee     : .rightKnee
        let ankleKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftAnkle    : .rightAnkle

        for joint in [shoulderKey, hipKey, kneeKey, ankleKey] {
            guard let p = points[joint], p.confidence > 0.2 else {
                result.issue = .notVisible; return result
            }
        }

        let shoulder = points[shoulderKey]!.location
        let hip      = points[hipKey]!.location
        let knee     = points[kneeKey]!.location
        let ankle    = points[ankleKey]!.location

        result.kneeAngle     = calculateAngle(first: hip,      middle: knee, last: ankle)
        result.hipAngle      = calculateAngle(first: shoulder, middle: hip,  last: knee)
        let rawAtan          = atan2(shoulder.y - hip.y, shoulder.x - hip.x) * 180 / .pi
        let torsoAngle       = abs(90.0 - abs(rawAtan))
        result.spineAngle    = torsoAngle
        result.kneeToeOffset = knee.x - ankle.x

        let isSquatting = result.kneeAngle < 160
        guard isSquatting else {
            result.kneeOk = true; result.hipOk = true
            result.spineOk = true; result.ankleOk = true
            result.issue = .ready; result.postureScore = 100
            return result
        }

        result.ankleOk = abs(result.kneeToeOffset) <= 0.15

        switch currentPhase {
        case .standing:
            result.kneeOk = true; result.hipOk = true; result.spineOk = true
        case .descending:
            result.kneeOk = true; result.hipOk = true
            result.spineOk = torsoAngle >= 0 && torsoAngle <= 55
        case .bottom:
            result.kneeOk  = result.kneeAngle >= 50 && result.kneeAngle <= 90
            result.hipOk   = result.hipAngle  >= 30 && result.hipAngle  <= 100
            result.spineOk = torsoAngle >= 20 && torsoAngle <= 55
        case .ascending:
            result.kneeOk = true; result.hipOk = true
            result.spineOk = true; result.ankleOk = true
        }

        var score = 100
        if currentPhase != .ascending {
            if !result.kneeOk  { score -= 30 }
            if !result.hipOk   { score -= 20 }
            if !result.spineOk { score -= 30 }
            if !result.ankleOk { score -= 20 }
        }
        result.postureScore = max(score, 0)

        if currentPhase == .ascending    { result.issue = .correct }
        else if !result.spineOk          { result.issue = .backNotStraight }
        else if !result.ankleOk          { result.issue = .kneesOverToes }
        else if !result.hipOk            { result.issue = .hipTooHigh }
        else if !result.kneeOk           { result.issue = .kneesNotDeep }
        else                             { result.issue = .correct }

        return result
    }

    // MARK: - Helpers
    private func betterSide(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        let lShoulder: Float = points[.leftShoulder]?.confidence ?? 0
        let lHip:      Float = points[.leftHip]?.confidence      ?? 0
        let lKnee:     Float = points[.leftKnee]?.confidence     ?? 0
        let lAnkle:    Float = points[.leftAnkle]?.confidence    ?? 0
        let rShoulder: Float = points[.rightShoulder]?.confidence ?? 0
        let rHip:      Float = points[.rightHip]?.confidence      ?? 0
        let rKnee:     Float = points[.rightKnee]?.confidence     ?? 0
        let rAnkle:    Float = points[.rightAnkle]?.confidence    ?? 0
        return (lShoulder+lHip+lKnee+lAnkle) >= (rShoulder+rHip+rKnee+rAnkle)
    }

    private func updateBodyPoints(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        var mapped: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (joint, point) in points where point.confidence > 0.3 {
            mapped[joint] = CGPoint(x: point.location.x, y: 1 - point.location.y)
        }
        pointsBuffer.append(mapped)
        if pointsBuffer.count > 6 { pointsBuffer.removeFirst() }
        var smoothed: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        let uniqueJoints = Set(pointsBuffer.flatMap { $0.keys })
        for joint in uniqueJoints {
            let positions = pointsBuffer.compactMap { $0[joint] }
            guard !positions.isEmpty else { continue }
            let n = CGFloat(positions.count)
            smoothed[joint] = CGPoint(x: positions.map(\.x).reduce(0,+)/n,
                                      y: positions.map(\.y).reduce(0,+)/n)
        }
        DispatchQueue.main.async { self.bodyPoints = smoothed }
    }

    private func calculateAngle(first: CGPoint, middle: CGPoint, last: CGPoint) -> Double {
        let a = atan2(first.y - middle.y, first.x - middle.x)
        let b = atan2(last.y  - middle.y, last.x  - middle.x)
        var angle = abs((a - b) * 180 / .pi)
        if angle > 180 { angle = 360 - angle }
        return angle
    }

    private func smoothResult(_ result: SquatResult) -> SquatResult {
        frameBuffer.append(result)
        if frameBuffer.count > 8 { frameBuffer.removeFirst() }
        let n = Double(frameBuffer.count)
        var smoothed = result
        smoothed.kneeAngle    = frameBuffer.map(\.kneeAngle).reduce(0,+)  / n
        smoothed.hipAngle     = frameBuffer.map(\.hipAngle).reduce(0,+)   / n
        smoothed.spineAngle   = frameBuffer.map(\.spineAngle).reduce(0,+) / n
        smoothed.postureScore = Int(Double(frameBuffer.map(\.postureScore).reduce(0,+)) / n)
        smoothed.trackedLeftSide = result.trackedLeftSide
        return smoothed
    }
}
