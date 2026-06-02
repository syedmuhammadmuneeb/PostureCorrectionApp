//
//  PlankView.swift
//  PostureCorrect
//
//  CHANGES IN THIS REVISION
//  ─────────────────────────
//  • Compact GluteBridge-style UI applied:
//      - Minimal top bar: timer pill, 40 px score ring, frosted button pill
//      - Bottom panel: issue label row, angle chips, hold timer + best, reset
//      - PlankAngleChip replaces PlankAngleCard
//  • All previous features (Session Stats, HoldRecord, session clock,
//    camera-freeze fixes, voice / notification fixes, goal sheet) retained unchanged.

import SwiftUI
import AVFoundation
import Vision
import Combine

// MARK: - PLANK ISSUE
enum PlankIssue: String {
    case correct      = "✅ Perfect Plank"
    case ready        = "🧍 Get Into Plank Position"
    case hipsTooHigh  = "❌ Lower Your Hips"
    case hipsTooLow   = "❌ Raise Your Hips"
    case backSagging  = "❌ Keep Back Straight"
    case headDropping = "❌ Keep Head Neutral"
    case detecting    = "🔍 Detecting..."
    case notVisible   = "📷 Full Body Not Visible"
}

// MARK: - HOLD RECORD
struct HoldRecord: Identifiable {
    let id          = UUID()
    let holdNumber:  Int
    let seconds:     Int
    let score:       Int
    let timestamp:   Date

    var isGood: Bool { seconds >= 5 && score >= 70 }

    var formattedDuration: String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - PLANK RESULT
struct PlankResult {
    var issue: PlankIssue = .detecting
    var postureScore: Int  = 100
    var hipAngle:   Double = 180
    var spineAngle: Double = 180
    var neckAngle:  Double = 180
    var trackedLeftSide: Bool = true
    var hipOk   = true
    var spineOk = true
    var neckOk  = true
    var formIsValid: Bool { hipOk && spineOk && neckOk }
}

// MARK: - PLANK CAMERA VIEW
struct PlankCameraView: View {
    @StateObject private var viewModel = PlankViewModel()
    @State private var showGoalSheet   = false

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.session).ignoresSafeArea()

            PlankSkeletonOverlay(
                bodyPoints: viewModel.bodyPoints,
                result:     viewModel.plankResult
            ).ignoresSafeArea()

            VStack {
                topBar
                Spacer()

                if viewModel.showFormAlert {
                    PlankFormAlertBanner(message: viewModel.formAlertMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4), value: viewModel.showFormAlert)
                }

