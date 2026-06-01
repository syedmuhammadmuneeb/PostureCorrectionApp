//
//  MountainClimberView.swift
//  PostureCorrect
//
//  Created by Syed Muhammad Muneeb on 30/05/26.
//

//
//  MountainClimberView.swift
//  PostureCorrect
//
//  Camera placement: SIDE-ON — phone level with the user's hips, ~1.5 m away.
//  Full body (wrist → shoulder → hip → knee → ankle) must be visible.
//  Person starts in a high-plank position (hands on floor, arms straight).
//
//  ─────────────────────────────────────────────────────────────────────────
//  EXERCISE MECHANICS
//  ─────────────────────────────────────────────────────────────────────────
//  Mountain climber: from high plank, alternately drive each knee toward
//  the chest while keeping the other leg extended and the hips level.
//  Each knee drive (tuck + return) on either side = 1 rep.
//
//  ─────────────────────────────────────────────────────────────────────────
//  KEY ANGLES  (raw Vision coords, y=0 at bottom)
//  ─────────────────────────────────────────────────────────────────────────
//
//  1. Spine angle — deviation of shoulder→hip from horizontal.
//     In plank the body should be flat → ≤ 20°.
//     Hips piking up or sagging down increase this angle.
//
//  2. Knee angle (hip→knee→ankle) of the DRIVING knee.
//     Extended (plank) position: knee nearly straight → ~160°–180°.
//     Fully tucked (knee to chest): ~60°–90°.
//     Rep trigger: knee angle drops below tuckTrigger then returns above extendTrigger.
//
//  3. Hip angle (shoulder→hip→knee of the DRIVING side).
//     At full tuck the hip flexes sharply: angle < 90°.
//     At extension: angle ~160°–180°.
//     This prevents counting a partial drive as a full rep.
//
//  ─────────────────────────────────────────────────────────────────────────
//  REP STATE MACHINE
//  ─────────────────────────────────────────────────────────────────────────
//  Gate 1: kneeAngle < tuckTrigger (≤ 100°) for 2 frames → tuck started
//  Gate 2: kneeAngle ≤ fullTuckAngle (≤ 80°) for 2 frames → full tuck confirmed
//  Gate 3: kneeAngle ≥ extendTrigger (≥ 155°) for 2 frames → rep complete
//
//  We use low frame counts (2) because mountain climbers are fast-paced.
//
//  ─────────────────────────────────────────────────────────────────────────

import SwiftUI
import AVFoundation
import Vision
import Combine

// MARK: - MOUNTAIN CLIMBER ISSUE
enum MountainClimberIssue: String {
    case correct      = "✅ Good Form"
    case ready        = "🏃 Get Into Plank"
    case hipsPiking   = "❌ Lower Your Hips"
    case hipsSagging  = "❌ Raise Your Hips"
    case backNotFlat  = "❌ Keep Back Flat"
    case notFullTuck  = "❌ Drive Knee Further"
    case detecting    = "🔍 Detecting..."
    case notVisible   = "📷 Full Body Not Visible"
}

// MARK: - MOUNTAIN CLIMBER PHASE
enum MountainClimberPhase { case plank, tucking, tucked, extending }

// MARK: - MOUNTAIN CLIMBER RESULT
struct MountainClimberResult {
    var issue: MountainClimberIssue = .detecting
    var postureScore: Int = 100
    // spineAngle: shoulder→hip deviation from horizontal — target ≤ 20°
    var spineAngle:  Double = 0
    // kneeAngle: hip→knee→ankle of the driving leg — cycles ~170° ↔ ~70°
    var kneeAngle:   Double = 170
    // hipAngle: shoulder→hip→knee — confirms full hip flexion at tuck
    var hipAngle:    Double = 170
    var trackedLeftSide: Bool = true
    var spineOk: Bool = true
    var kneeOk:  Bool = true
    var formIsValid: Bool { spineOk && kneeOk }
}

