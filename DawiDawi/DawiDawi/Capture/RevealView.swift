import SwiftUI
import SwiftData

/// La gran revelación: cápsula que cae, sacudidas con color creciente (suspense),
/// destello, rayos, confeti, fanfarria chiptune y la criatura 3D entrando en escena.
struct RevealView: View {
    let creature: Creature
    let stage: RetroStage
    let notice: String?
    let onDone: () -> Void
    let onAnother: () -> Void

    enum Phase: Int, Comparable {
        case drop, shaking, burst, naming
        static func < (a: Phase, b: Phase) -> Bool { a.rawValue < b.rawValue }
    }

    @Environment(\.modelContext) var context
    @State var phase: Phase = .drop
    @State var capsuleOffset: CGFloat = -700
    @State var capsuleAngle: Double = 0
    @State var capsuleScale: CGFloat = 1
    @State var glowTier = 0
    @State var flashOpacity: Double = 0
    @State var showCreature = false
    @State var bannerVisible = false
    @State var starsShown = 0
    @State var shakeOffset: CGSize = .zero
    @State var burstDate = Date()
    @State var name = ""
    @State var skip = false
    @FocusState var nameFocused: Bool

    private var rarity: Rarity { creature.rarity }
    private var glowColor: Color { Rarity.allCases[min(glowTier, Rarity.allCases.count - 1)].color }

