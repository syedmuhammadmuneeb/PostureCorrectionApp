//
//  BurpeeView.swift
//  PostureCorrect
//
//  Created by Syed Muhammad Muneeb on 30/05/26.
//

//
//  BurpeeView.swift
//  PostureCorrect
//
//  Camera placement: SIDE-ON — phone level with the user's hips, ~2 m away.
//  Enough vertical space needed to capture the full standing position.
//
//  ─────────────────────────────────────────────────────────────────────────
//  EXERCISE MECHANICS
//  ─────────────────────────────────────────────────────────────────────────
//  Burpee phases (in order):
//    1. STANDING   — upright, arms at sides
//    2. CROUCH     — hands hit floor, knees bent
//    3. PLANK      — jump feet back to plank position
//    4. PUSH-UP    — chest lowered (optional but we detect it)
//    5. PUSH-UP UP — return to plank
//    6. JUMP-IN    — jump feet back toward hands (crouch)
//    7. JUMP-UP    — explosive upward jump, arms overhead
//    8. LAND       — return to standing → rep complete
//
//  We simplify to four macro-phases detected by spine angle + hip height:
//    STANDING  : spineAngle > 60° (upright body)
//    CROUCH    : spineAngle 35°–60° AND hip low (transitioning to plank)
//    PLANK     : spineAngle < 30° (horizontal body)
//    JUMP      : hip y rises sharply above standing baseline (jump detected)
//
//  ─────────────────────────────────────────────────────────────────────────
//  KEY ANGLES
//  ─────────────────────────────────────────────────────────────────────────
//  1. Spine angle — deviation of shoulder→hip from horizontal.
//     Standing: ~70°–90°. Plank: ≤ 20°. Crouch: 30°–60°.
//     We use this as the primary phase discriminator.
//
//  2. Hip angle (shoulder→hip→knee).
//     In plank: ~160°–180°. In crouch/jump-in: ~60°–120°.
//     Detects plank form quality.
//
//  3. Elbow angle (shoulder→elbow→wrist) — optional push-up detection.
//     At push-up bottom: ~70°–110°. Arms extended: ~150°–180°.
//
//  4. Jump detection: hip Y rises above standing baseline + jumpThreshold.
//     We track the peak hip Y per rep to confirm the jump happened.
//
//  ─────────────────────────────────────────────────────────────────────────
//  REP STATE MACHINE  (sequential phase detection)
//  ─────────────────────────────────────────────────────────────────────────
//  A burpee rep requires visiting these phases in order:
//    STANDING → PLANK → STANDING (with jump)
//
//  Gates:
//  Gate 1: spineAngle < plankTrigger (< 30°) for 3 frames → plankReached
//  Gate 2: hip Y rises > standingHipY + jumpThreshold for 2 frames → jumpDetected
//  Gate 3: spineAngle > standingTrigger (> 55°) for 3 frames after jump → rep complete
//
//  Form errors: back not flat in plank; no jump detected
//

import SwiftUI
import AVFoundation
import Vision
import Combine

// MARK: - BURPEE ISSUE
enum BurpeeIssue: String {
    case correct       = "✅ Good Burpee"
    case ready         = "🧍 Stand Tall, Ready"
    case backNotFlat   = "❌ Keep Plank Back Flat"
    case hipsSagging   = "❌ Hips Sagging in Plank"
    case noJump        = "❌ Jump at the Top!"
    case detecting     = "🔍 Detecting..."
    case notVisible    = "📷 Full Body Not Visible"
}

// MARK: - BURPEE PHASE
enum BurpeePhase { case standing, crouching, plank, jumpingUp, landing }

// MARK: - BURPEE RESULT
struct BurpeeResult {
    var issue: BurpeeIssue = .detecting
    var postureScore: Int  = 100
    // spineAngle: shoulder→hip deviation from horizontal
    var spineAngle:  Double = 80
    // hipAngle:   shoulder→hip→knee — plank form quality
    var hipAngle:    Double = 170
    // elbowAngle: shoulder→elbow→wrist — push-up detection
    var elbowAngle:  Double = 170
    // hipRise: how much the hip has risen above the standing baseline (×100 for display)
    var hipRise:     Double = 0
    var trackedLeftSide: Bool = true
    var spineOk: Bool = true
    var hipOk:   Bool = true
    var formIsValid: Bool { spineOk && hipOk }
}

