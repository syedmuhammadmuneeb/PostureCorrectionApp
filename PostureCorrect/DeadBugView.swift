//
//  DeadBugView.swift
//  PostureCorrect
//
//  Created by Syed Muhammad Muneeb on 30/05/26.
//

//
//  DeadBugView.swift
//  PostureCorrect
//
//  Camera placement: SIDE-ON — phone level with the user's hips, ~1–1.5 m away.
//  The full body (wrist → elbow → shoulder → hip → knee → ankle) must be
//  visible on the camera side. Person lies flat on their back, arms pointing
//  straight up, knees bent at 90° (tabletop position).
//
//  ─────────────────────────────────────────────────────────────────────────
//  EXERCISE MECHANICS
//  ─────────────────────────────────────────────────────────────────────────
//  Dead bug: lying supine (on back), arms vertical, knees bent at 90°.
//  Lower the opposite arm (backward toward floor) and leg (forward/downward)
//  simultaneously while keeping the lower back PRESSED into the floor.
//  Return both limbs, repeat on the other side.
//  Each full extension (one side) = 1 rep.
//
//  ─────────────────────────────────────────────────────────────────────────
//  KEY ANGLES  (raw Vision coordinates, y=0 at bottom of frame)
//  ─────────────────────────────────────────────────────────────────────────
//
//  1. Lower-back / spine press angle
//     The lumbar spine must stay in contact with the floor throughout.
//     We measure the deviation of the shoulder→hip line from horizontal.
//     When the back arches off the floor, the hip rises and the
//     shoulder→hip angle deviates upward.
//     In Vision coords (y=0 at bottom) the person is lying flat, so shoulder
//     and hip should have similar y values → angle near 0°.
//     Acceptable: ≤ 20°.
//
//  2. Arm extension angle  (shoulder → wrist from horizontal)
//     Start position: arm points straight up → ~90° from horizontal
//                     (wrist.y >> shoulder.y in Vision coords).
//     End position:   arm lowered to near-floor behind head → ~10°–30° from
//                     horizontal (wrist.y ≈ shoulder.y or below).
//     We use the ABSOLUTE arm angle from horizontal (0° = floor-parallel).
//     At the fully lowered position the arm should be near-horizontal: ≤ 30°.
//     This is the rep trigger: when the arm angle drops from ~90° (up) to ≤ 30°
//     (lowered), the extension is counted as reached.
//
//  3. Leg extension angle  (hip → knee from horizontal, since ankle tracks knee)
//     Start (tabletop): knee bent 90°, thigh vertical (hip→knee ≈ 0°,
//                       i.e. thigh nearly horizontal at the top because the
//                       knee is lifted in the air above the hip when supine).
//
//     Wait — let's think carefully about supine orientation in Vision:
//       Person lies on back. Vision y=0 is the BOTTOM of the image.
//       If the phone is to their side, the person's body is roughly horizontal
//       in the frame, just like planks/glute bridges.
//       In tabletop, the knee is lifted above the hip (away from the floor).
//       In Vision coords (y=0 at bottom, floor-side is low y), the lifted
//       knee has HIGHER y than the hip.
//       When the leg lowers (extends toward the floor), the knee y DECREASES.
//
//     So the rep signal for the leg is the OPPOSITE of bird-dog: the knee y
//     DECREASES as the leg extends (lowers toward the floor).
//
//     We measure:  legExtension = hipKneeAngle from horizontal
//       Tabletop (knee up, thigh ~horizontal): hip→knee vector points upward
//         → large angle from horizontal toward 90°
//       Fully lowered (leg straight near floor): hip→knee vector points outward
//         → small angle from horizontal (near 0°)
//     Trigger: legAngle (hip→ankle horizontal deviation) drops to ≤ 30°.
//
//  4. Knee bend (hip → knee → ankle)
//     The leg should stay bent throughout — straightening the leg is a cheat.
//     Acceptable: 70°–120°. Below 70° = too straight (cheating with momentum).
//
//  ─────────────────────────────────────────────────────────────────────────
//  REP STATE MACHINE  (three-gate, dual-limb)
//  ─────────────────────────────────────────────────────────────────────────
//  Unlike bird-dog (which uses ankle Y), dead bug uses TWO simultaneous
//  signals because both limbs must move together:
//
//  Gate 1: armAngle < armExtensionTrigger AND legAngle < legExtensionTrigger
//          for 2 consecutive frames → repInProgress
//          (both limbs have started moving away from start position)
//
//  Gate 2: armAngle ≤ armFullyLowered AND legAngle ≤ legFullyLowered
//          for 3 frames → extensionReached
//          (both limbs at near-floor level simultaneously)
//
//  Gate 3: armAngle > armReturnedThreshold AND legAngle > legReturnedThreshold
//          for 3 frames → rep closes; evaluate form
//          (both limbs returned to start position)
//
//  Baseline: 10 consecutive frames where both arm and leg are in start
//  position (arm up ~90°, leg tabletop ~horizontal).
//
//  ─────────────────────────────────────────────────────────────────────────
//  VISION COORDINATE NOTE
//  ─────────────────────────────────────────────────────────────────────────
//  Vision y=0 is BOTTOM of frame. Person lying supine on the floor:
//    • Flat on floor → body is horizontal in frame, joints have similar y.
//    • Arm pointing UP → wrist y >> shoulder y (wrist toward top of frame).
//    • Arm lowered DOWN → wrist y ≈ shoulder y (or below).
//    • Knee in tabletop (lifted) → knee y > hip y.
//    • Knee fully lowered (leg near floor) → knee y ≈ hip y (or below).
//  updateBodyPoints() flips y with (1-y) for the overlay only.
//  All angle math uses raw (unflipped) Vision coordinates.
//

