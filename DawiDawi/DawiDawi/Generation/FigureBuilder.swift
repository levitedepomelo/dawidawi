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

    /// Recortes de textura sacados de la foto del sujeto.
    private struct Crops {
        let face: CGImage
        let headFur: CGImage
        let chest: CGImage
        let fur: CGImage
        let lower: CGImage
        let ear: CGImage
    }

    /// Fuente de texturas: el recorte del sujeto a buena resolución (sin tramado ni contorno), con el
    /// fondo transparente rellenado con los colores del propio animal para que ningún recorte
    /// muestre zonas negras.
    private struct TextureSource {
        let image: CGImage
        let alpha: PixelBuffer
        let minX: Int, minY: Int, maxX: Int, maxY: Int
        var bw: Int { maxX - minX + 1 }
        var bh: Int { maxY - minY + 1 }

        init?(_ source: CGImage) {
            guard let original = PixelBuffer(exact: source) else { return nil }
            alpha = original
            let w = original.width, h = original.height
            var x0 = w, y0 = h, x1 = -1, y1 = -1
            for y in 0..<h { for x in 0..<w where original.data[(y * w + x) * 4 + 3] > 60 {
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
            } }
            guard x1 > x0 + 3, y1 > y0 + 3 else { return nil }
            minX = x0; minY = y0; maxX = x1; maxY = y1

            // Relleno: varias pasadas de dilatación y, lo que quede, con el color medio del sujeto
            var buf = original
            var sum = [0, 0, 0], count = 0
            for i in stride(from: 0, to: buf.data.count, by: 4) {
                if buf.data[i + 3] > 60 {
                    buf.data[i + 3] = 255
                    sum[0] += Int(buf.data[i]); sum[1] += Int(buf.data[i + 1]); sum[2] += Int(buf.data[i + 2]); count += 1
                } else {
                    buf.data[i + 3] = 0
                }
            }
            for _ in 0..<12 {
                let src = buf
                var changed = false
                for y in 0..<h { for x in 0..<w where src.data[(y * w + x) * 4 + 3] == 0 {
                    var r = 0, g = 0, b = 0, n = 0
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                        let j = (ny * w + nx) * 4
                        if src.data[j + 3] > 0 { r += Int(src.data[j]); g += Int(src.data[j + 1]); b += Int(src.data[j + 2]); n += 1 }
                    }
                    if n > 0 {
                        let i = (y * w + x) * 4
                        buf.data[i] = UInt8(r / n); buf.data[i + 1] = UInt8(g / n); buf.data[i + 2] = UInt8(b / n)
                        buf.data[i + 3] = 255
                        changed = true
                    }
                } }
                if !changed { break }
            }
            let avg = count > 0 ? sum.map { UInt8($0 / count) } : [128, 128, 128]
            for i in stride(from: 0, to: buf.data.count, by: 4) where buf.data[i + 3] == 0 {
                buf.data[i] = avg[0]; buf.data[i + 1] = avg[1]; buf.data[i + 2] = avg[2]; buf.data[i + 3] = 255
            }
            guard let filled = buf.makeCGImage() else { return nil }
            image = filled
        }

        /// Centro X (en píxeles) de la masa del sujeto entre dos fracciones de altura.
        func massCenterX(from f0: Double, to f1: Double) -> Int {
            let w = alpha.width
            var sum = 0, n = 0
            let ya = minY + Int(Double(bh) * f0), yb = min(maxY, minY + Int(Double(bh) * f1))
            if ya <= yb {
                for y in ya...yb { for x in minX...maxX where alpha.data[(y * w + x) * 4 + 3] > 60 { sum += x; n += 1 } }
            }
            return n > 0 ? sum / n : (minX + maxX) / 2
        }

        /// Cabeza a partir del perfil de anchura de la silueta, fila a fila:
        /// las orejas son dos manchas separadas arriba; la cara empieza donde se unen y termina en el
        /// cuello (la fila más estrecha antes de que el cuerpo vuelva a ensancharse).
        func headRect() -> CGRect {
            let w = alpha.width
            var left = [Int](), right = [Int](), runs = [Int]()
            for y in minY...maxY {
                var l = -1, r = -1, n = 0, inside = false
                for x in minX...maxX {
                    let on = alpha.data[(y * w + x) * 4 + 3] > 60
                    if on { if l < 0 { l = x }; r = x; if !inside { n += 1 } }
                    inside = on
                }
                left.append(l); right.append(r); runs.append(n)
            }
            let rows = left.count
            func width(_ i: Int) -> Int { left[i] < 0 ? 0 : right[i] - left[i] + 1 }
            // Base de las orejas: primera fila con una sola mancha ancha tras las puntas
            var earBase = 0
            if let firstSplit = runs.prefix(rows / 3).firstIndex(where: { $0 >= 2 }),
               let joined = runs[firstSplit..<min(rows, rows / 2)].firstIndex(where: { $0 == 1 }) {
                earBase = joined
            }
            // Cuello: anchura mínima (suavizada) entre el 12 % y el 55 % de la altura, por debajo de la cara
            let start = min(rows - 1, earBase + max(2, rows / 10)), end = min(rows - 1, earBase + rows * 45 / 100)
            var neck = min(rows - 1, earBase + rows / 3)
            if start < end {
                var best = Int.max
                for i in start...end {
                    let a = max(0, i - 1), b = min(rows - 1, i + 1)
                    let smooth = (width(a) + width(i) + width(b)) / 3
                    if smooth < best { best = smooth; neck = i }
                }
                // Si no hay estrechamiento claro, el cuello está a ~1/3 de la altura
                let headWidth = (earBase..<start).map(width).max() ?? 0
                if best > headWidth * 9 / 10 { neck = min(rows - 1, earBase + rows * 30 / 100) }
            }
            let x0 = (earBase...neck).compactMap { left[$0] >= 0 ? left[$0] : nil }.min() ?? minX
            let x1 = (earBase...neck).map { right[$0] }.max() ?? maxX
            let faceW = Double(x1 - x0 + 1), faceH = Double(neck - earBase + 1)
            let side = max(4, min(max(faceW, faceH), Double(bw)))
            let cx = Double(x0 + x1) / 2, top = Double(minY + earBase)
            return CGRect(x: cx - side / 2, y: top - side * 0.04, width: side, height: side)
        }

        /// Recorte en píxeles → textura de 64 px como máximo, con niveles ajustados.
        func crop(_ rect: CGRect) -> CGImage {
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            var r = rect.integral.intersection(bounds)
            if r.width < 2 || r.height < 2 { r = CGRect(x: minX, y: minY, width: bw, height: bh) }
            let piece = image.cropping(to: r) ?? image
            let scale = min(1, Double(GraphicsStyle.textureSize) / Double(max(piece.width, piece.height)))
            let tw = max(2, Int(Double(piece.width) * scale)), th = max(2, Int(Double(piece.height) * scale))
            guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: tw * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return piece }
            ctx.interpolationQuality = .high
            ctx.draw(piece, in: CGRect(x: 0, y: 0, width: tw, height: th))
            guard let small = ctx.makeImage() else { return piece }
            return FigureBuilder.autoLevels(small) ?? small
        }

        /// Recorte en fracciones de la caja del sujeto.
        func crop(fx: Double, fy: Double, fw: Double, fh: Double) -> CGImage {
            crop(CGRect(x: Double(minX) + fx * Double(bw), y: Double(minY) + fy * Double(bh),
                        width: fw * Double(bw), height: fh * Double(bh)))
        }
    }

    /// - Parameters:
    ///   - sprite: textura pixelada con transparencia (para analizar la forma).
    ///   - cutout: recorte del sujeto a buena resolución (para las texturas). Si falta, se usa el sprite.
    ///   - face: rectángulo normalizado de la cara dentro de `cutout` (Vision), si se encontró.
    static func build(sprite: CGImage, cutout: CGImage? = nil, face: CGRect? = nil, seed: Int) -> Figure? {
        guard let buf = PixelBuffer(cgImage: sprite) else { return nil }
        // Caja del sujeto en el sprite (forma)
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

        // Lado de la cabeza en siluetas alargadas: el extremo cuyo punto más alto está más arriba
        func topRow(fromX: Int, toX: Int) -> Int {
            for y in minY...maxY { for x in fromX...toX where buf.alpha(x, y) > 0 { return y } }
            return maxY
        }
        let third = max(1, bw / 3)
        let headOnRight = topRow(fromX: maxX - third, toX: maxX) < topRow(fromX: minX, toX: minX + third)

        guard let tex = TextureSource(cutout ?? sprite) ?? TextureSource(sprite) else { return nil }
        let tw = Double(tex.bw), th = Double(tex.bh)
        // Cara detectada por Vision (en píxeles del recorte), si la hay
        let faceRect: CGRect? = (cutout != nil ? face : nil).map {
            CGRect(x: $0.minX * Double(tex.image.width), y: $0.minY * Double(tex.image.height),
                   width: $0.width * Double(tex.image.width), height: $0.height * Double(tex.image.height))
        }

        let crops: Crops
        if quadruped {
            let s = min(th * 0.6, tw * 0.45)
            let hx = headOnRight ? Double(tex.maxX) - s : Double(tex.minX)
            let head = faceRect ?? CGRect(x: hx, y: Double(tex.minY), width: s, height: s)
            crops = Crops(face: tex.crop(head),
                          headFur: tex.crop(CGRect(x: head.minX, y: head.minY, width: head.width, height: head.height * 0.3)),
                          chest: tex.crop(fx: 0.3, fy: 0.3, fw: 0.4, fh: 0.4),
                          fur: tex.crop(fx: 0.35, fy: 0.25, fw: 0.3, fh: 0.25),
                          lower: tex.crop(fx: 0.25, fy: 0.75, fw: 0.5, fh: 0.25),
                          ear: tex.crop(CGRect(x: head.minX, y: Double(tex.minY), width: head.width, height: max(4, head.minY - Double(tex.minY) + head.height * 0.2))))
        } else {
            // Muñeco erguido: cara en la parte alta, centrada en la masa del sujeto
            let head = faceRect ?? tex.headRect()
            let bodyCX = Double(tex.massCenterX(from: 0.45, to: 0.8))
            crops = Crops(face: tex.crop(head),
                          headFur: tex.crop(CGRect(x: head.minX + head.width * 0.1, y: head.minY,
                                                   width: head.width * 0.8, height: head.height * 0.28)),
                          chest: tex.crop(CGRect(x: bodyCX - tw * 0.22, y: Double(tex.minY) + th * 0.45,
                                                 width: tw * 0.44, height: th * 0.3)),
                          fur: tex.crop(CGRect(x: bodyCX - tw * 0.45, y: Double(tex.minY) + th * 0.5,
                                               width: tw * 0.25, height: th * 0.25)),
                          lower: tex.crop(CGRect(x: bodyCX - tw * 0.25, y: Double(tex.maxY) - th * 0.18,
                                                 width: tw * 0.5, height: th * 0.18)),
                          ear: tex.crop(CGRect(x: head.minX, y: Double(tex.minY),
                                               width: head.width, height: max(4, head.minY - Double(tex.minY) + head.height * 0.15))))
        }

        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed &* 31 &+ 5))
        func vary(_ v: Float, _ amount: Float = 0.08) -> Float { v * Float.random(in: (1 - amount)...(1 + amount), using: &rng) }

        let mats = Materials(crops)
        let root = SCNNode()
        var tris = 0
        func add(_ geometry: SCNGeometry, to parent: SCNNode, at position: SCNVector3, pivot: SCNVector3 = SCNVector3(0, 0, 0)) -> SCNNode {
            let node = SCNNode(geometry: geometry)
            node.position = position
            // Las primitivas de SceneKit (HD) están centradas; las cajas low-poly apoyan en y = 0
            node.pivot = SCNMatrix4MakeTranslation(pivot.x, pivot.y - centerLift(geometry), pivot.z)
            parent.addChildNode(node)
            tris += GraphicsStyle.isRetro ? 12 : 60
            return node
        }

        let width: Float, height: Float
        if quadruped {
            let bodyLen = vary(0.95) * min(1.25, max(0.85, aspect / 1.6))
            let bodyH = vary(0.36), bodyD = vary(0.36)
            let legH = vary(0.34), legW: Float = 0.12
            let dir: Float = headOnRight ? 1 : -1

            let body = add(box(bottom: [bodyLen, bodyD], top: [bodyLen * 0.94, bodyD * 0.88], height: bodyH,
                               materials: [mats.furPhoto, mats.furSide, mats.furDark, mats.furSide, mats.furSide, mats.furDark]),
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
                               materials: [mats.face, mats.headFur, mats.faceMirror, mats.headFur, mats.headFur, mats.headFurDark]),
                           to: neck, at: SCNVector3(dir * hs * 0.25, 0, 0))
            if !headOnRight { head.geometry?.materials = [mats.faceMirror, mats.headFur, mats.face, mats.headFur, mats.headFur, mats.headFurDark] }
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
                               materials: [mats.face, mats.headFur, mats.headFurDark, mats.headFur, mats.headFur, mats.headFurDark]),
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
    static func autoLevels(_ image: CGImage) -> CGImage? {
        guard var buf = PixelBuffer(exact: image) else { return nil }
        var lum: [Double] = []
        lum.reserveCapacity(buf.width * buf.height)
        for i in stride(from: 0, to: buf.data.count, by: 4) where buf.data[i + 3] > 0 {
            lum.append(0.299 * Double(buf.data[i]) + 0.587 * Double(buf.data[i + 1]) + 0.114 * Double(buf.data[i + 2]))
        }
        guard lum.count > 8 else { return image }
        lum.sort()
        let lo = lum[lum.count * 2 / 100], hi = lum[lum.count * 98 / 100]
        guard hi - lo > 8, hi - lo < 200 else { return image }
        let targetLo = 14.0, targetHi = 246.0
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
        let face, faceMirror, headFur, headFurDark, furPhoto, furPhotoBack, furSide, furDark, lower, ear: SCNMaterial

        init(_ c: Crops) {
            face = RetroStage.pixelMaterial(c.face)
            faceMirror = RetroStage.pixelMaterial(c.face)
            faceMirror.diffuse.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(-1, 1, 1), SCNMatrix4MakeTranslation(1, 0, 0))
            faceMirror.diffuse.wrapS = .repeat
            headFur = RetroStage.pixelMaterial(c.headFur)
            headFurDark = RetroStage.pixelMaterial(c.headFur)
            headFurDark.multiply.contents = UIColor(white: 0.78, alpha: 1)
            furPhoto = RetroStage.pixelMaterial(c.chest)       // frente del cuerpo (pecho)
            furPhotoBack = RetroStage.pixelMaterial(c.fur)
            furPhotoBack.multiply.contents = UIColor(white: 0.85, alpha: 1)
            furSide = RetroStage.pixelMaterial(c.fur)          // laterales, brazos y cola
            furDark = RetroStage.pixelMaterial(c.fur)
            furDark.multiply.contents = UIColor(white: 0.75, alpha: 1)
            lower = RetroStage.pixelMaterial(c.lower)
            ear = RetroStage.pixelMaterial(c.ear)
        }
    }

    // MARK: - Animación idle

    static func swing(_ node: SCNNode, axis: SCNVector3, amplitude: Float, period: Double, phase: Float) {
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
        if !GraphicsStyle.isRetro {
            // HD: bloque con bordes redondeados, o cápsula para las piezas finas (patas, brazos, cola)
            let w = CGFloat(max(bottom.x, top.x)), d = CGFloat(max(bottom.y, top.y)), h = CGFloat(height)
            let thin = min(w, d)
            if thin < 0.14, h > thin * 1.3 {
                let capsule = SCNCapsule(capRadius: thin / 2, height: h)
                capsule.radialSegmentCount = 14
                capsule.capSegmentCount = 6
                capsule.heightSegmentCount = 1
                capsule.materials = [materials.first ?? SCNMaterial()]
                return capsule
            }
            let rounded = SCNBox(width: w, height: h, length: d, chamferRadius: min(w, min(h, d)) * 0.2)
            rounded.chamferSegmentCount = 3
            rounded.materials = materials
            return rounded
        }
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

    /// Desplazamiento para apoyar en y = 0 una primitiva centrada de SceneKit.
    static func centerLift(_ geometry: SCNGeometry) -> Float {
        if let b = geometry as? SCNBox { return Float(b.height) / 2 }
        if let c = geometry as? SCNCapsule { return Float(c.height) / 2 }
        return 0
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
