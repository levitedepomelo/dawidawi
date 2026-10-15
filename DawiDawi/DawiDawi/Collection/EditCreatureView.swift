import SwiftUI
import SwiftData

/// Edición manual de todos los datos de la criatura. Nada se rellena automáticamente
/// a partir de la foto: el nombre, título, hábitat, notas y etiquetas son tuyos.
struct EditCreatureView: View {
    @Bindable var creature: Creature
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context

    @State var name = ""
    @State var epithet = ""
    @State var habitat = ""
    @State var notes = ""
    @State var tagsText = ""
    @State var favorite = false
    @State var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        if let thumb = CreatureStore.thumb(creature.id) {
                            PixelImage(image: thumb, contentMode: .fill)
                                .frame(width: 70, height: 84)
                                .clipShape(PixelRect(step: 3))
                                .overlay(PixelRect(step: 3).strokeBorder(creature.rarity.color, lineWidth: 3))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(creature.numberLabel).font(.retro(12)).foregroundStyle(Retro.yellow)
                            RarityBadge(rarity: creature.rarity, compact: true)
                            Text("Capturada: \(creature.capturedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.retro(10, weight: .semibold))
                                .foregroundStyle(Retro.cream.opacity(0.7))
                        }
                        Spacer()
                    }
                    .retroPanel()

                    field("Nombre", text: $name, placeholder: Creature.defaultName(for: creature.number))
                    field("Título / apodo", text: $epithet, placeholder: "p. ej. La reina del tejado")
                    field("Hábitat / lugar", text: $habitat, placeholder: "p. ej. Parque del barrio")
                    field("Notas", text: $notes, placeholder: "Qué hacía, cómo era, anécdotas...", multiline: true)
                    field("Etiquetas (separadas por comas)", text: $tagsText, placeholder: "naranja, dormilón, amigable")

                    Toggle(isOn: $favorite) {
                        Label("FAVORITA", systemImage: "heart.fill").font(.retro(13)).foregroundStyle(Retro.cream)
                    }
                    .tint(Retro.magenta)
                    .retroPanel()

                    Text("La rareza y la fecha de captura no se pueden editar: son el registro de tu hallazgo.")
                        .font(.retro(10, weight: .semibold))
                        .foregroundStyle(Retro.cream.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Retro.navy.ignoresSafeArea())
            .navigationTitle("EDITAR FICHA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        ChipSynth.shared.play(.back)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }.fontWeight(.heavy)
                }
            }
        }
        .onAppear(perform: load)
        .presentationDragIndicator(.visible)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.retro(11)).foregroundStyle(Retro.cyan)
            Group {
                if multiline {
                    TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Retro.cream.opacity(0.3)),
                              axis: .vertical)
                        .lineLimit(3...8)
                } else {
                    TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Retro.cream.opacity(0.3)))
                }
            }
            .font(.retro(15, weight: .bold))
            .foregroundStyle(Retro.cream)
            .padding(10)
            .background(Rectangle().fill(Retro.night))
            .overlay(Rectangle().strokeBorder(Retro.cream.opacity(0.5), lineWidth: 2))
        }
        .retroPanel(padding: 12)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        name = creature.name
        epithet = creature.epithet
        habitat = creature.habitat
        notes = creature.notes
        tagsText = creature.tags.joined(separator: ", ")
        favorite = creature.isFavorite
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        creature.name = trimmedName.isEmpty ? Creature.defaultName(for: creature.number) : trimmedName
        creature.epithet = epithet.trimmingCharacters(in: .whitespacesAndNewlines)
        creature.habitat = habitat.trimmingCharacters(in: .whitespacesAndNewlines)
        creature.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        creature.tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        creature.isFavorite = favorite
        try? context.save()
        ChipSynth.shared.play(.save)
        Haptics.success()
        dismiss()
    }
}
