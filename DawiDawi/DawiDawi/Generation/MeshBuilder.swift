import SceneKit
import simd

/// Genera un modelo 3D low-poly "inflando" la silueta del sprite (técnica tipo Monster Mash):
/// la silueta se discretiza en una rejilla gruesa, se calcula la distancia al borde y se
/// levanta una cúpula por delante y por detrás. Resultado: un muñeco poligonal facetado
/// con textura pixelada, como un modelo de PS1/N64.
enum MeshBuilder {
    struct Result {
        let geometry: SCNGeometry
        let width: Float
        let height: Float
        let minY: Float
        let centerX: Float
        let triangleCount: Int
    }

    static func build(sprite: CGImage, grid: Int, seed: Int) -> Result? {
        guard let buf = PixelBuffer(cgImage: sprite) else { return nil }
        let g = max(12, min(48, grid))
        let w = buf.width, h = buf.height

        // 1) Celdas dentro de la silueta
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
                inside[cy * g + cx] = Double(on) / Double(max(1, total)) > 0.38
            }
        }
        guard inside.contains(true) else { return nil }

        // 2) Transformada de distancia (BFS desde el exterior)
        var dist = [Int](repeating: Int.max, count: g * g)
        var queue: [Int] = []
        queue.reserveCapacity(g * g)
        for i in 0..<(g * g) where !inside[i] { dist[i] = 0; queue.append(i) }
        for cy in 0..<g {
            for cx in 0..<g {
                let i = cy * g + cx
                if inside[i] && (cx == 0 || cy == 0 || cx == g - 1 || cy == g - 1) {
                    dist[i] = 1
                    queue.append(i)
                }
            }
        }
        var head = 0
        while head < queue.count {
            let i = queue[head]; head += 1
            let cx = i % g, cy = i / g
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < g, ny < g else { continue }
                let j = ny * g + nx
                if dist[j] > dist[i] + 1 {
                    dist[j] = dist[i] + 1
                    queue.append(j)
                }
            }
        }
        var maxD = 1
        for i in 0..<(g * g) where inside[i] { maxD = max(maxD, dist[i]) }

        func isInside(_ cx: Int, _ cy: Int) -> Bool {
            guard cx >= 0, cy >= 0, cx < g, cy < g else { return false }
            return inside[cy * g + cx]
        }

        // 3) Altura de cada vértice de la rejilla
        let gf = Float(g)
        let hMax = 0.9 * Float(maxD) / gf
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed &* 7919 &+ 17))
        var front = [simd_float3](repeating: .zero, count: (g + 1) * (g + 1))
        var back = [simd_float3](repeating: .zero, count: (g + 1) * (g + 1))
        for vy in 0...g {
            for vx in 0...g {
                let cells = [(vx - 1, vy - 1), (vx, vy - 1), (vx - 1, vy), (vx, vy)]
                let boundary = cells.contains { !isInside($0.0, $0.1) }
                var z: Float = 0
                var jx: Float = 0, jy: Float = 0
                if !boundary {
                    let d = cells.map { dist[$0.1 * g + $0.0] }.min() ?? 1
                    let t = min(1, max(0, (Float(d) - 0.35) / Float(maxD)))
                    z = hMax * sqrt(max(0, 1 - (1 - t) * (1 - t)))
                    // Jitter: facetas irregulares, como modelado a mano en los 90
                    z *= Float.random(in: 0.9...1.08, using: &rng)
                    jx = Float.random(in: -0.18...0.18, using: &rng) / gf
                    jy = Float.random(in: -0.18...0.18, using: &rng) / gf
                }
                let x = Float(vx) / gf - 0.5 + jx
                let y = 1 - Float(vy) / gf + jy
                let k = vy * (g + 1) + vx
                front[k] = simd_float3(x, y, z)
                back[k] = simd_float3(x, y, -z * 0.82)
            }
        }

        // 4) Triángulos con normales planas (look facetado low-poly)
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var frontIdx: [UInt32] = []
        var backIdx: [UInt32] = []
        var minX: Float = .greatestFiniteMagnitude, maxX: Float = -.greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude, maxY: Float = -.greatestFiniteMagnitude

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
            for cx in 0..<g where inside[cy * g + cx] {
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

        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions),
                                             SCNGeometrySource(normals: normals),
                                             SCNGeometrySource(textureCoordinates: uvs)],
                                   elements: [SCNGeometryElement(indices: frontIdx, primitiveType: .triangles),
                                              SCNGeometryElement(indices: backIdx, primitiveType: .triangles)])
        return Result(geometry: geometry,
                      width: maxX - minX,
                      height: maxY - minY,
                      minY: minY,
                      centerX: (minX + maxX) / 2,
                      triangleCount: (frontIdx.count + backIdx.count) / 3)
    }
}
