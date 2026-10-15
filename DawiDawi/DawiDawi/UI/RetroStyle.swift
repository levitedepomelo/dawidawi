import SwiftUI
import UIKit

// MARK: - Paleta y tipografía

enum Retro {
    static let night = Color(red: 0.04, green: 0.05, blue: 0.14)
    static let navy = Color(red: 0.08, green: 0.10, blue: 0.26)
    static let panel = Color(red: 0.11, green: 0.13, blue: 0.33)
    static let panelLight = Color(red: 0.18, green: 0.21, blue: 0.47)
    static let cream = Color(red: 0.96, green: 0.93, blue: 0.80)
    static let yellow = Color(red: 1.00, green: 0.83, blue: 0.28)
    static let orange = Color(red: 1.00, green: 0.52, blue: 0.20)
    static let magenta = Color(red: 1.00, green: 0.31, blue: 0.64)
    static let cyan = Color(red: 0.22, green: 0.90, blue: 1.00)
    static let green = Color(red: 0.36, green: 0.90, blue: 0.42)
    static let shadow = Color.black.opacity(0.75)
}

extension Font {
    /// Tipografía "de videojuego": monoespaciada, gruesa, adaptable a Dynamic Type.
    static func retro(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func retroTitle(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }
}

enum RetroAppearance {
    static func apply() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.19, alpha: 1)
        nav.shadowColor = .clear
        let mono = UIFont.monospacedSystemFont(ofSize: 17, weight: .heavy)
        let monoLarge = UIFont.monospacedSystemFont(ofSize: 30, weight: .black)
        let cream = UIColor(red: 0.96, green: 0.93, blue: 0.80, alpha: 1)
        nav.titleTextAttributes = [.font: mono, .foregroundColor: cream]
        nav.largeTitleTextAttributes = [.font: monoLarge, .foregroundColor: cream]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UITextField.appearance().tintColor = UIColor(red: 1, green: 0.83, blue: 0.28, alpha: 1)
    }
}

// MARK: - Formas pixeladas

/// Rectángulo con esquinas "escalonadas" como los marcos de los RPG de 16 bits.
struct PixelRect: InsettableShape {
    var step: CGFloat = 4
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let s = min(step, min(r.width, r.height) / 4)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 2 * s, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.minY + s))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> PixelRect {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// Octágono "low-poly" (cápsulas, botones redondos).
struct LowPolyCircle: Shape {
    var sides: Int = 10
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<sides {
            let a = Double(i) / Double(sides) * 2 * .pi - .pi / 2 + .pi / Double(sides)
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Paneles y botones

struct RetroPanel: ViewModifier {
    var fill: Color = Retro.panel
    var border: Color = Retro.cream
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    PixelRect(step: 4).fill(Retro.shadow).offset(x: 4, y: 4)
                    PixelRect(step: 4).fill(fill)
                    PixelRect(step: 4).fill(
                        LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center))
                    PixelRect(step: 4).strokeBorder(border, lineWidth: 3)
                    PixelRect(step: 4).inset(by: 5).strokeBorder(border.opacity(0.22), lineWidth: 1)
                }
            )
    }
}

extension View {
    func retroPanel(fill: Color = Retro.panel, border: Color = Retro.cream, padding: CGFloat = 14) -> some View {
        modifier(RetroPanel(fill: fill, border: border, padding: padding))
    }
}

struct RetroButtonStyle: ButtonStyle {
    var color: Color = Retro.yellow
    var textColor: Color = Retro.night
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.retro(compact ? 13 : 16))
            .foregroundStyle(textColor)
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 8 : 13)
            .background(
                ZStack {
                    PixelRect(step: 3).fill(Retro.shadow).offset(y: pressed ? 1 : 5)
                    PixelRect(step: 3).fill(color)
                    PixelRect(step: 3).fill(LinearGradient(colors: [.white.opacity(0.35), .clear],
                                                           startPoint: .top, endPoint: .center))
                    PixelRect(step: 3).strokeBorder(Retro.night, lineWidth: 2.5)
                }
            )
            .offset(y: pressed ? 4 : 0)
            .animation(.easeOut(duration: 0.06), value: pressed)
            .onChange(of: pressed) { _, isDown in
                if isDown { ChipSynth.shared.play(.blip); Haptics.tap(.light) }
            }
    }
}

// MARK: - Efectos CRT

struct ScanlineOverlay: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            while y < size.height {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.16)))
                y += 3
            }
        }
        .overlay(
            RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 180, endRadius: 650)
        )
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

// MARK: - Fondo animado (cielo estrellado + suelo de ajedrez en perspectiva)

struct RetroBackground: View {
    var floorColor: Color = Retro.magenta
    var animated = true

