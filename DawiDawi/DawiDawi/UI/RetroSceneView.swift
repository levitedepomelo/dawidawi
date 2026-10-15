import SceneKit
import SwiftUI

/// SCNView que renderiza a baja resolución interna y escala con "vecino más cercano":
/// el truco que da el aspecto 240p de PS1/N64 a cualquier tamaño de iPhone.
final class PixelSCNView: SCNView {
    var pixelScale: CGFloat = 0.8 {
        didSet { applyPixelScale() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyPixelScale()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyPixelScale()
    }

    private func applyPixelScale() {
        if abs(contentScaleFactor - pixelScale) > 0.001 { contentScaleFactor = pixelScale }
        layer.magnificationFilter = .nearest
        layer.minificationFilter = .nearest
    }
}

/// Visor 3D de una criatura: gira sola y se puede arrastrar para rotarla.
struct RetroSceneView: UIViewRepresentable {
    let stage: RetroStage
    var pixelScale: CGFloat = 0.8
    var interactive = true

    func makeCoordinator() -> Coordinator { Coordinator(stage: stage) }

    func makeUIView(context: Context) -> PixelSCNView {
        let view = PixelSCNView(frame: .zero)
        view.pixelScale = pixelScale
        view.scene = stage.scene
        view.pointOfView = stage.cameraNode
        view.backgroundColor = .black
        view.antialiasingMode = .none
        view.preferredFramesPerSecond = 30 // 30 fps: auténtico y ahorra batería
        view.rendersContinuously = true
        view.isPlaying = true
        view.allowsCameraControl = false
        view.isJitteringEnabled = false
        if interactive {
            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
            view.addGestureRecognizer(pan)
        }
        return view
    }

    func updateUIView(_ view: PixelSCNView, context: Context) {
        view.pixelScale = pixelScale
        if view.scene !== stage.scene {
            view.scene = stage.scene
            view.pointOfView = stage.cameraNode
            context.coordinator.stage = stage
        }
    }

    static func dismantleUIView(_ view: PixelSCNView, coordinator: Coordinator) {
        view.isPlaying = false
        view.scene = nil
    }

    final class Coordinator: NSObject {
        var stage: RetroStage
        private var startAngle: Float = 0
        private var resumeWork: DispatchWorkItem?

        init(stage: RetroStage) { self.stage = stage }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                resumeWork?.cancel()
                stage.stopSpin()
                startAngle = stage.turntable.presentation.eulerAngles.y
                stage.turntable.eulerAngles.y = startAngle
            case .changed:
                let dx = Float(gesture.translation(in: gesture.view).x)
                stage.turntable.eulerAngles.y = startAngle + dx * 0.012
            default:
                let work = DispatchWorkItem { [weak self] in self?.stage.startSpin() }
                resumeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
            }
        }
    }
}
