//
//  GluteBridgeView.swift
//  PostureCorrect
//
//  Created by Syed Muhammad Muneeb on 30/05/26.
//

//
//  GluteBridgeView.swift
//  PostureCorrect
//
//  Camera placement: SIDE-ON — phone level with the user's hips, pointing
//  toward them. The full body (shoulder → hip → knee → ankle) must be
//  visible. Lying flat on the floor, knees bent, feet flat.
//
//  A glute bridge has two positions:
//    • Bottom  — lying flat, hips on floor, body straight (hip angle ~180°)
//    • Top     — hips lifted, torso/thigh form a straight line (~180° at hip),
//                knee bent at ~90°, shoulder/hip/knee collinear
//
//  Key angles measured:
//
//  1. Hip angle  (shoulder → hip → knee)
//     Bottom: ~160°–180° (flat on floor, legs bent)
//     Top:    ~160°–180° (hips fully extended, body straight from shoulder to knee)
//     If hips sag at the top, this angle drops below ~160°.
//
//  2. Knee angle (hip → knee → ankle)
//     At the start position and throughout: ~80°–110°.
//     Too straight (> 110°) means feet too far away.
//     Too acute (< 70°) means feet too close, reducing glute activation.
//     At the top the knee should stay at ~90°.
//
//  3. Spine angle — deviation of shoulder→hip line from horizontal.
//     At the top of the bridge the torso should be flat/horizontal → ≤ 20°.
//     A large deviation means the person is not fully extending.
//
//  4. Shoulder-ground check — deviation of shoulder position from flat.
//     Shoulders should stay pressed into the floor (low y in Vision) throughout.
//     We track whether the shoulder is rising off the floor.
//
//  Rep counting logic (three-gate state machine):
//    Gate 1: hipAngle drops below descentTrigger (person bends knees / lies down)
//            AND spineAngle confirms horizontal body → rep armed
//    Gate 2: hipAngle rises to bridgeTopMin AND knee stays in valid range → top reached
//    Gate 3: hipAngle returns to flatMin → rep complete; evaluate form
//
//  Vision y-axis: y=0 at BOTTOM of frame, y=1 at TOP.
//  updateBodyPoints() flips y for the overlay. All angle math uses raw Vision coords.
//

import SwiftUI
import AVFoundation
import Vision
import Combine

// MARK: - GLUTE BRIDGE ISSUE
enum GluteBridgeIssue: String {
    case correct        = "✅ Perfect Bridge"
    case ready          = "🧍 Lie Down & Begin"
    case hipsTooLow     = "❌ Push Hips Higher"
    case hipsTooHigh    = "❌ Don't Hyperextend"
    case kneeTooWide    = "❌ Move Feet Closer"
    case kneeTooClose   = "❌ Move Feet Further"
    case backArched     = "❌ Keep Back Neutral"
    case shoulderLifted = "❌ Keep Shoulders Down"
    case detecting      = "🔍 Detecting..."
    case notVisible     = "📷 Full Body Not Visible"
}

// MARK: - GLUTE BRIDGE PHASE
enum GluteBridgePhase { case flat, ascending, top, descending }

// MARK: - GLUTE BRIDGE RESULT
struct GluteBridgeResult {
    var issue: GluteBridgeIssue = .detecting
    var postureScore: Int       = 100

    // Angles (smoothed before evaluation)
    // hipAngle: shoulder → hip → knee — measures full-extension at top
    var hipAngle:    Double = 180
    // kneeAngle: hip → knee → ankle — measures foot placement validity
    var kneeAngle:   Double = 90
    // spineAngle: deviation of shoulder→hip line from horizontal
    var spineAngle:  Double = 0
    // shoulderLift: y-delta of shoulder from its baseline (rising = bad)
    var shoulderRise: Double = 0

    var trackedLeftSide: Bool = true

    // Per-check pass flags
    var hipOk:          Bool = true
    var kneeOk:         Bool = true
    var spineOk:        Bool = true
    var shoulderOk:     Bool = true

    var formIsValid: Bool { hipOk && kneeOk && spineOk && shoulderOk }
}

