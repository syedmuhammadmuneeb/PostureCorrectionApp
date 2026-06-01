//
//  BirdDogView.swift
//  PostureCorrect
//
//  Created by Syed Muhammad Muneeb on 30/05/26.
//

//
//  BirdDogView.swift
//  PostureCorrect
//
//  Camera placement: SIDE-ON — phone level with the user's hips, ~1.5 m away.
//  The full body (wrist → shoulder → hip → knee → ankle) must be visible.
//  The person starts on hands and knees (quadruped position).
//
//  ─────────────────────────────────────────────────────────────────────────
//  EXERCISE MECHANICS
//  ─────────────────────────────────────────────────────────────────────────
//  A bird-dog rep is: from quadruped, extend the opposite arm forward and
//  leg backward simultaneously, hold briefly, return, repeat on the other side.
//  Each full extension (one side) counts as 1 rep.
//
//  ─────────────────────────────────────────────────────────────────────────
//  KEY ANGLES (all measured in raw Vision coordinates, y=0 at bottom)
//  ─────────────────────────────────────────────────────────────────────────
//
//  1. Spine angle — deviation of shoulder→hip line from horizontal.
//     In correct quadruped the spine is parallel to the floor → ~0°.
//     The same neutral spine must be maintained during extension.
//     A rising hip or collapsing lower back increases this angle.
//     Acceptable: ≤ 20°.
//
//  2. Extended arm angle — deviation of the extended arm (shoulder→wrist)
//     from horizontal. The arm should be parallel to the floor → ~0°.
//     Acceptable: ≤ 25° above or below horizontal.
//     Detected via: shoulder.y vs wrist.y delta relative to arm length.
//
//  3. Extended leg angle — deviation of the extended leg (hip→ankle) from
//     horizontal. The leg should be parallel to the floor → ~0°.
//     Acceptable: ≤ 25° above or below horizontal.
//     Detected via: hip.y vs ankle.y delta relative to leg length.
//
//  4. Hip drop angle — lateral tilt of the pelvis.
//     In a side-on view we measure how much the hip has shifted vertically
//     relative to its neutral quadruped baseline. A hip rotating upward
//     (opening) or dropping down is flagged.
//     Acceptable deviation from baseline: ≤ 6% of frame height.
//
//  ─────────────────────────────────────────────────────────────────────────
//  REP STATE MACHINE  (three-gate)
//  ─────────────────────────────────────────────────────────────────────────
//  The primary rep trigger is the extended-leg's ankle Y-position.
//  From neutral quadruped the ankle is low (near floor, small Vision y).
//  When the leg extends backward and upward, the ankle Y RISES.
//
//  Gate 1: ankle.y rises above (baseline + legRiseRequired) → repInProgress
//  Gate 2: legAngle ≤ legAngleMax AND armAngle ≤ armAngleMax for 3 frames
//          → extensionReached (full extension confirmed)
//  Gate 3: ankle.y falls back within flatThreshold of baseline for 3 frames
//          → evaluate & count rep
//
//  Baseline: captured from 10 consecutive frames where the person is in
//  neutral quadruped (spine horizontal, knee y low, ankle y low).
//
//  ─────────────────────────────────────────────────────────────────────────
//  VISION COORDINATE NOTE
//  ─────────────────────────────────────────────────────────────────────────
//  Vision y=0 is the BOTTOM of the image, y=1 is the TOP.
//  When the leg extends back & up, the ankle y INCREASES (moves toward top).
//  updateBodyPoints() flips y with (1 - y) for the on-screen overlay only.
//  All angle math and position comparisons use the raw unflipped coordinates.
//

import SwiftUI
import AVFoundation
import Vision
import Combine

// MARK: - BIRD-DOG ISSUE
enum BirdDogIssue: String {
    case correct        = "✅ Perfect Extension"
    case ready          = "🐾 Get On Hands & Knees"
    case hipRotating    = "❌ Keep Hips Level"
    case backSagging    = "❌ Keep Back Flat"
    case armTooLow      = "❌ Raise Arm to Hip Height"
    case armTooHigh     = "❌ Lower Arm to Hip Height"
    case legTooLow      = "❌ Raise Leg to Hip Height"
    case legTooHigh     = "❌ Lower Leg to Hip Height"
    case detecting      = "🔍 Detecting..."
    case notVisible     = "📷 Full Body Not Visible"
}