    var body: some View {
        ZStack {
            RetroBackground(floorColor: phase >= .burst ? rarity.color : Retro.magenta)

            if phase >= .burst {
                SunburstView(color: rarity.color, rainbow: rarity == .mythic, speed: 0.15 + Double(rarity.tier) * 0.05)
                    .opacity(0.55 + Double(rarity.tier) * 0.07)
                    .transition(.opacity)
            }

            VStack(spacing: 10) {
                header
                    .padding(.top, 18)

                ZStack {
                    if showCreature {
                        RetroSceneView(stage: stage, pixelScale: 0.75)
                            .frame(maxWidth: .infinity)
                            .frame(height: 330)
                            .clipShape(PixelRect(step: 6))
                            .overlay(PixelRect(step: 6).strokeBorder(rarity.color, lineWidth: 4))
                            .shadow(color: rarity.color.opacity(0.8), radius: rarity >= .epic ? 18 : 6)
                            .padding(.horizontal, 22)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    } else {
                        CapsuleOrb(glow: glowColor, intensity: Double(glowTier + 1) / 6)
                            .frame(width: 150, height: 150)
                            .scaleEffect(capsuleScale)
                            .rotationEffect(.degrees(capsuleAngle), anchor: .bottom)
                            .offset(y: capsuleOffset)
                    }
                }
                .frame(height: 340)

                if bannerVisible {
                    VStack(spacing: 6) {
                        ExtrudedText(text: rarity.shout,
                                     size: rarity >= .legendary ? 36 : 32,
                                     fill: rarity == .mythic ? [.pink, .yellow, .cyan] : [rarity.color, rarity.color.opacity(0.7)],
                                     depthColor: rarity.darkColor)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                        StarsRow(count: starsShown, total: 6, size: 20, color: rarity == .mythic ? Retro.magenta : Retro.yellow)
                        Text(String(format: "Probabilidad: %.2f%%", AppSettings.shared.probability(rarity) * 100))
                            .font(.retro(11))
                            .foregroundStyle(Retro.cream.opacity(0.8))
                    }
                    .transition(.scale(scale: 3).combined(with: .opacity))
                }

                Spacer(minLength: 0)

                if phase == .naming {
                    namingPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if phase < .burst {
                    BlinkingText(text: "TOCA PARA ABRIR YA", font: .retro(12))
                        .padding(.bottom, 30)
                }
            }

            if phase >= .burst {
                ConfettiView(rarity: rarity, start: burstDate)
                    .allowsHitTesting(false)
            }

            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .offset(shakeOffset)
        .contentShape(Rectangle())
        .onTapGesture {
            if phase < .burst { skip = true }
            nameFocused = false
        }
        .task { await runSequence() }
    }

    // MARK: Piezas

    private var header: some View {
        VStack(spacing: 4) {
            Text(phase >= .burst ? "¡NUEVA CRIATURA!" : "CAPTURANDO...")
                .font(.retro(18))
                .foregroundStyle(Retro.cream)
                .shadow(color: .black, radius: 0, x: 2, y: 2)
            if phase >= .burst {
                Text("\(creature.numberLabel) DE TU COLECCIÓN")
                    .font(.retro(11))
                    .foregroundStyle(Retro.yellow)
            }
        }
    }

    private var namingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice {
                Text(notice).font(.retro(10, weight: .semibold)).foregroundStyle(Retro.orange)
            }
            Text("PONLE NOMBRE").font(.retro(13)).foregroundStyle(Retro.yellow)
            TextField("", text: $name, prompt: Text(creature.displayName).foregroundStyle(Retro.cream.opacity(0.35)))
                .font(.retro(20))
                .foregroundStyle(Retro.cream)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
                .padding(12)
                .background(Rectangle().fill(Retro.night))
                .overlay(Rectangle().strokeBorder(Retro.cream.opacity(0.7), lineWidth: 2))
                .onSubmit { nameFocused = false }

            HStack(spacing: 12) {
                Button {
                    commitName()
                    onAnother()
                } label: {
                    Label("OTRA", systemImage: "camera.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(RetroButtonStyle(color: Retro.cyan))

                Button {
                    commitName()
                    onDone()
                } label: {
                    Label("GUARDAR", systemImage: "star.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(RetroButtonStyle(color: Retro.yellow))
            }
        }
        .retroPanel(fill: Retro.night.opacity(0.94), border: rarity.color)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    // MARK: Secuencia

    private func pause(_ seconds: Double) async {
        guard !skip else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func runSequence() async {
        // 1) Caída de la cápsula
        ChipSynth.shared.play(.drop)
        withAnimation(.interpolatingSpring(stiffness: 160, damping: 11)) { capsuleOffset = 0 }
        await pause(0.9)
        Haptics.tap(.medium)

        // 2) Sacudidas: cada una puede "subir" el color — el brillo final anticipa la rareza
        phase = .shaking
        for i in 0..<rarity.shakeCount {
            if skip { break }
            let level = min(i, rarity.tier)
            ChipSynth.shared.play(.tick(level))
            Haptics.tap(level >= 3 ? .heavy : .medium)
            withAnimation(.easeInOut(duration: 0.07)) { capsuleAngle = -14; glowTier = level }
            await pause(0.08)
            withAnimation(.easeInOut(duration: 0.1)) { capsuleAngle = 14 }
            await pause(0.1)
            withAnimation(.easeInOut(duration: 0.07)) { capsuleAngle = 0 }
            await pause(i >= rarity.shakeCount - 2 ? 0.55 : 0.38)
        }
        glowTier = rarity.tier
        withAnimation(.easeIn(duration: 0.18)) { capsuleScale = 1.35 }
        try? await Task.sleep(nanoseconds: 180_000_000)

        // 3) ¡Estallido!
        ChipSynth.shared.play(.open)
        withAnimation(.easeIn(duration: 0.12)) { flashOpacity = 1 }
        try? await Task.sleep(nanoseconds: 140_000_000)
        burstDate = Date()
        phase = .burst
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { showCreature = true }
        stage.playEntrance()
        ChipSynth.shared.play(.fanfare(rarity))
        Haptics.reveal(rarity)
        withAnimation(.easeOut(duration: 0.7)) { flashOpacity = 0 }
        if rarity >= .epic { Task { await screenShake(strength: CGFloat(rarity.tier) * 2.5) } }

        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.55)) { bannerVisible = true }
        for s in 1...rarity.stars {
            try? await Task.sleep(nanoseconds: 170_000_000)
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { starsShown = s }
            ChipSynth.shared.play(.star)
        }
        try? await Task.sleep(nanoseconds: 600_000_000)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { phase = .naming }
    }

    private func screenShake(strength: CGFloat) async {
        for i in 0..<14 {
            let decay = 1 - CGFloat(i) / 14
            shakeOffset = CGSize(width: .random(in: -strength...strength) * decay,
                                 height: .random(in: -strength...strength) * decay)
            try? await Task.sleep(nanoseconds: 35_000_000)
        }
        shakeOffset = .zero
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { creature.name = trimmed }
        try? context.save()
        ChipSynth.shared.play(.save)
        Haptics.success()
    }
}

// MARK: - Cápsula

/// "Dawi-cristal": gema low-poly facetada con un núcleo que brilla con el color de la rareza.
struct CapsuleOrb: View {
    let glow: Color
    let intensity: Double

    /// Vértices del contorno (unidades 0…1): hexágono alargado tipo cristal.
    private static let outline: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.0), CGPoint(x: 0.86, y: 0.22), CGPoint(x: 0.92, y: 0.6),
        CGPoint(x: 0.5, y: 1.0), CGPoint(x: 0.08, y: 0.6), CGPoint(x: 0.14, y: 0.22)
    ]
    private static let core = CGPoint(x: 0.47, y: 0.5)
    /// Tonos por faceta: luz desde arriba a la izquierda, como un modelo vertex-lit.
    private static let shades: [Double] = [1.0, 0.72, 0.5, 0.38, 0.62, 0.86]

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [glow.opacity(0.9), glow.opacity(0)], center: .center,
                                     startRadius: 10, endRadius: 140))
                .scaleEffect(1.6 + intensity * 0.6)
                .blendMode(.screen)
            Canvas { ctx, size in
                func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
                let outline = Self.outline.map(pt)
                let center = pt(Self.core)
                // Sombra dura desplazada
                var shadow = Path()
                shadow.addLines(outline.map { CGPoint(x: $0.x + 6, y: $0.y + 8) })
                shadow.closeSubpath()
                ctx.fill(shadow, with: .color(.black.opacity(0.7)))
                // Facetas
                for i in 0..<outline.count {
                    var facet = Path()
                    facet.move(to: center)
                    facet.addLine(to: outline[i])
                    facet.addLine(to: outline[(i + 1) % outline.count])
                    facet.closeSubpath()
                    let s = Self.shades[i]
                    ctx.fill(facet, with: .color(Color(red: 0.25 + 0.75 * s, green: 0.18 + 0.2 * s, blue: 0.45 + 0.4 * s)))
                    ctx.stroke(facet, with: .color(Retro.night.opacity(0.55)), lineWidth: 1.5)
                }
                // Núcleo luminoso
                let r = size.width * 0.17
                var gem = Path()
                for k in 0..<6 {
                    let a = Double(k) / 6 * 2 * .pi - .pi / 2
                    let p = CGPoint(x: center.x + r * cos(a), y: center.y + r * 1.2 * sin(a))
                    if k == 0 { gem.move(to: p) } else { gem.addLine(to: p) }
                }
                gem.closeSubpath()
                ctx.fill(gem, with: .color(Retro.night))
                ctx.fill(gem.applying(CGAffineTransform(translationX: -center.x, y: -center.y)
                    .concatenating(CGAffineTransform(scaleX: 0.7, y: 0.7))
                    .concatenating(CGAffineTransform(translationX: center.x, y: center.y))),
                         with: .color(glow))
                // Contorno y brillo especular pintado
                var border = Path()
                border.addLines(outline)
                border.closeSubpath()
                ctx.stroke(border, with: .color(Retro.night), lineWidth: 5)
                ctx.fill(Path(CGRect(x: size.width * 0.3, y: size.height * 0.2, width: 12, height: 9)),
                         with: .color(.white.opacity(0.75)))
            }
            .shadow(color: glow.opacity(0.8), radius: 10)
        }
        .aspectRatio(0.8, contentMode: .fit)
    }
}

