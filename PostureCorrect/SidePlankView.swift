//
//  SidePlankView.swift
//  PostureCorrect
//
//  Created by Syed Muhammad Muneeb on 30/05/26.
//

//
//  SidePlankView.swift
//  PostureCorrect
//
//  Camera placement: SIDE-ON — phone on the floor to the side of the user,
//  pointing toward them. The full body (ear → shoulder → hip → ankle) must
//  be visible on the camera side.
//
//  Key angles for a correct side plank:
//
//  1. Body-line angle (shoulder → hip → ankle)
//     A straight body means these three joints are collinear, i.e. the
//     angle at the hip is ~180°. Dropping the hip reduces this angle;
//     raising it piked increases it past 180° (clamped to 180 by our
//     atan2 formula, so we check the hip-to-floor *elevation* instead —
//     see bodyLineAngle below).
//
//  2. Spine (torso) angle — deviation of shoulder→hip line from horizontal.
//     In a perfect side plank the torso is horizontal, so this should be
//     near 0°. If the body rotates forward/back it deviates.
//     Acceptable: ≤ 20°.
//
//  3. Top-arm alignment angle — angle of shoulder→wrist relative to vertical.
//     The top arm should point straight up (90° from horizontal = vertical),
//     giving good shoulder stacking. We measure deviation from vertical.
//     Acceptable deviation: ≤ 30° (arm between 60°–120° from horizontal).
//
//  4. Neck angle — deviation of ear→shoulder line from horizontal.
//     Head should stay in line with the spine (parallel to ground).
//     Acceptable: ≤ 25°.
//
//  Note: Vision's y-axis is FLIPPED relative to screen (y=0 at bottom).
//  updateBodyPoints() corrects this for the overlay with (1 - y).
//  All angle calculations use raw Vision coordinates (not flipped).
//

import SwiftUI
import AVFoundation
import Vision
import Combine

// MARK: - SIDE PLANK ISSUE
enum SidePlankIssue: String {
    case correct        = "✅ Perfect Side Plank"
    case ready          = "🧍 Get Into Position"
    case hipSagging     = "❌ Raise Your Hip"
    case hipPiked       = "❌ Lower Your Hip"
    case bodyRotated    = "❌ Keep Body Facing Side"
    case armNotUp       = "❌ Raise Top Arm Up"
    case headDropping   = "❌ Keep Head Neutral"
    case detecting      = "🔍 Detecting..."
    case notVisible     = "📷 Full Body Not Visible"
}

// MARK: - SIDE PLANK RESULT
struct SidePlankResult {
    var issue: SidePlankIssue = .detecting
    var postureScore: Int     = 100

    // Angles (all smoothed before form evaluation)
    // bodyLineAngle: shoulder → hip → ankle  — target ~175°–180°
    var bodyLineAngle: Double  = 180
    // spineAngle: deviation of shoulder–hip vector from horizontal — target ≤ 20°
    var spineAngle: Double     = 0
    // armAngle: deviation of shoulder–wrist vector from vertical — target ≤ 30°
    var armAngle: Double       = 90
    // neckAngle: deviation of ear–shoulder vector from horizontal — target ≤ 25°
    var neckAngle: Double      = 0

    // Which side is facing the camera (left joints are higher confidence)
    var trackedLeftSide: Bool  = true

    // Per-check pass flags
    var bodyLineOk: Bool = true
    var spineOk:    Bool = true
    var armOk:      Bool = true
    var neckOk:     Bool = true

    var formIsValid: Bool { bodyLineOk && spineOk && armOk && neckOk }
}

