import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @AppStorage("gen.style") var modelStyle = "figure"
    @ObservedObject var location = LocationProvider.shared
    @Environment(\.modelContext) var context
    @Query var creatures: [Creature]
    @State var apiKeyDraft = ""
    @State var confirmWipe = false
    @State var simulation: [Rarity: Int] = [:]

    var body: some View {
        ZStack {
            RetroBackground(floorColor: Retro.yellow, animated: false)
            ScrollView {
                VStack(spacing: 16) {
                    ExtrudedText(text: "AJUSTES", size: 30, depth: 4)
                        .padding(.top, 10)
                    probabilitiesPanel
                    generationPanel
                    experiencePanel
                    privacyPanel
                    dataPanel
                    aboutPanel
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .confirmationDialog("¿Borrar TODA la colección?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Borrar \(creatures.count) criaturas", role: .destructive) { wipe() }
        } message: {
            Text("Se eliminarán todas las criaturas, fotos y modelos de este iPhone. No se puede deshacer.")
        }
    }

    // MARK: Probabilidades

    private var probabilitiesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Probabilidades de rareza", icon: "dice.fill")
            Text("Ajusta el peso de cada rareza. Las probabilidades se normalizan automáticamente.")
                .font(.retro(10, weight: .semibold))
                .foregroundStyle(Retro.cream.opacity(0.65))
            ForEach(Rarity.allCases) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(r.title.uppercased()).font(.retro(11)).foregroundStyle(r.color)
                        Spacer()
                        Text(probabilityLabel(r)).font(.retro(11)).foregroundStyle(Retro.cream)
                    }
                    // Escala logarítmica: permite ajustar con precisión valores muy pequeños (míticos)
                    Slider(value: Binding(
                        get: { log10(max(0.01, settings.weight(r))) },
                        set: { settings.weights[r] = (pow(10, $0) * 100).rounded() / 100 }
                    ), in: -2...2)
                    .tint(r.color)
                }
            }
            HStack(spacing: 10) {
                Button("RESTABLECER") {
                    settings.resetWeights()
                    simulation = [:]
                }
                .buttonStyle(RetroButtonStyle(color: Retro.cream, compact: true))
                Button("SIMULAR 1000") { simulate() }
                    .buttonStyle(RetroButtonStyle(color: Retro.cyan, compact: true))
            }
            if !simulation.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RESULTADO DE 1000 TIRADAS:").font(.retro(10)).foregroundStyle(Retro.yellow)
                    ForEach(Rarity.allCases) { r in
                        HStack {
                            Text(r.title).foregroundStyle(r.color)
                            Spacer()
                            Text("\(simulation[r] ?? 0)").foregroundStyle(Retro.cream)
                        }
                        .font(.retro(10))
                    }
                }
                .padding(10)
                .background(Rectangle().fill(Retro.night))
            }
        }
        .retroPanel()
    }

    private func probabilityLabel(_ r: Rarity) -> String {
        let p = settings.probability(r)
        guard p > 0 else { return "0%" }
        let oneIn = Int((1 / p).rounded())
        return String(format: p < 0.01 ? "%.2f%%" : "%.1f%%", p * 100) + (oneIn > 1 ? "  (1 de \(oneIn))" : "")
    }

    private func simulate() {
        var g = SystemRandomNumberGenerator()
        var result: [Rarity: Int] = [:]
        for _ in 0..<1000 { result[AppSettings.roll(weights: settings.weights, using: &g), default: 0] += 1 }
        withAnimation { simulation = result }
        ChipSynth.shared.play(.select)
    }

    // MARK: Generación

    private var generationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Motor de generación", icon: "cube.transparent.fill")
            Picker("Motor", selection: $settings.generationMode) {
                ForEach(GenerationMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if settings.generationMode == .local {
                Text("100 % en el iPhone y sin conexión: recorta la silueta del sujeto (Vision), la pixela con paleta de 15 bits y tramado, y la convierte en un modelo 3D low-poly facetado.")
                    .font(.retro(10, weight: .semibold))
                    .foregroundStyle(Retro.cream.opacity(0.7))
            } else {
                Text("Envía la foto a un servicio de IA de imagen (compatible con /v1/images/edits de OpenAI) para que la redibuje con estilo PS1/N64; después se modela en 3D localmente. Si falla o no hay conexión, se usa el motor local automáticamente.")
                    .font(.retro(10, weight: .semibold))
                    .foregroundStyle(Retro.cream.opacity(0.7))
                labeledField("API key", trailing: settings.hasAPIKey ? "GUARDADA ✓" : "SIN CONFIGURAR") {
                    SecureField("", text: $apiKeyDraft, prompt: Text(settings.hasAPIKey ? "•••••••• (pega otra para cambiarla)" : "sk-...").foregroundStyle(Retro.cream.opacity(0.3)))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                HStack(spacing: 10) {
                    Button("GUARDAR KEY") {
                        settings.setAPIKey(apiKeyDraft)
                        apiKeyDraft = ""
                        ChipSynth.shared.play(.save)
                    }
                    .buttonStyle(RetroButtonStyle(color: Retro.green, compact: true))
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if settings.hasAPIKey {
                        Button("BORRAR KEY") { settings.setAPIKey("") }
                            .buttonStyle(RetroButtonStyle(color: Retro.orange, compact: true))
                    }
                }
                labeledField("Modelo", trailing: nil) {
                    TextField("", text: $settings.remoteModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                labeledField("Endpoint", trailing: nil) {
                    TextField("", text: $settings.remoteEndpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Text("La key se guarda cifrada en el Llavero del iPhone. La foto solo se envía cuando capturas en este modo.")
                    .font(.retro(9, weight: .semibold))
                    .foregroundStyle(Retro.cream.opacity(0.5))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("RESOLUCIÓN DE TEXTURA").font(.retro(10)).foregroundStyle(Retro.cyan)
                Picker("Textura", selection: $settings.textureResolution) {
                    Text("48px").tag(48)
                    Text("64px").tag(64)
                    Text("80px").tag(80)
                    Text("112px").tag(112)
                }
                .pickerStyle(.segmented)
                Text("ESTILO DEL MODELO 3D").font(.retro(10)).foregroundStyle(Retro.cyan).padding(.top, 4)
                Picker("Estilo", selection: $modelStyle) {
                    Text("Muñeco").tag("figure")
                    Text("Silueta").tag("silhouette")
                }
                .pickerStyle(.segmented)
                Text("DENSIDAD DE POLÍGONOS (SILUETA)").font(.retro(10)).foregroundStyle(Retro.cyan).padding(.top, 4)
                Picker("Polígonos", selection: $settings.meshDensity) {
                    Text("Tosco").tag(18)
                    Text("PS1").tag(26)
                    Text("N64").tag(34)
                    Text("Fino").tag(42)
                }
                .pickerStyle(.segmented)
                Text("Los cambios se aplican a nuevas capturas (la textura) y a cómo se muestran los modelos (los polígonos).")
                    .font(.retro(9, weight: .semibold))
                    .foregroundStyle(Retro.cream.opacity(0.5))
            }
        }
        .retroPanel()
    }

    private func labeledField<Content: View>(_ label: String, trailing: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label.uppercased()).font(.retro(10)).foregroundStyle(Retro.cyan)
                Spacer()
                if let trailing { Text(trailing).font(.retro(9)).foregroundStyle(Retro.green) }
            }
            content()
                .font(.retro(13, weight: .bold))
                .foregroundStyle(Retro.cream)
                .padding(9)
                .background(Rectangle().fill(Retro.night))
                .overlay(Rectangle().strokeBorder(Retro.cream.opacity(0.5), lineWidth: 2))
        }
    }

    // MARK: Experiencia

    private var experiencePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Experiencia", icon: "gamecontroller.fill")
            toggle("Sonidos chiptune", isOn: $settings.soundEnabled)
            toggle("Vibración háptica", isOn: $settings.hapticsEnabled)
            toggle("Efecto CRT (scanlines)", isOn: $settings.crtEffect)
            toggle("Pantalla de título al abrir", isOn: $settings.showTitleScreen)
        }
        .retroPanel()
    }

    private var privacyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Ubicación (opcional)", icon: "location.fill")
            toggle("Guardar lugar de captura", isOn: Binding(
                get: { settings.saveLocation },
                set: { newValue in
                    settings.saveLocation = newValue
                    if newValue { location.requestPermissionIfNeeded() }
                }))
            Text(locationStatusText)
                .font(.retro(10, weight: .semibold))
                .foregroundStyle(location.isDenied ? Retro.orange : Retro.cream.opacity(0.65))
            if location.isDenied {
                Button("ABRIR AJUSTES DEL IPHONE") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(RetroButtonStyle(color: Retro.cream, compact: true))
            }
        }
        .retroPanel()
    }

    private var locationStatusText: String {
        switch location.status {
        case .notDetermined: return "El permiso se pedirá solo cuando actives esta opción."
        case .denied, .restricted: return "Permiso denegado: las criaturas se guardarán sin lugar."
        case .authorizedWhenInUse, .authorizedAlways:
            return settings.saveLocation ? "Activo: se guardan coordenadas y nombre del lugar." : "Permiso concedido, pero desactivado en DawiDawi."
        @unknown default: return ""
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title.uppercased()).font(.retro(11)).foregroundStyle(Retro.cream)
        }
        .tint(Retro.green)
    }

    // MARK: Datos

    private var dataPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Datos", icon: "externaldrive.fill")
            Text("\(creatures.count) criaturas guardadas en este iPhone (funciona sin conexión).")
                .font(.retro(11, weight: .semibold))
                .foregroundStyle(Retro.cream)
            Button("BORRAR COLECCIÓN") { confirmWipe = true }
                .buttonStyle(RetroButtonStyle(color: Retro.orange, compact: true))
                .disabled(creatures.isEmpty)
        }
        .retroPanel()
    }

    private var aboutPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Acerca de", icon: "info.circle.fill")
            Text("DawiDawi 1.0 — colecciona cualquier criatura que fotografíes. La app nunca identifica ni clasifica especies: la foto es solo la referencia visual de tu modelo retro.")
                .font(.retro(10, weight: .semibold))
                .foregroundStyle(Retro.cream.opacity(0.7))
        }
        .retroPanel()
    }

    private func wipe() {
        for c in creatures { context.delete(c) }
        try? context.save()
        CreatureStore.deleteAll()
        ChipSynth.shared.play(.back)
    }
}