// MARK: - Rayos

struct SunburstView: View {
    let color: Color
    var rainbow = false
    var speed: Double = 0.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.36)
                let radius = max(size.width, size.height) * 1.2
                let rays = 18
                let rotation = t * speed * 2 * .pi
                for i in 0..<rays where i % 2 == 0 {
                    let a0 = rotation + Double(i) / Double(rays) * 2 * .pi
                    let a1 = a0 + 2 * .pi / Double(rays)
                    var p = Path()
                    p.move(to: center)
                    p.addLine(to: CGPoint(x: center.x + radius * cos(a0), y: center.y + radius * sin(a0)))
                    p.addLine(to: CGPoint(x: center.x + radius * cos(a1), y: center.y + radius * sin(a1)))
                    p.closeSubpath()
                    let c: Color = rainbow
                        ? Color(hue: (Double(i) / Double(rays) + t * 0.15).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 1)
                        : color
                    ctx.fill(p, with: .color(c.opacity(0.35)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - 120, y: center.y - 120, width: 240, height: 240)),
                         with: .radialGradient(Gradient(colors: [.white.opacity(0.55), .clear]),
                                               center: center, startRadius: 0, endRadius: 120))
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Confeti pixelado

struct ConfettiView: View {
    let rarity: Rarity
    let start: Date

    private struct Bit { let vx: Double; let vy: Double; let size: Double; let hue: Double; let spin: Double; let delay: Double }

    private var bits: [Bit] {
        var rng = SeededGenerator(seed: UInt64(rarity.tier + 1) * 7777)
        let count = 18 + rarity.tier * 22
        return (0..<count).map { _ in
            Bit(vx: .random(in: -260...260, using: &rng),
                vy: .random(in: -720 ... -260, using: &rng),
                size: .random(in: 4...9, using: &rng).rounded(),
                hue: .random(in: 0...1, using: &rng),
                spin: .random(in: 2...9, using: &rng),
                delay: .random(in: 0...0.25, using: &rng))
        }
    }

    var body: some View {
        let cached = bits
        let loops = rarity >= .legendary
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { ctx, size in
                var elapsed = timeline.date.timeIntervalSince(start)
                if loops { elapsed = elapsed.truncatingRemainder(dividingBy: 3.2) }
                guard elapsed < 3.4 else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.36)
                for b in cached {
                    let t = elapsed - b.delay
                    guard t > 0 else { continue }
                    let x = origin.x + b.vx * t
                    let y = origin.y + b.vy * t + 0.5 * 900 * t * t
                    let alpha = max(0, 1 - t / 3)
                    let color: Color = rarity == .mythic
                        ? Color(hue: b.hue, saturation: 0.85, brightness: 1)
                        : (b.hue > 0.5 ? rarity.color : Retro.cream)
                    let w = b.size * abs(cos(t * b.spin))
                    ctx.fill(Path(CGRect(x: x - w / 2, y: y, width: max(2, w), height: b.size)),
                             with: .color(color.opacity(alpha)))
                }
            }
        }
        .ignoresSafeArea()
    }
}
