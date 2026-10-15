import SceneKit
import simd

/// Genera automáticamente un "muñeco" low-poly estilo PS1/N64 para cada criatura, como los
/// modelos caseros de los 90: cabeza de bloque con la cara de la foto, cuerpo, patas/brazos,
/// orejas y cola, todo texturizado con recortes de la propia foto.
///
/// No reconoce qué animal es: solo mira la FORMA de la silueta.
///  - Silueta alargada (animal de perfil)  → cuadrúpedo (cuerpo horizontal y 4 patas).
///  - Silueta alta / compacta (de frente)   → muñeco erguido (patas, brazos y cabeza grande).
///  - Apéndices arriba → orejas. Apéndice lateral → cola.
enum FigureBuilder {
    struct Figure {
        let node: SCNNode
        let width: Float
        let height: Float
        let triangleCount: Int
    }

    /// Recortes de textura sacados del sprite (coordenadas de píxel, origen arriba a la izquierda).
    private struct Crops {
        let face: CGImage
        let fur: CGImage
        let lower: CGImage
        let ear: CGImage
    }

    static func build(sprite: CGImage, seed: Int) -> Figure? {
        guard let buf = PixelBuffer(cgImage: sprite) else { return nil }
        // Caja del sujeto
        var minX = buf.width, minY = buf.height, maxX = -1, maxY = -1
        for y in 0..<buf.height { for x in 0..<buf.width where buf.alpha(x, y) > 0 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX > minX + 3, maxY > minY + 3 else { return nil }
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        let aspect = Float(bw) / Float(bh)

        // Rasgos de forma (orejas, cola, patas) a partir del análisis por piezas de la silueta
        let analysis = MeshBuilder.build(sprite: sprite, grid: 22, seed: seed)
        let kinds = analysis?.parts.map(\.kind) ?? []
        let hasEars = kinds.contains(.top)
        let hasTail = kinds.contains(.side)
        let quadruped = aspect > 1.25

        guard let opaque = RetroStylizer.dilatedOpaque(sprite) else { return nil }
        // Lado de la cabeza en siluetas alargadas: el extremo cuyo punto más alto está más arriba
        func topRow(fromX: Int, toX: Int) -> Int {
            for y in minY...maxY { for x in fromX...toX where buf.alpha(x, y) > 0 { return y } }
            return maxY
        }
        let third = max(1, bw / 3)
        let headOnRight = topRow(fromX: maxX - third, toX: maxX) < topRow(fromX: minX, toX: minX + third)

        func crop(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CGImage {
            let rx = max(minX, min(x, maxX - 1)), ry = max(minY, min(y, maxY - 1))
            let rw = max(2, min(w, maxX + 1 - rx)), rh = max(2, min(h, maxY + 1 - ry))
            let piece = opaque.cropping(to: CGRect(x: rx, y: ry, width: rw, height: rh)) ?? opaque
            return autoLevels(piece) ?? piece
        }

        let crops: Crops
        if quadruped {
            let hs = Int(Float(bh) * 0.62)
            let hx = headOnRight ? maxX + 1 - hs : minX
            crops = Crops(face: crop(hx, minY, hs, hs),
                          fur: crop(minX + bw / 4, minY + bh / 4, bw / 2, bh / 2),
                          lower: crop(minX + bw / 4, maxY - bh / 4, bw / 2, bh / 4),
                          ear: crop(hx + hs / 4, minY, hs / 2, max(2, hs / 4)))
        } else {
            // Cara: parte alta (dejando fuera la punta de las orejas), centrada en la masa de píxeles
            let earCut = hasEars ? Int(Float(bh) * 0.10) : 0
            let hs = min(bw, Int(Float(bh) * 0.48))
            var sumX = 0, n = 0
            for y in minY..<(minY + bh / 2) { for x in minX...maxX where buf.alpha(x, y) > 0 { sumX += x; n += 1 } }
            let cx = n > 0 ? sumX / n : (minX + maxX) / 2
            crops = Crops(face: crop(cx - hs / 2, minY + earCut, hs, hs),
                          fur: crop(minX + bw / 5, minY + bh / 2, bw * 3 / 5, bh / 3),
                          lower: crop(minX + bw / 4, maxY - bh / 5, bw / 2, bh / 5),
                          ear: crop(cx - hs / 2, minY, hs, max(2, earCut + 2)))
        }

        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed &* 31 &+ 5))
        func vary(_ v: Float, _ amount: Float = 0.08) -> Float { v * Float.random(in: (1 - amount)...(1 + amount), using: &rng) }

        let mats = Materials(crops)
        let root = SCNNode()
        var tris = 0
        func add(_ geometry: SCNGeometry, to parent: SCNNode, at position: SCNVector3, pivot: SCNVector3 = SCNVector3(0, 0, 0)) -> SCNNode {
            let node = SCNNode(geometry: geometry)
            node.position = position
            node.pivot = SCNMatrix4MakeTranslation(pivot.x, pivot.y, pivot.z)
            parent.addChildNode(node)
            tris += 12
            return node
        }

        let width: Float, height: Float
        if quadruped {
            let bodyLen = vary(0.95) * min(1.25, max(0.85, aspect / 1.6))
            let bodyH = vary(0.36), bodyD = vary(0.36)
            let legH = vary(0.34), legW: Float = 0.12
            let dir: Float = headOnRight ? 1 : -1

            let body = add(box(bottom: [bodyLen, bodyD], top: [bodyLen * 0.94, bodyD * 0.88], height: bodyH,
                               materials: [mats.fur, mats.furSide, mats.furDark, mats.furSide, mats.furSide, mats.furDark]),
                           to: root, at: SCNVector3(0, legH, 0))
            // Las caras laterales (±z) muestran el cuerpo de la foto
            body.geometry?.materials = [mats.furPhoto, mats.furSide, mats.furPhotoBack, mats.furSide, mats.furSide, mats.furDark]

            let legSpots: [(Float, Float)] = [(0.34, 0.12), (0.34, -0.12), (-0.34, 0.12), (-0.34, -0.12)]
            for (i, spot) in legSpots.enumerated() {
                let lx = spot.0, lz = spot.1
                let leg = add(box(bottom: [legW, legW], top: [legW * 1.15, legW * 1.15], height: legH,
                                  materials: Array(repeating: mats.lower, count: 6)),
                              to: root, at: SCNVector3(lx * bodyLen, legH, lz * bodyD / 0.36),
                              pivot: SCNVector3(0, legH, 0))
                swing(leg, axis: SCNVector3(0, 0, 1), amplitude: 0.28, period: 0.9, phase: i == 0 || i == 3 ? 0 : .pi)
            }

            let hs = vary(0.42, 0.06)
            let neck = SCNNode()
            neck.position = SCNVector3(dir * bodyLen * 0.5, legH + bodyH * 0.75, 0)
            root.addChildNode(neck)
            // Cabeza: la cara de la foto en los lados (perfil) y en el frente
            let head = add(box(bottom: [hs, hs * 0.9], top: [hs * 0.9, hs * 0.8], height: hs * 0.95,
                               materials: [mats.face, mats.furSide, mats.faceMirror, mats.furSide, mats.furSide, mats.furDark]),
                           to: neck, at: SCNVector3(dir * hs * 0.25, 0, 0))
            if !headOnRight { head.geometry?.materials = [mats.faceMirror, mats.furSide, mats.face, mats.furSide, mats.furSide, mats.furDark] }
            swing(neck, axis: SCNVector3(0, 0, 1), amplitude: 0.06, period: 2.4, phase: 0)
            if hasEars {
                for ez: Float in [-1, 1] {
                    _ = add(pyramid(width: hs * 0.32, height: hs * 0.42, depth: hs * 0.12, material: mats.ear),
                            to: head, at: SCNVector3(0, hs * 0.92, ez * hs * 0.26))
                }
            }
            if hasTail {
                let tailRoot = SCNNode()
                tailRoot.position = SCNVector3(-dir * bodyLen * 0.5, legH + bodyH * 0.8, 0)
                tailRoot.eulerAngles.z = dir * 0.9
                root.addChildNode(tailRoot)
                _ = add(box(bottom: [0.08, 0.08], top: [0.05, 0.05], height: vary(0.42),
                            materials: Array(repeating: mats.furSide, count: 6)), to: tailRoot, at: SCNVector3(0, 0, 0))
                swing(tailRoot, axis: SCNVector3(0, 1, 0), amplitude: 0.5, period: 0.7, phase: 0)
            }
            width = bodyLen + hs * 1.2
            height = legH + bodyH * 0.75 + hs * (hasEars ? 1.35 : 0.95)
        } else {
            // Muñeco erguido (como el gatito de la referencia)
            let legH = vary(0.36), legW = vary(0.16)
            let bodyH = vary(0.46), bodyW = vary(0.46) * min(1.25, max(0.85, aspect * 1.25))
            let bodyD = bodyW * 0.7
            for (i, lx) in [Float(-1), Float(1)].enumerated() {
                let leg = add(box(bottom: [legW, legW * 1.15], top: [legW * 0.9, legW], height: legH,
                                  materials: Array(repeating: mats.lower, count: 6)),
                              to: root, at: SCNVector3(lx * bodyW * 0.25, legH, 0),
                              pivot: SCNVector3(0, legH, 0))
                swing(leg, axis: SCNVector3(1, 0, 0), amplitude: 0.12, period: 1.6, phase: Float(i) * .pi)
            }
            _ = add(box(bottom: [bodyW, bodyD], top: [bodyW * 0.8, bodyD * 0.85], height: bodyH,
                        materials: [mats.furPhoto, mats.furSide, mats.furDark, mats.furSide, mats.furSide, mats.furDark]),
                    to: root, at: SCNVector3(0, legH - 0.02, 0))
            // Brazos en diagonal, colgando desde los hombros
            let shoulderY = legH + bodyH * 0.9
            for (i, side) in [Float(-1), Float(1)].enumerated() {
                let shoulder = SCNNode()
                shoulder.position = SCNVector3(side * bodyW * 0.42, shoulderY, 0)
                shoulder.eulerAngles.z = side * 0.5
                root.addChildNode(shoulder)
                _ = add(box(bottom: [0.08, 0.09], top: [0.1, 0.11], height: vary(0.3),
                            materials: Array(repeating: mats.furSide, count: 6)),
                        to: shoulder, at: SCNVector3(0, 0, 0), pivot: SCNVector3(0, vary(0.3), 0))
                swing(shoulder, axis: SCNVector3(1, 0, 0), amplitude: 0.22, period: 1.6, phase: Float(i) * .pi + .pi)
            }
            // Cabeza grande de bloque con la cara de la foto
            let hw = vary(0.66, 0.05) * min(1.15, max(0.9, aspect)), hh = hw * 0.86, hd = hw * 0.72
            let neck = SCNNode()
            neck.position = SCNVector3(0, legH + bodyH - 0.04, 0)
            root.addChildNode(neck)
            let head = add(box(bottom: [hw * 0.92, hd], top: [hw, hd * 0.95], height: hh,
                               materials: [mats.face, mats.furSide, mats.furDark, mats.furSide, mats.furSide, mats.furDark]),
                           to: neck, at: SCNVector3(0, 0, 0))
            swing(neck, axis: SCNVector3(0, 0, 1), amplitude: 0.07, period: 2.6, phase: 0)
            if hasEars {
                for ex: Float in [-1, 1] {
                    let ear = add(pyramid(width: hw * 0.3, height: hh * 0.42, depth: hd * 0.22, material: mats.ear),
                                  to: head, at: SCNVector3(ex * hw * 0.32, hh * 0.97, -hd * 0.05))
                    ear.eulerAngles.z = -ex * 0.22
                }
            }
            if hasTail {
                let tailRoot = SCNNode()
                tailRoot.position = SCNVector3(0, legH + 0.08, -bodyD * 0.45)
                tailRoot.eulerAngles.x = -1.0
                root.addChildNode(tailRoot)
                _ = add(box(bottom: [0.08, 0.08], top: [0.05, 0.05], height: vary(0.4),
                            materials: Array(repeating: mats.furSide, count: 6)), to: tailRoot, at: SCNVector3(0, 0, 0))
                swing(tailRoot, axis: SCNVector3(0, 0, 1), amplitude: 0.45, period: 0.8, phase: 0)
            }
            width = max(bodyW + 0.5, hw)
            height = legH + bodyH - 0.04 + hh * (hasEars ? 1.32 : 1.0)
        }
        return Figure(node: root, width: width, height: height, triangleCount: tris)
    }