// MARK: - MOUNTAIN CLIMBER CAMERA VIEW
struct MountainClimberCameraView: View {
    @StateObject private var viewModel = MountainClimberViewModel()

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.session).ignoresSafeArea()
            MountainClimberSkeletonOverlay(bodyPoints: viewModel.bodyPoints,
                                           result: viewModel.result).ignoresSafeArea()
            VStack {
                topBar; Spacer()
                if viewModel.showFormAlert {
                    MountainClimberAlertBanner(message: viewModel.formAlertMessage)
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
        }
        .onAppear { viewModel.start() }.onDisappear { viewModel.stop() }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mountain Climber AI").font(.title2.bold()).foregroundColor(.white)
                Text("Real-Time Form Check").font(.caption).foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Button { viewModel.switchCamera() } label: {
                Image(systemName: "camera.rotate").font(.title2).foregroundColor(.white)
                    .padding(12).background(Color.white.opacity(0.2)).clipShape(Circle())
            }
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 5).frame(width: 55, height: 55)
                Circle().trim(from: 0, to: CGFloat(viewModel.result.postureScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 55, height: 55).rotationEffect(.degrees(-90))
                Text("\(viewModel.result.postureScore)").font(.headline.bold()).foregroundColor(.white)
            }
        }
        .padding().background(.black.opacity(0.65)).cornerRadius(20).padding()
    }

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            Text(viewModel.result.issue.rawValue)
                .font(.title2.bold()).foregroundColor(.white).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                MountainClimberAngleCard(title: "Back", angle: viewModel.result.spineAngle,
                                         isOk: viewModel.result.spineOk, idealRange: "0°-20°")
                MountainClimberAngleCard(title: "Knee", angle: viewModel.result.kneeAngle,
                                         isOk: viewModel.result.kneeOk, idealRange: "Tuck <80°")
                MountainClimberAngleCard(title: "Hip", angle: viewModel.result.hipAngle,
                                         isOk: true, idealRange: "Flex <90°")
            }
            HStack(spacing: 40) {
                VStack {
                    Text("\(viewModel.reps)").font(.system(size: 50, weight: .bold)).foregroundColor(.white)
                    Text("REPS").foregroundColor(.white.opacity(0.7)).font(.caption)
                }
                VStack {
                    Text(viewModel.phaseText).font(.title3.bold()).foregroundColor(viewModel.phaseColor)
                    Text("PHASE").foregroundColor(.white.opacity(0.7)).font(.caption)
                }
                Button { viewModel.resetReps() } label: {
                    VStack {
                        Image(systemName: "arrow.counterclockwise").font(.title2).foregroundColor(.white)
                        Text("RESET").foregroundColor(.white.opacity(0.7)).font(.caption)
                    }
                }
            }
        }
        .padding().background(.black.opacity(0.75)).cornerRadius(22).padding()
    }

    private var scoreColor: Color {
        let s = viewModel.result.postureScore
        return s >= 80 ? .green : s >= 55 ? .yellow : .red
    }
}

struct MountainClimberAlertBanner: View {
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

struct MountainClimberAngleCard: View {
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

// MARK: - SKELETON OVERLAY
struct MountainClimberSkeletonOverlay: View {
    let bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let result: MountainClimberResult

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let s  = result.trackedLeftSide
                let wr: VNHumanBodyPoseObservation.JointName = s ? .leftWrist    : .rightWrist
                let sh: VNHumanBodyPoseObservation.JointName = s ? .leftShoulder : .rightShoulder
                let hp: VNHumanBodyPoseObservation.JointName = s ? .leftHip      : .rightHip
                let kn: VNHumanBodyPoseObservation.JointName = s ? .leftKnee     : .rightKnee
                let an: VNHumanBodyPoseObservation.JointName = s ? .leftAnkle    : .rightAnkle

                drawLine(wr, sh, geo, ok: result.spineOk)
                drawLine(sh, hp, geo, ok: result.spineOk)
                drawLine(hp, kn, geo, ok: result.kneeOk)
                drawLine(kn, an, geo, ok: result.kneeOk)