// MARK: - SIDE PLANK CAMERA VIEW
struct SidePlankCameraView: View {
    @StateObject private var viewModel = SidePlankViewModel()

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.session).ignoresSafeArea()

            SidePlankSkeletonOverlay(
                bodyPoints: viewModel.bodyPoints,
                result:     viewModel.sidePlankResult
            ).ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if viewModel.showFormAlert {
                    SidePlankAlertBanner(message: viewModel.formAlertMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4), value: viewModel.showFormAlert)
                }
                Spacer()
                bottomPanel
            }

            if viewModel.showFormBreakFlash {
                Color.orange.opacity(0.22)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: viewModel.showFormBreakFlash)
            }
        }
        .onAppear    { viewModel.start() }
        .onDisappear { viewModel.stop()  }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Side Plank AI").font(.title2.bold()).foregroundColor(.white)
                Text("Real-Time Form Check").font(.caption).foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Button { viewModel.switchCamera() } label: {
                Image(systemName: "camera.rotate").font(.title2).foregroundColor(.white)
                    .padding(12).background(Color.white.opacity(0.2)).clipShape(Circle())
            }
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 5).frame(width: 55, height: 55)
                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.sidePlankResult.postureScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 55, height: 55).rotationEffect(.degrees(-90))
                Text("\(viewModel.sidePlankResult.postureScore)")
                    .font(.headline.bold()).foregroundColor(.white)
            }
        }
        .padding().background(.black.opacity(0.65)).cornerRadius(20).padding()
    }

    // MARK: - Bottom panel
    private var bottomPanel: some View {
        VStack(spacing: 14) {
            Text(viewModel.sidePlankResult.issue.rawValue)
                .font(.title2.bold()).foregroundColor(.white)
                .multilineTextAlignment(.center)

            // Four angle cards — one per check
            HStack(spacing: 8) {
                SidePlankAngleCard(title: "Body Line",
                                   angle: viewModel.sidePlankResult.bodyLineAngle,
                                   isOk:  viewModel.sidePlankResult.bodyLineOk,
                                   idealRange: "165°-180°")
                SidePlankAngleCard(title: "Torso",
                                   angle: viewModel.sidePlankResult.spineAngle,
                                   isOk:  viewModel.sidePlankResult.spineOk,
                                   idealRange: "0°-20°")
                SidePlankAngleCard(title: "Top Arm",
                                   angle: viewModel.sidePlankResult.armAngle,
                                   isOk:  viewModel.sidePlankResult.armOk,
                                   idealRange: "0°-30°")
                SidePlankAngleCard(title: "Neck",
                                   angle: viewModel.sidePlankResult.neckAngle,
                                   isOk:  viewModel.sidePlankResult.neckOk,
                                   idealRange: "0°-25°")
            }

            // Timer row
            HStack(spacing: 40) {
                VStack(spacing: 4) {
                    Text(viewModel.formattedTime)
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(viewModel.isHolding ? .green : .white)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: viewModel.formattedTime)
                    Text("TIME").foregroundColor(.white.opacity(0.7)).font(.caption)
                }
                VStack(spacing: 2) {
                    Text(viewModel.formattedBestTime)
                        .font(.title3.bold()).foregroundColor(.yellow)
                    Text("BEST").font(.caption).foregroundColor(.white.opacity(0.7))
                }
                Button { viewModel.resetTimer() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise").font(.title2).foregroundColor(.white)
                        Text("RESET").font(.caption).foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            // Status pill
            Text(viewModel.isHolding ? "🔥 Holding — Keep it up!" : "🛑 Fix your form to start timer")
                .font(.caption.bold())
                .foregroundColor(viewModel.isHolding ? .green : .orange)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background((viewModel.isHolding ? Color.green : Color.orange).opacity(0.15))
                .cornerRadius(20)
        }
        .padding().background(.black.opacity(0.75)).cornerRadius(22).padding()
    }

    private var scoreColor: Color {
        let s = viewModel.sidePlankResult.postureScore
        if s >= 80 { return .green }
        if s >= 55 { return .yellow }
        return .red
    }
}

// MARK: - ALERT BANNER
struct SidePlankAlertBanner: View {
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

// MARK: - ANGLE CARD
struct SidePlankAngleCard: View {
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
// Draws the camera-side body line (ear → shoulder → hip → ankle)
// plus the top arm (shoulder → wrist), all coloured green/red per check.
struct SidePlankSkeletonOverlay: View {
    let bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let result: SidePlankResult

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Camera-side chain ────────────────────────────────────────
                let ear:      VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftEar      : .rightEar
                let shoulder: VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftShoulder : .rightShoulder
                let hip:      VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftHip      : .rightHip
                let knee:     VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftKnee     : .rightKnee
                let ankle:    VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftAnkle    : .rightAnkle

