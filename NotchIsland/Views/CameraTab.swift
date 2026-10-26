import AVFoundation
import SwiftUI

/// Mirrored camera preview. The camera runs only while this view is on
/// screen: switching tabs or collapsing the panel removes it and stops it.
struct CameraTabView: View {
    @ObservedObject var camera: CameraService

    var body: some View {
        ZStack {
            switch camera.state {
            case .running:
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .aspectRatio(4 / 3, contentMode: .fit)
            case .idle, .requestingAccess:
                ProgressView()
                    .controlSize(.small)
            case .denied:
                CameraMessageView(
                    symbol: "video.slash.fill",
                    message: "Camera access is off for NotchIsland.",
                    buttonTitle: "Open System Settings",
                    action: camera.openPrivacySettings
                )
            case .unavailable:
                CameraMessageView(symbol: "video.slash", message: "No camera found.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}

private struct CameraMessageView: View {
    let symbol: String
    let message: LocalizedStringKey
    var buttonTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .controlSize(.small)
            }
        }
        .multilineTextAlignment(.center)
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}
}

private final class PreviewView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.addSublayer(previewLayer)

        // The preview connection only exists once the session is running.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionDidStartRunning),
            name: AVCaptureSession.didStartRunningNotification,
            object: session
        )
    }

    // Posted on the capture queue.
    @objc nonisolated private func sessionDidStartRunning(_ notification: Notification) {
        Task { @MainActor in self.needsLayout = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // bounds/position rather than frame, since the layer may be flipped.
        previewLayer.bounds = bounds
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        applyMirroring()
        CATransaction.commit()
    }

    /// Show the image like a mirror, via the connection when supported and
    /// by flipping the layer otherwise.
    private func applyMirroring() {
        guard let connection = previewLayer.connection else { return }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
            previewLayer.setAffineTransform(.identity)
        } else {
            previewLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        }
    }
}