                ForEach([wr, sh, hp, kn, an], id: \.self) { j in
                    if let pt = bodyPoints[j] {
                        Circle().fill(result.spineOk && result.kneeOk ? Color.green : Color.red)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                            .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func drawLine(_ j1: VNHumanBodyPoseObservation.JointName,
                          _ j2: VNHumanBodyPoseObservation.JointName,
                          _ geo: GeometryProxy, ok: Bool) -> some View {
        if let p1 = bodyPoints[j1], let p2 = bodyPoints[j2] {
            Path { p in
                p.move(to: CGPoint(x: p1.x * geo.size.width, y: p1.y * geo.size.height))
                p.addLine(to: CGPoint(x: p2.x * geo.size.width, y: p2.y * geo.size.height))
            }
            .stroke(ok ? Color.green : Color.red, style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
    }
}

// MARK: - VIEW MODEL
final class MountainClimberViewModel: NSObject, ObservableObject,
                                       AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    @Published var bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var result     = MountainClimberResult()
    @Published var reps       = 0
    @Published var phaseText  = "Get Into Plank"
    @Published var phaseColor: Color = .white
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var showFormAlert    = false
    @Published var formAlertMessage = ""
    @Published var showBadRepFlash  = false
    @Published var badRepReason     = ""

    // ── Thresholds ────────────────────────────────────────────────────────────
    private let spineMax:       Double = 22   // plank back flatness
    // Knee angle of the driving leg
    private let tuckTrigger:    Double = 100  // Gate 1: knee has started tucking
    private let fullTuckAngle:  Double = 80   // Gate 2: full tuck confirmed
    private let extendTrigger:  Double = 155  // Gate 3: leg returned to plank
    // In plank the spine must be horizontal (body not upright)
    private let inPlankSpineMax: Double = 35  // above this = person is standing up

    // Fast exercise — use 2-frame counts to avoid missing reps
    private let framesForTuck:   Int = 2
    private let framesForExtend: Int = 2
    private let errorLatch:      Int = 4      // slightly more lenient for fast movement

    // ── Smoothing — smaller window for fast exercise ───────────────────────────
    private var angleBuffer: [(spine: Double, knee: Double, hip: Double)] = []
    private let bufferSize = 4

    // ── Rep state ─────────────────────────────────────────────────────────────
    private var repInProgress  = false
    private var tuckReached    = false
    private var framesAtTuck   = 0
    private var framesAtExtend = 0
    private var currentPhase: MountainClimberPhase = .plank

    private var spineErrFrames = 0; private var hadSpineError = false

    private var stableIssueFrames = 0
    private var lastIssue: MountainClimberIssue = .detecting
    private var alertTimer: Timer?

    // MARK: - Lifecycle
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            DispatchQueue.global(qos: .userInitiated).async { self.setupCamera() }
        }
    }
    func stop() { session.stopRunning() }

    func resetReps() {
        DispatchQueue.main.async {
            self.reps = 0; self.angleBuffer.removeAll()
            self.repInProgress = false; self.tuckReached = false
            self.framesAtTuck = 0; self.framesAtExtend = 0
            self.spineErrFrames = 0; self.hadSpineError = false
            self.currentPhase = .plank
            self.phaseText = "Get Into Plank"; self.phaseColor = .white
        }
    }

    // MARK: - Camera
    private func setupCamera() {
        guard !session.isRunning else { return }
        session.beginConfiguration(); session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition),
              let input  = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { session.commitConfiguration(); return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "mcVideoQueue"))
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration(); session.startRunning()
    }