    private struct Star { let x: Double; let y: Double; let size: Double; let phase: Double }
    private static let stars: [Star] = {
        var rng = SeededGenerator(seed: 99)
        return (0..<70).map { _ in
            Star(x: Double.random(in: 0...1, using: &rng), y: Double.random(in: 0...0.62, using: &rng),
                 size: Double.random(in: 1...3, using: &rng).rounded(), phase: Double.random(in: 0...6, using: &rng))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                // Cielo por bandas (degradado "posterizado")
                let bands = 10
                for i in 0..<bands {
                    let f = Double(i) / Double(bands - 1)
                    let color = Color(red: 0.04 + 0.16 * f, green: 0.05 + 0.03 * f, blue: 0.14 + 0.20 * f)
                    let h = size.height * 0.62 / CGFloat(bands)
                    ctx.fill(Path(CGRect(x: 0, y: CGFloat(i) * h, width: size.width, height: h + 1)), with: .color(color))
                }
                for s in Self.stars {
                    let tw = 0.45 + 0.55 * abs(sin(t * 1.3 + s.phase))
                    ctx.fill(Path(CGRect(x: s.x * size.width, y: s.y * size.height, width: s.size, height: s.size)),
                             with: .color(.white.opacity(tw)))
                }
                // Suelo en perspectiva
                let horizon = size.height * 0.62
                ctx.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)),
                         with: .color(Retro.night))
                let lines = 14
                let scroll = (t * 0.6).truncatingRemainder(dividingBy: 1)
                for i in 0..<lines {
                    let z = (Double(i) + 1 - scroll) / Double(lines)
                    let y = horizon + (size.height - horizon) * pow(z, 2.2)
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 2)),
                             with: .color(floorColor.opacity(0.25 + 0.6 * z)))
                }
                let vanish = CGPoint(x: size.width / 2, y: horizon)
                for i in -12...12 {
                    var p = Path()
                    p.move(to: vanish)
                    p.addLine(to: CGPoint(x: size.width / 2 + CGFloat(i) * size.width / 7, y: size.height))
                    ctx.stroke(p, with: .color(floorColor.opacity(0.55)), lineWidth: 2)
                }
                ctx.fill(Path(CGRect(x: 0, y: horizon - 1, width: size.width, height: 3)), with: .color(floorColor))
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
                    .font(.system(size: size, weight: .black))
                    .foregroundStyle(i < count ? color : Color.white.opacity(0.2))
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
            .foregroundStyle(rarity == .common ? Retro.night : .white)
            .shadow(color: .black.opacity(rarity == .common ? 0 : 0.6), radius: 0, x: 1, y: 1)
            .padding(.horizontal, compact ? 6 : 10)
            .padding(.vertical, compact ? 3 : 5)
            .background(PixelRect(step: 2).fill(rarity.gradient))
            .overlay(PixelRect(step: 2).strokeBorder(Retro.night, lineWidth: 2))
    }
}

/// Barra segmentada estilo HUD.
struct PixelBar: View {
    let value: Double // 0...1
    var segments = 16
    var color: Color = Retro.green
    var height: CGFloat = 12
    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let w = (geo.size.width - gap * CGFloat(segments - 1)) / CGFloat(segments)
            HStack(spacing: gap) {
                ForEach(0..<segments, id: \.self) { i in
                    Rectangle()
                        .fill(Double(i) < value * Double(segments) ? color : Color.white.opacity(0.1))
                        .frame(width: max(1, w))
                }
            }
        }
        .frame(height: height)
        .padding(3)
        .background(Rectangle().fill(Retro.night))
        .overlay(Rectangle().strokeBorder(Retro.cream.opacity(0.6), lineWidth: 1.5))
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
            .opacity(visible ? 1 : 0.15)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { visible = false }
            }
    }
}

/// Texto con extrusión 3D a base de capas desplazadas (logos de los 90).
struct ExtrudedText: View {
    let text: String
    var size: CGFloat = 48
    var fill: [Color] = [Retro.yellow, Retro.orange]
    var depthColor: Color = Color(red: 0.45, green: 0.12, blue: 0.35)
    var depth = 6

    var body: some View {
        ZStack {
            ForEach(Array((1...depth).reversed()), id: \.self) { i in
                Text(text)
                    .font(.retroTitle(size))
                    .foregroundStyle(i == depth ? Color.black : depthColor)
                    .offset(x: CGFloat(i), y: CGFloat(i))
            }
            Text(text)
                .font(.retroTitle(size))
                .foregroundStyle(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom))
            Text(text)
                .font(.retroTitle(size))
                .foregroundStyle(.clear)
                .overlay(
                    LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
                        .mask(Text(text).font(.retroTitle(size)))
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(.system(size: 13, weight: .black)) }
            Text(title.uppercased()).font(.retro(13))
            Rectangle().fill(Retro.cream.opacity(0.3)).frame(height: 2)
        }
        .foregroundStyle(Retro.yellow)
    }
}

/// Imagen pixelada (sin suavizado) — imprescindible para la estética.
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