import SwiftUI
import AVFoundation
import Vision
import Combine

// MARK: - DEAD BUG ISSUE
enum DeadBugIssue: String {
    case correct         = "✅ Perfect Dead Bug"
    case ready           = "🪲 Lie Down, Arms Up"
    case backLifting     = "❌ Press Lower Back Down"
    case armNotLowered   = "❌ Lower Arm Toward Floor"
    case legNotLowered   = "❌ Lower Leg Toward Floor"
    case legStraightened = "❌ Keep Knee Bent"
    case asymmetric      = "❌ Move Both Limbs Together"
    case detecting       = "🔍 Detecting..."
    case notVisible      = "📷 Full Body Not Visible"
}

// MARK: - DEAD BUG PHASE
enum DeadBugPhase { case start, lowering, extended, returning }

// MARK: - DEAD BUG RESULT
struct DeadBugResult {
    var issue: DeadBugIssue = .detecting
    var postureScore: Int   = 100

    // All angles smoothed before evaluation
    // spineAngle:   deviation of shoulder→hip from horizontal  — target ≤ 20°
    var spineAngle:   Double = 0
    // armAngle:     deviation of shoulder→wrist from horizontal
    //               start ~90° (arm up), fully lowered ~0°–30°
    var armAngle:     Double = 90
    // legAngle:     deviation of hip→knee from horizontal
    //               tabletop ~45°–70° (knee lifted), lowered ~0°–30°
    var legAngle:     Double = 60
    // kneeBend:     hip→knee→ankle angle — must stay 70°–120°
    var kneeBend:     Double = 90

    var trackedLeftSide: Bool = true

    // Per-check flags
    var spineOk:   Bool = true
    var armOk:     Bool = true
    var legOk:     Bool = true
    var kneeBendOk: Bool = true

    var formIsValid: Bool { spineOk && armOk && legOk && kneeBendOk }
}

