import SwiftUI
import UIKit

// Sistema visual "Frutiger Aero": cielo azul, nubes, burbujas, cristal brillante y botones de gel.
// Se mantienen los nombres (Retro.*, retroPanel, RetroButtonStyle…) para que todas las pantallas
// usen el mismo estilo sin duplicar código.

// MARK: - Paleta y tipografía

enum Retro {
    /// Azul océano profundo: tinta de texto oscuro y cristal oscuro.
    static let night = Color(red: 0.02, green: 0.20, blue: 0.40)
    static let navy = Color(red: 0.04, green: 0.30, blue: 0.56)
    static let panel = Color(red: 0.08, green: 0.45, blue: 0.74)
    static let panelLight = Color(red: 0.42, green: 0.76, blue: 0.96)
    /// Blanco nube (texto principal).
    static let cream = Color(red: 0.99, green: 1.00, blue: 1.00)
    /// Verde lima "Aero" (acentos, pestaña activa, títulos de sección).
    static let yellow = Color(red: 0.74, green: 0.96, blue: 0.32)
    static let orange = Color(red: 1.00, green: 0.62, blue: 0.24)
    static let magenta = Color(red: 1.00, green: 0.46, blue: 0.72)
    static let cyan = Color(red: 0.38, green: 0.86, blue: 1.00)
    static let green = Color(red: 0.42, green: 0.90, blue: 0.34)
    static let shadow = Color(red: 0.0, green: 0.12, blue: 0.3).opacity(0.35)
    /// Cielo
    static let skyTop = Color(red: 0.13, green: 0.50, blue: 0.92)
    static let skyBottom = Color(red: 0.72, green: 0.92, blue: 1.00)
}

extension Font {
    /// Tipografía redondeada y limpia, como los sistemas de mediados de los 2000.
    static func retro(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight == .heavy ? .bold : weight, design: .rounded)
    }
    static func retroTitle(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
}

enum RetroAppearance {
    static func apply() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
        nav.backgroundColor = UIColor(red: 0.2, green: 0.55, blue: 0.9, alpha: 0.25)
        nav.shadowColor = .clear
        let rounded = UIFont.systemFont(ofSize: 17, weight: .bold).withRoundedDesign
        let roundedLarge = UIFont.systemFont(ofSize: 30, weight: .heavy).withRoundedDesign
        let shadow = NSShadow()
        shadow.shadowColor = UIColor(red: 0, green: 0.15, blue: 0.35, alpha: 0.5)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        nav.titleTextAttributes = [.font: rounded, .foregroundColor: UIColor.white, .shadow: shadow]
        nav.largeTitleTextAttributes = [.font: roundedLarge, .foregroundColor: UIColor.white, .shadow: shadow]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = .white
        UITextField.appearance().tintColor = UIColor(red: 0.38, green: 0.86, blue: 1, alpha: 1)
    }
}

private extension UIFont {
    var withRoundedDesign: UIFont {
        guard let d = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: d, size: pointSize)
    }
}

// MARK: - Formas

/// Rectángulo redondeado "de cristal". (`step` define el radio para compatibilidad.)
struct PixelRect: InsettableShape {
    var step: CGFloat = 4
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(step * 4 + 2, min(r.width, r.height) / 2)
        return RoundedRectangle(cornerRadius: max(0, radius - insetAmount), style: .continuous).path(in: r)
    }

    func inset(by amount: CGFloat) -> PixelRect {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Círculo (orbes de gel). `sides` se conserva por compatibilidad.
struct LowPolyCircle: Shape {
    var sides: Int = 10
    func path(in rect: CGRect) -> Path {
        Circle().path(in: rect)
    }
}

/// Brillo especular típico del cristal Aero: media elipse blanca en la parte superior.
struct GlossHighlight: View {
    var opacity: Double = 0.55
    var body: some View {
        GeometryReader { geo in
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(opacity), .white.opacity(0.04)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: geo.size.width * 1.1, height: geo.size.height * 0.62)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.2)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Paneles y botones

struct RetroPanel: ViewModifier {
    var fill: Color = Retro.panel
    var border: Color = Retro.cream
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return content
            .padding(padding)
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(LinearGradient(colors: [fill.opacity(0.42), fill.opacity(0.72)],
                                              startPoint: .top, endPoint: .bottom))
                    shape.fill(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.06), .clear],
                                              startPoint: .top, endPoint: .center))
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.95), border.opacity(0.35)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                }
                .shadow(color: Retro.night.opacity(0.28), radius: 14, x: 0, y: 8)
            )
    }
}