// MARK: - GLUTE BRIDGE CAMERA VIEW
struct GluteBridgeCameraView: View {
    @StateObject private var viewModel = GluteBridgeViewModel()

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.session).ignoresSafeArea()

            GluteBridgeSkeletonOverlay(
                bodyPoints: viewModel.bodyPoints,
                result:     viewModel.bridgeResult
            ).ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                if viewModel.showFormAlert {
                    GluteBridgeAlertBanner(message: viewModel.formAlertMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4), value: viewModel.showFormAlert)
                }
                Spacer()
                bottomPanel
            }

            if viewModel.showBadRepFlash {
                Color.red.opacity(0.25)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
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
                Text("Glute Bridge AI").font(.title2.bold()).foregroundColor(.white)
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
                    .trim(from: 0, to: CGFloat(viewModel.bridgeResult.postureScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 55, height: 55).rotationEffect(.degrees(-90))
                Text("\(viewModel.bridgeResult.postureScore)")
                    .font(.headline.bold()).foregroundColor(.white)
            }
        }
        .padding().background(.black.opacity(0.65)).cornerRadius(20).padding()
    }

    // MARK: - Bottom panel
    private var bottomPanel: some View {
        VStack(spacing: 14) {
            Text(viewModel.bridgeResult.issue.rawValue)
                .font(.title2.bold()).foregroundColor(.white)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                GluteBridgeAngleCard(title: "Hip",
                                     angle: viewModel.bridgeResult.hipAngle,
                                     isOk:  viewModel.bridgeResult.hipOk,
                                     idealRange: "160°-180°")
                GluteBridgeAngleCard(title: "Knee",
                                     angle: viewModel.bridgeResult.kneeAngle,
                                     isOk:  viewModel.bridgeResult.kneeOk,
                                     idealRange: "80°-110°")
                GluteBridgeAngleCard(title: "Back",
                                     angle: viewModel.bridgeResult.spineAngle,
                                     isOk:  viewModel.bridgeResult.spineOk,
                                     idealRange: "0°-20°")
                GluteBridgeAngleCard(title: "Shoulder",
                                     angle: viewModel.bridgeResult.shoulderRise,
                                     isOk:  viewModel.bridgeResult.shoulderOk,
                                     idealRange: "0°-5°")
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
        let s = viewModel.bridgeResult.postureScore
        if s >= 80 { return .green }
        if s >= 55 { return .yellow }
        return .red
    }
}

// MARK: - ALERT BANNER
struct GluteBridgeAlertBanner: View {
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
struct GluteBridgeAngleCard: View {
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
// Shows the full side-on chain: shoulder → hip → knee → ankle
// coloured per form check. Also draws a ground-reference line at the ankle.
struct GluteBridgeSkeletonOverlay: View {
    let bodyPoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let result: GluteBridgeResult

