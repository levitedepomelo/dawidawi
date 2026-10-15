import SceneKit
import simd

/// Genera automáticamente un modelo 3D low-poly POR PIEZAS a partir de la silueta del animal:
///
///  1. La silueta del sprite se discretiza en una rejilla y se calcula la distancia al borde.
///  2. Una apertura morfológica separa las masas gruesas (cuerpo, cabeza) de los apéndices
///     finos (patas, cola, orejas, alas…). No se reconoce qué es: solo se mira la forma.
///  3. Cada pieza se "infla" con su propio perfil circular → volúmenes redondeados
///     (las patas son cilindros, el cuerpo un volumen grueso) con normales planas.
///  4. Las patas que tocan el suelo se duplican delante/detrás para que el modelo se sostenga
///     en 3D, y cada apéndice tiene un punto de anclaje para animarlo (andar, menear la cola).
///  5. Todas las piezas usan la textura sacada de la propia foto (proyección frontal).
enum MeshBuilder {
    enum PartKind { case body, leg, top, side }

    struct Part {
        let geometry: SCNGeometry
        let kind: PartKind
        /// Punto de unión con el cuerpo (en coordenadas del modelo): pivote de su animación.
        let anchor: SCNVector3
        /// Desplazamiento en profundidad (patas delanteras / traseras).
        let zOffset: Float
        let phase: Float
        let triangleCount: Int
    }

    struct Result {
        let parts: [Part]
        let width: Float
        let height: Float
        let minY: Float
        let centerX: Float
        var triangleCount: Int { parts.reduce(0) { $0 + $1.triangleCount } }
    }

