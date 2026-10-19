import Vision
import CoreGraphics

/// Localiza la cara del sujeto para texturizar la cabeza del muñeco con ella.
/// Usa los puntos del cuerpo que detecta Vision (ojos, nariz, base de las orejas): solo posiciones,
/// sin etiquetas ni clasificación. Si Vision no encuentra puntos fiables, devuelve nil y el
/// generador usa una estimación por la forma de la silueta.
enum FaceLocator {
    /// Rectángulo cuadrado en coordenadas normalizadas de `image` (0…1, origen arriba a la izquierda).
    static func faceRect(in image: CGImage) -> CGRect? {
        let request = VNDetectAnimalBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let points = try? observation.recognizedPoints(.head) else { return nil }

        let w = Double(image.width), h = Double(image.height)
        func pixel(_ name: VNAnimalBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = points[name], p.confidence > 0.3 else { return nil }
            return CGPoint(x: Double(p.location.x) * w, y: (1 - Double(p.location.y)) * h)
        }
        let leftEye = pixel(.leftEye), rightEye = pixel(.rightEye), nose = pixel(.nose)
        let core = [leftEye, rightEye, nose].compactMap { $0 }
        guard core.count >= 2 else { return nil }

        let cx = core.map(\.x).reduce(0, +) / Double(core.count)
        let cy = core.map(\.y).reduce(0, +) / Double(core.count)
        // Tamaño: a partir de la distancia entre ojos (o entre orejas), con margen para mejillas y frente
        var span = 0.0
        if let l = leftEye, let r = rightEye { span = hypot(l.x - r.x, l.y - r.y) * 2.8 }
        if let l = pixel(.leftEarBottom), let r = pixel(.rightEarBottom) { span = max(span, hypot(l.x - r.x, l.y - r.y) * 1.25) }
        if span < 4, let n = nose, let e = leftEye ?? rightEye { span = hypot(n.x - e.x, n.y - e.y) * 3.4 }
        guard span > 4 else { return nil }

        let side = min(span, min(w, h))
        let rect = CGRect(x: cx - side / 2, y: cy - side * 0.45, width: side, height: side)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard rect.width > 4, rect.height > 4 else { return nil }
        return CGRect(x: rect.minX / w, y: rect.minY / h, width: rect.width / w, height: rect.height / h)
    }
}