                Spacer()
                bottomPanel
            }

            if viewModel.showFormBreakFlash {
                Color.orange.opacity(0.25)
                    .ignoresSafeArea().allowsHitTesting(false)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.4), value: viewModel.showFormBreakFlash)

                VStack {
                    Spacer()
                    Text("⏸ Timer Paused — Fix Your Form")
                        .font(.title3.bold()).foregroundColor(.white)
                        .padding().background(Color.orange.opacity(0.9))
                        .cornerRadius(14).padding(.bottom, 220)
                }
            }
        }
        .sheet(isPresented: $viewModel.showStats) { PlankStatsSheet(viewModel: viewModel) }
        .sheet(isPresented: $showGoalSheet)        { PlankGoalSetupSheet(viewModel: viewModel) }
        .onAppear    { viewModel.start() }
        .onDisappear { viewModel.stop()  }
    }

    // MARK: - Top bar (minimal floating pill)
    private var topBar: some View {
        HStack(spacing: 8) {
            // Session timer pill
            Text(viewModel.sessionTimeString)
                .font(.caption.monospacedDigit().bold())
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.5)).cornerRadius(20)

            Spacer()

            // Score ring (40 px)
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 3).frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.plankResult.postureScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 40, height: 40).rotationEffect(.degrees(-90))
                Text("\(viewModel.plankResult.postureScore)")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            }

            // Action buttons — single frosted pill
            HStack(spacing: 4) {
                Button { viewModel.showStats = true } label: {
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

            // Issue label + timer-state pill on same row
            HStack {
                Text(viewModel.plankResult.issue.rawValue)
                    .font(.subheadline.bold()).foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Text(viewModel.isHolding ? "🔥 Holding" : "⏸ Paused")
                    .font(.caption.bold())
                    .foregroundColor(viewModel.isHolding ? .green : .orange)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background((viewModel.isHolding ? Color.green : Color.orange).opacity(0.15))
                    .cornerRadius(12)
            }

            // Angle chips
            HStack(spacing: 6) {
                PlankAngleChip(label: "Hip",   angle: viewModel.plankResult.hipAngle,   isOk: viewModel.plankResult.hipOk)
                PlankAngleChip(label: "Back",  angle: viewModel.plankResult.spineAngle, isOk: viewModel.plankResult.spineOk)
                PlankAngleChip(label: "Neck",  angle: viewModel.plankResult.neckAngle,  isOk: viewModel.plankResult.neckOk)
            }

            // Goal progress bar (only when goal is active)
            if viewModel.targetSeconds > 0 {
                PlankGoalProgressBar(
                    elapsed: viewModel.elapsedSeconds,
                    target:  viewModel.targetSeconds
                )
            }

            // Hold time row
            HStack(alignment: .center, spacing: 0) {
                // Current hold — dominant
                VStack(spacing: 0) {
                    Text(viewModel.formattedTime)
                        .font(.system(size: 52, weight: .heavy, design: .monospaced))
                        .foregroundColor(viewModel.isHolding ? .green : .white.opacity(0.5))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: viewModel.formattedTime)
                    Text("HOLD")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .kerning(1.2)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 44)

                // Best hold
                VStack(spacing: 0) {
                    Text(viewModel.formattedBestTime)
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                        .foregroundColor(.yellow)
                    Text("BEST")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .kerning(1.2)
                }
                .frame(maxWidth: .infinity)

                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1, height: 44)

                // Reset
                Button { viewModel.resetTimer() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title3).foregroundColor(.white.opacity(0.7))
                        Text("RESET").font(.system(size: 10)).foregroundColor(.white.opacity(0.4)).kerning(1.2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 2)

            // Status pill (build-up indicator / holding state)
            PlankStatusPill(
                isHolding:    viewModel.isHolding,
                issue:        viewModel.plankResult.issue,
                readyFrames:  viewModel.consecutiveGoodFrames,
                neededFrames: viewModel.goodFramesNeeded
            )
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(.ultraThinMaterial.opacity(0.95))
        .background(Color.black.opacity(0.6))
        .cornerRadius(24)
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var scoreColor: Color {
        let s = viewModel.plankResult.postureScore
        if s >= 80 { return .green }
        if s >= 55 { return .yellow }
        return .red
    }
}

// MARK: - ANGLE CHIP  (replaces PlankAngleCard)
struct PlankAngleChip: View {
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

// MARK: - GOAL SETUP SHEET
struct PlankGoalSetupSheet: View {
    @ObservedObject var viewModel: PlankViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var targetSeconds = 60

    var body: some View {
        NavigationView {
            Form {
                Section("Hold Goal") {
                    Stepper("Target: \(targetSeconds)s",
                            value: $targetSeconds, in: 10...600, step: 10)
                    Text("≈ \(targetSeconds / 60)m \(targetSeconds % 60)s")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section {
                    Button("Set Goal") {
                        viewModel.setGoal(seconds: targetSeconds); dismiss()
                    }.foregroundColor(.green).bold()
                    Button("Clear Goal") {
                        viewModel.clearGoal(); dismiss()
                    }.foregroundColor(.red)
                }
            }
            .navigationTitle("Set Hold Goal")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if viewModel.targetSeconds > 0 { targetSeconds = viewModel.targetSeconds }
            }
        }
    }
}

// MARK: - GOAL PROGRESS BAR
struct PlankGoalProgressBar: View {
    let elapsed: Int
    let target:  Int