    func switchCamera() {
        DispatchQueue.global(qos: .userInitiated).async {
            let newPos: AVCaptureDevice.Position = self.cameraPosition == .front ? .back : .front
            self.session.beginConfiguration()
            if let old = self.session.inputs.first { self.session.removeInput(old) }
            guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPos),
                  let inp = try? AVCaptureDeviceInput(device: dev),
                  self.session.canAddInput(inp) else { self.session.commitConfiguration(); return }
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
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        do {
            try handler.perform([request])
            guard let obs = request.results?.first else { return }
            let pts = try obs.recognizedPoints(.all)
            updateBodyPoints(pts)
            guard var r = extractAngles(from: pts) else {
                DispatchQueue.main.async { self.result.issue = .notVisible }; return
            }
            let s = smooth(r)
            r.spineAngle = s.spine; r.kneeAngle = s.knee; r.hipAngle = s.hip
            evaluateForm(result: &r)
            updatePhaseAndReps(result: r)
            if r.issue == lastIssue { stableIssueFrames += 1 }
            else { stableIssueFrames = 0; lastIssue = r.issue }
            var pub = r; if stableIssueFrames < 3 { pub.issue = result.issue }
            updateFormAlert(result: pub)
            DispatchQueue.main.async { self.result = pub }
        } catch { print("MC Vision error: \(error)") }
    }

    private func extractAngles(from pts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint])
        -> MountainClimberResult? {
        let useLeft = betterSide(pts)
        let sh: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder
        let hp: VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let kn: VNHumanBodyPoseObservation.JointName = useLeft ? .leftKnee     : .rightKnee
        let an: VNHumanBodyPoseObservation.JointName = useLeft ? .leftAnkle    : .rightAnkle
        for j in [sh, hp, kn, an] { guard let p = pts[j], p.confidence > 0.35 else { return nil } }
        let shoulder = pts[sh]!.location; let hip   = pts[hp]!.location
        let knee     = pts[kn]!.location; let ankle = pts[an]!.location
        var r = MountainClimberResult(); r.trackedLeftSide = useLeft
        // Spine: shoulder→hip deviation from horizontal
        let spRad = atan2(shoulder.y - hip.y, shoulder.x - hip.x) * 180 / .pi
        r.spineAngle = min(abs(spRad), 90)
        // Knee: hip→knee→ankle — the driving leg's bend angle
        r.kneeAngle = calculateAngle(first: hip, middle: knee, last: ankle)
        // Hip: shoulder→hip→knee — measures hip flexion
        r.hipAngle = calculateAngle(first: shoulder, middle: hip, last: knee)
        return r
    }

    private func evaluateForm(result: inout MountainClimberResult) {
        // Guard: person is standing (spine too upright → not in plank)
        guard result.spineAngle < inPlankSpineMax else {
            result.spineOk = true; result.kneeOk = true
            result.issue = .ready; result.postureScore = 100; return
        }
        result.spineOk = result.spineAngle <= spineMax
        result.kneeOk = true   // knee ok is phase-dependent; always true for display during plank

        var score = 100
        if !result.spineOk { score -= 40 }
        result.postureScore = max(score, 0)

        if !result.spineOk {
            // Distinguish pike vs sag: in Vision coords (y=0 bottom), if hips are
            // higher than shoulder, spineAngle rises and hip→shoulder is upward
            let hip      = result.hipAngle
            result.issue = hip > 160 ? .hipsPiking : .hipsSagging
        } else { result.issue = .correct }
    }

