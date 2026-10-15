import SwiftUI
import SwiftData
import MapKit

struct CreatureDetailView: View {
    @Bindable var creature: Creature
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    @State var mode: ViewerMode = .model
    @State var editing = false
    @State var confirmDelete = false
    @State var shareImage: UIImage?

    enum ViewerMode: String, CaseIterable, Identifiable {
        case model = "3D", sprite = "SPRITE", photo = "FOTO"
        var id: String { rawValue }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        let rarity = creature.rarity
        ScrollView {
            VStack(spacing: 16) {
                viewer(rarity)
                titleBlock(rarity)
                infoPanel(rarity)
                statsPanel(rarity)
                dossierPanel
                if let lat = creature.latitude, let lon = creature.longitude {
                    mapPanel(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                }
                actions
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(RetroBackground(floorColor: rarity.color, animated: false))
        .navigationTitle(creature.numberLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    ChipSynth.shared.play(.select)
                    editing = true
                } label: {
                    Image(systemName: "pencil").font(.system(size: 15, weight: .black))
                }
                .accessibilityLabel("Editar datos")
            }
        }
        .sheet(isPresented: $editing) {
            EditCreatureView(creature: creature)
        }
        .confirmationDialog("¿Liberar a \(creature.displayName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Liberar (borrar)", role: .destructive) { deleteCreature() }
        } message: {
            Text("Se borrará de tu colección junto con su foto y su modelo. No se puede deshacer.")
        }
        .task(id: creature.name) { shareImage = await renderShareCard() }
    }

    // MARK: Visor