    private var progress: CGFloat {
        CGFloat(min(elapsed, target)) / CGFloat(max(target, 1))
    }
    private var isComplete: Bool { elapsed >= target }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(isComplete ? "🎉 Goal reached!" : "Goal")
                    .font(.caption)
                    .foregroundColor(isComplete ? .green : .white.opacity(0.7))
                Spacer()
                Text("\(elapsed)/\(target)s")
                    .font(.caption.bold()).foregroundColor(.white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.15)).frame(height: 10)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isComplete ? Color.yellow : Color.green)
                        .frame(width: geo.size.width * progress, height: 10)
                        .animation(.spring(response: 0.3), value: elapsed)
                }
            }.frame(height: 10)
        }.padding(.horizontal, 4)
    }
}

// MARK: - SESSION STATS SHEET
struct PlankStatsSheet: View {
    @ObservedObject var viewModel: PlankViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        PlankStatCard(title: "Best Hold",    value: viewModel.formattedBestTime, color: .yellow)
                        PlankStatCard(title: "Current Hold", value: viewModel.formattedTime,
                                      color: viewModel.isHolding ? .green : .white)
                        PlankStatCard(title: "Session Time", value: viewModel.sessionTimeString,  color: .cyan)
                        PlankStatCard(title: "Avg Form Score",
                                      value: viewModel.holdHistory.isEmpty
                                        ? "—" : "\(viewModel.averageFormScore)%",
                                      color: scoreColor(viewModel.averageFormScore))
                        PlankStatCard(title: "Total Holds",
                                      value: "\(viewModel.holdHistory.count)", color: .purple)
                        PlankStatCard(title: "Good Holds",
                                      value: "\(viewModel.holdHistory.filter(\.isGood).count)", color: .green)
                    }
                    .padding(.horizontal)

                    Divider().padding(.horizontal)

                    if viewModel.holdHistory.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 44)).foregroundColor(.secondary)
                            Text("No holds recorded yet.\nGet into position and hold! 🔥")
                                .multilineTextAlignment(.center).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Hold History").font(.headline).padding(.horizontal)
                            ForEach(viewModel.holdHistory.reversed()) { hold in
                                HStack {
                                    Text("#\(hold.holdNumber)")
                                        .font(.caption.bold()).foregroundColor(.secondary)
                                        .frame(width: 28, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hold.formattedDuration)
                                            .font(.headline.bold())
                                            .foregroundColor(hold.isGood ? .green : .orange)
                                        Text("Score: \(hold.score)%").font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(hold.isGood ? "✅" : "⚠️").font(.title3)
                                }
                                .padding(.horizontal).padding(.vertical, 8)
                                .background(Color(.systemGray6)).cornerRadius(10).padding(.horizontal)
                            }
                        }
                    }
                    Spacer(minLength: 30)
                }.padding(.top)
            }
            .navigationTitle("Session Stats")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 55 { return .yellow }
        return .red
    }
}

// MARK: - STAT CARD
struct PlankStatCard: View {
    let title: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundColor(color)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(Color(.systemGray6)).cornerRadius(12)
    }
}

// MARK: - FORM ALERT BANNER
struct PlankFormAlertBanner: View {
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

// MARK: - SKELETON OVERLAY
struct PlankSkeletonOverlay: View {
    let bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let result: PlankResult

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let ear:      VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftEar      : .rightEar
                let shoulder: VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftShoulder : .rightShoulder
                let hip:      VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftHip      : .rightHip
                let knee:     VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftKnee     : .rightKnee
                let ankle:    VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftAnkle    : .rightAnkle

                drawLine(ear,      shoulder, geo, ok: result.neckOk)
                drawLine(shoulder, hip,      geo, ok: result.spineOk)
                drawLine(hip,      knee,     geo, ok: result.hipOk)
                drawLine(knee,     ankle,    geo, ok: result.hipOk)