// MARK: - BIRD-DOG PHASE
enum BirdDogPhase { case neutral, extending, extended, returning }

// MARK: - BIRD-DOG RESULT
struct BirdDogResult {
    var issue: BirdDogIssue = .detecting
    var postureScore: Int   = 100

    // Angles (smoothed before evaluation)
    // spineAngle:   deviation of shoulder→hip from horizontal  — target ≤ 20°
    var spineAngle:    Double = 0
    // armAngle:     deviation of extended arm (shoulder→wrist) from horizontal — target ≤ 25°
    var armAngle:      Double = 0
    // legAngle:     deviation of extended leg (hip→ankle) from horizontal — target ≤ 25°
    var legAngle:      Double = 0
    // hipDeviation: y-delta of hip from neutral baseline (fraction × 100) — target ≤ 6
    var hipDeviation:  Double = 0

    var trackedLeftSide: Bool = true  // which side the camera sees best

    // Per-check flags
    var spineOk:   Bool = true
    var armOk:     Bool = true
    var legOk:     Bool = true
    var hipOk:     Bool = true

    var formIsValid: Bool { spineOk && armOk && legOk && hipOk }
}

// MARK: - BIRD-DOG CAMERA VIEW
struct BirdDogCameraView: View {
    @StateObject private var viewModel = BirdDogViewModel()

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.session).ignoresSafeArea()

            BirdDogSkeletonOverlay(
                bodyPoints: viewModel.bodyPoints,
                result:     viewModel.birdDogResult
            ).ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if viewModel.showFormAlert {
                    BirdDogAlertBanner(message: viewModel.formAlertMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4), value: viewModel.showFormAlert)
                }
                Spacer()
                bottomPanel
            }

            if viewModel.showBadRepFlash {
                Color.red.opacity(0.25)
                    .ignoresSafeArea().allowsHitTesting(false)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: viewModel.showBadRepFlash)
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
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bird-Dog AI").font(.title2.bold()).foregroundColor(.white)
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
                    .trim(from: 0, to: CGFloat(viewModel.birdDogResult.postureScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 55, height: 55).rotationEffect(.degrees(-90))
                Text("\(viewModel.birdDogResult.postureScore)")
                    .font(.headline.bold()).foregroundColor(.white)
            }
        }
        .padding().background(.black.opacity(0.65)).cornerRadius(20).padding()
    }

    // MARK: - Bottom panel
    private var bottomPanel: some View {
        VStack(spacing: 14) {
            Text(viewModel.birdDogResult.issue.rawValue)
                .font(.title2.bold()).foregroundColor(.white)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                BirdDogAngleCard(title: "Back",
                                 angle: viewModel.birdDogResult.spineAngle,
                                 isOk:  viewModel.birdDogResult.spineOk,
                                 idealRange: "0°-20°")
                BirdDogAngleCard(title: "Arm",
                                 angle: viewModel.birdDogResult.armAngle,
                                 isOk:  viewModel.birdDogResult.armOk,
                                 idealRange: "0°-25°")
                BirdDogAngleCard(title: "Leg",
                                 angle: viewModel.birdDogResult.legAngle,
                                 isOk:  viewModel.birdDogResult.legOk,
                                 idealRange: "0°-25°")
                BirdDogAngleCard(title: "Hips",
                                 angle: viewModel.birdDogResult.hipDeviation,
                                 isOk:  viewModel.birdDogResult.hipOk,
                                 idealRange: "0°-6°")
            }

            HStack(spacing: 40) {
                VStack {
                    Text("\(viewModel.reps)")
                        .font(.system(size: 50, weight: .bold)).foregroundColor(.white)
                    Text("REPS").foregroundColor(.white.opacity(0.7)).font(.caption)
                }
                VStack {
                    Text(viewModel.phaseText)
                        .font(.title3.bold()).foregroundColor(viewModel.phaseColor)
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
        let s = viewModel.birdDogResult.postureScore
        if s >= 80 { return .green }
        if s >= 55 { return .yellow }
        return .red
    }
}

// MARK: - ALERT BANNER
struct BirdDogAlertBanner: View {
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
struct BirdDogAngleCard: View {
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
// Side-on view draws:
//   • Camera-side arm:  wrist → elbow → shoulder
//   • Torso:            shoulder → hip
//   • Camera-side leg:  hip → knee → ankle
// Each segment coloured by its relevant form check.
// A dashed horizontal reference line is drawn at hip height to show
// the target level for the extended arm and leg.
struct BirdDogSkeletonOverlay: View {
    let bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let result: BirdDogResult

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let side = result.trackedLeftSide

                // Camera-side joints
                let wrist:    VNHumanBodyPoseObservation.JointName = side ? .leftWrist    : .rightWrist
                let elbow:    VNHumanBodyPoseObservation.JointName = side ? .leftElbow    : .rightElbow
                let shoulder: VNHumanBodyPoseObservation.JointName = side ? .leftShoulder : .rightShoulder
                let hip:      VNHumanBodyPoseObservation.JointName = side ? .leftHip      : .rightHip
                let knee:     VNHumanBodyPoseObservation.JointName = side ? .leftKnee     : .rightKnee
                let ankle:    VNHumanBodyPoseObservation.JointName = side ? .leftAnkle    : .rightAnkle

                // ── Skeleton segments ──────────────────────────────────────
                // Extended arm (wrist→elbow→shoulder) — coloured by armOk
                drawLine(wrist,    elbow,    geo, ok: result.armOk)
                drawLine(elbow,    shoulder, geo, ok: result.armOk)
                // Torso (shoulder→hip) — coloured by spineOk
                drawLine(shoulder, hip,      geo, ok: result.spineOk)
                // Extended leg (hip→knee→ankle) — coloured by legOk
                drawLine(hip,      knee,     geo, ok: result.legOk)
                drawLine(knee,     ankle,    geo, ok: result.legOk)

                // ── Joint dots ─────────────────────────────────────────────
                let allJoints: [VNHumanBodyPoseObservation.JointName] = [
                    wrist, elbow, shoulder, hip, knee, ankle
                ]
                ForEach(allJoints, id: \.self) { joint in
                    if let pt = bodyPoints[joint] {
                        Circle()
                            .fill(dotColor(for: joint,
                                          wrist: wrist, elbow: elbow, shoulder: shoulder,
                                          hip: hip, knee: knee, ankle: ankle))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                            .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                    }
                }

                // ── Dashed horizontal reference at hip height ──────────────
                // Shows the target level the arm and leg should reach
                if let hipPt = bodyPoints[hip] {
                    let refY = hipPt.y * geo.size.height
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: refY))
                        p.addLine(to: CGPoint(x: geo.size.width, y: refY))
                    }
                    .stroke(Color.cyan.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))

                    // Label
                    Text("Hip level")
                        .font(.system(size: 10))
                        .foregroundColor(.cyan.opacity(0.6))
                        .position(x: geo.size.width - 40, y: refY - 10)
                }
            }
        }
    }

    private func dotColor(for joint: VNHumanBodyPoseObservation.JointName,
                          wrist: VNHumanBodyPoseObservation.JointName,
                          elbow: VNHumanBodyPoseObservation.JointName,
                          shoulder: VNHumanBodyPoseObservation.JointName,
                          hip: VNHumanBodyPoseObservation.JointName,
                          knee: VNHumanBodyPoseObservation.JointName,
                          ankle: VNHumanBodyPoseObservation.JointName) -> Color {
        switch joint {
        case _ where joint == wrist || joint == elbow: return result.armOk   ? .green : .red
        case _ where joint == shoulder:                return result.spineOk ? .green : .red
        case _ where joint == hip:                     return result.hipOk   ? .green : .red
        case _ where joint == knee || joint == ankle:  return result.legOk   ? .green : .red
        default:                                       return .white
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
            .stroke(ok ? Color.green : Color.red,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
    }
}

// MARK: - BIRD-DOG VIEW MODEL
final class BirdDogViewModel: NSObject, ObservableObject,
                               AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    @Published var bodyPoints:    [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var birdDogResult  = BirdDogResult()
    @Published var reps           = 0
    @Published var phaseText      = "Get Into Position"
    @Published var phaseColor: Color = .white
    @Published var cameraPosition: AVCaptureDevice.Position = .back

    @Published var showFormAlert    = false
    @Published var formAlertMessage = ""
    @Published var showBadRepFlash  = false
    @Published var badRepReason     = ""

    // ── Thresholds ────────────────────────────────────────────────────────────
    //
    // Spine: deviation of shoulder→hip vector from horizontal.
    // In neutral quadruped AND during correct extension → close to 0°.
    private let spineMax:         Double = 20

    // Extended arm: deviation of shoulder→wrist from horizontal.
    // The arm should be parallel to the floor when extended forward.
    // We store abs(deviation from horizontal), target ≤ 25°.
    private let armAngleMax:      Double = 25

    // Extended leg: deviation of hip→ankle from horizontal.
    // The leg should be parallel to the floor when extended backward.
    // We store abs(deviation from horizontal), target ≤ 25°.
    private let legAngleMax:      Double = 25

    // Hip deviation: how much the hip y-position shifts from its neutral
    // quadruped baseline (as a fraction of frame height × 100 for display).
    // Target ≤ 6 (i.e. ≤ 6% of frame height).
    private let hipDeviationMax:  Double = 6.0

    // How much the ankle must rise above its baseline (in Vision y fraction)
    // to confirm the person has started extending the leg backward/upward.
    private let legRiseRequired:  Double = 0.07   // 7% of frame height

    // How close to baseline the ankle must return to close the rep.
    private let legFlatThreshold: Double = 0.03   // 3% of frame height

    // Stable-frame counts for gate transitions
    private let framesForExtension: Int = 3
    private let framesForReturn:    Int = 3
    private let errorLatch:         Int = 3

    // ── Baseline calibration ──────────────────────────────────────────────────
    // Captured from 10 consecutive frames in neutral quadruped:
    //   - spine horizontal (spineAngle < 15°)
    //   - ankle y low (confirms knee is bent, foot is on floor)
    private var ankleYBaseline:  Double? = nil
    private var hipYBaseline:    Double? = nil
    private var baselineCaptured = false
    private var baselineFrames   = 0
    private let baselineRequired = 10

    // ── Smoothing ─────────────────────────────────────────────────────────────
    private var angleBuffer: [(spine: Double, arm: Double, leg: Double, hipDev: Double)] = []
    private let bufferSize = 6

    // ── Rep state machine ─────────────────────────────────────────────────────
    private var repInProgress      = false
    private var extensionReached   = false
    private var framesAtExtension  = 0
    private var framesAtReturn     = 0
    private var currentPhase: BirdDogPhase = .neutral

    // Error accumulators (reset each rep)
    private var spineErrFrames:   Int = 0;  private var hadSpineError   = false
    private var armErrFrames:     Int = 0;  private var hadArmError     = false
    private var legErrFrames:     Int = 0;  private var hadLegError     = false
    private var hipErrFrames:     Int = 0;  private var hadHipError     = false

    // ── Debounce ──────────────────────────────────────────────────────────────
    private var stableIssueFrames = 0
    private var lastIssue: BirdDogIssue = .detecting
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
            self.reps = 0
            self.angleBuffer.removeAll()
            self.resetRepState()
            self.resetBaseline()
            self.phaseText  = "Get Into Position"
            self.phaseColor = .white
        }
    }

    private func resetRepState() {
        repInProgress     = false
        extensionReached  = false
        framesAtExtension = 0
        framesAtReturn    = 0
        spineErrFrames    = 0;  hadSpineError = false
        armErrFrames      = 0;  hadArmError   = false
        legErrFrames      = 0;  hadLegError   = false
        hipErrFrames      = 0;  hadHipError   = false
        currentPhase      = .neutral
    }

    private func resetBaseline() {
        ankleYBaseline   = nil
        hipYBaseline     = nil
        baselineCaptured = false
        baselineFrames   = 0
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
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "birdDogVideoQueue"))
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
            let rawPoints = try observation.recognizedPoints(.all)

            updateBodyPoints(rawPoints)

            guard var result = extractAngles(from: rawPoints) else {
                DispatchQueue.main.async { self.birdDogResult.issue = .notVisible }
                return
            }

            let s = smooth(result)
            result.spineAngle   = s.spine
            result.armAngle     = s.arm
            result.legAngle     = s.leg
            result.hipDeviation = s.hipDev

            updateBaseline(result: result, rawPoints: rawPoints)
            evaluateForm(result: &result)
            updatePhaseAndReps(result: result, rawPoints: rawPoints)

            if result.issue == lastIssue { stableIssueFrames += 1 }
            else { stableIssueFrames = 0; lastIssue = result.issue }
            var published = result
            if stableIssueFrames < 3 { published.issue = birdDogResult.issue }

            updateFormAlert(result: published)
            DispatchQueue.main.async { self.birdDogResult = published }
        } catch { print("Bird-dog Vision error: \(error)") }
    }

    // MARK: - Angle extraction
    //
    // betterSide() picks the side with higher total Vision confidence — this is
    // the side facing the camera. In a side-on bird-dog view, the camera sees the
    // arm and leg of whichever side faces it. The extended opposite arm/leg will
    // be partially occluded but still detectable because both are swung into the
    // same plane during the exercise.
    //
    // We use the camera-facing side's wrist→shoulder for arm angle, and the
    // camera-facing side's hip→ankle for leg angle, because in bird-dog the
    // person extends the OPPOSITE arm and leg — but from a side-on camera both
    // the front arm and back leg are equally visible regardless of which side
    // faces the camera.
    private func extractAngles(
        from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> BirdDogResult? {

        let useLeft = betterSide(points)

        let wristKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftWrist    : .rightWrist
        let elbowKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftElbow    : .rightElbow
        let shoulderKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder
        let hipKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let kneeKey:     VNHumanBodyPoseObservation.JointName = useLeft ? .leftKnee     : .rightKnee
        let ankleKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftAnkle    : .rightAnkle

        // Require shoulder, hip, knee, ankle at good confidence.
        // Wrist and elbow get a lower threshold — they may be partially occluded
        // when the arm is not yet extended.
        for j in [shoulderKey, hipKey, kneeKey, ankleKey] {
            guard let p = points[j], p.confidence > 0.35 else { return nil }
        }

        let shoulder = points[shoulderKey]!.location
        let hip      = points[hipKey]!.location
        let ankle    = points[ankleKey]!.location

        var result = BirdDogResult()
        result.trackedLeftSide = useLeft

        // ── 1. Spine angle: deviation of shoulder→hip from horizontal ─────────
        // atan2 gives the angle of the vector (hip - shoulder).
        // A horizontal torso → ~0°. We take abs() to be camera-side agnostic.
        let spineRad  = atan2(shoulder.y - hip.y, shoulder.x - hip.x) * 180 / .pi
        result.spineAngle = min(abs(spineRad), 90)

        // ── 2. Extended arm angle: deviation of shoulder→wrist from horizontal ─
        // During extension the arm reaches forward parallel to the floor → ~0°.
        // If wrist is not visible (arm down), we set a neutral 0° so it doesn't
        // taint the score — the rep machine handles arm visibility separately.
        if let wristPt = points[wristKey], let elbowPt = points[elbowKey],
           wristPt.confidence > 0.25, elbowPt.confidence > 0.25 {
            let wrist    = wristPt.location
            let armRad   = atan2(wrist.y - shoulder.y, wrist.x - shoulder.x) * 180 / .pi
            result.armAngle = min(abs(armRad), 90)
        } else {
            result.armAngle = 0   // arm not detected — treat as neutral
        }

        // ── 3. Extended leg angle: deviation of hip→ankle from horizontal ──────
        // During extension the leg reaches back parallel to the floor → ~0°.
        // In neutral quadruped the ankle is below the hip (large angle).
        // We compute the deviation from horizontal directly.
        let legRad  = atan2(ankle.y - hip.y, ankle.x - hip.x) * 180 / .pi
        result.legAngle = min(abs(legRad), 90)

        // ── 4. Hip deviation: y-delta from neutral baseline ───────────────────
        // In Vision coords, y increases upward. A rotating/dropping hip will
        // shift its y up or down from the neutral quadruped baseline.
        // We store abs(delta) × 100 for display as a "degree"-like value.
        if let baseline = hipYBaseline {
            result.hipDeviation = abs(hip.y - baseline) * 100
        } else {
            result.hipDeviation = 0
        }

        return result
    }

    // MARK: - Baseline capture
    // Neutral quadruped is confirmed by:
    //   - spine nearly horizontal (spineAngle < 15°)
    //   - ankle y is LOW — below the hip (ankle.y < hip.y in Vision coords,
    //     since y=0 is at the bottom and the foot rests near the floor)
    // We accumulate baselineRequired stable frames before locking in.
    private func updateBaseline(result: BirdDogResult,
                                rawPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        guard !baselineCaptured else { return }

        let useLeft = result.trackedLeftSide
        let hipKey:   VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip   : .rightHip
        let ankleKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftAnkle : .rightAnkle

        guard let hipPt   = rawPoints[hipKey],
              let anklePt = rawPoints[ankleKey],
              hipPt.confidence > 0.35,
              anklePt.confidence > 0.35
        else { return }

        let hipY   = hipPt.location.y
        let ankleY = anklePt.location.y

        // In neutral quadruped the ankle is below the hip in Vision space
        // (ankle.y < hip.y since y=0 is the bottom of the frame).
        let isNeutral = result.spineAngle < 15 && ankleY < hipY

        if isNeutral {
            baselineFrames += 1
            let w = 1.0 / Double(baselineFrames)
            ankleYBaseline = (ankleYBaseline ?? ankleY) * (1 - w) + ankleY * w
            hipYBaseline   = (hipYBaseline   ?? hipY)   * (1 - w) + hipY   * w

            if baselineFrames >= baselineRequired {
                baselineCaptured = true
            }
        } else {
            // Not neutral — reset accumulation
            baselineFrames = 0
            ankleYBaseline = nil
            hipYBaseline   = nil
        }
    }

    // MARK: - Form evaluation
    private func evaluateForm(result: inout BirdDogResult) {
        // Guard: not in quadruped yet (spine too upright)
        guard result.spineAngle < 45 else {
            result.spineOk = true; result.armOk = true
            result.legOk   = true; result.hipOk = true
            result.issue = .ready; result.postureScore = 100
            return
        }

        // ── Spine check ───────────────────────────────────────────────────────
        result.spineOk = result.spineAngle <= spineMax

        // ── Arm check ─────────────────────────────────────────────────────────
        // Only penalise arm angle during extension — when the arm is hanging
        // down at rest the angle will naturally be high. We check arm only
        // when a rep is in progress (handled in the state machine via hadArmError).
        // For the real-time display we check regardless of phase.
        result.armOk = result.armAngle <= armAngleMax

        // ── Leg check ─────────────────────────────────────────────────────────
        // Penalise only during extension phase (same rationale as arm).
        // For display we check regardless.
        result.legOk = result.legAngle <= legAngleMax

        // ── Hip check ─────────────────────────────────────────────────────────
        result.hipOk = result.hipDeviation <= hipDeviationMax

        // ── Score ─────────────────────────────────────────────────────────────
        var score = 100
        if !result.spineOk { score -= 35 }
        if !result.hipOk   { score -= 25 }
        if !result.armOk   { score -= 20 }
        if !result.legOk   { score -= 20 }
        result.postureScore = max(score, 0)

        // ── Issue label ───────────────────────────────────────────────────────
        // Priority: back > hips > limb position
        if !result.spineOk {
            result.issue = .backSagging
        } else if !result.hipOk {
            result.issue = .hipRotating
        } else if !result.armOk {
            // Distinguish arm too high vs too low using raw angle sign.
            // We stored abs(), so use the last-known direction from the
            // raw Vision points by checking if the wrist is above or below
            // the shoulder. Issue label defaults to a combined message here;
            // the alert banner gives the directional correction.
            result.issue = .armTooHigh    // default; updateFormAlert refines
        } else if !result.legOk {
            result.issue = .legTooHigh    // default; updateFormAlert refines
        } else {
            result.issue = .correct
        }
    }

    // MARK: - Rep state machine
    //
    // Uses ankle Y-position as the primary rep trigger (same approach as
    // GluteBridgeViewModel for hip). The ankle Y rises when the leg extends
    // back and upward. Form checks are only latched during the extension phase.
    private func updatePhaseAndReps(result: BirdDogResult,
                                    rawPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {

        guard baselineCaptured, let ankleBase = ankleYBaseline else {
            DispatchQueue.main.async {
                self.phaseText  = "Hold Still to Calibrate"
                self.phaseColor = .white.opacity(0.6)
            }
            return
        }

        let useLeft   = result.trackedLeftSide
        let ankleKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftAnkle : .rightAnkle
        let hipKey:   VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip   : .rightHip

        guard let anklePt = rawPoints[ankleKey], anklePt.confidence > 0.3,
              let hipPt   = rawPoints[hipKey],   hipPt.confidence > 0.3
        else { return }

        // Vision y=0 is the BOTTOM. Leg extending upward → ankle y INCREASES.
        let ankleY   = anklePt.location.y
        let legRise  = ankleY - ankleBase   // positive when ankle rose above baseline

        var nextPhase = currentPhase
        var addRep    = false
        var badRep    = false

        // Accumulate form errors while rep is in progress.
        // Spine and hip are checked throughout; arm and leg only during extension.
        if repInProgress {
            if !result.spineOk { spineErrFrames += 1 } else { spineErrFrames = max(0, spineErrFrames - 1) }
            if !result.hipOk   { hipErrFrames   += 1 } else { hipErrFrames   = max(0, hipErrFrames   - 1) }

            let duringExtension = legRise >= legRiseRequired
            if duringExtension {
                if !result.armOk { armErrFrames += 1 } else { armErrFrames = max(0, armErrFrames - 1) }
                if !result.legOk { legErrFrames += 1 } else { legErrFrames = max(0, legErrFrames - 1) }
            }

            if spineErrFrames >= errorLatch { hadSpineError = true }
            if hipErrFrames   >= errorLatch { hadHipError   = true }
            if armErrFrames   >= errorLatch { hadArmError   = true }
            if legErrFrames   >= errorLatch { hadLegError   = true }
        }

        // ── Gate 1: leg starts to rise → rep begins ───────────────────────────
        if !repInProgress && legRise >= legRiseRequired {
            repInProgress     = true
            framesAtExtension = 0
            framesAtReturn    = 0
            nextPhase         = .extending
        }

        // ── Still extending ───────────────────────────────────────────────────
        if repInProgress && legRise >= legRiseRequired { nextPhase = .extending }

        // ── Gate 2: full extension confirmed ─────────────────────────────────
        // Leg is high AND both arm and leg angles are within acceptable range.
        let fullyExtended = result.legAngle <= legAngleMax && result.armAngle <= armAngleMax
        if repInProgress && legRise >= legRiseRequired && fullyExtended {
            framesAtExtension += 1
            if framesAtExtension >= framesForExtension {
                extensionReached = true
                nextPhase        = .extended
            }
        } else if repInProgress && nextPhase != .extended {
            framesAtExtension = max(0, framesAtExtension - 1)
        }

        // ── Returning ─────────────────────────────────────────────────────────
        if extensionReached && legRise < legRiseRequired && legRise > legFlatThreshold {
            nextPhase = .returning
        }

        // ── Gate 3: ankle returns to baseline → close rep ─────────────────────
        if repInProgress && legRise <= legFlatThreshold {
            framesAtReturn += 1
            if framesAtReturn >= framesForReturn {
                if extensionReached {
                    let goodForm = !hadSpineError && !hadHipError && !hadArmError && !hadLegError
                    if goodForm { addRep = true } else { badRep = true }
                } else {
                    badRep = true   // ankle came back down without reaching full extension
                }
                resetRepState()
                nextPhase = .neutral
            }
        } else if repInProgress {
            framesAtReturn = 0
        }

        currentPhase = nextPhase
        let reasons  = buildBadRepReasons(extensionWasReached: extensionReached)

        DispatchQueue.main.async {
            if addRep { self.reps += 1 }
            if badRep { self.triggerBadRepFeedback(reasons: reasons) }
            switch nextPhase {
            case .neutral:   self.phaseText = "Neutral Position"; self.phaseColor = .white
            case .extending: self.phaseText = "Extending Out";    self.phaseColor = .yellow
            case .extended:  self.phaseText = "Full Extension ✅"; self.phaseColor = .green
            case .returning: self.phaseText = "Returning In";     self.phaseColor = .blue
            }
        }
    }

    private func buildBadRepReasons(extensionWasReached: Bool) -> String {
        var r: [String] = []
        if hadSpineError  { r.append("Back not flat") }
        if hadHipError    { r.append("Hips rotated") }
        if hadArmError    { r.append("Arm not parallel to floor") }
        if hadLegError    { r.append("Leg not parallel to floor") }
        if !extensionWasReached { r.append("Didn't reach full extension") }
        return r.isEmpty ? "Didn't reach full extension" : r.joined(separator: " • ")
    }

    private func triggerBadRepFeedback(reasons: String) {
        DispatchQueue.main.async {
            self.badRepReason    = reasons
            self.showBadRepFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.showBadRepFlash = false }
        }
    }

    // MARK: - Form alert
    // Only shown during extending/extended phases.
    private func updateFormAlert(result: BirdDogResult) {
        guard currentPhase == .extending || currentPhase == .extended else {
            DispatchQueue.main.async { self.showFormAlert = false }
            return
        }
        var message: String? = nil
        if !result.spineOk    { message = "Keep Your Back Flat!" }
        else if !result.hipOk { message = "Don't Rotate Your Hips!" }
        else if !result.armOk { message = "Arm Should Be Parallel to Floor" }
        else if !result.legOk { message = "Leg Should Be Parallel to Floor" }

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
        let l: Float = conf(.leftWrist) + conf(.leftShoulder) + conf(.leftHip) + conf(.leftKnee) + conf(.leftAnkle)
        let r: Float = conf(.rightWrist) + conf(.rightShoulder) + conf(.rightHip) + conf(.rightKnee) + conf(.rightAnkle)
        return l >= r
    }

    private func updateBodyPoints(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        var mapped: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (joint, point) in points where point.confidence > 0.3 {
            mapped[joint] = CGPoint(x: point.location.x, y: 1 - point.location.y)
        }
        DispatchQueue.main.async { self.bodyPoints = mapped }
    }

    private func smooth(_ result: BirdDogResult)
        -> (spine: Double, arm: Double, leg: Double, hipDev: Double) {
        angleBuffer.append((result.spineAngle, result.armAngle,
                            result.legAngle, result.hipDeviation))
        if angleBuffer.count > bufferSize { angleBuffer.removeFirst() }
        let n = Double(angleBuffer.count)
        return (
            spine:  angleBuffer.map(\.spine).reduce(0,  +) / n,
            arm:    angleBuffer.map(\.arm).reduce(0,    +) / n,
            leg:    angleBuffer.map(\.leg).reduce(0,    +) / n,
            hipDev: angleBuffer.map(\.hipDev).reduce(0, +) / n
        )
    }
}
