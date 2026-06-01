//
//  ContentView.swift
//  PostureCorrect
//
//  Shared camera infrastructure used by PushupCameraView,
//  LungeCameraView, and PlankCameraView.
//  Nothing else lives here — each exercise owns its own file.
//

import SwiftUI
import AVFoundation

// MARK: - SHARED CAMERA PREVIEW
// Wrap AVCaptureVideoPreviewLayer in a SwiftUI view.
// Used by every exercise camera view in the app.

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session      = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