    /// Estira el contraste de cada recorte (percentiles 4–96 %) para que los animales oscuros
    /// o muy claros sigan mostrando sus rasgos en la textura low-res.
    private static func autoLevels(_ image: CGImage) -> CGImage? {
        guard var buf = PixelBuffer(exact: image) else { return nil }
        var lum: [Double] = []
        lum.reserveCapacity(buf.width * buf.height)
        for i in stride(from: 0, to: buf.data.count, by: 4) where buf.data[i + 3] > 0 {
            lum.append(0.299 * Double(buf.data[i]) + 0.587 * Double(buf.data[i + 1]) + 0.114 * Double(buf.data[i + 2]))
        }
        guard lum.count > 8 else { return image }
        lum.sort()
        let lo = lum[lum.count * 4 / 100], hi = lum[lum.count * 96 / 100]
        guard hi - lo > 8 else { return image }
        let targetLo = 22.0, targetHi = 238.0
        let gain = (targetHi - targetLo) / (hi - lo)
        for i in stride(from: 0, to: buf.data.count, by: 4) where buf.data[i + 3] > 0 {
            for c in 0..<3 {
                let v = (Double(buf.data[i + c]) - lo) * gain + targetLo
                buf.data[i + c] = UInt8(max(0, min(255, v)))
            }
        }
        return buf.makeCGImage()
    }

