import CoreGraphics
import UIKit

/// Recorte figura/fondo sin aprendizaje automático, para cuando Vision no está disponible
/// (simulador, iPhones sin soporte o fotos donde no detecta sujeto).
/// Modela los colores del fondo a partir del borde de la foto, inunda desde fuera todo lo
/// parecido al fondo y se queda con la mancha principal cerca del centro. No reconoce nada.
enum ColorSegmenter {
    private struct RGB { var r: Float; var g: Float; var b: Float }

    static func cutout(_ cg: CGImage, workSize: Int = 256) -> CGImage? {
        let scale = Float(workSize) / Float(max(cg.width, cg.height))
        let w = max(16, Int(Float(cg.width) * scale)), h = max(16, Int(Float(cg.height) * scale))
        guard let pixels = rgba(cg, width: w, height: h) else { return nil }
        let n = w * h
        var px = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: n)
        for i in 0..<n {
            px[i] = RGB(r: Float(pixels[i * 4]), g: Float(pixels[i * 4 + 1]), b: Float(pixels[i * 4 + 2]))
        }

        // 1) Modelo de fondo: k-medias (k = 6) sobre el anillo exterior de la imagen.
        let ring = max(2, min(w, h) / 22)
        var border: [RGB] = []
        for y in 0..<h {
            for x in 0..<w where x < ring || y < ring || x >= w - ring || y >= h - ring {
                border.append(px[y * w + x])
            }
        }
        let centers = kMeans(border, k: 6)

