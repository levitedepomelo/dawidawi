import SwiftUI
import SwiftData

enum MainTab: Hashable { case collection, stats, settings }

struct RootView: View {
    @EnvironmentObject var settings: AppSettings
    @State var tab: MainTab = .collection
    @State var showTitle = true
    @State var showCapture = false
    @State var path = NavigationPath()
    @Environment(\.modelContext) var context

    var body: some View {
        ZStack {
            Group {
                switch tab {
                case .collection: CollectionView(path: $path, onCapture: openCapture)
                case .stats: StatsView(onCapture: openCapture)
                case .settings: SettingsView()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RetroTabBar(tab: $tab, onCapture: openCapture, onHome: {
                    ChipSynth.shared.play(.select)
                    withAnimation(.easeInOut(duration: 0.35)) { showTitle = true }
                })
            }

            if showTitle && (settings.showTitleScreen || DemoMode.scene == "title") {
                TitleScreen {
                    withAnimation(.easeInOut(duration: 0.35)) { showTitle = false }
                }
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .crt()
        .fullScreenCover(isPresented: $showCapture) {
            CaptureView(onFinished: { creature in
                guard let creature else { return }
                tab = .collection
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    path = NavigationPath()
                    path.append(creature)
                }
            })
            .environmentObject(settings)
        }
        .onAppear { ChipSynth.shared.prewarm() }
        .task { await runDemoIfNeeded() }
    }

    /// Solo con argumentos de lanzamiento (capturas automáticas de CI). Ver DemoMode.
    private func runDemoIfNeeded() async {
        guard let scene = DemoMode.scene else { return }
        showTitle = scene == "title"
        await DemoMode.seedIfNeeded(context: context, settings: settings)
        switch scene {
        case "stats": tab = .stats
        case "settings": tab = .settings
        case "capture", "reveal": showCapture = true
        case "detail":
            let all = (try? context.fetch(FetchDescriptor<Creature>(sortBy: [SortDescriptor(\.number)]))) ?? []
            if let target = all.first(where: { $0.number == DemoMode.detailNumber }) ?? all.first { path.append(target) }
        default: break
        }
    }

    private func openCapture() {
        ChipSynth.shared.play(.select)
        Haptics.tap(.medium)
        showCapture = true
    }
}

/// Dock de cristal flotante con botones de gel redondos y el orbe de captura en el centro.
struct RetroTabBar: View {
    @Binding var tab: MainTab
    let onCapture: () -> Void
    var onHome: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 0) {
                AeroDockButton(icon: "house.fill", title: "Inicio", active: false, tint: Retro.orange, action: onHome)
                tabButton(.collection, icon: "square.grid.2x2.fill", title: "Colección", tint: Retro.cyan)
            }
            .frame(maxWidth: .infinity)

            Button(action: onCapture) { CaptureOrb() }
                .buttonStyle(.plain)
                .offset(y: -16)
                .accessibilityLabel("Capturar criatura")

            HStack(spacing: 0) {
                tabButton(.stats, icon: "chart.bar.fill", title: "Logros", tint: Retro.green)
                tabButton(.settings, icon: "gearshape.fill", title: "Ajustes", tint: Color(white: 0.7))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.55), Retro.panelLight.opacity(0.35)],
                                         startPoint: .top, endPoint: .bottom))
                GlossHighlight(opacity: 0.5).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.95), lineWidth: 1.5)
            }
            .shadow(color: Retro.night.opacity(0.3), radius: 16, x: 0, y: 8)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    private func tabButton(_ value: MainTab, icon: String, title: String, tint: Color) -> some View {
        AeroDockButton(icon: icon, title: title, active: tab == value, tint: tint) {
            guard tab != value else { return }
            ChipSynth.shared.play(.select)
            Haptics.tap(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { tab = value }
        }
    }
}

/// Botón redondo de gel con icono (como los menús de consola de mediados de los 2000).
struct AeroDockButton: View {
    let icon: String
    let title: String
    let active: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle().fill(LinearGradient(colors: active ? [tint.mix(.white, 0.5), tint, tint.mix(.black, 0.25)]
                                                                : [.white, Color(red: 0.86, green: 0.93, blue: 0.98)],
                                                 startPoint: .top, endPoint: .bottom))
                    GlossHighlight(opacity: 0.8).clipShape(Circle()).padding(2)
                    Circle().strokeBorder(active ? Color.white : Color(red: 0.6, green: 0.78, blue: 0.9), lineWidth: 1.5)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(active ? Color.white : Retro.navy)
                        .shadow(color: active ? tint.mix(.black, 0.5) : .clear, radius: 1, x: 0, y: 1)
                }
                .frame(width: 44, height: 44)
                .shadow(color: active ? tint.opacity(0.8) : Retro.night.opacity(0.2), radius: active ? 8 : 3, x: 0, y: 2)
                .scaleEffect(active ? 1.06 : 1)
                Text(title)
                    .font(.retro(10, weight: .semibold))
                    .foregroundStyle(Retro.night)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Orbe de captura: esfera de gel aguamarina con reflejo y halo.