    // MARK: - Materiales

    private struct Materials {
        let face, faceMirror, furPhoto, furPhotoBack, fur, furSide, furDark, lower, ear: SCNMaterial

        init(_ c: Crops) {
            face = RetroStage.pixelMaterial(c.face)
            faceMirror = RetroStage.pixelMaterial(c.face)
            faceMirror.diffuse.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(-1, 1, 1), SCNMatrix4MakeTranslation(1, 0, 0))
            faceMirror.diffuse.wrapS = .repeat
            furPhoto = RetroStage.pixelMaterial(c.fur)
            furPhotoBack = RetroStage.pixelMaterial(c.fur)
            furPhotoBack.multiply.contents = UIColor(white: 0.82, alpha: 1)
            fur = RetroStage.pixelMaterial(c.fur)
            furSide = RetroStage.pixelMaterial(c.fur)
            furSide.diffuse.contentsTransform = SCNMatrix4MakeScale(0.5, 0.5, 1) // pelaje "ampliado"
            furSide.diffuse.wrapS = .repeat
            furSide.diffuse.wrapT = .repeat
            furDark = RetroStage.pixelMaterial(c.fur)
            furDark.multiply.contents = UIColor(white: 0.7, alpha: 1)
            lower = RetroStage.pixelMaterial(c.lower)
            ear = RetroStage.pixelMaterial(c.ear)
        }
    }

    // MARK: - Animación idle

    private static func swing(_ node: SCNNode, axis: SCNVector3, amplitude: Float, period: Double, phase: Float) {
        let base = node.eulerAngles
        let action = SCNAction.customAction(duration: period) { n, elapsed in
            let a = amplitude * sin(Float(elapsed / period) * 2 * .pi + phase)
            n.eulerAngles = SCNVector3(base.x + axis.x * a, base.y + axis.y * a, base.z + axis.z * a)
        }
        node.runAction(.repeatForever(action), forKey: "idle")
    }

    // MARK: - Geometría low-poly

    /// Caja (tronco de pirámide) de 12 triángulos con normales planas, base en y = 0.
    /// `bottom`/`top` = (ancho X, fondo Z). Materiales: frente, derecha, detrás, izquierda, arriba, abajo.
    static func box(bottom: SIMD2<Float>, top: SIMD2<Float>, height: Float, materials: [SCNMaterial]) -> SCNGeometry {
        let bx = bottom.x / 2, bz = bottom.y / 2, tx = top.x / 2, tz = top.y / 2, h = height
        func v(_ x: Float, _ y: Float, _ z: Float) -> simd_float3 { simd_float3(x, y, z) }
        var faces: [[simd_float3]] = []
        faces.append([v(-bx, 0, bz), v(bx, 0, bz), v(tx, h, tz), v(-tx, h, tz)])      // frente (+z)
        faces.append([v(bx, 0, bz), v(bx, 0, -bz), v(tx, h, -tz), v(tx, h, tz)])      // derecha (+x)
        faces.append([v(bx, 0, -bz), v(-bx, 0, -bz), v(-tx, h, -tz), v(tx, h, -tz)])  // detrás (−z)
        faces.append([v(-bx, 0, -bz), v(-bx, 0, bz), v(-tx, h, tz), v(-tx, h, -tz)])  // izquierda (−x)
        faces.append([v(-tx, h, tz), v(tx, h, tz), v(tx, h, -tz), v(-tx, h, -tz)])    // arriba
        faces.append([v(-bx, 0, -bz), v(bx, 0, -bz), v(bx, 0, bz), v(-bx, 0, bz)])    // abajo
        let quadUV = [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]
        var positions: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = []
        var elements: [SCNGeometryElement] = []
        for quad in faces {
            let n = simd_normalize(simd_cross(quad[1] - quad[0], quad[2] - quad[0]))
            let start = UInt16(positions.count)
            for (k, p) in quad.enumerated() {
                positions.append(SCNVector3(p.x, p.y, p.z))
                normals.append(SCNVector3(n.x, n.y, n.z))
                uvs.append(quadUV[k])
            }
            elements.append(SCNGeometryElement(indices: [start, start + 1, start + 2, start, start + 2, start + 3],
                                               primitiveType: .triangles))
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions),
                                             SCNGeometrySource(normals: normals),
                                             SCNGeometrySource(textureCoordinates: uvs)],
                                   elements: elements)
        geometry.materials = materials
        return geometry
    }

    /// Pirámide de base rectangular (orejas), base en y = 0.
    static func pyramid(width: Float, height: Float, depth: Float, material: SCNMaterial) -> SCNGeometry {
        let x = width / 2, z = depth / 2
        let apex = simd_float3(0, height, 0)
        let base: [simd_float3] = [simd_float3(-x, 0, z), simd_float3(x, 0, z),
                                   simd_float3(x, 0, -z), simd_float3(-x, 0, -z)]
        var positions: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = []
        var indices: [UInt16] = []
        for i in 0..<4 {
            let a = base[i], b = base[(i + 1) % 4]
            let n = simd_normalize(simd_cross(b - a, apex - a))
            let start = UInt16(positions.count)
            let corners: [(simd_float3, CGPoint)] = [(a, CGPoint(x: 0, y: 1)), (b, CGPoint(x: 1, y: 1)), (apex, CGPoint(x: 0.5, y: 0))]
            for (p, uv) in corners {
                positions.append(SCNVector3(p.x, p.y, p.z))
                normals.append(SCNVector3(n.x, n.y, n.z))
                uvs.append(uv)
            }
            indices += [start, start + 1, start + 2]
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions),
                                             SCNGeometrySource(normals: normals),
                                             SCNGeometrySource(textureCoordinates: uvs)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return geometry
    }
}