                if let hipPt = bodyPoints[hip] {
                    let refY = hipPt.y * geo.size.height
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: refY))
                        p.addLine(to: CGPoint(x: geo.size.width, y: refY))
                    }
                    .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [8, 5]))
                }

                ForEach([ear, shoulder, hip, knee, ankle], id: \.self) { joint in
                    if let point = bodyPoints[joint] {
                        Circle().fill(dotColor(for: joint, ear: ear, shoulder: shoulder,
                                               hip: hip, knee: knee, ankle: ankle))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                            .position(x: point.x * geo.size.width, y: point.y * geo.size.height)
                    }
                }
            }
        }
    }

    private func dotColor(for joint: VNHumanBodyPoseObservation.JointName,
                          ear: VNHumanBodyPoseObservation.JointName,
                          shoulder: VNHumanBodyPoseObservation.JointName,
                          hip: VNHumanBodyPoseObservation.JointName,
                          knee: VNHumanBodyPoseObservation.JointName,
                          ankle: VNHumanBodyPoseObservation.JointName) -> Color {
        if joint == ear                    { return result.neckOk  ? .green : .red }
        if joint == shoulder               { return result.spineOk ? .green : .red }
        if joint == hip                    { return result.hipOk   ? .green : .red }
        if joint == knee || joint == ankle { return result.hipOk   ? .green : .red }
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

// MARK: - STATUS PILL
struct PlankStatusPill: View {
    let isHolding:    Bool
    let issue:        PlankIssue
    let readyFrames:  Int
    let neededFrames: Int

    var body: some View {
        if isHolding {
            label("🔥 Keep holding — great form!", color: .green)
        } else if issue == .ready {
            label("📐 Get into plank position", color: .white.opacity(0.7),
                  bg: Color.white.opacity(0.1))
        } else if issue == .correct || issue == .detecting {
            buildUpView
        } else {
            label("⏸ Fix form to resume timer", color: .orange)
        }
    }

    private var buildUpView: some View {
        let progress = min(Double(readyFrames) / Double(max(neededFrames, 1)), 1.0)
        return VStack(spacing: 6) {
            Text("Hold steady — timer starting...")
                .font(.caption.bold()).foregroundColor(.yellow)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.15)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 4).fill(Color.yellow)
                        .frame(width: geo.size.width * CGFloat(progress), height: 6)
                        .animation(.linear(duration: 0.1), value: readyFrames)
                }
            }.frame(height: 6)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.yellow.opacity(0.1)).cornerRadius(20)
    }

    private func label(_ text: String, color: Color, bg: Color = Color.clear) -> some View {
        Text(text).font(.caption.bold()).foregroundColor(color)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(bg == Color.clear ? color.opacity(0.15) : bg)
            .cornerRadius(20)
    }
}