    private func viewer(_ rarity: Rarity) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                switch mode {
                case .model:
                    CreatureModelView(creatureID: creature.id, rarity: rarity, seed: creature.seed, showcase: true)
                case .sprite:
                    ZStack {
                        Color(red: 0.08, green: 0.08, blue: 0.12)
                        CheckerPattern().opacity(0.25)
                        if let sprite = CreatureStore.sprite(creature.id) {
                            PixelImage(image: sprite).padding(20)
                        }
                    }
                case .photo:
                    ZStack {
                        Color.black
                        if let photo = CreatureStore.photo(creature.id) {
                            Image(uiImage: photo).resizable().scaledToFit()
                        }
                    }
                }
                RarityBadge(rarity: rarity).padding(10)
            }
            .frame(height: 340)
            .clipShape(PixelRect(step: 6))
            .overlay(PixelRect(step: 6).strokeBorder(rarity.color, lineWidth: 4))
            .shadow(color: .black.opacity(0.8), radius: 0, x: 5, y: 5)

            HStack(spacing: 8) {
                ForEach(ViewerMode.allCases) { m in
                    Button {
                        ChipSynth.shared.play(.blip)
                        mode = m
                    } label: {
                        Text(m.rawValue)
                            .font(.retro(12))
                            .foregroundStyle(mode == m ? Retro.night : Retro.cream)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(PixelRect(step: 2).fill(mode == m ? Retro.yellow : Retro.night.opacity(0.9)))
                            .overlay(PixelRect(step: 2).strokeBorder(Retro.cream.opacity(0.7), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            if mode == .model {
                Text("Arrastra para girar el modelo")
                    .font(.retro(10, weight: .semibold))
                    .foregroundStyle(Retro.cream.opacity(0.6))
            }
        }
    }

    private func titleBlock(_ rarity: Rarity) -> some View {
        VStack(spacing: 6) {
            Text(creature.displayName)
                .font(.retroTitle(30))
                .foregroundStyle(Retro.cream)
                .shadow(color: rarity.darkColor, radius: 0, x: 3, y: 3)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
            if !creature.epithet.isEmpty {
                Text("« \(creature.epithet) »")
                    .font(.retro(13, weight: .bold))
                    .foregroundStyle(Retro.yellow)
            }
            StarsRow(count: rarity.stars, size: 16, color: rarity == .mythic ? Retro.magenta : Retro.yellow)
        }
        .frame(maxWidth: .infinity)
    }

    private func infoPanel(_ rarity: Rarity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Registro de captura", icon: "doc.text.fill")
            infoRow("Nº", creature.numberLabel)
            infoRow("Fecha", Self.dateFormatter.string(from: creature.capturedAt).capitalized)
            infoRow("Rareza", rarity.title)
            infoRow("Lugar", creature.placeName ?? (creature.hasLocation ? "Coordenadas guardadas" : "Sin ubicación"))
            infoRow("Motor", creature.generator == "remote" ? "IA remota + modelado local" : "Modelado local")
        }
        .retroPanel()
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label.uppercased())
                .font(.retro(11))
                .foregroundStyle(Retro.cyan)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.retro(12, weight: .semibold))
                .foregroundStyle(Retro.cream)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statsPanel(_ rarity: Rarity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Atributos", icon: "bolt.fill")
                Text("PODER \(creature.totalPower)").font(.retro(12)).foregroundStyle(Retro.yellow)
            }
            statRow("VIT", creature.vitality, Retro.green)
            statRow("FUE", creature.power, Retro.orange)
            statRow("AGI", creature.agility, Retro.cyan)
            statRow("ENC", creature.charm, Retro.magenta)
            Text("Atributos de juego generados al azar al capturarla (mejores cuanto más rara).")
                .font(.retro(9, weight: .semibold))
                .foregroundStyle(Retro.cream.opacity(0.5))
        }
        .retroPanel()
    }

    private func statRow(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.retro(12)).foregroundStyle(Retro.cream).frame(width: 36, alignment: .leading)
            PixelBar(value: Double(value) / 99, segments: 20, color: color, height: 10)
            Text("\(value)").font(.retro(12)).foregroundStyle(color).frame(width: 28, alignment: .trailing)
        }
    }

    private var dossierPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Ficha personal", icon: "pencil.and.list.clipboard")
                Text("\(Int(creature.dossierProgress * 100))%").font(.retro(12)).foregroundStyle(Retro.green)
            }
            dossierRow("Título", creature.epithet)
            dossierRow("Hábitat", creature.habitat)
            dossierRow("Notas", creature.notes)
            if creature.tags.isEmpty {
                dossierRow("Etiquetas", "")
            } else {
                FlowTags(tags: creature.tags)
            }
            Button {
                ChipSynth.shared.play(.select)
                editing = true
            } label: {
                Label("EDITAR FICHA", systemImage: "pencil").frame(maxWidth: .infinity)
            }
            .buttonStyle(RetroButtonStyle(color: Retro.cyan, compact: true))
        }
        .retroPanel()
    }

    private func dossierRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.retro(10)).foregroundStyle(Retro.cyan)
            Text(value.isEmpty ? "— sin rellenar —" : value)
                .font(.retro(12, weight: .semibold))
                .foregroundStyle(value.isEmpty ? Retro.cream.opacity(0.35) : Retro.cream)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mapPanel(_ coordinate: CLLocationCoordinate2D) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Lugar de captura", icon: "map.fill")
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 700, longitudinalMeters: 700)),
                interactionModes: []) {
                Marker(creature.displayName, systemImage: "pawprint.fill", coordinate: coordinate)
                    .tint(creature.rarity.color)
            }
            .frame(height: 170)
            .clipShape(Rectangle())
            .overlay(Rectangle().strokeBorder(Retro.cream.opacity(0.6), lineWidth: 2))
            Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                .font(.retro(10))
                .foregroundStyle(Retro.cream.opacity(0.6))
        }
        .retroPanel()
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                creature.isFavorite.toggle()
                try? context.save()
                Haptics.tap(.medium)
            } label: {
                Image(systemName: creature.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .black))
                    .frame(width: 30)
            }
            .buttonStyle(RetroButtonStyle(color: creature.isFavorite ? Retro.magenta : Retro.cream))
            .accessibilityLabel(creature.isFavorite ? "Quitar de favoritas" : "Marcar favorita")

            if let shareImage {
                ShareLink(item: Image(uiImage: shareImage),
                          preview: SharePreview(creature.displayName, image: Image(uiImage: shareImage))) {
                    Label("COMPARTIR", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(RetroButtonStyle(color: Retro.yellow))
            }

            Button {
                confirmDelete = true
            } label: {
                Image(systemName: "trash.fill").font(.system(size: 18, weight: .black)).frame(width: 30)
            }
            .buttonStyle(RetroButtonStyle(color: Retro.orange))
            .accessibilityLabel("Liberar criatura")
        }
        .padding(.bottom, 10)
    }

    // MARK: Acciones

    private func deleteCreature() {
        let target = creature
        ChipSynth.shared.play(.back)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            CreatureStore.delete(target.id)
            context.delete(target)
            try? context.save()
        }
    }

    @MainActor
    private func renderShareCard() -> UIImage? {
        let renderer = ImageRenderer(content: ShareCard(creature: creature).frame(width: 360, height: 480))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// Tarjeta para compartir (imagen generada con ImageRenderer).
struct ShareCard: View {
    let creature: Creature
    var body: some View {
        let rarity = creature.rarity
        VStack(spacing: 10) {
            Text("DAWIDAWI").font(.retroTitle(26)).foregroundStyle(Retro.yellow)
                .shadow(color: Retro.magenta, radius: 0, x: 3, y: 3)
            Group {
                if let thumb = CreatureStore.thumb(creature.id) {
                    PixelImage(image: thumb, contentMode: .fill)
                } else {
                    Color.black
                }
            }
            .frame(width: 260, height: 300)
            .clipShape(PixelRect(step: 6))
            .overlay(PixelRect(step: 6).strokeBorder(rarity.color, lineWidth: 5))
            Text(creature.displayName).font(.retro(20)).foregroundStyle(Retro.cream).lineLimit(1)
            HStack {
                RarityBadge(rarity: rarity)
                Text(creature.numberLabel).font(.retro(13)).foregroundStyle(Retro.cream)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Retro.navy, Retro.night], startPoint: .top, endPoint: .bottom)
        )
    }
}

struct CheckerPattern: View {
    var cell: CGFloat = 16
    var body: some View {
        Canvas { ctx, size in
            let cols = Int(size.width / cell) + 1, rows = Int(size.height / cell) + 1
            for r in 0..<rows {
                for c in 0..<cols where (r + c) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)),
                             with: .color(.white))
                }
            }
        }
    }
}

struct FlowTags: View {
    let tags: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ETIQUETAS").font(.retro(10)).foregroundStyle(Retro.cyan)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.retro(11))
                            .foregroundStyle(Retro.night)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PixelRect(step: 2).fill(Retro.cream))
                    }
                }
            }
        }
    }
}
