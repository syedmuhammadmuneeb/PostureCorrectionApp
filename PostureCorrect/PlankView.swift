//
//  PlankView.swift
//  PostureCorrect
//
//  Camera placement: SIDE-ON — phone on the floor to your left or right,
//  1.5–2 m away, lens at hip height. Full body ear→shoulder→hip→knee→ankle
//  must be visible.
//
//  ─────────────────────────────────────────────────────────────────────────
//  BIOMECHANICALLY CORRECT PLANK ANGLES
//  ─────────────────────────────────────────────────────────────────────────
//
//  1. Hip angle  (shoulder → hip → knee)
//     A perfect plank has the body in a straight line from shoulder to ankle.
//     The hip is the critical alignment point.
//     • Ideal:      160°–175°  (slight natural curve is fine, fully straight = 180°)
//     • Too low:    < 155°     hips sagging toward the floor
//     • Too high:   > 178°     hips piked up toward the ceiling
//
//  2. Spine angle  (deviation of shoulder→hip line from horizontal)
//     In a correct plank the torso is parallel to the floor → ~0°.
//     • Ideal:      0°–18°     (some tolerance for camera angle variation)
//     • Too high:   > 18°      torso tilted — hips too high or body rotated
//
//  3. Neck angle  (deviation of ear→shoulder line from horizontal)
//     The head should be in neutral alignment with the spine — neither
//     dropping toward the floor nor craning up.
//     • Ideal:      0°–25°
//     • Too high:   > 25°      head dropping or hyper-extended
//
//  ─────────────────────────────────────────────────────────────────────────
//  TIMER LOGIC
//  ─────────────────────────────────────────────────────────────────────────
//  • Starts automatically after ALL THREE checks pass for 10 consecutive
//    frames (~333ms at 30fps) — ensures full body is properly aligned
//    before the clock begins.
//  • Pauses after any check fails for 5 consecutive frames (~167ms).
//    Short enough to catch a real form break, long enough to ignore
//    a single noisy Vision frame.
//  • An orange flash + watch haptic fires when the timer pauses.
//  • Timer resumes automatically (no button needed) when form is corrected.
//
//  ─────────────────────────────────────────────────────────────────────────
//  WATCH NOTIFICATIONS
//  ─────────────────────────────────────────────────────────────────────────
//  1. Exercise opened    — "🏋️ Plank Started"
//  2. Form breaks live   — "⚠️ Fix Your Form — [specific issue]"  (5s throttle)
//  3. New personal best  — "🏆 New Best! — You held for mm:ss"
//

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

// MARK: - PLANK RESULT
struct PlankResult {
    var issue: PlankIssue = .detecting
    var postureScore: Int  = 100
    var hipAngle:   Double = 180
    var spineAngle: Double = 0
    var neckAngle:  Double = 0
    var trackedLeftSide: Bool = true
    var hipOk   = true
    var spineOk = true
    var neckOk  = true
    var formIsValid: Bool { hipOk && spineOk && neckOk }
}

// MARK: - PLANK CAMERA VIEW
struct PlankCameraView: View {
    @StateObject private var viewModel = PlankViewModel()

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

