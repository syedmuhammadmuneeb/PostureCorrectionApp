//
//  JumpingJackView.swift
//  PostureCorrect
//
//  Created by Syed Muhammad Muneeb on 30/05/26.
//

//
//  JumpingJackView.swift
//  PostureCorrect
//
//  Camera placement: FRONT-FACING — phone in front of the user, ~2 m away.
//  Full body (both shoulders, both hips, both ankles) must be visible.
//  Person stands upright; performs jumping jacks (arms and legs open/close).
//
//  ─────────────────────────────────────────────────────────────────────────
//  EXERCISE MECHANICS
//  ─────────────────────────────────────────────────────────────────────────
//  Jumping jack: start with feet together, arms at sides.
//  Jump to spread feet wide apart while raising arms overhead.
//  Jump back to start position. Each open+close = 1 rep.
//
//  ─────────────────────────────────────────────────────────────────────────
//  KEY MEASUREMENTS  (raw Vision coords, front-facing camera, y=0 bottom)
//  ─────────────────────────────────────────────────────────────────────────
//
//  1. Arm abduction angle
//     Measured as the angle of the shoulder→wrist vector from vertical.
//     Arms at sides: ~0° from vertical (wrist directly below shoulder).
//     Arms overhead: ~160°–180° from vertical (wrist above shoulder).
//     We use LEFT and RIGHT arms independently and average them.
//     Good form: both arms move symmetrically.
//
//  2. Leg spread (ankle separation)
//     We measure the horizontal distance between left and right ankles
//     as a fraction of shoulder width (normalised to body size).
//     Feet together: ratio ~0–0.5
//     Feet spread:   ratio ≥ 1.5 (ankles are ~1.5× shoulder width apart)
//     This is more robust than an angle for a front-facing exercise.
//
//  3. Arm symmetry: abs(leftArmAngle - rightArmAngle) ≤ 30°
//     Flags if one arm is significantly lower than the other.
//
//  4. Full extension: arms must reach ≥ 140° (near overhead) AND
//     ankle spread ratio ≥ 1.5 simultaneously.
//
//  ─────────────────────────────────────────────────────────────────────────
//  REP STATE MACHINE
//  ─────────────────────────────────────────────────────────
//  Gate 1: armAngle > openTrigger (>60°) AND ankleRatio > spreadTrigger (>0.8)
//          → repInProgress (both limbs opening)
//  Gate 2: armAngle ≥ fullOpenAngle (≥140°) AND ankleRatio ≥ fullSpread (≥1.4)
//          for 2 frames → extensionReached
//  Gate 3: armAngle < closedAngle (<40°) AND ankleRatio < closedRatio (<0.5)
//          for 2 frames → rep complete
//

import SwiftUI
import AVFoundation
import Vision
import Combine

// MARK: - JUMPING JACK ISSUE
enum JumpingJackIssue: String {
    case correct        = "✅ Perfect Jack"
    case ready          = "🧍 Stand Tall, Arms Down"
    case armsNotUp      = "❌ Raise Arms Higher"
    case legsNotSpread  = "❌ Spread Legs Wider"
    case armAsymmetry   = "❌ Keep Arms Even"
    case partialRep     = "❌ Full Open Required"
    case detecting      = "🔍 Detecting..."
    case notVisible     = "📷 Full Body Not Visible"
}

// MARK: - JUMPING JACK PHASE
enum JumpingJackPhase { case closed, opening, open, closing }

// MARK: - JUMPING JACK RESULT
struct JumpingJackResult {
    var issue: JumpingJackIssue = .detecting
    var postureScore: Int = 100
    // armAngle: average of left+right shoulder→wrist angle from vertical (0=down, 180=overhead)
    var armAngle:     Double = 0
    // leftArmAngle / rightArmAngle: individual arm angles
    var leftArmAngle:  Double = 0
    var rightArmAngle: Double = 0
    // ankleRatio: ankle separation / shoulder width (normalised)
    var ankleRatio:    Double = 0
    // armSymmetry: difference between left and right arm angles
    var armSymmetry:   Double = 0
    var armsOk:       Bool = true
    var legsOk:       Bool = true
    var symmetryOk:   Bool = true
    var formIsValid: Bool { armsOk && legsOk && symmetryOk }
}

