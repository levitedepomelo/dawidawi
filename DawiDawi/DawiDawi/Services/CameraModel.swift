import AVFoundation
import SwiftUI
import UIKit

/// Cámara nativa con AVFoundation. El permiso se pide solo al abrir el modo captura.
/// `@unchecked Sendable`: la sesión y sus entradas solo se tocan en `queue` (cola serie) y las
/// propiedades publicadas solo en el hilo principal, así que cruzar `self` a esa cola es seguro.
final class CameraModel: NSObject, ObservableObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "dawidawi.camera.session")
    private var input: AVCaptureDeviceInput?
    private var photoContinuation: CheckedContinuation<UIImage?, Never>?

    @Published var authorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var isAvailable = true
    @Published var isRunning = false
    @Published var position: AVCaptureDevice.Position = .back
    @Published var flashOn = false

    @MainActor
    func start() async {
        if authorization == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorization = granted ? .authorized : .denied
        }
        guard authorization == .authorized else { return }
        let configured = await configureIfNeeded()
        isAvailable = configured
        guard configured else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                if !self.session.isRunning { self.session.startRunning() }
                cont.resume()
            }
        }
        isRunning = session.isRunning
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private func configureIfNeeded() async -> Bool {
        await withCheckedContinuation { cont in
            queue.async {
                if self.input != nil { cont.resume(returning: true); return }
                guard let device = Self.device(for: self.position),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    cont.resume(returning: false); return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                if self.session.canAddInput(input) { self.session.addInput(input) }
                if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
                self.output.maxPhotoQualityPrioritization = .balanced
                self.session.commitConfiguration()
                self.input = input
                cont.resume(returning: true)
            }
        }
    }

    private static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera,
                                                   .builtInDualCamera, .builtInWideAngleCamera]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position)
        return discovery.devices.first
    }

    @MainActor
    func flip() {
        let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back
        queue.async {
            guard let device = Self.device(for: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            if let current = self.input { self.session.removeInput(current) }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.input = newInput
            } else if let current = self.input {
                self.session.addInput(current)
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async { self.position = newPosition }
        }
    }

    @MainActor
    func capture() async -> UIImage? {
        guard isRunning, photoContinuation == nil else { return nil }
        let flash = flashOn
        return await withCheckedContinuation { cont in
            photoContinuation = cont
            queue.async {
                let settings = AVCapturePhotoSettings()
                if self.output.supportedFlashModes.contains(.on) && flash && self.position == .back {
                    settings.flashMode = .on
                }
                settings.photoQualityPrioritization = .balanced
                if let connection = self.output.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                    if self.position == .front, connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = true
                    }
                }
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func finish(_ image: UIImage?) {
        DispatchQueue.main.async {
            self.photoContinuation?.resume(returning: image)
            self.photoContinuation = nil
        }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            finish(nil); return
        }
        finish(image)
    }
}

/// Vista previa en vivo de la cámara.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
