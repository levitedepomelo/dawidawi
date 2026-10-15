import UIKit
import Vision
import CoreImage

/// Recorta el sujeto principal de la foto (lo que Apple llama "lift subject").
/// Importante: esto SOLO separa figura y fondo. No reconoce, clasifica ni nombra nada.
enum SubjectExtractor {
    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Devuelve una imagen RGBA con el fondo transparente, recortada al sujeto.
    /// Si Vision no encuentra un sujeto (o en el simulador), usa un recorte central ovalado.
    static func extractSubject(from image: UIImage) -> CGImage? {
        guard let cg = image.cgImage else { return nil }
        if let lifted = liftWithVision(cg) { return lifted }
        return ovalCrop(cg)
    }

    private static func liftWithVision(_ cg: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let instances = observation.allInstances
            guard !instances.isEmpty else { return nil }

            let chosen = pickMainInstance(observation: observation, candidates: instances)
            let buffer = try observation.generateMaskedImage(ofInstances: chosen,
                                                             from: handler,
                                                             croppedToInstancesExtent: true)
            let ci = CIImage(cvPixelBuffer: buffer)
            return ciContext.createCGImage(ci, from: ci.extent)
        } catch {
            return nil
        }
    }

    /// Si hay varios sujetos, elige el que tenga mejor combinación de tamaño y cercanía al centro
    /// (el que el usuario está encuadrando).
    private static func pickMainInstance(observation: VNInstanceMaskObservation, candidates: IndexSet) -> IndexSet {
        guard candidates.count > 1 else { return candidates }
        let mask = observation.instanceMask
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return candidates }
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        var scores: [Int: Double] = [:]
        let cx = Double(width) / 2, cy = Double(height) / 2
        let maxDist = sqrt(cx * cx + cy * cy)
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                let label = Int(ptr[y * rowBytes + x])
                guard label != 0, candidates.contains(label) else { continue }
                let dx = Double(x) - cx, dy = Double(y) - cy
                let centerWeight = 1.0 - 0.7 * (sqrt(dx * dx + dy * dy) / maxDist)
                scores[label, default: 0] += centerWeight
            }
        }
        guard let best = scores.max(by: { $0.value < $1.value })?.key else { return candidates }
        return IndexSet(integer: best)
    }

    /// Alternativa sin Vision: recorte central con máscara ovalada.
    private static func ovalCrop(_ cg: CGImage) -> CGImage? {
        let side = min(cg.width, cg.height)
        let w = Int(Double(side) * 0.78), h = Int(Double(side) * 0.88)
        let originX = (cg.width - w) / 2, originY = (cg.height - h) / 2
        guard let cropped = cg.cropping(to: CGRect(x: originX, y: originY, width: w, height: h)) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: {
            let f = UIGraphicsImageRendererFormat()
            f.scale = 1
            f.opaque = false
            return f
        }())
        let image = renderer.image { ctx in
            let rect = CGRect(x: 0, y: 0, width: w, height: h)
            UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).addClip()
            UIImage(cgImage: cropped).draw(in: rect)
        }
        return image.cgImage
    }
}

extension UIImage {
    /// Corrige la orientación EXIF y limita el tamaño máximo (rendimiento y almacenamiento).
    func normalized(maxDimension: CGFloat = 1280) -> UIImage {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            self.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