    var body: some View {
        GeometryReader { geo in
            ZStack {
                let shoulder: VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftShoulder : .rightShoulder
                let hip:      VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftHip      : .rightHip
                let knee:     VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftKnee     : .rightKnee
                let ankle:    VNHumanBodyPoseObservation.JointName = result.trackedLeftSide ? .leftAnkle    : .rightAnkle

                // Body chain segments, each coloured by its relevant check
                drawLine(shoulder, hip,   geo, ok: result.spineOk)   // torso
                drawLine(hip,      knee,  geo, ok: result.hipOk)     // upper leg
                drawLine(knee,     ankle, geo, ok: result.kneeOk)    // lower leg

                // Shoulder dot coloured by shoulder-lift check
                let joints: [VNHumanBodyPoseObservation.JointName] = [shoulder, hip, knee, ankle]
                ForEach(joints, id: \.self) { joint in
                    if let pt = bodyPoints[joint] {
                        Circle()
                            .fill(dotColor(for: joint, shoulder: shoulder, hip: hip,
                                           knee: knee, ankle: ankle))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.5))
                            .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
                    }
                }

                // Dashed ground reference line at ankle height
                if let anklePt = bodyPoints[ankle] {
                    let y = anklePt.y * geo.size.height
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.2),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                }
            }
        }
    }

    private func dotColor(for joint: VNHumanBodyPoseObservation.JointName,
                          shoulder: VNHumanBodyPoseObservation.JointName,
                          hip: VNHumanBodyPoseObservation.JointName,
                          knee: VNHumanBodyPoseObservation.JointName,
                          ankle: VNHumanBodyPoseObservation.JointName) -> Color {
        if joint == shoulder { return result.shoulderOk  ? .green : .red }
        if joint == hip      { return result.hipOk       ? .green : .red }
        if joint == knee     { return result.kneeOk      ? .green : .red }
        if joint == ankle    { return result.kneeOk      ? .green : .red }
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

// MARK: - GLUTE BRIDGE VIEW MODEL
final class GluteBridgeViewModel: NSObject, ObservableObject,
                                   AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    @Published var bodyPoints:   [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var bridgeResult  = GluteBridgeResult()
    @Published var reps          = 0
    @Published var phaseText     = "Lie Flat"
    @Published var phaseColor: Color = .white
    @Published var cameraPosition: AVCaptureDevice.Position = .back

    @Published var showFormAlert    = false
    @Published var formAlertMessage = ""
    @Published var showBadRepFlash  = false
    @Published var badRepReason     = ""

    // ── Thresholds ────────────────────────────────────────────────────────────
    //
    // Hip angle (shoulder → hip → knee)
    // Flat / bottom position: person is lying with knees bent.
    // Vision sees a high hip angle here because shoulder, hip, knee are nearly
    // collinear when flat → ~160°–180°.
    // Bridge top: hips elevated, body still straight shoulder→hip→knee → ~160°–180°.
    // Hip sag at the top means the angle drops below bridgeTopMin.
    //
    // We detect the transition by tracking the hip's y-position (Vision y = 0
    // at bottom). When the person lifts, the hip y-coordinate INCREASES.
    // We use hip y-rise as the primary rep trigger, and hip angle as the
    // quality check at the top.

    // Bottom / flat position: hip angle is naturally high when lying flat
    private let flatHipMin:      Double = 150   // minimum angle in the flat position
    // Top of bridge: hip must reach full extension
    private let bridgeTopHipMin: Double = 155   // hip angle must be ≥ this at the top
    private let bridgeTopHipMax: Double = 195   // > this means hyperextension/lumbar arch

    // Knee angle (hip → knee → ankle) — foot placement quality
    // Optimal foot placement: knee bent ~80°–110°
    private let kneeMin:         Double = 75    // below → feet too close
    private let kneeMax:         Double = 115   // above → feet too far

    // Spine angle — deviation of shoulder→hip from horizontal
    // At the top of the bridge the torso should be flat/horizontal
    private let spineMax:        Double = 20

    // Shoulder-rise threshold: how much (as fraction of frame height) the
    // shoulder y-position is allowed to rise off its baseline before we flag it.
    // In Vision y-coords, shoulder y INCREASES when it rises off the floor.
    private let shoulderRiseMax: Double = 0.06  // 6% of frame height

    // Hip y-rise needed to confirm bridge top reached (fraction of frame height)
    // The hip must travel upward by at least this amount from the flat baseline.
    private let hipRiseRequired: Double = 0.08  // 8% of frame height

    // Stable-frame counts for state-machine gates
    private let framesForTop:    Int = 3
    private let framesForFlat:   Int = 3
    private let errorLatch:      Int = 3

    // ── Smoothing ─────────────────────────────────────────────────────────────
    private var angleBuffer: [(hip: Double, knee: Double, spine: Double, shoulderRise: Double)] = []
    private let bufferSize = 6

    // ── Rep state machine ─────────────────────────────────────────────────────
    // Three gates:
    //   1. Hip y rises above hipRiseRequired from baseline → repInProgress
    //   2. hipAngle ≥ bridgeTopHipMin for 3 frames      → topReached
    //   3. Hip y returns within flatThreshold of baseline → evaluate rep
    private var repInProgress   = false
    private var topReached      = false
    private var framesAtTop     = 0
    private var framesAtFlat    = 0

    // Baseline: the hip y-position when the person is lying flat.
    // Captured once when the spine is confirmed horizontal (person is down).
    private var hipYBaseline:      Double? = nil
    private var shoulderYBaseline: Double? = nil
    private var baselineCaptured   = false
    private var baselineFrames     = 0        // frames confirming flat position
    private let baselineRequired   = 10       // capture baseline after 10 flat frames

    // Error accumulators
    private var hipErrFrames:      Int = 0;  private var hadHipError      = false
    private var kneeErrFrames:     Int = 0;  private var hadKneeError     = false
    private var spineErrFrames:    Int = 0;  private var hadSpineError    = false
    private var shoulderErrFrames: Int = 0;  private var hadShoulderError = false

    // ── Debounce ──────────────────────────────────────────────────────────────
    private var stableIssueFrames = 0
    private var lastIssue: GluteBridgeIssue = .detecting
    private var alertTimer: Timer?
    private var currentPhase: GluteBridgePhase = .flat

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
            self.reps           = 0
            self.angleBuffer.removeAll()
            self.resetRepState()
            self.resetBaseline()
            self.phaseText  = "Lie Flat"
            self.phaseColor = .white
        }
    }

    private func resetRepState() {
        repInProgress   = false
        topReached      = false
        framesAtTop     = 0
        framesAtFlat    = 0
        hipErrFrames      = 0;  hadHipError      = false
        kneeErrFrames     = 0;  hadKneeError     = false
        spineErrFrames    = 0;  hadSpineError    = false
        shoulderErrFrames = 0;  hadShoulderError = false
        currentPhase    = .flat
    }

    private func resetBaseline() {
        hipYBaseline      = nil
        shoulderYBaseline = nil
        baselineCaptured  = false
        baselineFrames    = 0
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
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "gluteBridgeVideoQueue"))
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
                DispatchQueue.main.async { self.bridgeResult.issue = .notVisible }
                return
            }

            // Smooth all four channels
            let s = smooth(result)
            result.hipAngle     = s.hip
            result.kneeAngle    = s.knee
            result.spineAngle   = s.spine
            result.shoulderRise = s.shoulderRise

            // Capture the flat baseline once the person settles
            updateBaseline(result: result, rawPoints: rawPoints)

            // Evaluate form
            evaluateForm(result: &result)

            // Run rep state machine
            updatePhaseAndReps(result: result, rawPoints: rawPoints)

            // Debounce issue label
            if result.issue == lastIssue { stableIssueFrames += 1 }
            else { stableIssueFrames = 0; lastIssue = result.issue }
            var published = result
            if stableIssueFrames < 3 { published.issue = bridgeResult.issue }

            updateFormAlert(result: published)
            DispatchQueue.main.async { self.bridgeResult = published }
        } catch { print("Glute bridge Vision error: \(error)") }
    }

    // MARK: - Angle extraction
    //
    // Requires shoulder, hip, knee, ankle on the camera-facing side.
    // betterSide() picks whichever side has higher Vision confidence.
    private func extractAngles(
        from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> GluteBridgeResult? {

        let useLeft = betterSide(points)

        let shoulderKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder
        let hipKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let kneeKey:     VNHumanBodyPoseObservation.JointName = useLeft ? .leftKnee     : .rightKnee
        let ankleKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftAnkle    : .rightAnkle

        for j in [shoulderKey, hipKey, kneeKey, ankleKey] {
            guard let p = points[j], p.confidence > 0.35 else { return nil }
        }

        let shoulder = points[shoulderKey]!.location
        let hip      = points[hipKey]!.location
        let knee     = points[kneeKey]!.location
        let ankle    = points[ankleKey]!.location

        var result = GluteBridgeResult()
        result.trackedLeftSide = useLeft

        // ── Hip angle: shoulder → hip → knee ────────────────────────────────
        // Measures how straight the body is from shoulder through to knee.
        // At the top of the bridge this should be ~160°–180° (flat line).
        // Sagging hips reduce this angle.
        result.hipAngle = calculateAngle(first: shoulder, middle: hip, last: knee)

        // ── Knee angle: hip → knee → ankle ──────────────────────────────────
        // Measures the bend of the knee / foot placement.
        // Optimal: ~80°–110° throughout the movement.
        result.kneeAngle = calculateAngle(first: hip, middle: knee, last: ankle)

        // ── Spine angle: deviation of shoulder→hip from horizontal ───────────
        // When lying flat AND at the top of the bridge the torso should be
        // horizontal → close to 0°.
        // A large spine angle at the top indicates lumbar hyperextension
        // (the lower back is arching up rather than the glutes driving the lift).
        let spineRaw     = atan2(shoulder.y - hip.y, shoulder.x - hip.x) * 180 / .pi
        result.spineAngle = min(abs(spineRaw), 90)

        // ── Shoulder rise: how much the shoulder has lifted off its baseline ──
        // We compute this relative to shoulderYBaseline captured when flat.
        // Vision y increases upward; a rising shoulder has a higher y.
        // We store the absolute rise (in Vision y fraction) in shoulderRise
        // and compare against shoulderRiseMax in evaluateForm.
        if let baseline = shoulderYBaseline {
            // Positive value = shoulder rose above baseline
            result.shoulderRise = max(0, shoulder.y - baseline) * 100  // display as "degrees"-like units
        } else {
            result.shoulderRise = 0
        }

        return result
    }

    // MARK: - Baseline capture
    // The baseline is the hip and shoulder y when the person is lying flat
    // (confirmed by spineAngle < 20° and hipAngle > flatHipMin).
    // We accumulate baselineRequired stable flat frames before locking it in,
    // which prevents a mid-rep snapshot from becoming the baseline.
    private func updateBaseline(result: GluteBridgeResult,
                                rawPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {
        guard !baselineCaptured else { return }

        let useLeft = result.trackedLeftSide
        let hipKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let shoulderKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder

        guard let hipPt      = rawPoints[hipKey],
              let shoulderPt = rawPoints[shoulderKey],
              hipPt.confidence > 0.35,
              shoulderPt.confidence > 0.35
        else { return }

        // Confirm flat: spine nearly horizontal + hip angle high
        let isFlat = result.spineAngle < 25 && result.hipAngle > flatHipMin

        if isFlat {
            baselineFrames += 1
            // Rolling average of hip and shoulder y during flat frames
            let w = 1.0 / Double(baselineFrames)
            hipYBaseline      = (hipYBaseline ?? hipPt.location.y) * (1 - w) + hipPt.location.y * w
            shoulderYBaseline = (shoulderYBaseline ?? shoulderPt.location.y) * (1 - w) + shoulderPt.location.y * w

            if baselineFrames >= baselineRequired {
                baselineCaptured = true
            }
        } else {
            // Body not flat — reset accumulation
            baselineFrames    = 0
            hipYBaseline      = nil
            shoulderYBaseline = nil
        }
    }

    // MARK: - Form evaluation
    private func evaluateForm(result: inout GluteBridgeResult) {
        // Guard: person is upright / not lying down yet
        // spine angle > 45° means they are standing or sitting
        guard result.spineAngle < 45 else {
            result.hipOk = true; result.kneeOk = true
            result.spineOk = true; result.shoulderOk = true
            result.issue = .ready; result.postureScore = 100
            return
        }

        // ── Hip check ────────────────────────────────────────────────────────
        // At the top the hip must be fully extended.
        // We only penalise hip sag/hyperextension during the top phase;
        // mid-rep transitional angles are expected.
        let atTop = currentPhase == .top || currentPhase == .ascending
        if atTop {
            if result.hipAngle < bridgeTopHipMin {
                result.hipOk = false   // hips not pushed high enough
            } else if result.hipAngle > bridgeTopHipMax {
                result.hipOk = false   // hyperextension / lumbar arching
            } else {
                result.hipOk = true
            }
        } else {
            result.hipOk = true        // bottom / descending — transitional
        }

        // ── Knee check ───────────────────────────────────────────────────────
        // Foot placement is checked throughout: it doesn't change during the rep.
        result.kneeOk = result.kneeAngle >= kneeMin && result.kneeAngle <= kneeMax

        // ── Spine / back check ───────────────────────────────────────────────
        // Only flag arching at the top of the bridge, where a horizontal
        // body is expected. Mid-rep the spine angle changes naturally.
        if atTop {
            result.spineOk = result.spineAngle <= spineMax
        } else {
            result.spineOk = true
        }

        // ── Shoulder-rise check ──────────────────────────────────────────────
        // Shoulders should stay on the ground throughout.
        // shoulderRise is stored as percentage-like units (Vision fraction × 100).
        result.shoulderOk = result.shoulderRise <= (shoulderRiseMax * 100)

        // ── Score ─────────────────────────────────────────────────────────────
        var score = 100
        if !result.hipOk      { score -= 35 }
        if !result.kneeOk     { score -= 25 }
        if !result.spineOk    { score -= 25 }
        if !result.shoulderOk { score -= 15 }
        result.postureScore = max(score, 0)

        // ── Issue label (most critical first) ────────────────────────────────
        if !result.hipOk {
            result.issue = result.hipAngle < bridgeTopHipMin ? .hipsTooLow : .hipsTooHigh
        } else if !result.spineOk {
            result.issue = .backArched
        } else if !result.kneeOk {
            result.issue = result.kneeAngle < kneeMin ? .kneeTooClose : .kneeTooWide
        } else if !result.shoulderOk {
            result.issue = .shoulderLifted
        } else {
            result.issue = .correct
        }
    }

    // MARK: - Rep state machine
    //
    // The rep uses hip Y-position (raw Vision coords) as the primary trigger
    // because it directly measures elevation independent of body rotation.
    //
    // Gate 1: hip.y rises above (baseline + hipRiseRequired) → rep starts
    // Gate 2: hipAngle ≥ bridgeTopHipMin for framesForTop frames → top confirmed
    // Gate 3: hip.y falls back within flatThreshold of baseline → rep closes
    //
    // flatThreshold: how close to baseline the hip must return to close the rep.
    private let flatThreshold: Double = 0.04  // 4 % of frame height

    private func updatePhaseAndReps(result: GluteBridgeResult,
                                    rawPoints: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) {

        guard baselineCaptured, let hipBase = hipYBaseline else {
            // Baseline not yet established — show phase as waiting
            DispatchQueue.main.async {
                self.phaseText  = "Hold Still to Calibrate"
                self.phaseColor = .white.opacity(0.6)
            }
            return
        }

        let useLeft  = result.trackedLeftSide
        let hipKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip : .rightHip
        guard let hipPt = rawPoints[hipKey], hipPt.confidence > 0.35 else { return }

        let currentHipY = hipPt.location.y  // Vision y increases upward
        let hipRise     = currentHipY - hipBase  // positive = hip went up

        var nextPhase = currentPhase
        var addRep    = false
        var badRep    = false

        // Accumulate form errors while rep is in progress
        if repInProgress {
            if !result.hipOk      { hipErrFrames      += 1 } else { hipErrFrames      = max(0, hipErrFrames      - 1) }
            if !result.kneeOk     { kneeErrFrames     += 1 } else { kneeErrFrames     = max(0, kneeErrFrames     - 1) }
            if !result.spineOk    { spineErrFrames    += 1 } else { spineErrFrames    = max(0, spineErrFrames    - 1) }
            if !result.shoulderOk { shoulderErrFrames += 1 } else { shoulderErrFrames = max(0, shoulderErrFrames - 1) }
            if hipErrFrames      >= errorLatch { hadHipError      = true }
            if kneeErrFrames     >= errorLatch { hadKneeError     = true }
            if spineErrFrames    >= errorLatch { hadSpineError    = true }
            if shoulderErrFrames >= errorLatch { hadShoulderError = true }
        }

        // ── Gate 1: hip starts to rise → rep begins ──────────────────────────
        if !repInProgress && hipRise >= hipRiseRequired {
            repInProgress  = true
            framesAtTop    = 0
            framesAtFlat   = 0
            nextPhase      = .ascending
        }

        // ── Ascending vs top ──────────────────────────────────────────────────
        if repInProgress && hipRise >= hipRiseRequired {
            nextPhase = .ascending
        }

        // ── Gate 2: confirm top ──────────────────────────────────────────────
        // Hip is high enough AND hip angle confirms full extension
        if repInProgress && result.hipAngle >= bridgeTopHipMin && hipRise >= hipRiseRequired {
            framesAtTop += 1
            if framesAtTop >= framesForTop {
                topReached = true
                nextPhase  = .top
            }
        } else if repInProgress && nextPhase != .top {
            framesAtTop = max(0, framesAtTop - 1)  // decay if momentarily out of range
        }

        // ── Descending ───────────────────────────────────────────────────────
        if topReached && hipRise < hipRiseRequired && hipRise > flatThreshold {
            nextPhase = .descending
        }

        // ── Gate 3: hip returns to flat → close rep ──────────────────────────
        if repInProgress && hipRise <= flatThreshold {
            framesAtFlat += 1
            if framesAtFlat >= framesForFlat {
                if topReached {
                    let goodForm = !hadHipError && !hadKneeError && !hadSpineError && !hadShoulderError
                    if goodForm { addRep = true } else { badRep = true }
                } else {
                    badRep = true   // never reached full extension
                }
                resetRepState()
                nextPhase = .flat
            }
        } else if repInProgress {
            framesAtFlat = 0
        }

        currentPhase = nextPhase
        let reasons  = buildBadRepReasons(topWasReached: topReached)

        DispatchQueue.main.async {
            if addRep { self.reps += 1 }
            if badRep { self.triggerBadRepFeedback(reasons: reasons) }
            switch nextPhase {
            case .flat:        self.phaseText = "Lie Flat";       self.phaseColor = .white
            case .ascending:   self.phaseText = "Lifting Up";     self.phaseColor = .yellow
            case .top:         self.phaseText = "Full Bridge ✅"; self.phaseColor = .green
            case .descending:  self.phaseText = "Lowering Down";  self.phaseColor = .blue
            }
        }
    }

    private func buildBadRepReasons(topWasReached: Bool) -> String {
        var r: [String] = []
        if hadHipError      { r.append("Hips not high enough") }
        if hadSpineError    { r.append("Back arching") }
        if hadKneeError     { r.append("Foot placement off") }
        if hadShoulderError { r.append("Shoulders lifted") }
        if !topWasReached   { r.append("Didn't reach full extension") }
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
    private func updateFormAlert(result: GluteBridgeResult) {
        // Only show alerts during the active part of the rep
        guard currentPhase == .ascending || currentPhase == .top else {
            DispatchQueue.main.async { self.showFormAlert = false }
            return
        }
        var message: String? = nil
        if !result.hipOk {
            message = result.hipAngle < bridgeTopHipMin ? "Push Hips Higher!" : "Don't Hyperextend!"
        } else if !result.spineOk    { message = "Keep Back Neutral — Use Your Glutes!" }
        else if !result.shoulderOk   { message = "Keep Shoulders on the Floor!" }
        else if !result.kneeOk       { message = result.kneeAngle < kneeMin ? "Move Feet Further Away!" : "Move Feet Closer!" }

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
        let l: Float = conf(.leftShoulder) + conf(.leftHip) + conf(.leftKnee) + conf(.leftAnkle)
        let r: Float = conf(.rightShoulder) + conf(.rightHip) + conf(.rightKnee) + conf(.rightAnkle)
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

    private func smooth(_ result: GluteBridgeResult)
        -> (hip: Double, knee: Double, spine: Double, shoulderRise: Double) {
        angleBuffer.append((result.hipAngle, result.kneeAngle,
                            result.spineAngle, result.shoulderRise))
        if angleBuffer.count > bufferSize { angleBuffer.removeFirst() }
        let n = Double(angleBuffer.count)
        return (
            hip:          angleBuffer.map(\.hip).reduce(0,          +) / n,
            knee:         angleBuffer.map(\.knee).reduce(0,         +) / n,
            spine:        angleBuffer.map(\.spine).reduce(0,        +) / n,
            shoulderRise: angleBuffer.map(\.shoulderRise).reduce(0, +) / n
        )
    }
}