// MARK: - JUMPING JACK CAMERA VIEW
struct JumpingJackCameraView: View {
    @StateObject private var viewModel = JumpingJackViewModel()

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.session).ignoresSafeArea()
            JumpingJackSkeletonOverlay(bodyPoints: viewModel.bodyPoints,
                                       result: viewModel.result).ignoresSafeArea()
            VStack {
                topBar; Spacer()
                if viewModel.showFormAlert {
                    JumpingJackAlertBanner(message: viewModel.formAlertMessage)
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
                Text("Jumping Jack AI").font(.title2.bold()).foregroundColor(.white)
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
            HStack(spacing: 8) {
                JumpingJackAngleCard(title: "Arms",
                                     value: viewModel.result.armAngle,
                                     isOk:  viewModel.result.armsOk, idealRange: "≥140°")
                JumpingJackAngleCard(title: "Leg Spread",
                                     value: viewModel.result.ankleRatio,
                                     isOk:  viewModel.result.legsOk, idealRange: "×1.4+",
                                     isRatio: true)
                JumpingJackAngleCard(title: "Symmetry",
                                     value: viewModel.result.armSymmetry,
                                     isOk:  viewModel.result.symmetryOk, idealRange: "≤30°")
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

struct JumpingJackAlertBanner: View {
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

struct JumpingJackAngleCard: View {
    let title: String; let value: Double; let isOk: Bool; let idealRange: String
    var isRatio: Bool = false
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundColor(.white.opacity(0.7))
            Text(isRatio ? String(format: "×%.1f", value) : "\(Int(value))°")
                .font(.headline.bold()).foregroundColor(isOk ? .green : .red)
            Text(idealRange).font(.caption2).foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(isOk ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
        .cornerRadius(12)
    }
}

// MARK: - SKELETON OVERLAY
// Front-facing: draws both arms and both legs plus torso
struct JumpingJackSkeletonOverlay: View {
    let bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let result: JumpingJackResult

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Torso centre line
                drawLine(.leftShoulder, .rightShoulder, geo, ok: true)
                drawLine(.leftHip,      .rightHip,      geo, ok: true)
                drawLine(.leftShoulder, .leftHip,       geo, ok: true)
                drawLine(.rightShoulder,.rightHip,      geo, ok: true)

                // Arms
                drawLine(.leftShoulder,  .leftElbow,   geo, ok: result.armsOk && result.symmetryOk)
                drawLine(.leftElbow,     .leftWrist,   geo, ok: result.armsOk && result.symmetryOk)
                drawLine(.rightShoulder, .rightElbow,  geo, ok: result.armsOk && result.symmetryOk)
                drawLine(.rightElbow,    .rightWrist,  geo, ok: result.armsOk && result.symmetryOk)

                // Legs
                drawLine(.leftHip,  .leftKnee,   geo, ok: result.legsOk)
                drawLine(.leftKnee, .leftAnkle,  geo, ok: result.legsOk)
                drawLine(.rightHip, .rightKnee,  geo, ok: result.legsOk)
                drawLine(.rightKnee,.rightAnkle, geo, ok: result.legsOk)

                // Dots for key joints
                let joints: [VNHumanBodyPoseObservation.JointName] = [
                    .leftShoulder, .rightShoulder, .leftHip, .rightHip,
                    .leftWrist, .rightWrist, .leftAnkle, .rightAnkle
                ]
                ForEach(joints, id: \.self) { j in
                    if let pt = bodyPoints[j] {
                        Circle().fill(dotColor(for: j)).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                            .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                    }
                }
            }
        }
    }

    private func dotColor(for joint: VNHumanBodyPoseObservation.JointName) -> Color {
        switch joint {
        case .leftWrist, .leftElbow, .leftShoulder:
            return result.armsOk ? .green : .red
        case .rightWrist, .rightElbow, .rightShoulder:
            return result.armsOk ? .green : .red
        case .leftAnkle, .leftKnee, .rightAnkle, .rightKnee:
            return result.legsOk ? .green : .red
        default: return .white
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
            .stroke(ok ? Color.green : Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }
}

// MARK: - VIEW MODEL
final class JumpingJackViewModel: NSObject, ObservableObject,
                                    AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    @Published var bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var result     = JumpingJackResult()
    @Published var reps       = 0
    @Published var phaseText  = "Stand Ready"
    @Published var phaseColor: Color = .white
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var showFormAlert    = false
    @Published var formAlertMessage = ""
    @Published var showBadRepFlash  = false
    @Published var badRepReason     = ""

    // ── Thresholds ────────────────────────────────────────────────────────────
    // Arm angle from vertical (0=down, 180=overhead)
    private let openTrigger:    Double = 60    // Gate 1: arms starting to open
    private let fullOpenAngle:  Double = 140   // Gate 2: arms near overhead
    private let closedAngle:    Double = 40    // Gate 3: arms back down

    // Ankle spread ratio (ankle separation / shoulder width)
    private let spreadTrigger:  Double = 0.8   // Gate 1: legs starting to spread
    private let fullSpread:     Double = 1.4   // Gate 2: full spread
    private let closedRatio:    Double = 0.5   // Gate 3: legs back together

    // Symmetry tolerance
    private let symmetryMax:    Double = 30

    // Frame counts — fast exercise
    private let framesForOpen:  Int = 2
    private let framesForClose: Int = 2
    private let errorLatch:     Int = 4

    // ── Smoothing ─────────────────────────────────────────────────────────────
    private var buffer: [(arm: Double, lArm: Double, rArm: Double, ankle: Double)] = []
    private let bufferSize = 4

    // ── Rep state ─────────────────────────────────────────────────────────────
    private var repInProgress    = false
    private var extensionReached = false
    private var framesAtOpen     = 0
    private var framesAtClose    = 0
    private var currentPhase: JumpingJackPhase = .closed

    private var armsErrFrames = 0; private var hadArmsError  = false
    private var legsErrFrames = 0; private var hadLegsError  = false
    private var asymErrFrames = 0; private var hadAsymError  = false

    private var stableIssueFrames = 0
    private var lastIssue: JumpingJackIssue = .detecting
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
            self.reps = 0; self.buffer.removeAll()
            self.repInProgress = false; self.extensionReached = false
            self.framesAtOpen = 0; self.framesAtClose = 0
            self.armsErrFrames = 0; self.hadArmsError = false
            self.legsErrFrames = 0; self.hadLegsError = false
            self.asymErrFrames = 0; self.hadAsymError = false
            self.currentPhase = .closed
            self.phaseText = "Stand Ready"; self.phaseColor = .white
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
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "jjVideoQueue"))
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

    // MARK: - Analysis
    private func analyzeFrame(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        do {
            try handler.perform([request])
            guard let obs = request.results?.first else { return }
            let pts = try obs.recognizedPoints(.all)
            updateBodyPoints(pts)
            guard var r = extractMeasurements(from: pts) else {
                DispatchQueue.main.async { self.result.issue = .notVisible }; return
            }
            let s = smooth(r)
            r.armAngle = s.arm; r.leftArmAngle = s.lArm; r.rightArmAngle = s.rArm; r.ankleRatio = s.ankle
            r.armSymmetry = abs(r.leftArmAngle - r.rightArmAngle)
            evaluateForm(result: &r)
            updatePhaseAndReps(result: r)
            if r.issue == lastIssue { stableIssueFrames += 1 }
            else { stableIssueFrames = 0; lastIssue = r.issue }
            var pub = r; if stableIssueFrames < 3 { pub.issue = result.issue }
            updateFormAlert(result: pub)
            DispatchQueue.main.async { self.result = pub }
        } catch { print("JJ Vision error: \(error)") }
    }

    private func extractMeasurements(from pts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint])
        -> JumpingJackResult? {
        // Front-facing: require both sides
        let required: [VNHumanBodyPoseObservation.JointName] = [
            .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftAnkle, .rightAnkle
        ]
        for j in required { guard let p = pts[j], p.confidence > 0.35 else { return nil } }

        let lSh = pts[.leftShoulder]!.location
        let rSh = pts[.rightShoulder]!.location
        // Hips validated above but not used in current measurements.
        // let lHip = pts[.leftHip]!.location
        // let rHip = pts[.rightHip]!.location
        let lAnk = pts[.leftAnkle]!.location
        let rAnk = pts[.rightAnkle]!.location

        var r = JumpingJackResult()

        // ── Arm angles from vertical ─────────────────────────────────────────
        // For a front-facing camera, the arm is in the same image plane.
        // We measure the angle from vertical using atan2.
        // Arm straight down (at side): atan2 toward negative y → ~-90° from horizontal → ~0° from vertical
        // Arm straight up (overhead): atan2 toward positive y → ~+90° from horizontal → ~180° from vertical
        // We map: angleFromVertical = 90 + atan2(wrist.y - shoulder.y, wrist.x - shoulder.x) * 180/π
        // which gives 0° when arm is fully down and 180° when arm is overhead.

        func armAngleFromVertical(shoulder: CGPoint, wrist: CGPoint) -> Double {
            let raw = atan2(wrist.y - shoulder.y, wrist.x - shoulder.x) * 180 / .pi
            // raw: pointing straight up in Vision (y increases up) → ~+90°
            //      pointing straight down → ~-90°
            // Convert: add 90 to shift range from [-90,90] to [0,180]
            return max(0, min(180, raw + 90))
        }

        if let lWrPt = pts[.leftWrist], lWrPt.confidence > 0.3 {
            r.leftArmAngle = armAngleFromVertical(shoulder: lSh, wrist: lWrPt.location)
        }
        if let rWrPt = pts[.rightWrist], rWrPt.confidence > 0.3 {
            r.rightArmAngle = armAngleFromVertical(shoulder: rSh, wrist: rWrPt.location)
        }
        r.armAngle = (r.leftArmAngle + r.rightArmAngle) / 2
        r.armSymmetry = abs(r.leftArmAngle - r.rightArmAngle)

        // ── Ankle spread ratio ───────────────────────────────────────────────
        // Normalise ankle separation by shoulder width so body-to-camera
        // distance doesn't affect the measurement.
        let shoulderWidth = abs(lSh.x - rSh.x)
        let ankleWidth    = abs(lAnk.x - rAnk.x)
        // Avoid division by zero; fallback to 1.0 shoulder width
        r.ankleRatio = shoulderWidth > 0.01 ? ankleWidth / shoulderWidth : 0

        return r
    }

    private func evaluateForm(result: inout JumpingJackResult) {
        let opening = result.armAngle > openTrigger || result.ankleRatio > spreadTrigger
        result.armsOk     = !opening || result.armAngle >= fullOpenAngle
        result.legsOk     = !opening || result.ankleRatio >= fullSpread
        result.symmetryOk = result.armSymmetry <= symmetryMax

        var score = 100
        if !result.armsOk     { score -= 35 }
        if !result.legsOk     { score -= 35 }
        if !result.symmetryOk { score -= 20 }
        result.postureScore = max(score, 0)

        if !result.symmetryOk { result.issue = .armAsymmetry }
        else if !result.armsOk  { result.issue = .armsNotUp }
        else if !result.legsOk  { result.issue = .legsNotSpread }
        else                    { result.issue = .correct }
    }

    private func updatePhaseAndReps(result: JumpingJackResult) {
        let arm   = result.armAngle
        let ankle = result.ankleRatio
        var next  = currentPhase
        var addRep = false; var badRep = false

        if repInProgress {
            if !result.armsOk     { armsErrFrames += 1 } else { armsErrFrames = max(0, armsErrFrames - 1) }
            if !result.legsOk     { legsErrFrames += 1 } else { legsErrFrames = max(0, legsErrFrames - 1) }
            if !result.symmetryOk { asymErrFrames += 1 } else { asymErrFrames = max(0, asymErrFrames - 1) }
            if armsErrFrames >= errorLatch { hadArmsError = true }
            if legsErrFrames >= errorLatch { hadLegsError = true }
            if asymErrFrames >= errorLatch { hadAsymError = true }
        }

        let bothOpening = arm > openTrigger && ankle > spreadTrigger
        let bothOpen    = arm >= fullOpenAngle && ankle >= fullSpread
        let bothClosed  = arm < closedAngle && ankle < closedRatio

        // Gate 1
        if !repInProgress && bothOpening {
            repInProgress = true; extensionReached = false
            framesAtOpen = 0; framesAtClose = 0; next = .opening
        }

        if repInProgress && bothOpening { next = .opening }

        // Gate 2
        if repInProgress && bothOpen {
            framesAtOpen += 1
            if framesAtOpen >= framesForOpen { extensionReached = true; next = .open }
        } else { framesAtOpen = max(0, framesAtOpen - 1) }

        if extensionReached && !bothOpen && !bothClosed { next = .closing }

        // Gate 3
        if repInProgress && bothClosed {
            framesAtClose += 1
            if framesAtClose >= framesForClose {
                if extensionReached {
                    let goodForm = !hadArmsError && !hadLegsError && !hadAsymError
                    if goodForm { addRep = true } else { badRep = true }
                } else { badRep = true }
                repInProgress = false; extensionReached = false
                framesAtOpen = 0; framesAtClose = 0
                armsErrFrames = 0; hadArmsError = false
                legsErrFrames = 0; hadLegsError = false
                asymErrFrames = 0; hadAsymError = false
                next = .closed
            }
        } else { framesAtClose = max(0, framesAtClose - 1) }

        if !repInProgress { next = bothClosed ? .closed : .closing }

        currentPhase = next
        var reasons: [String] = []
        if hadArmsError  { reasons.append("Arms not raised high enough") }
        if hadLegsError  { reasons.append("Legs not spread wide enough") }
        if hadAsymError  { reasons.append("Arms uneven") }
        if !extensionReached { reasons.append("Didn't fully open") }
        let reasonStr = reasons.isEmpty ? "Didn't fully open" : reasons.joined(separator: " • ")

        DispatchQueue.main.async {
            if addRep { self.reps += 1 }
            if badRep { self.triggerBadRepFeedback(reasons: reasonStr) }
            switch next {
            case .closed:  self.phaseText = "Closed";       self.phaseColor = .white
            case .opening: self.phaseText = "Opening Out";  self.phaseColor = .yellow
            case .open:    self.phaseText = "Full Open ✅"; self.phaseColor = .green
            case .closing: self.phaseText = "Closing In";   self.phaseColor = .blue
            }
        }
    }

    private func triggerBadRepFeedback(reasons: String) {
        DispatchQueue.main.async {
            self.badRepReason = reasons; self.showBadRepFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.showBadRepFlash = false }
        }
    }

    private func updateFormAlert(result: JumpingJackResult) {
        guard currentPhase == .opening || currentPhase == .open else {
            DispatchQueue.main.async { self.showFormAlert = false }; return
        }
        var msg: String? = nil
        if !result.symmetryOk  { msg = "Keep Both Arms Even!" }
        else if !result.armsOk { msg = "Raise Arms Higher!" }
        else if !result.legsOk { msg = "Spread Legs Wider!" }
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

    private func updateBodyPoints(_ pts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        var m: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (j, p) in pts where p.confidence > 0.3 { m[j] = CGPoint(x: p.location.x, y: 1-p.location.y) }
        DispatchQueue.main.async { self.bodyPoints = m }
    }

    private func smooth(_ r: JumpingJackResult)
        -> (arm: Double, lArm: Double, rArm: Double, ankle: Double) {
        buffer.append((r.armAngle, r.leftArmAngle, r.rightArmAngle, r.ankleRatio))
        if buffer.count > bufferSize { buffer.removeFirst() }
        let n = Double(buffer.count)
        return (buffer.map(\.arm).reduce(0,+)/n,
                buffer.map(\.lArm).reduce(0,+)/n,
                buffer.map(\.rArm).reduce(0,+)/n,
                buffer.map(\.ankle).reduce(0,+)/n)
    }
}