        // 2) Distancia de cada píxel al color de fondo más cercano (suavizada 3×3).
        var dist = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var best = Float.greatestFiniteMagnitude
            for c in centers { best = min(best, distance(px[i], c)) }
            dist[i] = best
        }
        dist = blur(dist, w, h)

        // 3) Umbral adaptativo (Otsu) con un poco de preferencia por el centro del encuadre.
        let threshold = max(18, otsu(dist))
        var isBackground = [Bool](repeating: false, count: n)
        let cx = Float(w) / 2, cy = Float(h) / 2
        var similar = [Bool](repeating: false, count: n)
        for y in 0..<h {
            for x in 0..<w {
                let dx = (Float(x) - cx) / cx, dy = (Float(y) - cy) / cy
                let edgeBias = 1 + 0.35 * min(1, (dx * dx + dy * dy) / 1.4)
                similar[y * w + x] = dist[y * w + x] < threshold * edgeBias
            }
        }

        // 4) Inundación desde el borde a través de píxeles parecidos al fondo.
        var queue: [Int] = []
        queue.reserveCapacity(n)
        for y in 0..<h {
            for x in 0..<w where (x == 0 || y == 0 || x == w - 1 || y == h - 1) && similar[y * w + x] {
                isBackground[y * w + x] = true
                queue.append(y * w + x)
            }
        }
        var head = 0
        while head < queue.count {
            let i = queue[head]; head += 1
            let x = i % w, y = i / w
            for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where nx >= 0 && ny >= 0 && nx < w && ny < h {
                let j = ny * w + nx
                if !isBackground[j] && similar[j] { isBackground[j] = true; queue.append(j) }
            }
        }

        // 5) Limpieza: apertura morfológica y mayor componente ponderada hacia el centro.
        var fg = isBackground.map { !$0 }
        fg = dilate(erode(fg, w, h), w, h)
        fg = mainComponent(fg, w, h)
        fg = erode(dilate(fg, w, h), w, h)

        let area = fg.filter { $0 }.count
        let fraction = Float(area) / Float(n)
        guard fraction > 0.04, fraction < 0.9 else { return nil }

        // 6) Recorte a la caja del sujeto con alfa suavizado en el borde.
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in 0..<h { for x in 0..<w where fg[y * w + x] {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        let alpha = blur(fg.map { $0 ? Float(255) : 0 }, w, h)
        let bw = maxX - minX + 1, bh = maxY - minY + 1
        // Salida a mayor resolución que la de trabajo, muestreando la imagen original.
        let outScale = max(1, min(4, 512 / max(bw, bh)))
        let ow = bw * outScale, oh = bh * outScale
        guard let hiRes = rgba(cg, width: w * outScale, height: h * outScale) else { return nil }
        var out = [UInt8](repeating: 0, count: ow * oh * 4)
        let hw = w * outScale
        for y in 0..<oh {
            for x in 0..<ow {
                let sx = minX * outScale + x, sy = minY * outScale + y
                let a = alpha[min(h - 1, sy / outScale) * w + min(w - 1, sx / outScale)]
                let src = (sy * hw + sx) * 4, dst = (y * ow + x) * 4
                let af = a / 255
                out[dst] = UInt8(Float(hiRes[src]) * af)       // premultiplicado
                out[dst + 1] = UInt8(Float(hiRes[src + 1]) * af)
                out[dst + 2] = UInt8(Float(hiRes[src + 2]) * af)
                out[dst + 3] = UInt8(a)
            }
        }
        guard let provider = CGDataProvider(data: Data(out) as CFData) else { return nil }
        return CGImage(width: ow, height: oh, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: ow * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: Utilidades

    /// Píxeles RGBA8 (fila 0 = arriba) de la imagen escalada a width × height.
    private static func rgba(_ cg: CGImage, width: Int, height: Int) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? data : nil
    }

    /// Distancia de color con pesos perceptuales aproximados.
    private static func distance(_ a: RGB, _ b: RGB) -> Float {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        let rMean = (a.r + b.r) / 2
        return sqrt((2 + rMean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rMean) / 256) * db * db) / 3
    }

    private static func kMeans(_ samples: [RGB], k: Int) -> [RGB] {
        guard !samples.isEmpty else { return [RGB(r: 128, g: 128, b: 128)] }
        let step = max(1, samples.count / k)
        var centers = (0..<k).map { samples[min(samples.count - 1, $0 * step)] }
        for _ in 0..<8 {
            var sums = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: k)
            var counts = [Int](repeating: 0, count: k)
            for s in samples {
                var best = 0, bestD = Float.greatestFiniteMagnitude
                for (j, c) in centers.enumerated() {
                    let d = distance(s, c)
                    if d < bestD { bestD = d; best = j }
                }
                sums[best].r += s.r; sums[best].g += s.g; sums[best].b += s.b; counts[best] += 1
            }
            for j in 0..<k where counts[j] > 0 {
                let c = Float(counts[j])
                centers[j] = RGB(r: sums[j].r / c, g: sums[j].g / c, b: sums[j].b / c)
            }
        }
        return centers
    }

    private static func otsu(_ values: [Float]) -> Float {
        let bins = 128
        let maxV = max(1, values.max() ?? 1)
        var hist = [Int](repeating: 0, count: bins)
        for v in values { hist[min(bins - 1, Int(v / maxV * Float(bins - 1)))] += 1 }
        let total = Float(values.count)
        var sumAll: Float = 0
        for i in 0..<bins { sumAll += Float(i) * Float(hist[i]) }
        var sumB: Float = 0, wB: Float = 0, best: Float = 0, bestT = 0
        for t in 0..<bins {
            wB += Float(hist[t])
            if wB == 0 { continue }
            let wF = total - wB
            if wF == 0 { break }
            sumB += Float(t) * Float(hist[t])
            let mB = sumB / wB, mF = (sumAll - sumB) / wF
            let between = wB * wF * (mB - mF) * (mB - mF)
            if between > best { best = between; bestT = t }
        }
        return (Float(bestT) + 0.5) / Float(bins - 1) * maxV
    }

    private static func blur(_ v: [Float], _ w: Int, _ h: Int) -> [Float] {
        var out = v
        for y in 0..<h {
            for x in 0..<w {
                var s: Float = 0, c: Float = 0
                for yy in max(0, y - 1)...min(h - 1, y + 1) {
                    for xx in max(0, x - 1)...min(w - 1, x + 1) { s += v[yy * w + xx]; c += 1 }
                }
                out[y * w + x] = s / c
            }
        }
        return out
    }

    private static func erode(_ m: [Bool], _ w: Int, _ h: Int) -> [Bool] {
        var out = m
        for y in 0..<h { for x in 0..<w where m[y * w + x] {
            if x == 0 || y == 0 || x == w - 1 || y == h - 1 ||
                !m[y * w + x - 1] || !m[y * w + x + 1] || !m[(y - 1) * w + x] || !m[(y + 1) * w + x] {
                out[y * w + x] = false
            }
        } }
        return out
    }

    private static func dilate(_ m: [Bool], _ w: Int, _ h: Int) -> [Bool] {
        var out = m
        for y in 0..<h { for x in 0..<w where !m[y * w + x] {
            if (x > 0 && m[y * w + x - 1]) || (x < w - 1 && m[y * w + x + 1]) ||
                (y > 0 && m[(y - 1) * w + x]) || (y < h - 1 && m[(y + 1) * w + x]) {
                out[y * w + x] = true
            }
        } }
        return out
    }

    /// Componente conexa con más área ponderada hacia el centro; rellena sus huecos interiores.
    private static func mainComponent(_ m: [Bool], _ w: Int, _ h: Int) -> [Bool] {
        var label = [Int](repeating: -1, count: w * h)
        var scores: [Float] = []
        let cx = Float(w) / 2, cy = Float(h) / 2, maxR = sqrt(cx * cx + cy * cy)
        for start in 0..<(w * h) where m[start] && label[start] < 0 {
            let id = scores.count
            var score: Float = 0
            var stack = [start]
            label[start] = id
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                let dx = Float(x) - cx, dy = Float(y) - cy
                score += 1 - 0.75 * sqrt(dx * dx + dy * dy) / maxR
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where nx >= 0 && ny >= 0 && nx < w && ny < h {
                    let j = ny * w + nx
                    if m[j] && label[j] < 0 { label[j] = id; stack.append(j) }
                }
            }
            scores.append(score)
        }
        guard let best = scores.indices.max(by: { scores[$0] < scores[$1] }) else { return m }
        let keep = label.map { $0 == best }
        // Rellenar huecos: todo lo que no se alcanza desde el borde por fuera de la figura.
        var outside = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        for y in 0..<h { for x in 0..<w where (x == 0 || y == 0 || x == w - 1 || y == h - 1) && !keep[y * w + x] {
            outside[y * w + x] = true; stack.append(y * w + x)
        } }
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where nx >= 0 && ny >= 0 && nx < w && ny < h {
                let j = ny * w + nx
                if !keep[j] && !outside[j] { outside[j] = true; stack.append(j) }
            }
        }
        return outside.map { !$0 }
    }
}
