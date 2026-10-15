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
                RetroTabBar(tab: $tab, onCapture: openCapture)
            }

            if showTitle && settings.showTitleScreen {
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
            let first = try? context.fetch(FetchDescriptor<Creature>(sortBy: [SortDescriptor(\.number)])).first
            if let first { path.append(first) }
        default: break
        }
    }

    private func openCapture() {
        ChipSynth.shared.play(.select)
        Haptics.tap(.medium)
        showCapture = true
    }
}

/// Barra inferior tipo menú de consola, con el botón de captura destacado.
struct RetroTabBar: View {
    @Binding var tab: MainTab
    let onCapture: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            item(.collection, icon: "square.grid.3x3.fill", title: "COLECCIÓN")
            Button(action: onCapture) {
                VStack(spacing: 2) {
                    ZStack {
                        LowPolyCircle(sides: 10).fill(Retro.shadow).offset(y: 4)
                        LowPolyCircle(sides: 10).fill(LinearGradient(colors: [Retro.magenta, Color(red: 0.6, green: 0.05, blue: 0.3)],
                                                                    startPoint: .top, endPoint: .bottom))
                        LowPolyCircle(sides: 10).strokeBorderCompat(Retro.cream, lineWidth: 3)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(Retro.cream)
                    }
                    .frame(width: 66, height: 66)
                    Text("CAPTURAR").font(.retro(9)).foregroundStyle(Retro.yellow)
                }
                .offset(y: -10)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Capturar criatura")
            item(.stats, icon: "chart.bar.fill", title: "STATS")
            item(.settings, icon: "gearshape.fill", title: "AJUSTES")
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .background(
            ZStack(alignment: .top) {
                Retro.night
                Rectangle().fill(Retro.cream).frame(height: 3)
                Rectangle().fill(Retro.magenta.opacity(0.6)).frame(height: 2).offset(y: 3)
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func item(_ value: MainTab, icon: String, title: String) -> some View {
        Button {
            guard tab != value else { return }
            ChipSynth.shared.play(.select)
            Haptics.tap(.light)
            tab = value
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 18, weight: .black))
                Text(title).font(.retro(9))
                Rectangle().fill(tab == value ? Retro.yellow : .clear).frame(width: 26, height: 3)
            }
            .foregroundStyle(tab == value ? Retro.yellow : Retro.cream.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.capitalized)
    }
}

/// Pantalla de título "PULSA START" (se puede desactivar en Ajustes).
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
            RetroBackground(floorColor: Retro.magenta)
            VStack(spacing: 18) {
                Spacer(minLength: 30)
                VStack(spacing: -6) {
                    ExtrudedText(text: "DAWI", size: 72)
                    ExtrudedText(text: "DAWI", size: 72, fill: [Retro.cyan, Color(red: 0.2, green: 0.4, blue: 1)],
                                 depthColor: Color(red: 0.08, green: 0.1, blue: 0.4))
                }
                .rotationEffect(.degrees(-4))
                .scaleEffect(logoIn ? 1 : 0.2)
                .opacity(logoIn ? 1 : 0)

                Text("COLECCIONA LO QUE ENCUENTRES")
                    .font(.retro(12))
                    .foregroundStyle(Retro.cream)
                    .shadow(color: .black, radius: 0, x: 2, y: 2)

                Group {
                    if let hero {
                        CreatureModelView(creatureID: hero.id, rarity: hero.rarity, seed: hero.seed,
                                          showcase: true, interactive: false)
                            .frame(width: 230, height: 230)
                            .clipShape(PixelRect(step: 6))
                            .overlay(PixelRect(step: 6).strokeBorder(hero.rarity.color, lineWidth: 4))
                    } else {
                        CapsuleOrb(glow: Retro.yellow, intensity: 0.4)
                            .frame(width: 130, height: 130)
                            .offset(y: bob ? -10 : 8)
                            .frame(height: 230)
                    }
                }

                Spacer()
                BlinkingText(text: "PULSA START", font: .retro(22), color: Retro.yellow)
                Text("© 2026 DAWIDAWI · \(creatures.count) CRIATURAS")
                    .font(.retro(10))
                    .foregroundStyle(Retro.cream.opacity(0.6))
                    .padding(.bottom, 30)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            ChipSynth.shared.play(.fanfare(.common))
            Haptics.tap(.medium)
            onStart()
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.55).delay(0.1)) { logoIn = true }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bob = true }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("DawiDawi. Pulsa para empezar")
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
            Color.black
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
            guard let sprite = CreatureStore.sprite(creatureID)?.cgImage else { failed = true; return }
            stage = RetroStage(sprite: sprite, rarity: rarity, seed: seed,
                               meshDensity: settings.meshDensity, showcase: showcase)
        }
    }
}