// MARK: - DEAD BUG CAMERA VIEW
struct DeadBugCameraView: View {
    @StateObject private var viewModel = DeadBugViewModel()

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.session).ignoresSafeArea()

            DeadBugSkeletonOverlay(
                bodyPoints: viewModel.bodyPoints,
                result:     viewModel.deadBugResult
            ).ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if viewModel.showFormAlert {
                    DeadBugAlertBanner(message: viewModel.formAlertMessage)
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
                Text("Dead Bug AI").font(.title2.bold()).foregroundColor(.white)
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
                    .trim(from: 0, to: CGFloat(viewModel.deadBugResult.postureScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 55, height: 55).rotationEffect(.degrees(-90))
                Text("\(viewModel.deadBugResult.postureScore)")
                    .font(.headline.bold()).foregroundColor(.white)
            }
        }
        .padding().background(.black.opacity(0.65)).cornerRadius(20).padding()
    }

    // MARK: - Bottom panel
    private var bottomPanel: some View {
        VStack(spacing: 14) {
            Text(viewModel.deadBugResult.issue.rawValue)
                .font(.title2.bold()).foregroundColor(.white)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                DeadBugAngleCard(title: "Back",
                                 angle: viewModel.deadBugResult.spineAngle,
                                 isOk:  viewModel.deadBugResult.spineOk,
                                 idealRange: "0°-20°")
                DeadBugAngleCard(title: "Arm",
                                 angle: viewModel.deadBugResult.armAngle,
                                 isOk:  viewModel.deadBugResult.armOk,
                                 idealRange: "↓ 0°-30°")
                DeadBugAngleCard(title: "Leg",
                                 angle: viewModel.deadBugResult.legAngle,
                                 isOk:  viewModel.deadBugResult.legOk,
                                 idealRange: "↓ 0°-30°")
                DeadBugAngleCard(title: "Knee",
                                 angle: viewModel.deadBugResult.kneeBend,
                                 isOk:  viewModel.deadBugResult.kneeBendOk,
                                 idealRange: "70°-120°")
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
        let s = viewModel.deadBugResult.postureScore
        if s >= 80 { return .green }
        if s >= 55 { return .yellow }
        return .red
    }
}

// MARK: - ALERT BANNER
struct DeadBugAlertBanner: View {
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
struct DeadBugAngleCard: View {
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
// Side-on view draws the full camera-side chain:
//   wrist → elbow → shoulder → hip → knee → ankle
// Each segment coloured by its relevant form check.
// A dashed floor-level reference line is drawn at shoulder height
// to show where the arm should reach when fully lowered.
struct DeadBugSkeletonOverlay: View {
    let bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let result: DeadBugResult

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let side = result.trackedLeftSide

                let wrist:    VNHumanBodyPoseObservation.JointName = side ? .leftWrist    : .rightWrist
                let elbow:    VNHumanBodyPoseObservation.JointName = side ? .leftElbow    : .rightElbow
                let shoulder: VNHumanBodyPoseObservation.JointName = side ? .leftShoulder : .rightShoulder
                let hip:      VNHumanBodyPoseObservation.JointName = side ? .leftHip      : .rightHip
                let knee:     VNHumanBodyPoseObservation.JointName = side ? .leftKnee     : .rightKnee
                let ankle:    VNHumanBodyPoseObservation.JointName = side ? .leftAnkle    : .rightAnkle

                // ── Skeleton segments ────────────────────────────────────────
                // Arm chain: wrist→elbow→shoulder (armOk colour)
                drawLine(wrist,    elbow,    geo, ok: result.armOk)
                drawLine(elbow,    shoulder, geo, ok: result.armOk)
                // Torso: shoulder→hip (spineOk colour)
                drawLine(shoulder, hip,      geo, ok: result.spineOk)
                // Upper leg: hip→knee (legOk colour)
                drawLine(hip,      knee,     geo, ok: result.legOk)
                // Lower leg: knee→ankle (kneeBendOk colour)
                drawLine(knee,     ankle,    geo, ok: result.kneeBendOk)

                // ── Joint dots ───────────────────────────────────────────────
                let allJoints: [VNHumanBodyPoseObservation.JointName] = [
                    wrist, elbow, shoulder, hip, knee, ankle
                ]
                ForEach(allJoints, id: \.self) { joint in
                    if let pt = bodyPoints[joint] {
                        Circle()
                            .fill(dotColor(for: joint, wrist: wrist, elbow: elbow,
                                          shoulder: shoulder, hip: hip, knee: knee, ankle: ankle))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                            .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                    }
                }