    private func updatePhaseAndReps(result: MountainClimberResult) {
        let knee     = result.kneeAngle
        var next     = currentPhase
        var addRep   = false
        var badRep   = false

        if repInProgress {
            if !result.spineOk { spineErrFrames += 1 } else { spineErrFrames = max(0, spineErrFrames - 1) }
            if spineErrFrames >= errorLatch { hadSpineError = true }
        }

        // Gate 1: knee starts tucking
        if !repInProgress && knee < tuckTrigger {
            repInProgress = true; tuckReached = false
            framesAtTuck = 0; framesAtExtend = 0; next = .tucking
        }

        // Still tucking
        if repInProgress && knee < tuckTrigger { next = .tucking }

        // Gate 2: full tuck confirmed
        if repInProgress && knee <= fullTuckAngle {
            framesAtTuck += 1
            if framesAtTuck >= framesForTuck { tuckReached = true; next = .tucked }
        } else { framesAtTuck = max(0, framesAtTuck - 1) }

        // Extending back
        if tuckReached && knee > fullTuckAngle && knee < extendTrigger { next = .extending }

        // Gate 3: leg back to plank
        if repInProgress && knee >= extendTrigger {
            framesAtExtend += 1
            if framesAtExtend >= framesForExtend {
                if tuckReached {
                    if !hadSpineError { addRep = true } else { badRep = true }
                } else { badRep = true }
                repInProgress = false; tuckReached = false
                framesAtTuck = 0; framesAtExtend = 0
                spineErrFrames = 0; hadSpineError = false
                next = .plank
            }
        } else { if knee < extendTrigger { framesAtExtend = max(0, framesAtExtend - 1) } }

        currentPhase = next
        let reasons = hadSpineError ? "Hips not level in plank" : "Knee not fully tucked"

        DispatchQueue.main.async {
            if addRep { self.reps += 1 }
            if badRep { self.triggerBadRepFeedback(reasons: reasons) }
            switch next {
            case .plank:     self.phaseText = "Plank Hold";     self.phaseColor = .white
            case .tucking:   self.phaseText = "Driving Knee";   self.phaseColor = .yellow
            case .tucked:    self.phaseText = "Knee In ✅";     self.phaseColor = .green
            case .extending: self.phaseText = "Extending Out";  self.phaseColor = .blue
            }
        }
    }

    private func triggerBadRepFeedback(reasons: String) {
        DispatchQueue.main.async {
            self.badRepReason = reasons; self.showBadRepFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.showBadRepFlash = false }
        }
    }

    private func updateFormAlert(result: MountainClimberResult) {
        var msg: String? = nil
        if !result.spineOk { msg = result.hipAngle > 160 ? "Lower Your Hips!" : "Raise Your Hips!" }
        DispatchQueue.main.async {
            if let m = msg {
                self.formAlertMessage = m; self.showFormAlert = true
                self.alertTimer?.invalidate()
                self.alertTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                    DispatchQueue.main.async { self.showFormAlert = false }
                }
            } else { self.showFormAlert = false }
        }
    }

    private func betterSide(_ pts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        func c(_ j: VNHumanBodyPoseObservation.JointName) -> Float { pts[j]?.confidence ?? 0 }
        return (c(.leftShoulder)+c(.leftHip)+c(.leftKnee)+c(.leftAnkle)) >=
               (c(.rightShoulder)+c(.rightHip)+c(.rightKnee)+c(.rightAnkle))
    }

    private func updateBodyPoints(_ pts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        var m: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (j, p) in pts where p.confidence > 0.3 { m[j] = CGPoint(x: p.location.x, y: 1 - p.location.y) }
        DispatchQueue.main.async { self.bodyPoints = m }
    }

    private func calculateAngle(first: CGPoint, middle: CGPoint, last: CGPoint) -> Double {
        let a = atan2(first.y-middle.y, first.x-middle.x)
        let b = atan2(last.y-middle.y,  last.x-middle.x)
        var angle = abs((a-b) * 180 / Double.pi)
        if angle > 180 { angle = 360-angle }
        return angle
    }

    private func smooth(_ r: MountainClimberResult) -> (spine: Double, knee: Double, hip: Double) {
        angleBuffer.append((r.spineAngle, r.kneeAngle, r.hipAngle))
        if angleBuffer.count > bufferSize { angleBuffer.removeFirst() }
        let n = Double(angleBuffer.count)
        return (angleBuffer.map(\.spine).reduce(0,+)/n,
                angleBuffer.map(\.knee).reduce(0,+)/n,
                angleBuffer.map(\.hip).reduce(0,+)/n)
    }
}

