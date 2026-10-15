import CoreGraphics
import UIKit

/// Raw RGBA8 (no premultiplicado) para procesar píxel a píxel texturas pequeñas.
struct PixelBuffer {
    let width: Int
    let height: Int
    var data: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        data = [UInt8](repeating: 0, count: width * height * 4)
    }

    /// Dibuja `image` en un lienzo cuadrado de `size`, apoyado en el suelo (abajo) y centrado.
    init?(image: CGImage, canvas size: Int, margin: Double = 0.06) {
        self.init(width: size, height: size)
        let iw = Double(image.width), ih = Double(image.height)
        guard iw > 0, ih > 0 else { return nil }
        let usable = Double(size) * (1 - margin * 2)
        let scale = usable / max(iw, ih)
        let dw = iw * scale, dh = ih * scale
        let rect = CGRect(x: (Double(size) - dw) / 2,
                          y: Double(size) * margin * 0.5, // CoreGraphics: y=0 es abajo → "pies" en el suelo
                          width: dw, height: dh)
        let space = CGColorSpaceCreateDeviceRGB()
        var premult = [UInt8](repeating: 0, count: size * size * 4)
        let ok: Bool = premult.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: size * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: rect)
            return true
        }
        guard ok else { return nil }
        // Des-premultiplicar
        for i in stride(from: 0, to: premult.count, by: 4) {
            let a = premult[i + 3]
            if a == 0 { continue }
            let af = Double(a) / 255
            data[i] = UInt8(min(255, Double(premult[i]) / af))
            data[i + 1] = UInt8(min(255, Double(premult[i + 1]) / af))
            data[i + 2] = UInt8(min(255, Double(premult[i + 2]) / af))
            data[i + 3] = a
        }
    }

    init?(cgImage: CGImage) {
        self.init(image: cgImage, canvas: max(cgImage.width, cgImage.height), margin: 0)
    }

    @inline(__always) func index(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }

    func alpha(_ x: Int, _ y: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return data[index(x, y) + 3]
    }

    func makeCGImage() -> CGImage? {
        // Re-premultiplicar para CoreGraphics
        var premult = data
        for i in stride(from: 0, to: premult.count, by: 4) {
            let a = Double(premult[i + 3]) / 255
            premult[i] = UInt8(Double(premult[i]) * a)
            premult[i + 1] = UInt8(Double(premult[i + 1]) * a)
            premult[i + 2] = UInt8(Double(premult[i + 2]) * a)
        }
        let space = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(premult) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Convierte el recorte del sujeto en una textura "de consola de 32/64 bits":
/// baja resolución, color de 15 bits con tramado Bayer (como la PS1), bordes duros y contorno oscuro.
enum RetroStylizer {
    private static let bayer4: [Double] = ([
         0,  8,  2, 10,
        12,  4, 14,  6,
         3, 11,  1,  9,
        15,  7, 13,  5
    ] as [Double]).map { ($0 + 0.5) / 16 - 0.5 }

    static func makeSprite(from subject: CGImage, resolution: Int) -> CGImage? {
        let res = max(32, min(160, resolution))
        guard var buf = PixelBuffer(image: subject, canvas: res) else { return nil }
        let levels = 14.0 // niveles por canal → paleta reducida (≈ color de 15 bits de PS1)

        // 1) Alfa binaria + color: saturación/contraste + cuantización con tramado
        for y in 0..<res {
            for x in 0..<res {
                let i = buf.index(x, y)
                if buf.data[i + 3] < 110 {
                    buf.data[i] = 0; buf.data[i + 1] = 0; buf.data[i + 2] = 0; buf.data[i + 3] = 0
                    continue
                }
                var r = Double(buf.data[i]) / 255
                var g = Double(buf.data[i + 1]) / 255
                var b = Double(buf.data[i + 2]) / 255
                // Saturación +20 %, contraste +12 % (look de textura de juego)
                let l = 0.299 * r + 0.587 * g + 0.114 * b
                r = l + (r - l) * 1.2; g = l + (g - l) * 1.2; b = l + (b - l) * 1.2
                r = (r - 0.5) * 1.12 + 0.52; g = (g - 0.5) * 1.12 + 0.52; b = (b - 0.5) * 1.12 + 0.52
                let d = 0.7 * bayer4[(y % 4) * 4 + (x % 4)] / (levels - 1)
                func q(_ v: Double) -> UInt8 {
                    let c = min(1, max(0, v + d))
                    return UInt8((c * (levels - 1)).rounded() / (levels - 1) * 255)
                }
                buf.data[i] = q(r); buf.data[i + 1] = q(g); buf.data[i + 2] = q(b); buf.data[i + 3] = 255
            }
        }

        // 2) Quitar píxeles sueltos (ruido de la máscara)
        let snapshot = buf
        for y in 0..<res {
            for x in 0..<res where snapshot.alpha(x, y) > 0 {
                let neighbours = [snapshot.alpha(x + 1, y), snapshot.alpha(x - 1, y),
                                  snapshot.alpha(x, y + 1), snapshot.alpha(x, y - 1)].filter { $0 > 0 }.count
                if neighbours <= 1 { buf.data[buf.index(x, y) + 3] = 0 }
            }
        }

        // 3) Contorno oscuro de 1 píxel (sensación sprite/cel)
        let clean = buf
        for y in 0..<res {
            for x in 0..<res where clean.alpha(x, y) > 0 {
                let edge = clean.alpha(x + 1, y) == 0 || clean.alpha(x - 1, y) == 0 ||
                           clean.alpha(x, y + 1) == 0 || clean.alpha(x, y - 1) == 0
                if edge {
                    let i = buf.index(x, y)
                    buf.data[i] = UInt8(Double(buf.data[i]) * 0.38)
                    buf.data[i + 1] = UInt8(Double(buf.data[i + 1]) * 0.38)
                    buf.data[i + 2] = UInt8(Double(buf.data[i + 2]) * 0.42)
                }
            }
        }
        return buf.makeCGImage()
    }

    /// Versión sin transparencia para la malla 3D: extiende el color hacia el fondo
    /// para que los bordes de los polígonos no muestren huecos.
    static func dilatedOpaque(_ sprite: CGImage, passes: Int = 4) -> CGImage? {
        guard var buf = PixelBuffer(cgImage: sprite) else { return nil }
        for _ in 0..<passes {
            let src = buf
            for y in 0..<buf.height {
                for x in 0..<buf.width where src.alpha(x, y) == 0 {
                    var r = 0, g = 0, b = 0, n = 0
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where src.alpha(x + dx, y + dy) > 0 {
                        let j = src.index(x + dx, y + dy)
                        r += Int(src.data[j]); g += Int(src.data[j + 1]); b += Int(src.data[j + 2]); n += 1
                    }
                    if n > 0 {
                        let i = buf.index(x, y)
                        buf.data[i] = UInt8(r / n); buf.data[i + 1] = UInt8(g / n)
                        buf.data[i + 2] = UInt8(b / n); buf.data[i + 3] = 255
                    }
                }
            }
        }
        for i in stride(from: 3, to: buf.data.count, by: 4) where buf.data[i] == 0 {
            buf.data[i - 3] = 40; buf.data[i - 2] = 40; buf.data[i - 1] = 48; buf.data[i] = 255
        }
        return buf.makeCGImage()
    }
}