                // ── Top arm (opposite side — the raised arm) ─────────────────
                // In a left-side-down side plank the RIGHT arm points up;
                // in a right-side-down plank the LEFT arm points up.
                let topShoulder: VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .rightShoulder : .leftShoulder
                let topWrist:    VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .rightWrist    : .leftWrist

                // Body-line segments
                drawLine(ear,      shoulder, geo, ok: result.neckOk)
                drawLine(shoulder, hip,      geo, ok: result.spineOk)
                drawLine(hip,      knee,     geo, ok: result.bodyLineOk)
                drawLine(knee,     ankle,    geo, ok: result.bodyLineOk)

                // Top arm segment — connects both shoulders first, then up to wrist
                drawLine(shoulder, topShoulder, geo, ok: result.armOk)
                drawLine(topShoulder, topWrist, geo, ok: result.armOk)

                // Dots
                let joints: [VNHumanBodyPoseObservation.JointName] = [
                    ear, shoulder, hip, knee, ankle, topShoulder, topWrist
                ]
                ForEach(joints, id: \.self) { joint in
                    if let pt = bodyPoints[joint] {
                        Circle()
                            .fill(dotColor(for: joint))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                            .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                    }
                }
            }
        }
    }

    private func dotColor(for joint: VNHumanBodyPoseObservation.JointName) -> Color {
        switch joint {
        case .leftEar,      .rightEar:      return result.neckOk     ? .green : .red
        case .leftShoulder, .rightShoulder: return result.spineOk    ? .green : .red
        case .leftHip,      .rightHip:      return result.bodyLineOk ? .green : .red
        case .leftKnee,     .rightKnee:     return result.bodyLineOk ? .green : .red
        case .leftAnkle,    .rightAnkle:    return result.bodyLineOk ? .green : .red
        case .leftWrist,    .rightWrist:    return result.armOk      ? .green : .red
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

// MARK: - SIDE PLANK VIEW MODEL
final class SidePlankViewModel: NSObject, ObservableObject,
                                 AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    @Published var bodyPoints:      [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var sidePlankResult  = SidePlankResult()
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published var elapsedSeconds:  Int  = 0
    @Published var bestSeconds:     Int  = 0
    @Published var isHolding:       Bool = false
    @Published var showFormAlert      = false
    @Published var formAlertMessage   = ""
    @Published var showFormBreakFlash = false

    // ── Thresholds ────────────────────────────────────────────────────────────
    //
    // Body-line: shoulder → hip → ankle.
    // Perfect side plank = straight body = 180° at the hip.
    // Hip sagging (dropping) bends this angle below ~165°.
    // Hip piking raises the hip, which shortens the angle too (body bows
    // the other way). We detect piking separately via spineAngle going too
    // high AND body-line angle simultaneously below threshold.
    //
    // In practice: if bodyLineAngle < 165° AND spine horizontal → hip dropped.
    //              if bodyLineAngle < 165° AND spine tilted up   → hip piked.
    // We simplify: use hip y-position relative to shoulder/ankle midpoint.
    private let bodyLineMin:   Double = 165   // hip must stay this straight

    // Spine angle: deviation of shoulder→hip line from horizontal (Vision y-flipped).
    // Horizontal body = 0°. Rotating toward camera or away raises this.
    private let spineMax:      Double = 20    // ≤ 20° tilt from horizontal

    // Top-arm angle: deviation of the top-arm (shoulder→wrist) from vertical.
    // Perfect = arm pointing straight up = 90° from horizontal.
    // We compute deviation = |measured_from_horizontal - 90°|, target ≤ 30°.
    private let armDeviationMax: Double = 30

    // Neck angle: deviation of ear→shoulder from horizontal, target ≤ 25°.
    private let neckMax:       Double = 25

    // Timer hysteresis — same as PlankViewModel
    private let goodFramesRequired = 8
    private var consecutiveGoodFrames = 0
    private let badFramesRequired  = 6
    private var consecutiveBadFrames  = 0

    // ── Smoothing ─────────────────────────────────────────────────────────────
    private var angleBuffer: [(bodyLine: Double, spine: Double, arm: Double, neck: Double)] = []
    private let bufferSize = 6

    // ── Debounce ──────────────────────────────────────────────────────────────
    private var stableIssueFrames = 0
    private var lastIssue: SidePlankIssue = .detecting

    private var timerTask:  Task<Void, Never>?
    private var alertTimer: Timer?

    // MARK: - Lifecycle
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            DispatchQueue.global(qos: .userInitiated).async { self.setupCamera() }
        }
    }
    func stop() { session.stopRunning(); stopTimer() }

    func resetTimer() {
        DispatchQueue.main.async {
            self.stopTimer()
            self.elapsedSeconds        = 0
            self.isHolding             = false
            self.consecutiveGoodFrames = 0
            self.consecutiveBadFrames  = 0
            self.angleBuffer.removeAll()
        }
    }

    // MARK: - Camera
    private func setupCamera() {
        guard !session.isRunning else { return }
        session.beginConfiguration(); session.sessionPreset = .high
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition),
            let input  = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { session.commitConfiguration(); return }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sidePlankVideoQueue"))
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
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return }
            let points = try observation.recognizedPoints(.all)

            updateBodyPoints(points)

            guard var result = extractAngles(from: points) else {
                DispatchQueue.main.async { self.sidePlankResult.issue = .notVisible }
                pauseTimer()
                return
            }

            // Smooth all four angles over a sliding window
            let s = smooth(result)
            result.bodyLineAngle = s.bodyLine
            result.spineAngle    = s.spine
            result.armAngle      = s.arm
            result.neckAngle     = s.neck

            evaluateForm(result: &result)
            updateTimerState(result: result)

            // Debounce issue label
            if result.issue == lastIssue { stableIssueFrames += 1 }
            else { stableIssueFrames = 0; lastIssue = result.issue }
            var published = result
            if stableIssueFrames < 3 { published.issue = sidePlankResult.issue }

            updateFormAlert(result: published)
            DispatchQueue.main.async { self.sidePlankResult = published }
        } catch { print("Side plank Vision error: \(error)") }
    }

    // MARK: - Angle extraction
    //
    // All four angles are computed in raw Vision coordinates (y=0 at bottom).
    // We use the side of the body with higher total confidence — that is the
    // side facing the camera, which is the load-bearing side.
    private func extractAngles(
        from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> SidePlankResult? {

        let useLeft = betterSide(points)

        // Camera-side joints (the arm/leg on the ground)
        let earKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftEar      : .rightEar
        let shoulderKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder
        let hipKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let kneeKey:     VNHumanBodyPoseObservation.JointName = useLeft ? .leftKnee     : .rightKnee
        let ankleKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftAnkle    : .rightAnkle

        // Top-arm joints (the arm raised vertically — opposite side)
        let topShoulderKey: VNHumanBodyPoseObservation.JointName = useLeft ? .rightShoulder : .leftShoulder
        let topWristKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .rightWrist    : .leftWrist

        // Require all body-line joints at high confidence
        for j in [earKey, shoulderKey, hipKey, kneeKey, ankleKey] {
            guard let p = points[j], p.confidence > 0.35 else { return nil }
        }

        let ear      = points[earKey]!.location
        let shoulder = points[shoulderKey]!.location
        let hip      = points[hipKey]!.location
        let knee     = points[kneeKey]!.location
        let ankle    = points[ankleKey]!.location

        var result = SidePlankResult()
        result.trackedLeftSide = useLeft

        // ── 1. Body-line angle: shoulder → hip → ankle ───────────────────────
        // In a perfect side plank these three are collinear → 180°.
        // Hip dropping pulls this below ~165°.
        result.bodyLineAngle = calculateAngle(first: shoulder, middle: hip, last: ankle)

        // ── 2. Spine (torso) angle ───────────────────────────────────────────
        // Deviation of the shoulder→hip line from horizontal.
        // Vision y=0 is at the BOTTOM of the frame, so a body lying horizontally
        // has shoulder.y ≈ hip.y → atan2 ≈ 0°. We take abs() so both directions count.
        let spineRaw     = atan2(shoulder.y - hip.y, shoulder.x - hip.x) * 180 / .pi
        result.spineAngle = min(abs(spineRaw), 90)

        // ── 3. Top-arm angle ─────────────────────────────────────────────────
        // We measure how far the top arm deviates from vertical (i.e. from 90°
        // from horizontal). A perfectly raised arm has the wrist directly above
        // the shoulder, giving atan2(wrist-shoulder) ≈ 90° (pointing straight up
        // in Vision space where y increases upward).
        // deviation = |atan2_degrees - 90°|  → target ≤ 30°.
        if let topShPt = points[topShoulderKey], let topWrPt = points[topWristKey],
           topShPt.confidence > 0.25, topWrPt.confidence > 0.25 {
            let topSh = topShPt.location
            let topWr = topWrPt.location
            let armRaw  = atan2(topWr.y - topSh.y, topWr.x - topSh.x) * 180 / .pi
            // atan2 gives angle from horizontal. Vertical-up = 90°, vertical-down = -90°/270°.
            // We want deviation from vertical-up (90°).
            let armFromHorizontal = armRaw < 0 ? armRaw + 360 : armRaw
            result.armAngle = abs(armFromHorizontal - 90)
        } else {
            // If arm not visible, treat as ok (user might be doing elbow variant)
            result.armAngle = 0
        }

        // ── 4. Neck angle ────────────────────────────────────────────────────
        // Deviation of the ear→shoulder line from horizontal. Same formula as
        // PlankViewModel. Head in neutral = parallel to ground = 0°.
        let neckRaw     = atan2(ear.y - shoulder.y, ear.x - shoulder.x) * 180 / .pi
        result.neckAngle = min(abs(neckRaw), 90)

        return result
    }

    // MARK: - Form evaluation
    //
    // Not-in-position guard: if the spine angle is > 45° the person is upright.
    // We use the same guard as PlankViewModel.
    private func evaluateForm(result: inout SidePlankResult) {
        let bodyLine = result.bodyLineAngle
        let spine    = result.spineAngle
        let arm      = result.armAngle
        let neck     = result.neckAngle

        // Guard: body is upright / not in side-plank position yet
        guard spine < 45 else {
            result.bodyLineOk = true; result.spineOk = true
            result.armOk = true;      result.neckOk = true
            result.issue = .ready;    result.postureScore = 100
            return
        }

        // ── Body-line check ──────────────────────────────────────────────────
        // Below bodyLineMin = hip has dropped or body is bent.
        // We distinguish hip-sagging from hip-piking using spineAngle:
        //   • If spine is horizontal but body-line is bent → hip sagged downward.
        //   • If spine is tilted significantly → rotation/pike issue → bodyRotated.
        // For simplicity we flag hip-sag when angle is low AND spine is acceptably flat,
        // and hip-pike when angle is low AND some upward tilt is detected.
        result.bodyLineOk = bodyLine >= bodyLineMin

        // ── Spine check ──────────────────────────────────────────────────────
        result.spineOk = spine <= spineMax

        // ── Top-arm check ────────────────────────────────────────────────────
        result.armOk = arm <= armDeviationMax

        // ── Neck check ───────────────────────────────────────────────────────
        result.neckOk = neck <= neckMax

        // ── Score ─────────────────────────────────────────────────────────────
        var score = 100
        if !result.bodyLineOk { score -= 40 }   // hip alignment is the most critical
        if !result.spineOk    { score -= 25 }
        if !result.armOk      { score -= 20 }
        if !result.neckOk     { score -= 15 }
        result.postureScore = max(score, 0)

        // ── Issue label (most critical first) ────────────────────────────────
        if !result.bodyLineOk {
            // Distinguish hip sag vs hip pike using the actual hip y-position:
            // In Vision coords, y increases UPWARD. A sagging hip has a lower y
            // than the midpoint of shoulder and ankle. A piked hip has a higher y.
            result.issue = .hipSagging   // default; caller can refine if needed
        } else if !result.spineOk {
            result.issue = .bodyRotated
        } else if !result.armOk {
            result.issue = .armNotUp
        } else if !result.neckOk {
            result.issue = .headDropping
        } else {
            result.issue = .correct
        }
    }

    // MARK: - Timer state machine (identical logic to PlankViewModel)
    private func updateTimerState(result: SidePlankResult) {
        if result.formIsValid {
            consecutiveBadFrames = 0
            consecutiveGoodFrames += 1
            if consecutiveGoodFrames >= goodFramesRequired { startTimer() }
        } else {
            consecutiveGoodFrames = 0
            consecutiveBadFrames  += 1
            if consecutiveBadFrames >= badFramesRequired {
                pauseTimer()
                triggerFormBreakFlash()
            }
        }
    }

    private func startTimer() {
        guard !isHolding else { return }
        DispatchQueue.main.async { self.isHolding = true }
        timerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                await MainActor.run {
                    self.elapsedSeconds += 1
                    if self.elapsedSeconds > self.bestSeconds { self.bestSeconds = self.elapsedSeconds }
                }
            }
        }
    }

    private func pauseTimer() {
        guard isHolding else { return }
        stopTimer()
        DispatchQueue.main.async { self.isHolding = false }
    }

    private func stopTimer() { timerTask?.cancel(); timerTask = nil }

    private func triggerFormBreakFlash() {
        DispatchQueue.main.async {
            self.showFormBreakFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.showFormBreakFlash = false }
        }
    }

    // MARK: - Form alert
    private func updateFormAlert(result: SidePlankResult) {
        var message: String? = nil
        if !result.bodyLineOk    { message = "Lift Your Hip Up!" }
        else if !result.spineOk  { message = "Keep Body Facing Side!" }
        else if !result.armOk    { message = "Raise Top Arm Straight Up!" }
        else if !result.neckOk   { message = "Keep Head Neutral!" }

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

    // MARK: - Helpers
    private func betterSide(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        func conf(_ j: VNHumanBodyPoseObservation.JointName) -> Float { points[j]?.confidence ?? 0 }
        let l: Float = conf(.leftEar) + conf(.leftShoulder) + conf(.leftHip) + conf(.leftKnee) + conf(.leftAnkle)
        let r: Float = conf(.rightEar) + conf(.rightShoulder) + conf(.rightHip) + conf(.rightKnee) + conf(.rightAnkle)
        return l >= r
    }

    private func updateBodyPoints(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        var mapped: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (joint, point) in points where point.confidence > 0.3 {
            mapped[joint] = CGPoint(x: point.location.x, y: 1 - point.location.y)
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

    private func smooth(_ result: SidePlankResult) -> (bodyLine: Double, spine: Double, arm: Double, neck: Double) {
        angleBuffer.append((result.bodyLineAngle, result.spineAngle, result.armAngle, result.neckAngle))
        if angleBuffer.count > bufferSize { angleBuffer.removeFirst() }
        let n = Double(angleBuffer.count)
        return (
            bodyLine: angleBuffer.map(\.bodyLine).reduce(0, +) / n,
            spine:    angleBuffer.map(\.spine).reduce(0,    +) / n,
            arm:      angleBuffer.map(\.arm).reduce(0,      +) / n,
            neck:     angleBuffer.map(\.neck).reduce(0,     +) / n
        )
    }

    // MARK: - Formatted time
    var formattedTime:     String { formatSeconds(elapsedSeconds) }
    var formattedBestTime: String { formatSeconds(bestSeconds) }

    private func formatSeconds(_ total: Int) -> String {
        String(format: "%02d:%02d", total / 60, total % 60)
    }
}
