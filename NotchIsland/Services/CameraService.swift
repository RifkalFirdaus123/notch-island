import AVFoundation
import AppKit
import Combine

enum CameraState: Equatable {
    case idle
    case requestingAccess
    case running
    case denied
    case unavailable
}

/// Runs the capture session only while someone is looking at it.
/// Frames go straight to the preview layer; nothing is recorded or stored.
final class CameraService: ObservableObject {
    @Published private(set) var state: CameraState = .idle

    let capture = CaptureSessionController()
    /// True between `start()` and `stop()`; guards against a late permission
    /// answer starting the camera after the tab was closed.
    private var wantsRunning = false

    var session: AVCaptureSession { capture.session }

    static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
    )!

    func start() {
        wantsRunning = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            state = .requestingAccess
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !granted {
                        self.state = .denied
                    } else if self.wantsRunning {
                        self.run()
                    } else {
                        self.state = .idle
                    }
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    func stop() {
        wantsRunning = false
        capture.stop()
        if state == .running { state = .idle }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(Self.privacySettingsURL)
    }

    private func run() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            state = .unavailable
            return
        }
        capture.start(with: device)
        state = .running
    }
}

/// Owns the AVCaptureSession and touches it only on its own serial queue,
/// since starting/stopping blocks.
nonisolated final class CaptureSessionController: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "NotchIsland.camera")
    private var configuredDeviceID: String?

    func start(with device: AVCaptureDevice) {
        let deviceID = device.uniqueID
        queue.async { [self] in
            if configuredDeviceID != deviceID {
                configure(deviceID: deviceID)
            }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure(deviceID: String) {
        guard let device = AVCaptureDevice(uniqueID: deviceID),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }

        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if session.canAddInput(input) {
            session.addInput(input)
            configuredDeviceID = deviceID
        }
        if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }
        session.commitConfiguration()
    }
}
