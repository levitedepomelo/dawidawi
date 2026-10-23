import SceneKit
import UIKit

/// Construye en SceneKit el muñeco descrito por un `CreatureRig`: cada pieza es una primitiva
/// low-poly texturizada con su recorte de la foto (pixelado, filtrado "nearest" como en PS1).
enum RigBuilder {
    static func build(rig: CreatureRig, photo: UIImage) -> FigureBuilder.Figure? {
        guard let cg = photo.cgImage else { return nil }
        let root = SCNNode()
        var minX = Float.greatestFiniteMagnitude, maxX = -Float.greatestFiniteMagnitude
        var minY = Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        var tris = 0

        for (index, part) in rig.parts.prefix(40).enumerated() {
            let center = vector(part.center, default: 0)
            let size = vector(part.size, default: 0.2).map { max(0.02, min(3, $0)) }
            let rotation = vector(part.rotation, default: 0).map { $0 * .pi / 180 }
            let pivot = part.pivot.count == 3 ? vector(part.pivot, default: 0) : center
            let taper = Float(max(0.05, min(2, part.taper)))

            let colorMat = colorMaterial(part.color)
            var texMat: SCNMaterial? = nil
            if part.texture_faces != "none", let crop = crop(cg, region: part.texture_region) {
                texMat = RetroStage.pixelMaterial(crop)
            }
            let front = texMat ?? colorMat
            var other = colorMat
            if part.texture_faces == "all", let texMat {
                other = texMat
            } else if part.texture_faces == "front", let texture = texMat?.diffuse.contents {
                // Laterales y nuca: parche ampliado de la parte alta de la misma textura (pelaje),
                // algo más oscuro, para que la pieza no quede de color plano por detrás.
                let patch = RetroStage.pixelMaterial(texture)
                patch.diffuse.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(0.35, 0.25, 1),
                                                                 SCNMatrix4MakeTranslation(0.32, 0.02, 0))
                patch.multiply.contents = UIColor(white: 0.82, alpha: 1)
                other = patch
            }

            let geoNode = SCNNode()
            switch part.shape {
            case "box", "wedge":
                let topDepth = part.shape == "wedge" ? size[2] * 0.12 : size[2] * taper
                geoNode.geometry = FigureBuilder.box(bottom: [size[0], size[2]], top: [size[0] * taper, topDepth],
                                                     height: size[1],
                                                     materials: [front, other, other, other, other, other])
                if let g = geoNode.geometry { geoNode.position.y = FigureBuilder.centerLift(g) - size[1] / 2 }
                tris += 12
            case "pyramid":
                geoNode.geometry = FigureBuilder.pyramid(width: size[0], height: size[1], depth: size[2], material: front)
                geoNode.position.y = -size[1] / 2
                tris += 4
            case "cylinder", "cone":
                let geometry: SCNGeometry
                if part.shape == "cone" {
                    let cone = SCNCone(topRadius: CGFloat(0.5 * min(taper, 0.9)), bottomRadius: 0.5, height: 1)
                    cone.radialSegmentCount = GraphicsStyle.isRetro ? 7 : 16
                    geometry = cone
                } else {
                    let cylinder = SCNCylinder(radius: 0.5, height: 1)
                    cylinder.radialSegmentCount = GraphicsStyle.isRetro ? 7 : 16
                    geometry = cylinder
                }
                geometry.materials = [other, colorMat, colorMat]
                geoNode.geometry = geometry
                geoNode.scale = SCNVector3(size[0], size[1], size[2])
                tris += 28
            default: // sphere
                let sphere = SCNSphere(radius: 0.5)
                sphere.isGeodesic = GraphicsStyle.isRetro
                sphere.segmentCount = GraphicsStyle.isRetro ? 2 : 20
                sphere.materials = [front]
                geoNode.geometry = sphere
                geoNode.scale = SCNVector3(size[0], size[1], size[2])
                tris += 80
            }

            let partNode = SCNNode()
            partNode.position = SCNVector3(center[0] - pivot[0], center[1] - pivot[1], center[2] - pivot[2])
            partNode.eulerAngles = SCNVector3(rotation[0], rotation[1], rotation[2])
            partNode.addChildNode(geoNode)

            let joint = SCNNode()
            joint.position = SCNVector3(pivot[0], pivot[1], pivot[2])
            joint.addChildNode(partNode)
            root.addChildNode(joint)
            animate(joint, kind: part.animation, side: pivot[0] < 0 ? -1 : 1, index: index)

            let r = max(size[0], size[2]) / 2
            minX = min(minX, center[0] - r); maxX = max(maxX, center[0] + r)
            minY = min(minY, center[1] - size[1] / 2); maxY = max(maxY, center[1] + size[1] / 2)
        }
        guard maxX > minX, maxY > minY else { return nil }
        // Apoyar en el suelo y centrar
        root.position = SCNVector3(-(minX + maxX) / 2, -minY, 0)
        let container = SCNNode()
        container.addChildNode(root)
        return FigureBuilder.Figure(node: container, width: maxX - minX, height: maxY - minY, triangleCount: tris)
    }

    // MARK: - Utilidades

    private static func vector(_ values: [Double], default value: Float) -> [Float] {
        values.count >= 3 ? values.prefix(3).map { Float($0) } : [value, value, value]
    }

    private static func colorMaterial(_ hex: String) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(hex: hex) ?? UIColor(white: 0.7, alpha: 1)
        m.lightingModel = .lambert
        return m
    }

    /// Recorta la región normalizada de la foto y la reduce a textura de 40 px como máximo.
    private static func crop(_ cg: CGImage, region: [Double]) -> CGImage? {
        guard region.count == 4 else { return nil }
        let x0 = max(0, min(1, region[0])), y0 = max(0, min(1, region[1]))
        let x1 = max(0, min(1, region[2])), y1 = max(0, min(1, region[3]))
        guard x1 - x0 > 0.01, y1 - y0 > 0.01 else { return nil }
        let rect = CGRect(x: x0 * Double(cg.width), y: y0 * Double(cg.height),
                          width: (x1 - x0) * Double(cg.width), height: (y1 - y0) * Double(cg.height)).integral
        guard let piece = cg.cropping(to: rect) else { return nil }
        let scale = min(1, (GraphicsStyle.isRetro ? 40 : 160) / Double(max(piece.width, piece.height)))
        let w = max(2, Int(Double(piece.width) * scale)), h = max(2, Int(Double(piece.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return piece }
        ctx.interpolationQuality = .high
        ctx.draw(piece, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? piece
    }

    private static func animate(_ node: SCNNode, kind: String, side: Float, index: Int) {
        let phase: Float = index % 2 == 0 ? 0 : .pi
        switch kind {
        case "sway": FigureBuilder.swing(node, axis: SCNVector3(0, 0, 1), amplitude: 0.07, period: 2.6, phase: 0)
        case "twitch": FigureBuilder.swing(node, axis: SCNVector3(0, 0, 1), amplitude: 0.12 * side, period: 1.7, phase: phase)
        case "wag": FigureBuilder.swing(node, axis: SCNVector3(0, 1, 0), amplitude: 0.5, period: 0.75, phase: 0)
        case "flap": FigureBuilder.swing(node, axis: SCNVector3(0, 0, 1), amplitude: 0.45 * side, period: 0.5, phase: 0)
        case "step": FigureBuilder.swing(node, axis: SCNVector3(1, 0, 0), amplitude: 0.18, period: 1.2, phase: side > 0 ? 0 : .pi)
        case "bob": FigureBuilder.swing(node, axis: SCNVector3(1, 0, 0), amplitude: 0.06, period: 2.0, phase: phase)
        default: break
        }
    }
}

extension UIColor {
    /// "#RRGGBB" → UIColor
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