extension View {
    func retroPanel(fill: Color = Retro.panel, border: Color = Retro.cream, padding: CGFloat = 14) -> some View {
        modifier(RetroPanel(fill: fill, border: border, padding: padding))
    }

    /// Sombra suave para texto blanco sobre el cielo.
    func aeroTextShadow() -> some View {
        shadow(color: Retro.night.opacity(0.45), radius: 3, x: 0, y: 1)
    }
}

/// Botón de "gel": píldora brillante con reflejo, como los botones de 2006.
struct RetroButtonStyle: ButtonStyle {
    var color: Color = Retro.yellow
    var textColor: Color = Retro.night
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = Capsule(style: .continuous)
        return configuration.label
            .font(.retro(compact ? 14 : 17))
            .foregroundStyle(textColor)
            .shadow(color: .white.opacity(0.6), radius: 0, x: 0, y: 1)
            .padding(.horizontal, compact ? 13 : 22)
            .padding(.vertical, compact ? 9 : 14)
            .background(
                ZStack {
                    shape.fill(LinearGradient(colors: [color.mix(.white, 0.35), color, color.mix(.black, 0.18)],
                                              startPoint: .top, endPoint: .bottom))
                    // Brillo interior inferior (luz que atraviesa el gel)
                    shape.fill(RadialGradient(colors: [.white.opacity(0.45), .clear],
                                              center: .bottom, startRadius: 0, endRadius: 40))
                    GlossHighlight(opacity: 0.75).clipShape(shape).padding(2)
                    shape.strokeBorder(LinearGradient(colors: [.white, color.mix(.black, 0.3).opacity(0.6)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                }
                .shadow(color: color.mix(.black, 0.4).opacity(0.45), radius: pressed ? 2 : 8, x: 0, y: pressed ? 1 : 5)
            )
            .scaleEffect(pressed ? 0.96 : 1)
            .brightness(pressed ? -0.05 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: pressed)
            .onChange(of: pressed) { _, isDown in
                if isDown { ChipSynth.shared.play(.blip); Haptics.tap(.light) }
            }
    }
}

extension Color {
    /// Mezcla lineal con otro color (para degradados de gel).
    func mix(_ other: Color, _ amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(amount)
        return Color(red: Double(r1 + (r2 - r1) * t), green: Double(g1 + (g2 - g1) * t),
                     blue: Double(b1 + (b2 - b1) * t), opacity: Double(a1 + (a2 - a1) * t))
    }
}

// MARK: - Brillo ambiental (antes "CRT"): destello de sol suave

struct ScanlineOverlay: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [.white.opacity(0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 420)
            LinearGradient(colors: [.clear, .white.opacity(0.06), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

struct CRTEffect: ViewModifier {
    @EnvironmentObject var settings: AppSettings
    func body(content: Content) -> some View {
        content.overlay { if settings.crtEffect { ScanlineOverlay() } }
    }
}

extension View {
    func crt() -> some View { modifier(CRTEffect()) }
}

// MARK: - Fondo: cielo, nubes, colina verde y burbujas

struct RetroBackground: View {
    /// Color del "swoosh" de luz (cambia según la rareza o la pantalla).
    var floorColor: Color = Retro.cyan
    var animated = true

    private struct Bubble { let x: Double; let size: Double; let speed: Double; let phase: Double; let drift: Double }
    private struct Cloud { let x: Double; let y: Double; let scale: Double; let speed: Double }

    private static let bubbles: [Bubble] = {
        var rng = SeededGenerator(seed: 99)
        return (0..<16).map { _ in
            Bubble(x: Double.random(in: 0...1, using: &rng), size: Double.random(in: 10...46, using: &rng),
                   speed: Double.random(in: 0.025...0.07, using: &rng), phase: Double.random(in: 0...1, using: &rng),
                   drift: Double.random(in: 0...6, using: &rng))
        }
    }()
    private static let clouds: [Cloud] = {
        var rng = SeededGenerator(seed: 7)
        return (0..<5).map { i in
            Cloud(x: Double(i) / 5 + Double.random(in: 0...0.1, using: &rng),
                  y: Double.random(in: 0.06...0.42, using: &rng),
                  scale: Double.random(in: 0.7...1.3, using: &rng), speed: Double.random(in: 0.004...0.01, using: &rng))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width, h = size.height
                // Cielo
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [Retro.skyTop, Retro.skyBottom]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.8)))
                // Sol
                let sun = CGPoint(x: w * 0.85, y: h * 0.08)
                ctx.fill(Path(ellipseIn: CGRect(x: sun.x - 220, y: sun.y - 220, width: 440, height: 440)),
                         with: .radialGradient(Gradient(colors: [.white.opacity(0.85), .white.opacity(0.0)]),
                                               center: sun, startRadius: 0, endRadius: 220))
                // Nubes
                for c in Self.clouds {
                    let x = ((c.x + t * c.speed).truncatingRemainder(dividingBy: 1.3) - 0.15) * w
                    let y = c.y * h
                    let s = 70 * c.scale
                    for (dx, dy, r) in [(0.0, 0.0, 1.0), (0.8, 0.15, 0.8), (-0.8, 0.2, 0.75), (0.35, -0.35, 0.8), (-0.3, -0.25, 0.7)] {
                        let rr = s * r
                        ctx.fill(Path(ellipseIn: CGRect(x: x + dx * s - rr, y: y + dy * s - rr * 0.75,
                                                        width: rr * 2, height: rr * 1.5)),
                                 with: .color(.white.opacity(0.55)))
                    }
                }
                // Swoosh de luz (cintas translúcidas)
                for k in 0..<2 {
                    var p = Path()
                    let baseY = h * (0.5 + 0.06 * Double(k))
                    p.move(to: CGPoint(x: -20, y: baseY))
                    for i in 0...24 {
                        let x = w * Double(i) / 24
                        let y = baseY + sin(Double(i) / 24 * .pi * 2 + t * 0.4 + Double(k)) * 28 - Double(i) * 3
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                    ctx.stroke(p, with: .color(floorColor.opacity(0.35 - Double(k) * 0.12)),
                               style: StrokeStyle(lineWidth: 18 - CGFloat(k) * 8, lineCap: .round))
                    ctx.stroke(p, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                // Colina verde
                var hill = Path()
                hill.move(to: CGPoint(x: 0, y: h))
                hill.addLine(to: CGPoint(x: 0, y: h * 0.84))
                hill.addQuadCurve(to: CGPoint(x: w, y: h * 0.80), control: CGPoint(x: w * 0.45, y: h * 0.70))
                hill.addLine(to: CGPoint(x: w, y: h))
                hill.closeSubpath()
                ctx.fill(hill, with: .linearGradient(Gradient(colors: [Color(red: 0.55, green: 0.88, blue: 0.25),
                                                                     Color(red: 0.16, green: 0.58, blue: 0.12)]),
                                                     startPoint: CGPoint(x: 0, y: h * 0.72), endPoint: CGPoint(x: 0, y: h)))
                var shine = Path()
                shine.move(to: CGPoint(x: 0, y: h * 0.845))
                shine.addQuadCurve(to: CGPoint(x: w, y: h * 0.805), control: CGPoint(x: w * 0.45, y: h * 0.705))
                ctx.stroke(shine, with: .color(.white.opacity(0.6)), lineWidth: 2)
                // Burbujas que suben
                for b in Self.bubbles {
                    let progress = (b.phase + t * b.speed).truncatingRemainder(dividingBy: 1)
                    let y = h * (1.05 - progress * 1.15)
                    let x = b.x * w + sin(t * 0.8 + b.drift) * 14
                    let rect = CGRect(x: x - b.size / 2, y: y - b.size / 2, width: b.size, height: b.size)
                    ctx.fill(Path(ellipseIn: rect),
                             with: .radialGradient(Gradient(colors: [.white.opacity(0.05), .white.opacity(0.10), .white.opacity(0.45)]),
                                                   center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: b.size / 2))
                    ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.6)), lineWidth: 1)
                    ctx.fill(Path(ellipseIn: CGRect(x: rect.minX + b.size * 0.2, y: rect.minY + b.size * 0.14,
                                                    width: b.size * 0.3, height: b.size * 0.2)),
                             with: .color(.white.opacity(0.8)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Piezas reutilizables

struct StarsRow: View {
    let count: Int
    var total = 6
    var size: CGFloat = 12
    var color: Color = Retro.yellow
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<total, id: \.self) { i in
                Image(systemName: i < count ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i < count ? color : Color.white.opacity(0.45))
                    .shadow(color: i < count ? color.opacity(0.8) : .clear, radius: 3)
            }
        }
    }
}

struct RarityBadge: View {
    let rarity: Rarity
    var compact = false
    var body: some View {
        Text(rarity.title.uppercased())
            .font(.retro(compact ? 9 : 12))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            .padding(.horizontal, compact ? 7 : 11)
            .padding(.vertical, compact ? 3 : 5)
            .background(
                ZStack {
                    Capsule().fill(rarity == .common
                                   ? LinearGradient(colors: [Color(white: 0.75), Color(white: 0.5)], startPoint: .top, endPoint: .bottom)
                                   : rarity.gradient)
                    GlossHighlight(opacity: 0.6).clipShape(Capsule())
                    Capsule().strokeBorder(.white.opacity(0.85), lineWidth: 1)
                }
            )
    }
}

/// Barra de progreso de cristal verde (estilo Windows 7).
struct PixelBar: View {
    let value: Double // 0...1
    var segments = 16
    var color: Color = Retro.green
    var height: CGFloat = 12
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule()
                    .fill(LinearGradient(colors: [color.mix(.white, 0.4), color, color.mix(.black, 0.2)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(GlossHighlight(opacity: 0.7).clipShape(Capsule()))
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .padding(2)
        .background(Capsule().fill(Retro.night.opacity(0.35)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1))
    }
}

struct BlinkingText: View {
    let text: String
    var font: Font = .retro(14)
    var color: Color = Retro.cream
    @State var visible = true
    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .aeroTextShadow()
            .opacity(visible ? 1 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { visible = false }
            }
    }
}

/// Título brillante "de cristal": degradado, reflejo blanco y halo.
struct ExtrudedText: View {
    let text: String
    var size: CGFloat = 48
    var fill: [Color] = [Color(red: 0.55, green: 0.95, blue: 1.0), Color(red: 0.10, green: 0.50, blue: 0.95)]
    var depthColor: Color = Retro.night
    var depth = 6

    var body: some View {
        ZStack {
            Text(text)
                .font(.retroTitle(size))
                .foregroundStyle(depthColor.opacity(0.55))
                .offset(y: 3)
                .blur(radius: 2)
            Text(text)
                .font(.retroTitle(size))
                .foregroundStyle(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom))
            Text(text)
                .font(.retroTitle(size))
                .foregroundStyle(.clear)
                .overlay(
                    LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.1), .clear],
                                   startPoint: .top, endPoint: .center)
                        .mask(Text(text).font(.retroTitle(size)))
                )
        }
        .shadow(color: .white.opacity(0.7), radius: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(.system(size: 14, weight: .bold)) }
            Text(title.uppercased()).font(.retro(13))
            Capsule().fill(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0)],
                                          startPoint: .leading, endPoint: .trailing))
                .frame(height: 2)
        }
        .foregroundStyle(Retro.yellow)
        .aeroTextShadow()
    }
}

/// Imagen pixelada (sin suavizado) para sprites y modelos low-poly.
struct PixelImage: View {
    let image: UIImage
    var contentMode: ContentMode = .fit
    var body: some View {
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .aspectRatio(contentMode: contentMode)
    }
}
