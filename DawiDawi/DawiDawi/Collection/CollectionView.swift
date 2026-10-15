import SwiftUI
import SwiftData

struct CollectionView: View {
    @Binding var path: NavigationPath
    var onCapture: () -> Void

    @Environment(\.modelContext) var context
    @Query(sort: \Creature.capturedAt, order: .reverse) var creatures: [Creature]
    @State var filter: Rarity? = nil
    @State var favoritesOnly = false
    @State var sort: SortMode = .newest
    @State var search = ""
    @State var pendingDelete: Creature?

    enum SortMode: String, CaseIterable, Identifiable {
        case newest = "Recientes", oldest = "Antiguas", rarity = "Rareza", name = "Nombre", power = "Poder"
        var id: String { rawValue }
    }

    private var stats: CollectionStats { CollectionStats(creatures) }

    private var filtered: [Creature] {
        var list = creatures
        if let filter { list = list.filter { $0.rarity == filter } }
        if favoritesOnly { list = list.filter(\.isFavorite) }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter {
                $0.displayName.localizedCaseInsensitiveContains(q) ||
                $0.epithet.localizedCaseInsensitiveContains(q) ||
                $0.habitat.localizedCaseInsensitiveContains(q) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(q) } ||
                $0.numberLabel.contains(q)
            }
        }
        switch sort {
        case .newest: list.sort { $0.capturedAt > $1.capturedAt }
        case .oldest: list.sort { $0.capturedAt < $1.capturedAt }
        case .rarity: list.sort { $0.rarity == $1.rarity ? $0.capturedAt > $1.capturedAt : $0.rarity > $1.rarity }
        case .name: list.sort { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        case .power: list.sort { $0.totalPower > $1.totalPower }
        }
        return list
    }

    private static let columns = [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                RetroBackground(floorColor: Retro.magenta, animated: false)
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        if !creatures.isEmpty {
                            searchBar
                            filterChips
                        }
                        if creatures.isEmpty {
                            emptyState
                        } else if filtered.isEmpty {
                            Text("NINGUNA CRIATURA COINCIDE")
                                .font(.retro(13))
                                .foregroundStyle(Retro.cream)
                                .retroPanel()
                                .padding(.top, 20)
                        } else {
                            LazyVGrid(columns: Self.columns, spacing: 14) {
                                ForEach(filtered) { creature in
                                    NavigationLink(value: creature) {
                                        CreatureCard(creature: creature)
                                    }
                                    .buttonStyle(CardPressStyle())
                                    .contextMenu { contextMenu(for: creature) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Creature.self) { creature in
                CreatureDetailView(creature: creature)
            }
            .confirmationDialog("¿Liberar esta criatura?", isPresented: Binding(get: { pendingDelete != nil },
                                                                               set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Liberar (borrar)", role: .destructive) {
                    if let c = pendingDelete { delete(c) }
                }
            } message: {
                Text("Se borrará de tu colección junto con su foto y su modelo. No se puede deshacer.")
            }
        }
    }

    // MARK: Piezas

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                ExtrudedText(text: "MI COLECCIÓN", size: 28, depth: 4)
                Spacer()
                Text("\(creatures.count)")
                    .font(.retro(26, weight: .black))
                    .foregroundStyle(Retro.yellow)
            }
            HStack(spacing: 10) {
                Text("COMPLETADO").font(.retro(11)).foregroundStyle(Retro.cream)
                PixelBar(value: stats.completion, segments: 20, color: Retro.green)
                Text("\(Int((stats.completion * 100).rounded()))%")
                    .font(.retro(13)).foregroundStyle(Retro.green)
                    .frame(minWidth: 42, alignment: .trailing)
            }
            HStack(spacing: 6) {
                ForEach(Rarity.allCases) { r in
                    let found = stats.count(r) > 0
                    Text(found ? r.shortCode : "?")
                        .font(.retro(10))
                        .foregroundStyle(found ? (r == .common ? Retro.night : .white) : Retro.cream.opacity(0.4))
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background(PixelRect(step: 2).fill(found ? AnyShapeStyle(r.gradient) : AnyShapeStyle(Retro.night)))
                        .overlay(PixelRect(step: 2).strokeBorder(found ? r.color : Retro.cream.opacity(0.2), lineWidth: 1.5))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rarezas descubiertas: \(stats.tiersDiscovered) de 6")
        }
        .retroPanel()
        .padding(.top, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .black)).foregroundStyle(Retro.yellow)
            TextField("", text: $search, prompt: Text("Buscar por nombre, lugar, etiqueta...").foregroundStyle(Retro.cream.opacity(0.35)))
                .font(.retro(13, weight: .bold))
                .foregroundStyle(Retro.cream)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Retro.cream.opacity(0.6))
                }
            }
            Menu {
                Picker("Ordenar", selection: $sort) {
                    ForEach(SortMode.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 14, weight: .black)).foregroundStyle(Retro.yellow)
            }
            .accessibilityLabel("Ordenar")
        }
        .padding(10)
        .background(Rectangle().fill(Retro.night.opacity(0.92)))
        .overlay(Rectangle().strokeBorder(Retro.cream.opacity(0.5), lineWidth: 2))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "TODAS \(creatures.count)", active: filter == nil && !favoritesOnly, color: Retro.cream) {
                    filter = nil; favoritesOnly = false
                }
                chip(title: "♥ \(stats.favorites)", active: favoritesOnly, color: Retro.magenta) {
                    favoritesOnly.toggle()
                }
                ForEach(Rarity.allCases) { r in
                    chip(title: "\(r.title.uppercased()) \(stats.count(r))", active: filter == r, color: r.color) {
                        filter = filter == r ? nil : r
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
    }

    private func chip(title: String, active: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            ChipSynth.shared.play(.blip)
            Haptics.tap(.light)
            withAnimation(.snappy) { action() }
        } label: {
            Text(title)
                .font(.retro(11))
                .foregroundStyle(active ? Retro.night : color)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(PixelRect(step: 2).fill(active ? color : Retro.night.opacity(0.9)))
                .overlay(PixelRect(step: 2).strokeBorder(color, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            CapsuleOrb(glow: Retro.cyan, intensity: 0.3)
                .frame(width: 110, height: 110)
                .padding(.top, 10)
            Text("TU COLECCIÓN ESTÁ VACÍA")
                .font(.retro(16))
                .foregroundStyle(Retro.yellow)
            Text("Sal a explorar. Cuando veas un animal (o cualquier criatura), hazle una foto y DawiDawi lo convertirá en un modelo retro con una rareza aleatoria.")
                .font(.retro(12, weight: .semibold))
                .foregroundStyle(Retro.cream)
                .multilineTextAlignment(.center)
            Button(action: onCapture) {
                Label("PRIMERA CAPTURA", systemImage: "camera.fill")
            }
            .buttonStyle(RetroButtonStyle(color: Retro.magenta, textColor: Retro.cream))
        }
        .frame(maxWidth: .infinity)
        .retroPanel()
        .padding(.top, 10)
    }

    @ViewBuilder
    private func contextMenu(for creature: Creature) -> some View {
        Button {
            creature.isFavorite.toggle()
            try? context.save()
        } label: {
            Label(creature.isFavorite ? "Quitar de favoritas" : "Marcar favorita",
                  systemImage: creature.isFavorite ? "heart.slash" : "heart")
        }
        Button(role: .destructive) {
            pendingDelete = creature
        } label: {
            Label("Liberar", systemImage: "trash")
        }
    }

    private func delete(_ creature: Creature) {
        CreatureStore.delete(creature.id)
        context.delete(creature)
        try? context.save()
        pendingDelete = nil
        ChipSynth.shared.play(.back)
    }
}

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