                // Real-time form alert banner
                if viewModel.showFormAlert {
                    PlankFormAlertBanner(message: viewModel.formAlertMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4), value: viewModel.showFormAlert)
                }

                Spacer()
                bottomPanel
            }

            // Orange flash when form breaks
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
        .onAppear    { viewModel.start() }
        .onDisappear { viewModel.stop()  }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Plank AI").font(.title2.bold()).foregroundColor(.white)
                // Shows "HOLDING" or "PAUSED" clearly
                Text(viewModel.isHolding ? "🟢 Timer Running" : "🔴 Timer Paused")
                    .font(.caption.bold())
                    .foregroundColor(viewModel.isHolding ? .green : .red)
            }
            Spacer()
            Button { viewModel.switchCamera() } label: {
                Image(systemName: "camera.rotate").font(.title2).foregroundColor(.white)
                    .padding(12).background(Color.white.opacity(0.2)).clipShape(Circle())
            }
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 5).frame(width: 65, height: 65)
                Circle()
                    .trim(from: 0, to: CGFloat(viewModel.plankResult.postureScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 65, height: 65).rotationEffect(.degrees(-90))
                Text("\(viewModel.plankResult.postureScore)")
                    .font(.headline.bold()).foregroundColor(.white)
            }
        }
        .padding().background(.black.opacity(0.65)).cornerRadius(20).padding()
    }

    // MARK: - Bottom panel
    private var bottomPanel: some View {
        VStack(spacing: 16) {
            // Issue label — most important feedback
            Text(viewModel.plankResult.issue.rawValue)
                .font(.title2.bold()).foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            // Three angle cards
            HStack(spacing: 12) {
                PlankAngleCard(
                    title: "Hip",
                    angle: viewModel.plankResult.hipAngle,
                    isOk:  viewModel.plankResult.hipOk,
                    idealRange: "160°-175°"
                )
                PlankAngleCard(
                    title: "Back",
                    angle: viewModel.plankResult.spineAngle,
                    isOk:  viewModel.plankResult.spineOk,
                    idealRange: "0°-18°"
                )
                PlankAngleCard(
                    title: "Neck",
                    angle: viewModel.plankResult.neckAngle,
                    isOk:  viewModel.plankResult.neckOk,
                    idealRange: "0°-25°"
                )
            }

            // Timer row
            HStack(spacing: 36) {
                // Current hold
                VStack(spacing: 4) {
                    Text(viewModel.formattedTime)
                        .font(.system(size: 52, weight: .bold, design: .monospaced))
                        .foregroundColor(viewModel.isHolding ? .green : .white.opacity(0.6))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: viewModel.formattedTime)
                    Text("HOLD").font(.caption).foregroundColor(.white.opacity(0.7))
                }

                // Best hold
                VStack(spacing: 4) {
                    Text(viewModel.formattedBestTime)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                    Text("BEST").font(.caption).foregroundColor(.white.opacity(0.7))
                }

                // Reset
                Button { viewModel.resetTimer() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title2).foregroundColor(.white)
                        Text("RESET").font(.caption).foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            // Status pill — tells the user exactly what's needed
            statusPill
        }
        .padding().background(.black.opacity(0.75)).cornerRadius(22).padding()
    }

    private var statusPill: some View {
        PlankStatusPill(
            isHolding:    viewModel.isHolding,
            issue:        viewModel.plankResult.issue,
            readyFrames:  viewModel.consecutiveGoodFrames,
            neededFrames: viewModel.goodFramesNeeded
        )
    }

    private var scoreColor: Color {
        let s = viewModel.plankResult.postureScore
        if s >= 80 { return .green }
        if s >= 55 { return .yellow }
        return .red
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

// MARK: - ANGLE CARD
struct PlankAngleCard: View {
    let title: String; let angle: Double; let isOk: Bool; let idealRange: String
    var body: some View {
        VStack(spacing: 5) {
            Text(title).font(.caption).foregroundColor(.white.opacity(0.7))
            Text("\(Int(angle))°").font(.headline.bold()).foregroundColor(isOk ? .green : .red)
            Text(idealRange).font(.caption2).foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(isOk ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
        .cornerRadius(12)
    }
}

// MARK: - SKELETON OVERLAY
// Draws the full side-on chain: ear → shoulder → hip → knee → ankle
// Each segment coloured green/red by its specific form check.
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

                // Ideal body-line reference — dashed horizontal line at hip height
                if let hipPt = bodyPoints[hip] {
                    let refY = hipPt.y * geo.size.height
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: refY))
                        p.addLine(to: CGPoint(x: geo.size.width, y: refY))
                    }
                    .stroke(Color.white.opacity(0.15),
                            style: StrokeStyle(lineWidth: 1, dash: [8, 5]))
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
        if joint == ear                      { return result.neckOk  ? .green : .red }
        if joint == shoulder                 { return result.spineOk ? .green : .red }
        if joint == hip                      { return result.hipOk   ? .green : .red }
        if joint == knee || joint == ankle   { return result.hipOk   ? .green : .red }
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
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.15)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.yellow)
                        .frame(width: geo.size.width * CGFloat(progress), height: 6)
                        .animation(.linear(duration: 0.1), value: readyFrames)
                }
            }.frame(height: 6)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.yellow.opacity(0.1)).cornerRadius(20)
    }

    private func label(_ text: String, color: Color,
                       bg: Color = Color.clear) -> some View {
        Text(text)
            .font(.caption.bold()).foregroundColor(color)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(bg == Color.clear
                ? color.opacity(0.15)
                : bg)
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

    // Exposed to View for progress bar
    @Published var consecutiveGoodFrames = 0
    let goodFramesNeeded = 10   // frames of perfect form before timer starts (~333ms)

    // ── Biomechanically correct plank thresholds ──────────────────────────────
    //
    // Hip angle (shoulder→hip→knee):
    //   A straight plank body = ~170°. We allow 160°–175°.
    //   Below 155° = clear sag. Above 178° = clear pike.
    private let hipIdealMin:    Double = 160
    private let hipIdealMax:    Double = 175
    private let hipSagLimit:    Double = 155   // below this → definitely sagging
    private let hipPikeLimit:   Double = 178   // above this → definitely piked

    // Spine angle (shoulder→hip line deviation from horizontal):
    //   Perfect plank = body parallel to floor = ~0°.
    //   We allow up to 18° for natural variation and camera angle tolerance.
    private let spineIdealMax:  Double = 18

    // Neck angle (ear→shoulder line deviation from horizontal):
    //   Head in neutral = parallel to body = ~0°.
    //   Up to 25° is acceptable; beyond this the head is drooping or craning.
    private let neckIdealMax:   Double = 25

    // ── Timer hysteresis ──────────────────────────────────────────────────────
    // goodFramesNeeded = 10 (published above)
    // badFramesRequired: how many bad frames before timer pauses
    private let badFramesRequired = 5
    private var consecutiveBadFrames = 0

    // ── Smoothing ─────────────────────────────────────────────────────────────
    // 8-frame sliding window smooths out Vision jitter
    private var angleBuffer: [(hip: Double, spine: Double, neck: Double)] = []
    private let bufferSize = 8

    // ── Debounce (prevents issue label flickering) ────────────────────────────
    private var stableIssueFrames = 0
    private var lastIssue: PlankIssue = .detecting

    private var timerTask:  Task<Void, Never>?
    private var alertTimer: Timer?

    // Watch notification throttle
    private var lastNotifTime: [String: Date] = [:]
    private let notifCooldown: TimeInterval   = 4.0

    // MARK: - Lifecycle
    func start() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            DispatchQueue.global(qos: .userInitiated).async { self.setupCamera() }
        }
        fireWatchNotification(
            title: "🏋️ Plank Started",
            body:  "Get into position. Timer starts when form is perfect."
        )
    }

    func stop() { session.stopRunning(); stopTimer() }

    func resetTimer() {
        DispatchQueue.main.async {
            self.stopTimer()
            self.elapsedSeconds          = 0
            self.isHolding               = false
            self.consecutiveGoodFrames   = 0
            self.consecutiveBadFrames    = 0
            self.angleBuffer.removeAll()
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
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "plankVideoQueue"))
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
                DispatchQueue.main.async { self.plankResult.issue = .notVisible }
                pauseTimer()
                return
            }

            // Smooth angles over 8 frames
            let s = smooth(result)
            result.hipAngle   = s.hip
            result.spineAngle = s.spine
            result.neckAngle  = s.neck

            // Evaluate form against biomechanical thresholds
            evaluateForm(result: &result)

            // Update timer state based on form
            updateTimerState(result: result)

            // Debounce issue label (prevents flickering)
            if result.issue == lastIssue { stableIssueFrames += 1 }
            else { stableIssueFrames = 0; lastIssue = result.issue }
            var published = result
            if stableIssueFrames < 3 { published.issue = plankResult.issue }

            // Fire real-time form alert
            // Use non-debounced result for alerts so corrections appear immediately
            // The displayed issue label uses debounced `published` to prevent flickering
            updateFormAlert(result: result)
            DispatchQueue.main.async { self.plankResult = published }
        } catch { print("Plank Vision error: \(error)") }
    }

    // MARK: - Angle extraction
    private func extractAngles(
        from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> PlankResult? {
        let useLeft = betterSide(points)

        let shoulderKey: VNHumanBodyPoseObservation.JointName = useLeft ? .leftShoulder : .rightShoulder
        let hipKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftHip      : .rightHip
        let kneeKey:     VNHumanBodyPoseObservation.JointName = useLeft ? .leftKnee     : .rightKnee
        let ankleKey:    VNHumanBodyPoseObservation.JointName = useLeft ? .leftAnkle    : .rightAnkle
        let earKey:      VNHumanBodyPoseObservation.JointName = useLeft ? .leftEar      : .rightEar

        // All five joints required — plank needs the full chain
        for joint in [shoulderKey, hipKey, kneeKey, ankleKey, earKey] {
            guard let p = points[joint], p.confidence > 0.35 else { return nil }
        }

        let shoulder = points[shoulderKey]!.location
        let hip      = points[hipKey]!.location
        let knee     = points[kneeKey]!.location
        let ear      = points[earKey]!.location

        var result = PlankResult()
        result.trackedLeftSide = useLeft

        // 1. Hip angle: shoulder → hip → knee
        //    Measures straightness of the body line.
        //    180° = perfectly straight. Lower = hips sagging. Higher = piked.
        result.hipAngle = calculateAngle(first: shoulder, middle: hip, last: knee)

        // 2. Spine angle: deviation of shoulder→hip vector from horizontal
        //    In Vision coords y=0 is at the bottom, so a horizontal body
        //    (lying in plank) gives shoulder.y ≈ hip.y → atan2 ≈ 0°.
        let spineRad  = atan2(shoulder.y - hip.y, shoulder.x - hip.x) * 180 / .pi
        result.spineAngle = min(abs(spineRad), 90)

        // 3. Neck angle: deviation of ear→shoulder vector from horizontal
        //    Same principle — head neutral = parallel to floor = ~0°.
        let neckRad   = atan2(ear.y - shoulder.y, ear.x - shoulder.x) * 180 / .pi
        result.neckAngle = min(abs(neckRad), 90)

        return result
    }

    // MARK: - Form evaluation
    // Uses a two-tier system for the hip:
    //   • Ideal range (160°–175°) — green, timer runs
    //   • Tolerance range (155°–178°) — yellow, timer still runs but flags issue
    //   • Outside tolerance — red, timer pauses
    // This avoids pausing the timer for a 1–2° deviation from perfect.
    private func evaluateForm(result: inout PlankResult) {
        let hip   = result.hipAngle
        let spine = result.spineAngle
        let neck  = result.neckAngle

        // Guard: person is upright (spine > 45° = standing/sitting)
        guard spine < 45 else {
            result.hipOk = true; result.spineOk = true; result.neckOk = true
            result.issue = .ready; result.postureScore = 100
            return
        }

        // Hip check — use tolerance range for ok/not-ok (not just ideal)
        // This means the timer runs if hips are between 155°–178°,
        // but the issue label will show a correction if outside 160°–175°.
        result.hipOk = hip >= hipSagLimit && hip <= hipPikeLimit

        // Spine and neck use their ideal ranges
        result.spineOk = spine <= spineIdealMax
        result.neckOk  = neck  <= neckIdealMax

        // Score (weighted: hip most important, then spine, then neck)
        var score = 100
        if !result.hipOk   { score -= 45 }
        if !result.spineOk { score -= 35 }
        if !result.neckOk  { score -= 20 }
        result.postureScore = max(score, 0)

        // Issue label — most critical error shown first
        if !result.hipOk {
            result.issue = hip < hipSagLimit ? .hipsTooLow : .hipsTooHigh
        } else if !result.spineOk { result.issue = .backSagging }
        else if !result.neckOk    { result.issue = .headDropping }
        else {
            // Form is within tolerance — show ideal corrections subtly if outside ideal
            if hip < hipIdealMin      { result.issue = .hipsTooLow  }
            else if hip > hipIdealMax { result.issue = .hipsTooHigh }
            else                      { result.issue = .correct }
        }
    }

    // MARK: - Timer state machine
    //
    // The timer only starts when ALL checks pass for goodFramesNeeded frames.
    // This is the key "posture must be correct first" requirement.
    // If any check fails for badFramesRequired frames, the timer pauses.
    private func updateTimerState(result: PlankResult) {
        if result.formIsValid {
            consecutiveBadFrames = 0
            consecutiveGoodFrames += 1
            if consecutiveGoodFrames >= goodFramesNeeded {
                startTimer()
            }
        } else {
            consecutiveGoodFrames = max(0, consecutiveGoodFrames - 1)  // decay, don't reset hard
            consecutiveBadFrames  += 1
            if consecutiveBadFrames >= badFramesRequired {
                pauseTimer()
                triggerFormBreakFlash()
            }
        }
        // Publish consecutiveGoodFrames for the progress bar in the View
        DispatchQueue.main.async { }   // already on background; publish happens via @Published
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
                    // Personal best notification
                    if self.elapsedSeconds > self.bestSeconds {
                        self.bestSeconds = self.elapsedSeconds
                        // Only notify at meaningful milestones: 10s, 30s, 60s, then every 30s
                        let milestones = [10, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300]
                        if milestones.contains(self.bestSeconds) {
                            self.fireWatchNotification(
                                title: "🏆 New Best!",
                                body:  "You held for \(self.formatSeconds(self.bestSeconds))!"
                            )
                        }
                    }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.showFormBreakFlash = false
            }
        }
    }

    // MARK: - Form alert + watch notification
    private func updateFormAlert(result: PlankResult) {
        var message: String? = nil

        if !result.hipOk {
            message = result.hipAngle < hipSagLimit
                ? "Raise Your Hips — They're Sagging!"
                : "Lower Your Hips — They're Too High!"
        } else if !result.spineOk {
            message = "Keep Your Back Straight!"
        } else if !result.neckOk {
            message = "Keep Your Head Neutral!"
        } else if result.issue == .hipsTooLow {
            message = "Push Hips Up Slightly"
        } else if result.issue == .hipsTooHigh {
            message = "Drop Hips Down Slightly"
        }

        if let msg = message {
            // Key by the specific message so each error type has its own 5s throttle.
            // "Raise Your Hips" and "Keep Back Straight" are independent throttles.
            fireWatchNotification(title: "⚠️ Fix Your Form", body: msg, key: msg)
        }

        DispatchQueue.main.async {
            if let msg = message {
                // Show banner immediately and keep it visible as long as error persists.
                // Only reset the 2s dismiss timer when the message CHANGES.
                if self.formAlertMessage != msg {
                    self.formAlertMessage = msg
                    self.alertTimer?.invalidate()
                    self.alertTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { _ in
                        DispatchQueue.main.async { self.showFormAlert = false }
                    }
                }
                self.showFormAlert = true
            } else {
                // No error — hide banner immediately
                self.alertTimer?.invalidate()
                self.showFormAlert = false
            }
        }
    }

    // MARK: - Watch notification
    func fireWatchNotification(title: String, body: String, key: String? = nil) {
        let throttleKey = key ?? title
        let now = Date()
        if let last = lastNotifTime[throttleKey], now.timeIntervalSince(last) < notifCooldown { return }
        lastNotifTime[throttleKey] = now
        NotificationManager.shared.send(title: title, body: body)
        WatchConnectivityManager.shared.sendFormAlert(exercise: "Plank", issue: "\(title): \(body)")
    }

    // MARK: - Helpers
    private func betterSide(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        func c(_ j: VNHumanBodyPoseObservation.JointName) -> Float { points[j]?.confidence ?? 0 }
        let l: Float = c(.leftShoulder) + c(.leftHip) + c(.leftKnee) + c(.leftAnkle) + c(.leftEar)
        let r: Float = c(.rightShoulder) + c(.rightHip) + c(.rightKnee) + c(.rightAnkle) + c(.rightEar)
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

    private func smooth(_ result: PlankResult) -> (hip: Double, spine: Double, neck: Double) {
        angleBuffer.append((result.hipAngle, result.spineAngle, result.neckAngle))
        if angleBuffer.count > bufferSize { angleBuffer.removeFirst() }
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