                // ── Dashed floor reference at shoulder height ─────────────────
                // Shows the target y the wrist should reach when the arm is
                // fully lowered — i.e. parallel to the floor at shoulder level.
                if let shPt = bodyPoints[shoulder] {
                    let refY = shPt.y * geo.size.height
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: refY))
                        p.addLine(to: CGPoint(x: geo.size.width, y: refY))
                    }
                    .stroke(Color.yellow.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))

                    Text("Floor level")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow.opacity(0.5))
                        .position(x: geo.size.width - 45, y: refY - 10)
                }
            }
        }
    }

    private func dotColor(for joint: VNHumanBodyPoseObservation.JointName,
                          wrist:    VNHumanBodyPoseObservation.JointName,
                          elbow:    VNHumanBodyPoseObservation.JointName,
                          shoulder: VNHumanBodyPoseObservation.JointName,
                          hip:      VNHumanBodyPoseObservation.JointName,
                          knee:     VNHumanBodyPoseObservation.JointName,
                          ankle:    VNHumanBodyPoseObservation.JointName) -> Color {
        switch joint {
        case _ where joint == wrist || joint == elbow: return result.armOk      ? .green : .red
        case _ where joint == shoulder:                return result.spineOk    ? .green : .red
        case _ where joint == hip:                     return result.spineOk    ? .green : .red
        case _ where joint == knee:                    return result.legOk      ? .green : .red
        case _ where joint == ankle:                   return result.kneeBendOk ? .green : .red
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

// MARK: - DEAD BUG VIEW MODEL
final class DeadBugViewModel: NSObject, ObservableObject,
                               AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    @Published var bodyPoints:   [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var deadBugResult = DeadBugResult()
    @Published var reps          = 0
    @Published var phaseText     = "Get Into Position"
    @Published var phaseColor: Color = .white
    @Published var cameraPosition: AVCaptureDevice.Position = .back

    @Published var showFormAlert    = false
    @Published var formAlertMessage = ""
    @Published var showBadRepFlash  = false
    @Published var badRepReason     = ""

    // ── Thresholds ────────────────────────────────────────────────────────────
    //
    // Spine: shoulder→hip deviation from horizontal.
    // Lying flat → ~0°. Back arching off the floor raises this.
    private let spineMax:            Double = 20

    // Arm angle from horizontal (shoulder→wrist).
    // Start position: arm straight up → ~90°.
    // Moving: arm descending → angle decreasing from ~90° toward ~0°.
    // Fully lowered: arm near-floor → ≤ 30°.
    //
    // Rep trigger (Gate 1): arm has dropped below this from start
    private let armMovingThreshold:  Double = 70   // angle has dropped from ~90° past here
    // Gate 2 — full extension: arm must be this low
    private let armFullyLowered:     Double = 30
    // Gate 3 — returned: arm must be back up past this
    private let armReturnedAngle:    Double = 65

    // Leg angle from horizontal (hip→knee).
    // Tabletop start: knee lifted, thigh roughly horizontal or slightly up → ~50°–80°.
    // Moving: knee descending toward floor → angle decreasing.
    // Fully lowered: leg near-floor → ≤ 30°.
    //
    // Gate 1 trigger: leg has dropped below tabletop angle
    private let legMovingThreshold:  Double = 45   // below tabletop level
    // Gate 2: full extension
    private let legFullyLowered:     Double = 30
    // Gate 3: returned
    private let legReturnedAngle:    Double = 40

    // Knee bend: hip→knee→ankle. Must stay 70°–120° throughout.
    private let kneeBendMin:         Double = 70
    private let kneeBendMax:         Double = 120

    // Asymmetry tolerance: abs(armAngle - legAngle) should be < this.
    // If one limb is fully down but the other is still up, it's asymmetric.
    private let asymmetryTolerance:  Double = 35

    // Stable-frame counts for gate transitions
    private let framesForExtension:  Int = 3
    private let framesForReturn:     Int = 3
    private let framesForStart:      Int = 2    // Gate 1 needs only 2 frames
    private let errorLatch:          Int = 3

    // ── Baseline calibration ──────────────────────────────────────────────────
    // Captured from 10 consecutive frames in start position:
    //   - spine horizontal (spineAngle < 15°)
    //   - arm pointing up (armAngle > 70°)
    //   - knee in tabletop (legAngle > 40°)
    private var baselineCaptured  = false
    private var baselineFrames    = 0
    private let baselineRequired  = 10
    // Baseline arm and leg angles — used to detect movement away from start
    private var baselineArmAngle: Double = 90
    private var baselineLegAngle: Double = 60

    // ── Smoothing ─────────────────────────────────────────────────────────────
    private var angleBuffer: [(spine: Double, arm: Double, leg: Double, knee: Double)] = []
    private let bufferSize = 6

    // ── Rep state machine ─────────────────────────────────────────────────────
    private var repInProgress      = false
    private var extensionReached   = false
    private var framesAtStart      = 0   // Gate 1 counter
    private var framesAtExtension  = 0   // Gate 2 counter
    private var framesAtReturn     = 0   // Gate 3 counter
    private var currentPhase: DeadBugPhase = .start

    // Error accumulators
    private var spineErrFrames:  Int = 0;  private var hadSpineError  = false
    private var armErrFrames:    Int = 0;  private var hadArmError    = false
    private var legErrFrames:    Int = 0;  private var hadLegError    = false
    private var kneeErrFrames:   Int = 0;  private var hadKneeError   = false
    private var asymErrFrames:   Int = 0;  private var hadAsymError   = false

    // ── Debounce ──────────────────────────────────────────────────────────────
    private var stableIssueFrames = 0
    private var lastIssue: DeadBugIssue = .detecting
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
        framesAtStart     = 0
        framesAtExtension = 0
        framesAtReturn    = 0
        spineErrFrames    = 0;  hadSpineError = false
        armErrFrames      = 0;  hadArmError   = false
        legErrFrames      = 0;  hadLegError   = false
        kneeErrFrames     = 0;  hadKneeError  = false
        asymErrFrames     = 0;  hadAsymError  = false
        currentPhase      = .start
    }

    private func resetBaseline() {
        baselineCaptured  = false
        baselineFrames    = 0
        baselineArmAngle  = 90
        baselineLegAngle  = 60
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
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "deadBugVideoQueue"))
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
                DispatchQueue.main.async { self.deadBugResult.issue = .notVisible }
                return
            }

            let s = smooth(result)
            result.spineAngle = s.spine
            result.armAngle   = s.arm
            result.legAngle   = s.leg
            result.kneeBend   = s.knee

            updateBaseline(result: result)
            evaluateForm(result: &result)
            updatePhaseAndReps(result: result)

            if result.issue == lastIssue { stableIssueFrames += 1 }
            else { stableIssueFrames = 0; lastIssue = result.issue }
            var published = result
            if stableIssueFrames < 3 { published.issue = deadBugResult.issue }

            updateFormAlert(result: published)
            DispatchQueue.main.async { self.deadBugResult = published }
        } catch { print("Dead bug Vision error: \(error)") }
    }

    // MARK: - Angle extraction
    //
    // Dead bug is a supine exercise. The person lies on their back.
    // Camera is side-on. The camera-facing side determines which joints we use.
    //
    // For the arm: we use the camera-side arm (shoulder→wrist) because the
    // exercise involves the arms on both sides, but from a side-on view the
    // camera-side arm is always clearly visible. During a rep, the camera-side
    // arm either lowers (if it's the active arm) or stays up (if the opposite
    // arm is active). We track whichever arm is moving.
    //
    // For the leg: same logic — we track the camera-side hip→knee→ankle.
    // In dead bug, opposite arm + leg move together, but from a side-on view
    // both the front-moving arm and the lowering leg are in the same plane of
    // motion and equally detectable.
    private func extractAngles(
        from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> DeadBugResult? {

        let useLeft = betterSide(points)

        let wristKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftWrist    : .rightWrist
        let elbowKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftElbow    : .rightElbow
        let shoulderKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder
        let hipKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let kneeKey:     VNHumanBodyPoseObservation.JointName = useLeft ? .leftKnee     : .rightKnee
        let ankleKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftAnkle    : .rightAnkle

        // Require shoulder, hip, knee. Wrist, elbow, ankle get lower thresholds
        // since they may be harder to detect when the limbs are stationary.
        for j in [shoulderKey, hipKey, kneeKey] {
            guard let p = points[j], p.confidence > 0.35 else { return nil }
        }

        let shoulder = points[shoulderKey]!.location
        let hip      = points[hipKey]!.location
        let knee     = points[kneeKey]!.location

        var result = DeadBugResult()
        result.trackedLeftSide = useLeft

        // ── 1. Spine angle: deviation of shoulder→hip from horizontal ─────────
        // When lying flat, both shoulder and hip are at similar y.
        // Back arching lifts the hip → shoulder→hip vector tilts → angle rises.
        let spineRad  = atan2(shoulder.y - hip.y, shoulder.x - hip.x) * 180 / .pi
        result.spineAngle = min(abs(spineRad), 90)

        // ── 2. Arm angle: deviation of shoulder→wrist from horizontal ─────────
        // Vision y=0 at bottom. Arm pointing UP: wrist.y >> shoulder.y.
        // atan2(wrist.y - shoulder.y, wrist.x - shoulder.x):
        //   Arm straight up  → ~90° (vector points toward top of frame)
        //   Arm horizontal   → ~0°
        //   Arm below horiz  → negative (but we clamp with abs)
        // We want "how far from floor" → use the raw angle directly.
        // Start ~90°, lowers toward 0°.
        if let wristPt = points[wristKey], let elbowPt = points[elbowKey],
           wristPt.confidence > 0.25, elbowPt.confidence > 0.25 {
            let wrist    = wristPt.location
            let armRad   = atan2(wrist.y - shoulder.y, wrist.x - shoulder.x) * 180 / .pi
            // Take the angle as-is (can be negative if arm below horizontal).
            // Clamp to [-90, 90] then shift to [0, 90] for display.
            let clamped  = max(-90.0, min(90.0, armRad))
            // For display and thresholds, we want 90° = straight up, 0° = horizontal.
            result.armAngle = clamped   // positive = above horizontal, negative = below
        } else {
            // Wrist not visible → assume arm is in start (up) position
            result.armAngle = 90
        }

        // ── 3. Leg angle: deviation of hip→knee from horizontal ───────────────
        // Vision y=0 at bottom. Knee lifted in tabletop: knee.y > hip.y.
        // atan2(knee.y - hip.y, knee.x - hip.x):
        //   Knee straight up  → ~90° (not typical)
        //   Tabletop (knee up, thigh roughly horizontal/angled) → ~45°–70°
        //   Leg lowered near floor → ~0° or slightly negative
        let legRad    = atan2(knee.y - hip.y, knee.x - hip.x) * 180 / .pi
        let legClamped = max(-90.0, min(90.0, legRad))
        result.legAngle = legClamped   // positive = knee above hip, negative = below

        // ── 4. Knee bend: hip→knee→ankle ─────────────────────────────────────
        // Measures the actual bend in the knee — must stay 70°–120°.
        // Straightening the leg (cheat) would push this toward 180°.
        if let anklePt = points[ankleKey], anklePt.confidence > 0.25 {
            result.kneeBend = calculateAngle(first: hip, middle: knee, last: anklePt.location)
        } else {
            result.kneeBend = 90   // ankle not visible — neutral assumption
        }

        return result
    }

    // MARK: - Baseline capture
    // Start position confirmed by:
    //   - spine horizontal (spineAngle < 15°) — person is lying down
    //   - arm pointing up (armAngle > armMovingThreshold) — arm not yet lowered
    //   - knee lifted in tabletop (legAngle > legMovingThreshold) — leg not yet lowered
    private func updateBaseline(result: DeadBugResult) {
        guard !baselineCaptured else { return }

        let inStartPosition = result.spineAngle < 15
                           && result.armAngle   > armMovingThreshold
                           && result.legAngle   > legMovingThreshold

        if inStartPosition {
            baselineFrames += 1
            let w = 1.0 / Double(baselineFrames)
            baselineArmAngle = baselineArmAngle * (1 - w) + result.armAngle * w
            baselineLegAngle = baselineLegAngle * (1 - w) + result.legAngle * w

            if baselineFrames >= baselineRequired {
                baselineCaptured = true
            }
        } else {
            baselineFrames   = 0
            baselineArmAngle = 90
            baselineLegAngle = 60
        }
    }

    // MARK: - Form evaluation
    private func evaluateForm(result: inout DeadBugResult) {
        // Guard: person is upright / not lying down
        guard result.spineAngle < 45 else {
            result.spineOk = true; result.armOk = true
            result.legOk   = true; result.kneeBendOk = true
            result.issue   = .ready; result.postureScore = 100
            return
        }

        // ── Spine: checked throughout ────────────────────────────────────────
        result.spineOk = result.spineAngle <= spineMax

        // ── Arm: during extension the arm should be lowering smoothly ─────────
        // We only flag arm issues when the rep is in progress (during lowering/extended).
        // For display purposes we always compute but weight it more during active phase.
        let armIsMoving = result.armAngle < armMovingThreshold
        result.armOk = !armIsMoving || result.armAngle >= -armFullyLowered
        // Simplified: arm is ok if it's either in start position or within
        // the acceptable lowered range. We flag if arm is below -30° (too far down).
        result.armOk = result.armAngle > -armFullyLowered

        // ── Leg: same principle ───────────────────────────────────────────────
        result.legOk = result.legAngle > -legFullyLowered

        // ── Knee bend: checked throughout ────────────────────────────────────
        result.kneeBendOk = result.kneeBend >= kneeBendMin && result.kneeBend <= kneeBendMax

        // ── Asymmetry: arm and leg should move in sync ────────────────────────
        // Both should be at similar stages of their range simultaneously.
        // We check this in the state machine where it's more meaningful,
        // but capture it here for the display.
        let asymmetry = abs(result.armAngle - result.legAngle)
        let isAsymmetric = asymmetry > asymmetryTolerance
                        && result.armAngle < armMovingThreshold  // only flag during movement

        // ── Score ─────────────────────────────────────────────────────────────
        var score = 100
        if !result.spineOk    { score -= 40 }   // most critical — back arching is the key fault
        if !result.kneeBendOk { score -= 25 }
        if !result.armOk      { score -= 15 }
        if !result.legOk      { score -= 15 }
        if isAsymmetric       { score -= 10 }
        result.postureScore = max(score, 0)

        // ── Issue label ───────────────────────────────────────────────────────
        if !result.spineOk    { result.issue = .backLifting }
        else if !result.kneeBendOk { result.issue = .legStraightened }
        else if isAsymmetric  { result.issue = .asymmetric }
        else if !result.armOk { result.issue = .armNotLowered }
        else if !result.legOk { result.issue = .legNotLowered }
        else                  { result.issue = .correct }
    }

    // MARK: - Rep state machine
    //
    // Dead bug uses angle thresholds directly (no Y-position tracking needed)
    // because both the arm and leg travel through clearly distinct angular ranges:
    //   Arm: ~90° (up) → ~0° or lower (down)
    //   Leg: ~50°–70° (tabletop) → ~0° or lower (extended)
    //
    // Gate 1: BOTH limbs have moved away from start position
    //   armAngle < armMovingThreshold AND legAngle < legMovingThreshold
    //
    // Gate 2: BOTH limbs are at near-floor level
    //   armAngle ≤ armFullyLowered AND legAngle ≤ legFullyLowered
    //
    // Gate 3: BOTH limbs have returned to start position
    //   armAngle > armReturnedAngle AND legAngle > legReturnedAngle
    private func updatePhaseAndReps(result: DeadBugResult) {
        guard baselineCaptured else {
            DispatchQueue.main.async {
                self.phaseText  = "Hold Position to Calibrate"
                self.phaseColor = .white.opacity(0.6)
            }
            return
        }

        var nextPhase = currentPhase
        var addRep    = false
        var badRep    = false

        // Error accumulation during active rep
        if repInProgress {
            if !result.spineOk    { spineErrFrames += 1 } else { spineErrFrames = max(0, spineErrFrames - 1) }
            if !result.kneeBendOk { kneeErrFrames  += 1 } else { kneeErrFrames  = max(0, kneeErrFrames  - 1) }

            // Arm and leg errors only count during the lowering/extended phase
            let activelyLowering = result.armAngle < armMovingThreshold
            if activelyLowering {
                if !result.armOk { armErrFrames += 1 } else { armErrFrames = max(0, armErrFrames - 1) }
                if !result.legOk { legErrFrames += 1 } else { legErrFrames = max(0, legErrFrames - 1) }

                // Asymmetry check: arm and leg should be at comparable stages
                let asymmetry   = abs(result.armAngle - result.legAngle)
                if asymmetry > asymmetryTolerance { asymErrFrames += 1 } else { asymErrFrames = max(0, asymErrFrames - 1) }
            }

            if spineErrFrames >= errorLatch { hadSpineError = true }
            if kneeErrFrames  >= errorLatch { hadKneeError  = true }
            if armErrFrames   >= errorLatch { hadArmError   = true }
            if legErrFrames   >= errorLatch { hadLegError   = true }
            if asymErrFrames  >= errorLatch { hadAsymError  = true }
        }

        let bothMoving  = result.armAngle < armMovingThreshold && result.legAngle < legMovingThreshold
        let bothLowered = result.armAngle <= armFullyLowered   && result.legAngle <= legFullyLowered
        let bothBack    = result.armAngle > armReturnedAngle   && result.legAngle > legReturnedAngle

        // ── Gate 1: both limbs start moving ──────────────────────────────────
        if !repInProgress && bothMoving {
            framesAtStart += 1
            if framesAtStart >= framesForStart {
                repInProgress     = true
                framesAtExtension = 0
                framesAtReturn    = 0
                nextPhase         = .lowering
            }
        } else if !repInProgress {
            framesAtStart = max(0, framesAtStart - 1)
        }

        // ── Still lowering ────────────────────────────────────────────────────
        if repInProgress && !extensionReached { nextPhase = .lowering }

        // ── Gate 2: both at floor level → full extension ──────────────────────
        if repInProgress && bothLowered {
            framesAtExtension += 1
            if framesAtExtension >= framesForExtension {
                extensionReached = true
                nextPhase        = .extended
            }
        } else if repInProgress && !extensionReached {
            framesAtExtension = max(0, framesAtExtension - 1)
        }

        // ── Returning ─────────────────────────────────────────────────────────
        if extensionReached && !bothLowered && !bothBack { nextPhase = .returning }

        // ── Gate 3: both limbs returned → close rep ───────────────────────────
        if repInProgress && bothBack {
            framesAtReturn += 1
            if framesAtReturn >= framesForReturn {
                if extensionReached {
                    let goodForm = !hadSpineError && !hadKneeError
                                && !hadArmError  && !hadLegError && !hadAsymError
                    if goodForm { addRep = true } else { badRep = true }
                } else {
                    badRep = true   // came back without reaching full extension
                }
                resetRepState()
                nextPhase = .start
            }
        } else if repInProgress && !extensionReached {
            framesAtReturn = max(0, framesAtReturn - 1)
        }

        currentPhase = nextPhase
        let reasons  = buildBadRepReasons(extensionWasReached: extensionReached)

        DispatchQueue.main.async {
            if addRep { self.reps += 1 }
            if badRep { self.triggerBadRepFeedback(reasons: reasons) }
            switch nextPhase {
            case .start:    self.phaseText = "Arms & Legs Up";     self.phaseColor = .white
            case .lowering: self.phaseText = "Lowering Out";       self.phaseColor = .yellow
            case .extended: self.phaseText = "Full Extension ✅";  self.phaseColor = .green
            case .returning:self.phaseText = "Returning Up";       self.phaseColor = .blue
            }
        }
    }

    private func buildBadRepReasons(extensionWasReached: Bool) -> String {
        var r: [String] = []
        if hadSpineError { r.append("Lower back lifted off floor") }
        if hadKneeError  { r.append("Knee straightened") }
        if hadAsymError  { r.append("Arm & leg not in sync") }
        if hadArmError   { r.append("Arm out of range") }
        if hadLegError   { r.append("Leg out of range") }
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
    private func updateFormAlert(result: DeadBugResult) {
        guard currentPhase == .lowering || currentPhase == .extended else {
            DispatchQueue.main.async { self.showFormAlert = false }
            return
        }
        var message: String? = nil
        if !result.spineOk        { message = "Press Lower Back Into Floor!" }
        else if !result.kneeBendOk { message = "Keep Your Knee Bent!" }
        else if currentPhase == .extended && abs(result.armAngle - result.legAngle) > asymmetryTolerance {
            message = "Keep Arm & Leg Moving Together!"
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

    private func calculateAngle(first: CGPoint, middle: CGPoint, last: CGPoint) -> Double {
        let a = atan2(first.y  - middle.y, first.x  - middle.x)
        let b = atan2(last.y   - middle.y, last.x   - middle.x)
        var angle = abs((a - b) * 180 / .pi)
        if angle > 180 { angle = 360 - angle }
        return angle
    }

    private func smooth(_ result: DeadBugResult)
        -> (spine: Double, arm: Double, leg: Double, knee: Double) {
        angleBuffer.append((result.spineAngle, result.armAngle,
                            result.legAngle,   result.kneeBend))
        if angleBuffer.count > bufferSize { angleBuffer.removeFirst() }
        let n = Double(angleBuffer.count)
        return (
            spine: angleBuffer.map(\.spine).reduce(0, +) / n,
            arm:   angleBuffer.map(\.arm).reduce(0,   +) / n,
            leg:   angleBuffer.map(\.leg).reduce(0,   +) / n,
            knee:  angleBuffer.map(\.knee).reduce(0,  +) / n
        )
    }
}