    static func build(sprite: CGImage, grid: Int, seed: Int) -> Result? {
        guard let buf = PixelBuffer(cgImage: sprite) else { return nil }
        let g = max(24, min(52, grid + 10))
        let w = buf.width, h = buf.height

        // 1) Celdas dentro de la silueta (solo la mancha principal)
        var inside = [Bool](repeating: false, count: g * g)
        for cy in 0..<g {
            for cx in 0..<g {
                let x0 = cx * w / g, x1 = max(x0 + 1, (cx + 1) * w / g)
                let y0 = cy * h / g, y1 = max(y0 + 1, (cy + 1) * h / g)
                var on = 0, total = 0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        total += 1
                        if buf.alpha(x, y) > 0 { on += 1 }
                    }
                }
                inside[cy * g + cx] = Double(on) / Double(max(1, total)) > 0.4
            }
        }
        inside = largestComponent(inside, g)
        guard inside.filter({ $0 }).count >= 6 else { return nil }

        // 2) Distancia (chaflán ≈ euclídea) de cada celda al exterior, en celdas
        let dist = distanceField(inside, g)
        let maxD = dist.max() ?? 1

        // 3) Apertura morfológica: masas gruesas vs. apéndices
        let radius = max(1.6, 0.45 * maxD)
        let core = opening(inside, dist, radius: radius, g)
        var bodyMask = core
        var appendages: [[Int]] = []
        for comp in components(zip(inside, core).map { $0 && !$1 }, g) {
            if comp.count >= 3 { appendages.append(comp) } else { for i in comp { bodyMask[i] = true } }
        }
        if bodyMask.filter({ $0 }).count < 6 {
            // Forma fina sin masa central (serpiente, pájaro de perfil…): una sola pieza
            bodyMask = inside
            appendages = []
        }

        // Medidas globales de la silueta
        var minRow = g, maxRow = 0
        for i in 0..<(g * g) where inside[i] { minRow = min(minRow, i / g); maxRow = max(maxRow, i / g) }
        var bodyRows: [Int] = []
        for i in 0..<(g * g) where bodyMask[i] { bodyRows.append(i / g) }
        let bodyCenterRow = Float(bodyRows.reduce(0, +)) / Float(max(1, bodyRows.count))
        let bodyRadius = bodyMask.indices.filter { bodyMask[$0] }.map { dist[$0] }.max() ?? 1

        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed &* 7919 &+ 17))
        var builder = Builder(g: g, dist: dist)
        var parts: [Part] = []

        // Cuerpo (con 1 celda de solape hacia los apéndices para que no queden grietas)
        let bodyRegion = grow(bodyMask, into: inside, steps: 1, g)
        if let geo = builder.inflate(region: bodyRegion, radius: bodyRadius, depth: 1.0, rng: &rng) {
            parts.append(Part(geometry: geo.0, kind: .body, anchor: SCNVector3(0, 0, 0), zOffset: 0,
                              phase: 0, triangleCount: geo.1))
        }

        // Apéndices
        for comp in appendages {
            var mask = [Bool](repeating: false, count: g * g)
            for i in comp { mask[i] = true }
            let partRadius = max(1, comp.map { dist[$0] }.max() ?? 1)
            // Raíz metida dentro del cuerpo para que la pieza "salga" de él
            let region = grow(mask, into: inside, steps: 3, g)

            // Anclaje: celdas del apéndice que tocan el cuerpo
            var ax: Float = 0, ay: Float = 0, an: Float = 0
            var sumRow: Float = 0, lowest = 0
            for i in comp {
                let x = i % g, y = i / g
                sumRow += Float(y); lowest = max(lowest, y)
                var touches = false
                for (dx, dy) in neighbours4 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < g, ny < g else { continue }
                    if bodyMask[ny * g + nx] { touches = true; break }
                }
                if touches { ax += Float(x); ay += Float(y); an += 1 }
            }
            if an == 0 {
                for i in comp { ax += Float(i % g); ay += Float(i / g) }
                an = Float(comp.count)
            }
            let anchorX: Float = (ax / an + 0.5) / Float(g) - 0.5
            let anchorY: Float = 1 - (ay / an + 0.5) / Float(g)
            let anchor = SCNVector3(anchorX, anchorY, 0)
            let centerRow = sumRow / Float(comp.count)

            let kind: PartKind
            if lowest >= maxRow - 1 && centerRow > bodyCenterRow {
                kind = .leg
            } else if centerRow < bodyCenterRow && ay / an <= Float(minRow) + Float(maxRow - minRow) * 0.45 {
                kind = .top
            } else {
                kind = .side
            }

            guard let geo = builder.inflate(region: region, radius: partRadius, depth: 1.0, rng: &rng) else { continue }
            let phase = Float.random(in: 0...(2 * .pi), using: &rng)
            if kind == .leg {
                // Pata visible en la foto → par delante/detrás del cuerpo
                let offset = 0.42 * bodyRadius / Float(g)
                parts.append(Part(geometry: geo.0, kind: .leg, anchor: anchor, zOffset: offset,
                                  phase: phase, triangleCount: geo.1))
                parts.append(Part(geometry: geo.0, kind: .leg, anchor: anchor, zOffset: -offset,
                                  phase: phase + .pi, triangleCount: geo.1))
            } else {
                parts.append(Part(geometry: geo.0, kind: kind, anchor: anchor, zOffset: 0,
                                  phase: phase, triangleCount: geo.1))
            }
        }

        guard !parts.isEmpty, builder.maxX > builder.minX else { return nil }
        return Result(parts: parts,
                      width: builder.maxX - builder.minX,
                      height: builder.maxY - builder.minY,
                      minY: builder.minY,
                      centerX: (builder.minX + builder.maxX) / 2)
    }

    // MARK: - Malla de una pieza

    private struct Builder {
        let g: Int
        let dist: [Float]
        var minX: Float = .greatestFiniteMagnitude, maxX: Float = -.greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude, maxY: Float = -.greatestFiniteMagnitude

        init(g: Int, dist: [Float]) { self.g = g; self.dist = dist }

        /// Infla la región con un perfil circular de radio `radius` (celdas) y emite triángulos
        /// facetados por delante y por detrás. Devuelve la geometría y su número de triángulos.
        mutating func inflate(region: [Bool], radius: Float, depth: Float,
                              rng: inout SeededGenerator) -> (SCNGeometry, Int)? {
            let gf = Float(g)
            func isIn(_ cx: Int, _ cy: Int) -> Bool {
                guard cx >= 0, cy >= 0, cx < g, cy < g else { return false }
                return region[cy * g + cx]
            }
            var front = [simd_float3](repeating: .zero, count: (g + 1) * (g + 1))
            var back = front
            for vy in 0...g {
                for vx in 0...g {
                    let cells = [(vx - 1, vy - 1), (vx, vy - 1), (vx - 1, vy), (vx, vy)]
                    let boundary = cells.contains { !isIn($0.0, $0.1) }
                    var z: Float = 0, jx: Float = 0, jy: Float = 0
                    if !boundary {
                        let d = cells.map { dist[$0.1 * g + $0.0] }.min() ?? 1
                        let t = min(1, max(0, d / max(radius, 1)))
                        let profile: Float = sqrt(max(0, 1 - (1 - t) * (1 - t)))
                        z = depth * max(radius, 1) / gf * profile
                        // Jitter: facetas irregulares, como modelado a mano en los 90
                        z *= Float.random(in: 0.9...1.08, using: &rng)
                        jx = Float.random(in: -0.16...0.16, using: &rng) / gf
                        jy = Float.random(in: -0.16...0.16, using: &rng) / gf
                    }
                    let x = Float(vx) / gf - 0.5 + jx
                    let y = 1 - Float(vy) / gf + jy
                    let k = vy * (g + 1) + vx
                    front[k] = simd_float3(x, y, z)
                    back[k] = simd_float3(x, y, -z * 0.85)
                }
            }

            var positions: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var uvs: [CGPoint] = []
            var frontIdx: [UInt32] = []
            var backIdx: [UInt32] = []

            func emit(_ a: (Int, Int), _ b: (Int, Int), _ c: (Int, Int), isFront: Bool) {
                let verts = isFront ? front : back
                var ids = [a, b, c]
                var p = ids.map { verts[$0.1 * (g + 1) + $0.0] }
                var n = simd_cross(p[1] - p[0], p[2] - p[0])
                if (isFront && n.z < 0) || (!isFront && n.z > 0) {
                    ids.swapAt(1, 2); p.swapAt(1, 2); n = -n
                }
                let len = simd_length(n)
                let nn = len > 0 ? n / len : simd_float3(0, 0, isFront ? 1 : -1)
                for (k, v) in p.enumerated() {
                    let index = UInt32(positions.count)
                    positions.append(SCNVector3(v.x, v.y, v.z))
                    normals.append(SCNVector3(nn.x, nn.y, nn.z))
                    uvs.append(CGPoint(x: CGFloat(ids[k].0) / CGFloat(g), y: CGFloat(ids[k].1) / CGFloat(g)))
                    if isFront { frontIdx.append(index) } else { backIdx.append(index) }
                    minX = min(minX, v.x); maxX = max(maxX, v.x)
                    minY = min(minY, v.y); maxY = max(maxY, v.y)
                }
            }

            for cy in 0..<g {
                for cx in 0..<g where region[cy * g + cx] {
                    let v00 = (cx, cy), v10 = (cx + 1, cy), v01 = (cx, cy + 1), v11 = (cx + 1, cy + 1)
                    for isFront in [true, false] {
                        if (cx + cy) % 2 == 0 {
                            emit(v00, v10, v11, isFront: isFront)
                            emit(v00, v11, v01, isFront: isFront)
                        } else {
                            emit(v00, v10, v01, isFront: isFront)
                            emit(v10, v11, v01, isFront: isFront)
                        }
                    }
                }
            }
            guard !frontIdx.isEmpty else { return nil }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions),
                                                 SCNGeometrySource(normals: normals),
                                                 SCNGeometrySource(textureCoordinates: uvs)],
                                       elements: [SCNGeometryElement(indices: frontIdx, primitiveType: .triangles),
                                                  SCNGeometryElement(indices: backIdx, primitiveType: .triangles)])
            return (geometry, (frontIdx.count + backIdx.count) / 3)
        }
    }

    // MARK: - Morfología sobre la rejilla

    private static let neighbours4 = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    static func components(_ mask: [Bool], _ g: Int) -> [[Int]] {
        var seen = [Bool](repeating: false, count: g * g)
        var result: [[Int]] = []
        for start in 0..<(g * g) where mask[start] && !seen[start] {
            var comp: [Int] = []
            var stack = [start]
            seen[start] = true
            while let i = stack.popLast() {
                comp.append(i)
                let x = i % g, y = i / g
                for (dx, dy) in neighbours4 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < g, ny < g else { continue }
                    let j = ny * g + nx
                    if mask[j] && !seen[j] { seen[j] = true; stack.append(j) }
                }
            }
            result.append(comp)
        }
        return result
    }

    private static func largestComponent(_ mask: [Bool], _ g: Int) -> [Bool] {
        guard let biggest = components(mask, g).max(by: { $0.count < $1.count }) else { return mask }
        var out = [Bool](repeating: false, count: g * g)
        for i in biggest { out[i] = true }
        return out
    }

    /// Transformada de distancia por chaflán (1, √2) en dos pasadas. El exterior de la rejilla cuenta como fuera.
    static func distanceField(_ inside: [Bool], _ g: Int) -> [Float] {
        let big: Float = 1e6
        var d = inside.map { $0 ? big : 0 }
        func at(_ x: Int, _ y: Int) -> Float {
            guard x >= 0, y >= 0, x < g, y < g else { return 0 }
            return d[y * g + x]
        }
        let diag: Float = 1.4142
        for y in 0..<g {
            for x in 0..<g where inside[y * g + x] {
                let a: Float = min(at(x - 1, y), at(x, y - 1)) + 1
                let b: Float = min(at(x - 1, y - 1), at(x + 1, y - 1)) + diag
                d[y * g + x] = min(d[y * g + x], min(a, b))
            }
        }
        for y in stride(from: g - 1, through: 0, by: -1) {
            for x in stride(from: g - 1, through: 0, by: -1) where inside[y * g + x] {
                let a: Float = min(at(x + 1, y), at(x, y + 1)) + 1
                let b: Float = min(at(x + 1, y + 1), at(x - 1, y + 1)) + diag
                d[y * g + x] = min(d[y * g + x], min(a, b))
            }
        }
        return d
    }

    /// Apertura con un disco de `radius`: lo que sobrevive son las masas más gruesas que el disco.
    private static func opening(_ inside: [Bool], _ dist: [Float], radius: Float, _ g: Int) -> [Bool] {
        let r = Int(radius.rounded(.up))
        var out = [Bool](repeating: false, count: g * g)
        for i in 0..<(g * g) where inside[i] && dist[i] > radius {
            let x = i % g, y = i / g
            for yy in max(0, y - r)...min(g - 1, y + r) {
                for xx in max(0, x - r)...min(g - 1, x + r) {
                    let dx = Float(xx - x), dy = Float(yy - y)
                    let d2: Float = dx * dx + dy * dy
                    if d2 <= radius * radius && inside[yy * g + xx] { out[yy * g + xx] = true }
                }
            }
        }
        return out
    }

    /// Crece la máscara `steps` celdas dentro de `limit`.
    private static func grow(_ mask: [Bool], into limit: [Bool], steps: Int, _ g: Int) -> [Bool] {
        var current = mask
        for _ in 0..<steps {
            var next = current
            for i in 0..<(g * g) where !current[i] && limit[i] {
                let x = i % g, y = i / g
                for (dx, dy) in neighbours4 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < g, ny < g else { continue }
                    if current[ny * g + nx] { next[i] = true; break }
                }
            }
            current = next
        }
        return current
    }
}