// MARK: - BURPEE CAMERA VIEW
struct BurpeeCameraView: View {
    @StateObject private var viewModel = BurpeeViewModel()

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.session).ignoresSafeArea()
            BurpeeSkeletonOverlay(bodyPoints: viewModel.bodyPoints,
                                  result: viewModel.result).ignoresSafeArea()
            VStack {
                topBar; Spacer()
                if viewModel.showFormAlert {
                    BurpeeAlertBanner(message: viewModel.formAlertMessage)
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
                Text("Burpee AI").font(.title2.bold()).foregroundColor(.white)
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
                BurpeeAngleCard(title: "Back", angle: viewModel.result.spineAngle,
                                isOk: viewModel.result.spineOk, idealRange: "Plank ≤20°")
                BurpeeAngleCard(title: "Hip", angle: viewModel.result.hipAngle,
                                isOk: viewModel.result.hipOk, idealRange: "Plank ≥155°")
                BurpeeAngleCard(title: "Elbow", angle: viewModel.result.elbowAngle,
                                isOk: true, idealRange: "70°-110°")
                BurpeeAngleCard(title: "Jump", angle: viewModel.result.hipRise,
                                isOk: viewModel.result.hipRise > 3.0, idealRange: ">3 rise")
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

struct BurpeeAlertBanner: View {
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

struct BurpeeAngleCard: View {
    let title: String; let angle: Double; let isOk: Bool; let idealRange: String
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundColor(.white.opacity(0.7))
            Text("\(Int(angle))°").font(.headline.bold()).foregroundColor(isOk ? .green : .red)
            Text(idealRange).font(.system(size: 9)).foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(isOk ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
        .cornerRadius(12)
    }
}

// MARK: - SKELETON OVERLAY
struct BurpeeSkeletonOverlay: View {
    let bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let result: BurpeeResult

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let s  = result.trackedLeftSide
                let wr: VNHumanBodyPoseObservation.JointName = s ? .leftWrist    : .rightWrist
                let el: VNHumanBodyPoseObservation.JointName = s ? .leftElbow    : .rightElbow
                let sh: VNHumanBodyPoseObservation.JointName = s ? .leftShoulder : .rightShoulder
                let hp: VNHumanBodyPoseObservation.JointName = s ? .leftHip      : .rightHip
                let kn: VNHumanBodyPoseObservation.JointName = s ? .leftKnee     : .rightKnee
                let an: VNHumanBodyPoseObservation.JointName = s ? .leftAnkle    : .rightAnkle

                drawLine(wr, el, geo, ok: true)
                drawLine(el, sh, geo, ok: true)
                drawLine(sh, hp, geo, ok: result.spineOk)
                drawLine(hp, kn, geo, ok: result.hipOk)
                drawLine(kn, an, geo, ok: result.hipOk)

                ForEach([wr, el, sh, hp, kn, an], id: \.self) { j in
                    if let pt = bodyPoints[j] {
                        Circle().fill(result.spineOk && result.hipOk ? Color.green : Color.red)
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
final class BurpeeViewModel: NSObject, ObservableObject,
                               AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    @Published var bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var result     = BurpeeResult()
    @Published var reps       = 0
    @Published var phaseText  = "Stand Tall"
    @Published var phaseColor: Color = .white
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var showFormAlert    = false
    @Published var formAlertMessage = ""
    @Published var showBadRepFlash  = false
    @Published var badRepReason     = ""

    // ── Thresholds ────────────────────────────────────────────────────────────
    // Phase discrimination via spine angle
    private let standingSpineMin: Double = 55    // above this → person is upright
    private let plankSpineMax:    Double = 30    // below this → person is in plank
    private let hipMin:           Double = 150   // plank form: hip angle must be ≥ this
    private let plankSpineMax2:   Double = 22    // strict plank back-flat threshold

    // Jump detection: hip Y must rise this many frame-height fractions above baseline
    private let jumpThreshold:    Double = 0.06  // 6% of frame height

    private let framesForPlank:  Int = 3
    private let framesForJump:   Int = 2
    private let framesForLand:   Int = 3
    private let errorLatch:      Int = 4

    // ── Baseline ──────────────────────────────────────────────────────────────
    // Standing hip Y baseline (captured when person is upright at start)
    private var standingHipY:    Double? = nil
    private var baselineFrames   = 0
    private var baselineCaptured = false
    private let baselineRequired = 8

    // ── Smoothing ─────────────────────────────────────────────────────────────
    private var angleBuffer: [(spine: Double, hip: Double, elbow: Double)] = []
    private let bufferSize = 5

    // ── Rep state ─────────────────────────────────────────────────────────────
    private var repInProgress   = false
    private var plankReached    = false
    private var jumpDetected    = false
    private var peakHipY:       Double = 0
    private var framesAtPlank   = 0
    private var framesAtJump    = 0
    private var framesAtLand    = 0
    private var currentPhase: BurpeePhase = .standing

    private var spineErrFrames  = 0; private var hadSpineError = false
    private var hipErrFrames    = 0; private var hadHipError   = false

    private var stableIssueFrames = 0
    private var lastIssue: BurpeeIssue = .detecting
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
            self.repInProgress = false; self.plankReached = false
            self.jumpDetected = false; self.peakHipY = 0
            self.framesAtPlank = 0; self.framesAtJump = 0; self.framesAtLand = 0
            self.spineErrFrames = 0; self.hadSpineError = false
            self.hipErrFrames = 0; self.hadHipError = false
            self.standingHipY = nil; self.baselineFrames = 0; self.baselineCaptured = false
            self.currentPhase = .standing
            self.phaseText = "Stand Tall"; self.phaseColor = .white
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
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "burpeeVideoQueue"))
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
            guard var r = extractAngles(from: pts) else {
                DispatchQueue.main.async { self.result.issue = .notVisible }; return
            }
            let s = smooth(r)
            r.spineAngle = s.spine; r.hipAngle = s.hip; r.elbowAngle = s.elbow
            updateBaseline(result: r, rawPoints: pts)
            evaluateForm(result: &r)
            updatePhaseAndReps(result: r, rawPoints: pts)
            if r.issue == lastIssue { stableIssueFrames += 1 }
            else { stableIssueFrames = 0; lastIssue = r.issue }
            var pub = r; if stableIssueFrames < 3 { pub.issue = result.issue }
            updateFormAlert(result: pub)
            DispatchQueue.main.async { self.result = pub }
        } catch { print("Burpee Vision error: \(error)") }
    }

    private func extractAngles(from pts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint])
        -> BurpeeResult? {
        let useLeft = betterSide(pts)
        let sh: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder
        let hp: VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let kn: VNHumanBodyPoseObservation.JointName = useLeft ? .leftKnee     : .rightKnee
        let el: VNHumanBodyPoseObservation.JointName = useLeft ? .leftElbow    : .rightElbow
        let wr: VNHumanBodyPoseObservation.JointName = useLeft ? .leftWrist    : .rightWrist
        for j in [sh, hp, kn] { guard let p = pts[j], p.confidence > 0.35 else { return nil } }
        var r = BurpeeResult(); r.trackedLeftSide = useLeft
        let sh_ = pts[sh]!.location; let hp_ = pts[hp]!.location; let kn_ = pts[kn]!.location
        let spRad = atan2(sh_.y - hp_.y, sh_.x - hp_.x) * 180 / .pi
        r.spineAngle = min(abs(spRad), 90)
        r.hipAngle   = calculateAngle(first: sh_, middle: hp_, last: kn_)
        if let elPt = pts[el], let wrPt = pts[wr], elPt.confidence > 0.3, wrPt.confidence > 0.3 {
            r.elbowAngle = calculateAngle(first: sh_, middle: elPt.location, last: wrPt.location)
        }
        return r
    }

    private func updateBaseline(result: BurpeeResult,
                                rawPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        guard !baselineCaptured else { return }
        let useLeft = result.trackedLeftSide
        let hpKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip : .rightHip
        guard let hpPt = rawPoints[hpKey], hpPt.confidence > 0.35 else { return }
        let isStanding = result.spineAngle > standingSpineMin
        if isStanding {
            baselineFrames += 1
            let w = 1.0 / Double(baselineFrames)
            standingHipY = (standingHipY ?? hpPt.location.y) * (1-w) + hpPt.location.y * w
            if baselineFrames >= baselineRequired { baselineCaptured = true }
        } else { baselineFrames = 0; standingHipY = nil }
    }

    private func evaluateForm(result: inout BurpeeResult) {
        let inPlank = result.spineAngle < plankSpineMax
        result.spineOk = !inPlank || result.spineAngle <= plankSpineMax2
        result.hipOk   = !inPlank || result.hipAngle >= hipMin
        var score = 100
        if !result.spineOk { score -= 40 }; if !result.hipOk { score -= 35 }
        result.postureScore = max(score, 0)
        if !result.spineOk      { result.issue = .backNotFlat }
        else if !result.hipOk   { result.issue = .hipsSagging }
        else                    { result.issue = .correct }
    }

    private func updatePhaseAndReps(result: BurpeeResult,
                                    rawPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        guard baselineCaptured, let hipBase = standingHipY else {
            DispatchQueue.main.async { self.phaseText = "Calibrating..."; self.phaseColor = .white.opacity(0.6) }
            return
        }
        let useLeft = result.trackedLeftSide
        let hpKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip : .rightHip
        guard let hpPt = rawPoints[hpKey], hpPt.confidence > 0.35 else { return }
        let hipY   = hpPt.location.y
        let hipRise = hipY - hipBase   // positive if jumped above baseline

        // Update hipRise for display
        var mutableResult = result
        mutableResult.hipRise = max(0, hipRise) * 100

        var next     = currentPhase
        var addRep   = false
        var badRep   = false

        if repInProgress {
            let inPlank = result.spineAngle < plankSpineMax
            if inPlank {
                if !result.spineOk { spineErrFrames += 1 } else { spineErrFrames = max(0, spineErrFrames - 1) }
                if !result.hipOk   { hipErrFrames   += 1 } else { hipErrFrames   = max(0, hipErrFrames   - 1) }
            }
            if spineErrFrames >= errorLatch { hadSpineError = true }
            if hipErrFrames   >= errorLatch { hadHipError   = true }
            peakHipY = max(peakHipY, hipY)
        }

        let isStanding = result.spineAngle > standingSpineMin
        let isPlank    = result.spineAngle < plankSpineMax
        let isCrouching = !isStanding && !isPlank

        // Detect transition from standing to crouching/plank → start rep
        if !repInProgress && !isStanding {
            repInProgress = true; plankReached = false; jumpDetected = false
            peakHipY = hipY; framesAtPlank = 0; framesAtJump = 0; framesAtLand = 0
            next = .crouching
        }

        // Gate 1: reached plank
        if repInProgress && isPlank {
            framesAtPlank += 1
            if framesAtPlank >= framesForPlank { plankReached = true; next = .plank }
        } else if isCrouching { framesAtPlank = max(0, framesAtPlank - 1) }

        // Gate 2: jump detected (hip rises above standing baseline)
        if repInProgress && hipRise >= jumpThreshold {
            framesAtJump += 1
            if framesAtJump >= framesForJump { jumpDetected = true; next = .jumpingUp }
        } else if repInProgress && !jumpDetected { framesAtJump = max(0, framesAtJump - 1) }

        // Gate 3: returned to standing (after jump)
        if repInProgress && jumpDetected && isStanding {
            framesAtLand += 1
            if framesAtLand >= framesForLand {
                if plankReached && jumpDetected {
                    let goodForm = !hadSpineError && !hadHipError
                    if goodForm { addRep = true } else { badRep = true }
                } else if !plankReached {
                    badRep = true   // skipped the plank
                } else {
                    badRep = true   // no jump
                }
                repInProgress = false; plankReached = false; jumpDetected = false
                peakHipY = 0; framesAtPlank = 0; framesAtJump = 0; framesAtLand = 0
                spineErrFrames = 0; hadSpineError = false
                hipErrFrames   = 0; hadHipError   = false
                next = .standing
            }
        } else if !jumpDetected { framesAtLand = max(0, framesAtLand - 1) }

        // Phase from spine angle when not in state-machine transitions
        if !repInProgress {
            if isStanding { next = .standing }
            else if isCrouching { next = .crouching }
        }

        currentPhase = next
        var reasons: [String] = []
        if hadSpineError { reasons.append("Back not flat in plank") }
        if hadHipError   { reasons.append("Hips sagging in plank") }
        if !plankReached { reasons.append("Skipped plank position") }
        if !jumpDetected { reasons.append("Jump not detected") }
        let reasonStr = reasons.isEmpty ? "Incomplete rep" : reasons.joined(separator: " • ")

        DispatchQueue.main.async {
            if addRep { self.reps += 1 }
            if badRep { self.triggerBadRepFeedback(reasons: reasonStr) }
            switch next {
            case .standing:   self.phaseText = "Standing";       self.phaseColor = .white
            case .crouching:  self.phaseText = "Going Down";     self.phaseColor = .yellow
            case .plank:      self.phaseText = "Plank ✅";       self.phaseColor = .green
            case .jumpingUp:  self.phaseText = "Jump! 🚀";       self.phaseColor = .cyan
            case .landing:    self.phaseText = "Landing";        self.phaseColor = .blue
            }
        }
    }

    private func triggerBadRepFeedback(reasons: String) {
        DispatchQueue.main.async {
            self.badRepReason = reasons; self.showBadRepFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.showBadRepFlash = false }
        }
    }

    private func updateFormAlert(result: BurpeeResult) {
        guard currentPhase == .plank else {
            DispatchQueue.main.async { self.showFormAlert = false }; return
        }
        var msg: String? = nil
        if !result.spineOk { msg = "Keep Your Plank Back Flat!" }
        else if !result.hipOk { msg = "Hips Are Sagging — Raise Them!" }
        DispatchQueue.main.async {
            if let m = msg {
                self.formAlertMessage = m; self.showFormAlert = true
                self.alertTimer?.invalidate()
                self.alertTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    DispatchQueue.main.async { self.showFormAlert = false }
                }
            } else { self.showFormAlert = false }
        }
    }

    private func betterSide(_ pts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        func c(_ j: VNHumanBodyPoseObservation.JointName) -> Float { pts[j]?.confidence ?? 0 }
        return (c(.leftShoulder)+c(.leftHip)+c(.leftKnee)) >= (c(.rightShoulder)+c(.rightHip)+c(.rightKnee))
    }

    private func updateBodyPoints(_ pts: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        var m: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (j, p) in pts where p.confidence > 0.3 { m[j] = CGPoint(x: p.location.x, y: 1-p.location.y) }
        DispatchQueue.main.async { self.bodyPoints = m }
    }

    private func calculateAngle(first: CGPoint, middle: CGPoint, last: CGPoint) -> Double {
        let a = atan2(first.y - middle.y, first.x - middle.x)
        let b = atan2(last.y - middle.y, last.x - middle.x)
        var angle = abs((a - b) * 180.0 / .pi)
        if angle > 180 { angle = 360 - angle }
        return angle
    }

    private func smooth(_ r: BurpeeResult) -> (spine: Double, hip: Double, elbow: Double) {
        angleBuffer.append((r.spineAngle, r.hipAngle, r.elbowAngle))
        if angleBuffer.count > bufferSize { angleBuffer.removeFirst() }
        let n = Double(angleBuffer.count)
        return (angleBuffer.map(\.spine).reduce(0,+)/n,
                angleBuffer.map(\.hip).reduce(0,+)/n,
                angleBuffer.map(\.elbow).reduce(0,+)/n)
    }
}