struct CaptureOrb: View {
    var size: CGFloat = 74
    @State var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(Retro.cyan.opacity(0.35)).scaleEffect(pulse ? 1.25 : 1.05).blur(radius: 6)
            Circle().fill(RadialGradient(colors: [Color(red: 0.55, green: 0.95, blue: 1), Color(red: 0.05, green: 0.55, blue: 0.95),
                                                  Color(red: 0.02, green: 0.30, blue: 0.70)],
                                         center: UnitPoint(x: 0.5, y: 0.75), startRadius: 2, endRadius: size * 0.6))
            GlossHighlight(opacity: 0.85).clipShape(Circle()).padding(3)
            Circle().strokeBorder(Color.white, lineWidth: 2.5)
            Image(systemName: "camera.fill")
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(Color.white)
                .shadow(color: Retro.night.opacity(0.6), radius: 2, x: 0, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.0, green: 0.35, blue: 0.8).opacity(0.5), radius: 10, x: 0, y: 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Pantalla de inicio: logo de cristal, tu criatura estrella dentro de una burbuja y "toca para empezar".
struct TitleScreen: View {
    let onStart: () -> Void
    @Query(sort: \Creature.rarityRaw) var creatures: [Creature]
    @State var bob = false
    @State var logoIn = false

    private var hero: Creature? {
        creatures.max { a, b in
            a.rarity == b.rarity ? a.totalPower < b.totalPower : a.rarity < b.rarity
        }
    }

    var body: some View {
        ZStack {
            RetroBackground(floorColor: Retro.cyan)
            VStack(spacing: 16) {
                Spacer(minLength: 40)
                ExtrudedText(text: "DawiDawi", size: 64)
                    .scaleEffect(logoIn ? 1 : 0.4)
                    .opacity(logoIn ? 1 : 0)

                Text("Colecciona lo que encuentres")
                    .font(.retro(15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .aeroTextShadow()

                ZStack {
                    if let hero {
                        CreatureModelView(creatureID: hero.id, rarity: hero.rarity, seed: hero.seed,
                                          showcase: true, interactive: false)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 80, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .shadow(color: Retro.night.opacity(0.4), radius: 6)
                    }
                    // Burbuja de cristal
                    Circle().fill(RadialGradient(colors: [.clear, .white.opacity(0.08), .white.opacity(0.45)],
                                                 center: .center, startRadius: 60, endRadius: 135))
                    GlossHighlight(opacity: 0.55).clipShape(Circle()).padding(10)
                    Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                }
                .frame(width: 260, height: 260)
                .shadow(color: Retro.night.opacity(0.3), radius: 18, x: 0, y: 12)
                .offset(y: bob ? -8 : 8)

                Spacer()

                Text("Toca para empezar")
                    .font(.retro(18))
                    .foregroundStyle(Retro.night)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 14)
                    .background(
                        ZStack {
                            Capsule().fill(LinearGradient(colors: [.white, Color(red: 0.8, green: 0.93, blue: 1)],
                                                          startPoint: .top, endPoint: .bottom))
                            GlossHighlight(opacity: 0.9).clipShape(Capsule())
                            Capsule().strokeBorder(Color.white, lineWidth: 1.5)
                        }
                        .shadow(color: Retro.night.opacity(0.3), radius: 10, x: 0, y: 6)
                    )
                    .scaleEffect(bob ? 1.04 : 0.98)

                Text("\(creatures.count) criaturas en tu colección")
                    .font(.retro(12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .aeroTextShadow()
                    .padding(.bottom, 36)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ChipSynth.shared.play(.fanfare(.common))
            Haptics.tap(.medium)
            onStart()
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.1)) { logoIn = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { bob = true }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("DawiDawi. Toca para empezar")
    }
}

/// Carga el sprite guardado de una criatura y monta su escenario 3D.
struct CreatureModelView: View {
    let creatureID: UUID
    let rarity: Rarity
    let seed: Int
    var showcase = true
    var interactive = true
    var pixelScale: CGFloat = 0.8
    @EnvironmentObject var settings: AppSettings
    @State var stage: RetroStage?
    @State var failed = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Retro.skyTop, Retro.skyBottom], startPoint: .top, endPoint: .bottom)
            if let stage {
                RetroSceneView(stage: stage, pixelScale: pixelScale, interactive: interactive)
            } else if failed {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 26, weight: .black))
                    Text("MODELO NO ENCONTRADO").font(.retro(11))
                }
                .foregroundStyle(Retro.orange)
            } else {
                BlinkingText(text: "CARGANDO...", font: .retro(12))
            }
        }
        .task(id: creatureID) {
            // Lectura de ficheros y construcción del modelo fuera del hilo principal (sin tirones al abrir)
            let id = creatureID, rarity = rarity, seed = seed, showcase = showcase
            let meshDensity = settings.meshDensity
            let built = await Task.detached(priority: .userInitiated) { () -> RetroStage? in
                guard let sprite = CreatureStore.sprite(id)?.cgImage else { return nil }
                let rig = CreatureStore.rig(id)
                return RetroStage(sprite: sprite, rarity: rarity, seed: seed,
                                  meshDensity: meshDensity, showcase: showcase,
                                  rig: rig, photo: rig != nil ? CreatureStore.photo(id) : nil,
                                  cutout: CreatureStore.cutout(id), face: CreatureStore.face(id))
            }.value
            guard !Task.isCancelled else { return }
            if let built { stage = built } else { failed = true }
        }
    }
}