// MARK: - PLANK VIEW MODEL
final class PlankViewModel: NSObject, ObservableObject,
                             AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    @Published var bodyPoints:      [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var plankResult      = PlankResult()
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var elapsedSeconds:  Int  = 0
    @Published var bestSeconds:     Int  = 0
    @Published var isHolding:       Bool = false
    @Published var showFormAlert      = false
    @Published var formAlertMessage   = ""
    @Published var showFormBreakFlash = false
    @Published var consecutiveGoodFrames = 0
    @Published var showStats = false

    @Published var targetSeconds: Int = 0

    func setGoal(seconds: Int) {
        DispatchQueue.main.async { self.targetSeconds = seconds }
    }

    func clearGoal() {
        DispatchQueue.main.async { self.targetSeconds = 0 }
    }

    @Published var holdHistory:      [HoldRecord] = []
    @Published var sessionTimeString = "00:00"

    private var sessionStartDate: Date?
    private var sessionClockTimer: Timer?

    private var holdScoreAccum:   Int = 0
    private var holdScoreFrames:  Int = 0

    var averageFormScore: Int {
        guard !holdHistory.isEmpty else { return 0 }
        return holdHistory.map(\.score).reduce(0, +) / holdHistory.count
    }

    let goodFramesNeeded = 10

    private let hipExcellentMin:    Double = 170
    private let hipAcceptableMin:   Double = 165
    private let spineExcellentMin:  Double = 175
    private let spineAcceptableMin: Double = 165
    private let neckExcellentMin:   Double = 170
    private let neckAcceptableMin:  Double = 160
    private let standingGuardMin:   Double = 120

    private let badFramesRequired    = 5
    private var consecutiveBadFrames = 0
    private var holdingState         = false

    private var isProcessingFrame = false
    private let poseRequest = VNDetectHumanBodyPoseRequest()

    private var pointsBuffer: [[VNHumanBodyPoseObservation.JointName: CGPoint]] = []
    private let pointsBufferSize = 6

    private var angleBuffer: [(hip: Double, spine: Double, neck: Double)] = []
    private let angleBufferSize = 8

    private var stableIssueFrames = 0
    private var lastIssue: PlankIssue = .detecting
    private var notVisibleFrames = 0

    private var timerTask:  Task<Void, Never>?
    private var alertTimer: Timer?

    private var lastNotifTime: [String: Date] = [:]
    private let notifCooldown: TimeInterval   = 4.0

    private var announcedMilestones = Set<Int>()
    private var goalAnnounced       = false

    private let speechSynthesizer = AVSpeechSynthesizer()
    private var lastSpokenTime: [String: Date] = [:]
    private let voiceCooldown: TimeInterval = 4.0

    // MARK: - Lifecycle
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            DispatchQueue.global(qos: .userInitiated).async { self.setupCamera() }
        }
        startSessionClock()
        speak("Get into plank position. Timer starts when your form is perfect.")
        fireWatchNotification(
            title: "🏋️ Plank Started",
            body:  "Get into position. Timer starts when form is perfect."
        )
    }

    func stop() {
        session.stopRunning()
        stopTimer()
        stopSessionClock()
        speechSynthesizer.stopSpeaking(at: .immediate)
        recordHoldIfNeeded()
    }

    func resetTimer() {
        DispatchQueue.main.async {
            self.recordHoldIfNeeded()
            self.stopTimer()
            self.holdingState            = false
            self.isHolding               = false
            self.elapsedSeconds          = 0
            self.consecutiveGoodFrames   = 0
            self.consecutiveBadFrames    = 0
            self.angleBuffer.removeAll()
            self.pointsBuffer.removeAll()
            self.announcedMilestones.removeAll()
            self.goalAnnounced   = false
            self.holdScoreAccum  = 0
            self.holdScoreFrames = 0
        }
    }

    private func startSessionClock() {
        sessionStartDate = Date()
        sessionClockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let start = self.sessionStartDate else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            self.sessionTimeString = self.formatSeconds(elapsed)
        }
    }

    private func stopSessionClock() {
        sessionClockTimer?.invalidate()
        sessionClockTimer = nil
    }

    private func recordHoldIfNeeded() {
        guard elapsedSeconds >= 1 else { return }
        let avgScore = holdScoreFrames > 0 ? holdScoreAccum / holdScoreFrames : plankResult.postureScore
        let record = HoldRecord(
            holdNumber: holdHistory.count + 1,
            seconds:    elapsedSeconds,
            score:      avgScore,
            timestamp:  Date()
        )
        holdHistory.append(record)
        holdScoreAccum  = 0
        holdScoreFrames = 0
    }

    // MARK: - Camera setup
    private func setupCamera() {
        guard !session.isRunning else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        session.inputs.forEach { session.removeInput($0) }
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition),
            let input  = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { session.commitConfiguration(); return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "plankVideoQueue",
                                                                   qos: .userInteractive))
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
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
            self.session.addInput(inp)
            self.session.commitConfiguration()
            DispatchQueue.main.async { self.cameraPosition = newPos }
        }
    }

    // MARK: - Frame delivery
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !isProcessingFrame else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessingFrame = true
        let orientation: CGImagePropertyOrientation = cameraPosition == .front ? .leftMirrored : .right
        analyzeFrame(pixelBuffer: pixelBuffer, orientation: orientation)
    }

    // MARK: - Analysis pipeline
    private func analyzeFrame(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        defer { isProcessingFrame = false }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        do {
            try handler.perform([poseRequest])
            guard let observation = poseRequest.results?.first else { return }
            let points = try observation.recognizedPoints(.all)

            let smoothedBodyPoints = buildSmoothedPoints(points)

            guard var result = extractAngles(from: points) else {
                notVisibleFrames += 1
                if notVisibleFrames >= 8 {
                    DispatchQueue.main.async { self.plankResult.issue = .notVisible }
                    pauseTimer()
                }
                return
            }
            notVisibleFrames = 0

            let s = smooth(result)
            result.hipAngle   = s.hip
            result.spineAngle = s.spine
            result.neckAngle  = s.neck

            evaluateForm(result: &result)
            updateTimerState(result: result)

            if holdingState {
                holdScoreAccum  += result.postureScore
                holdScoreFrames += 1
            }

            if result.issue == lastIssue { stableIssueFrames += 1 }
            else { stableIssueFrames = 0; lastIssue = result.issue }
            var published = result
            if stableIssueFrames < 3 { published.issue = plankResult.issue }

            let alertMsg   = buildAlertMessage(result: result)
            let goodFrames = consecutiveGoodFrames

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.bodyPoints  = smoothedBodyPoints
                self.plankResult = published
                self.consecutiveGoodFrames = goodFrames

                if let msg = alertMsg {
                    if self.formAlertMessage != msg {
                        self.formAlertMessage = msg
                        self.alertTimer?.invalidate()
                        self.alertTimer = Timer.scheduledTimer(
                            withTimeInterval: 2.5, repeats: false
                        ) { [weak self] _ in self?.showFormAlert = false }
                    }
                    self.showFormAlert = true
                } else {
                    self.alertTimer?.invalidate()
                    self.alertTimer = nil
                    self.showFormAlert = false
                }
            }

            if let msg = alertMsg {
                fireWatchNotification(title: "⚠️ Fix Your Form", body: msg, key: msg)
                speak(msg)
            }
        } catch { print("Plank Vision error: \(error)") }
    }

    private func buildSmoothedPoints(
        _ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        var mapped: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (joint, point) in points where point.confidence > 0.2 {
            mapped[joint] = CGPoint(x: point.location.x, y: 1 - point.location.y)
        }
        pointsBuffer.append(mapped)
        if pointsBuffer.count > pointsBufferSize { pointsBuffer.removeFirst() }
        var smoothed: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        let uniqueJoints = Set(pointsBuffer.flatMap { $0.keys })
        for joint in uniqueJoints {
            let positions = pointsBuffer.compactMap { $0[joint] }
            guard !positions.isEmpty else { continue }
            let n = CGFloat(positions.count)
            smoothed[joint] = CGPoint(x: positions.map(\.x).reduce(0,+)/n,
                                      y: positions.map(\.y).reduce(0,+)/n)
        }
        return smoothed
    }

    private func extractAngles(
        from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> PlankResult? {
        let useLeft = betterSide(points)
        let shoulderKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder
        let hipKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let kneeKey:     VNHumanBodyPoseObservation.JointName = useLeft ? .leftKnee     : .rightKnee
        let ankleKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftAnkle    : .rightAnkle
        let earKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftEar      : .rightEar

        for joint in [shoulderKey, hipKey, kneeKey, ankleKey, earKey] {
            guard let p = points[joint], p.confidence > 0.2 else { return nil }
        }

        let shoulder = points[shoulderKey]!.location
        let hip      = points[hipKey]!.location
        let knee     = points[kneeKey]!.location
        let ankle    = points[ankleKey]!.location
        let ear      = points[earKey]!.location

        var result = PlankResult()
        result.trackedLeftSide = useLeft
        result.hipAngle   = calculateAngle(first: shoulder, middle: hip,      last: knee)
        result.spineAngle = calculateAngle(first: shoulder, middle: hip,      last: ankle)
        result.neckAngle  = calculateAngle(first: ear,      middle: shoulder, last: hip)
        return result
    }

    private func evaluateForm(result: inout PlankResult) {
        let hip   = result.hipAngle
        let spine = result.spineAngle
        let neck  = result.neckAngle

        guard spine >= standingGuardMin else {
            result.hipOk = true; result.spineOk = true; result.neckOk = true
            result.issue = .ready; result.postureScore = 100
            return
        }

        result.hipOk   = hip   >= hipAcceptableMin
        result.spineOk = spine >= spineAcceptableMin
        result.neckOk  = neck  >= neckAcceptableMin

        var score = 100
        if !result.spineOk { score -= 40 }
        if !result.hipOk   { score -= 35 }
        if !result.neckOk  { score -= 25 }
        result.postureScore = max(score, 0)

        if !result.spineOk      { result.issue = .backSagging  }
        else if !result.hipOk   { result.issue = .hipsTooLow   }
        else if !result.neckOk  { result.issue = .headDropping }
        else                    { result.issue = .correct      }
    }

    private func updateTimerState(result: PlankResult) {
        if result.formIsValid {
            consecutiveBadFrames  = 0
            consecutiveGoodFrames = min(consecutiveGoodFrames + 1, goodFramesNeeded + 1)
            if consecutiveGoodFrames >= goodFramesNeeded { startTimer() }
        } else {
            consecutiveGoodFrames = max(0, consecutiveGoodFrames - 1)
            consecutiveBadFrames += 1
            if consecutiveBadFrames >= badFramesRequired {
                pauseTimer()
                DispatchQueue.main.async {
                    self.showFormBreakFlash = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.showFormBreakFlash = false
                    }
                }
            }
        }
    }

    private func startTimer() {
        guard !holdingState else { return }
        holdingState = true
        DispatchQueue.main.async { self.isHolding = true }

        timerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self.elapsedSeconds += 1

                    if self.targetSeconds > 0,
                       self.elapsedSeconds == self.targetSeconds,
                       !self.goalAnnounced {
                        self.goalAnnounced = true
                        self.speakImmediate("Goal reached! Amazing hold!")
                        self.fireWatchNotification(
                            title: "🎯 Goal Reached!",
                            body:  "You hit your \(self.formatSeconds(self.targetSeconds)) target!"
                        )
                    }

                    let milestones = [10, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300]
                    if milestones.contains(self.elapsedSeconds),
                       !self.announcedMilestones.contains(self.elapsedSeconds) {
                        self.announcedMilestones.insert(self.elapsedSeconds)
                        let secs  = self.elapsedSeconds
                        let label = secs < 60 ? "\(secs) seconds"
                                              : "\(secs / 60) minute\(secs / 60 > 1 ? "s" : "")"
                        self.speakImmediate("\(label)! Keep it up!")
                    }

                    if self.elapsedSeconds > self.bestSeconds {
                        self.bestSeconds = self.elapsedSeconds
                        if milestones.contains(self.bestSeconds) {
                            self.fireWatchNotification(
                                title: "🏆 New Best!",
                                body:  "You held for \(self.formatSeconds(self.bestSeconds))!"
                            )
                            self.speakImmediate("New personal best!")
                        }
                    }
                }
            }
        }
    }

    private func pauseTimer() {
        guard holdingState else { return }
        holdingState = false
        timerTask?.cancel()
        timerTask = nil
        DispatchQueue.main.async {
            self.isHolding = false
            self.recordHoldIfNeeded()
            self.elapsedSeconds = 0
            self.announcedMilestones.removeAll()
            self.goalAnnounced = false
        }
    }

    private func stopTimer() {
        holdingState = false
        timerTask?.cancel()
        timerTask = nil
    }

    private func buildAlertMessage(result: PlankResult) -> String? {
        guard !result.formIsValid else { return nil }
        if !result.spineOk { return "Keep Your Back Straight — Hips Are Sagging!" }
        if !result.hipOk   { return "Raise Your Hips — They're Too Low!" }
        if !result.neckOk  { return "Keep Your Head Neutral — Don't Drop It!" }
        return nil
    }

    func fireWatchNotification(title: String, body: String, key: String? = nil) {
        let throttleKey = key ?? title
        let now = Date()
        if let last = lastNotifTime[throttleKey],
           now.timeIntervalSince(last) < notifCooldown { return }
        lastNotifTime[throttleKey] = now
        NotificationManager.shared.send(title: title, body: body)
        WatchConnectivityManager.shared.sendFormAlert(exercise: "Plank", issue: "\(title): \(body)")
    }

    private func speak(_ text: String) {
        let now = Date()
        if let last = lastSpokenTime[text], now.timeIntervalSince(last) < voiceCooldown { return }
        lastSpokenTime[text] = now
        guard !speechSynthesizer.isSpeaking else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5; utterance.voice = AVSpeechSynthesisVoice(language: "en-US"); utterance.volume = 1.0
        speechSynthesizer.speak(utterance)
    }

    private func speakImmediate(_ text: String) {
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5; utterance.voice = AVSpeechSynthesisVoice(language: "en-US"); utterance.volume = 1.0
        speechSynthesizer.speak(utterance)
    }

    private func betterSide(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        let lShoulder: Float = points[.leftShoulder]?.confidence ?? 0
        let lHip:      Float = points[.leftHip]?.confidence      ?? 0
        let lKnee:     Float = points[.leftKnee]?.confidence     ?? 0
        let lAnkle:    Float = points[.leftAnkle]?.confidence    ?? 0
        let lEar:      Float = points[.leftEar]?.confidence      ?? 0
        let rShoulder: Float = points[.rightShoulder]?.confidence ?? 0
        let rHip:      Float = points[.rightHip]?.confidence      ?? 0
        let rKnee:     Float = points[.rightKnee]?.confidence     ?? 0
        let rAnkle:    Float = points[.rightAnkle]?.confidence    ?? 0
        let rEar:      Float = points[.rightEar]?.confidence      ?? 0
        return (lShoulder + lHip + lKnee + lAnkle + lEar) >= (rShoulder + rHip + rKnee + rAnkle + rEar)
    }

    private func calculateAngle(first: CGPoint, middle: CGPoint, last: CGPoint) -> Double {
        let a = atan2(first.y  - middle.y, first.x  - middle.x)
        let b = atan2(last.y   - middle.y, last.x   - middle.x)
        var angle = abs((a - b) * 180 / .pi)
        if angle > 180 { angle = 360 - angle }
        return angle
    }

    private func smooth(_ result: PlankResult) -> (hip: Double, spine: Double, neck: Double) {
        angleBuffer.append((result.hipAngle, result.spineAngle, result.neckAngle))
        if angleBuffer.count > angleBufferSize { angleBuffer.removeFirst() }
        let n = Double(angleBuffer.count)
        return (
            hip:   angleBuffer.map(\.hip).reduce(0,   +) / n,
            spine: angleBuffer.map(\.spine).reduce(0, +) / n,
            neck:  angleBuffer.map(\.neck).reduce(0,  +) / n
        )
    }

    var formattedTime:     String { formatSeconds(elapsedSeconds) }
    var formattedBestTime: String { formatSeconds(bestSeconds) }

    func formatSeconds(_ total: Int) -> String {
        String(format: "%02d:%02d", total / 60, total % 60)
    }
}
