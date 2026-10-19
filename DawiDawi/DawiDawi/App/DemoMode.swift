import SwiftUI
import SwiftData

/// Modo demo para las capturas automáticas en CI (simulador sin cámara).
/// Solo se activa con argumentos de lanzamiento; en uso normal no hace nada.
///
///   -demoScene  title | collection | detail | stats | settings | capture | reveal
///   -demoImages /ruta/a.jpg,/ruta/b.jpg   fotos de referencia para sembrar la colección
///   -demoRarity common…mythic             fuerza la rareza de la escena "reveal"
enum DemoMode {
    private static let args = ProcessInfo.processInfo.arguments

    private static func value(_ key: String) -> String? {
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static let scene: String? = value("-demoScene")
    static var isActive: Bool { scene != nil }
    static let imagePaths: [String] = value("-demoImages")?.split(separator: ",").map(String.init) ?? []
    static let forcedRarity: Rarity? = value("-demoRarity").flatMap(Rarity.init(rawValue:))
    /// Rig de ejemplo (como el que devolvería el escultor IA) para la primera foto de prueba.
    /// Número de criatura que abre la escena "detail" (por defecto la #001).
    static let detailNumber: Int = value("-demoNumber").flatMap(Int.init) ?? 1
    static let rigData: Data? = value("-demoRig").flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }

    static func image(at index: Int) -> UIImage? {
        guard !imagePaths.isEmpty else { return nil }
        return UIImage(contentsOfFile: imagePaths[index % imagePaths.count])
    }

    /// Rarezas de la colección sembrada: una de cada para ver todos los marcos y filtros.
    private static let seedRarities: [Rarity] = [.mythic, .legendary, .epic, .rare, .uncommon, .common, .common, .uncommon]
    private static let seedNames = ["Michi Dorado", "", "Sr. Bigotes", "Luna", "", "Pelusa", "", "Canela"]

    /// Crea criaturas reales (mismo pipeline que la cámara) si la colección está vacía.
    @MainActor
    static func seedIfNeeded(context: ModelContext, settings: AppSettings) async {
        guard isActive, !imagePaths.isEmpty,
              ((try? context.fetchCount(FetchDescriptor<Creature>())) ?? 0) == 0 else { return }
        var options = settings.generationOptions
        options.mode = .local
        let calendar = Calendar.current
        for (i, rarity) in seedRarities.enumerated() {
            guard let photo = image(at: i),
                  let generated = try? await CreatureGenerator.generate(photo: photo, options: options, progress: { _ in })
            else { continue }
            let date = calendar.date(byAdding: .day, value: -(seedRarities.count - i), to: Date()) ?? Date()
            guard let (creature, _) = try? CaptureFlow.persist(generated, rarity: rarity, capturedAt: date,
                                                                context: context, meshDensity: settings.meshDensity,
                                                                rigOverride: i % max(1, imagePaths.count) == 0 ? rigData : nil)
            else { continue }
            if !seedNames[i].isEmpty { creature.name = seedNames[i] }
            if i == 0 {
                creature.epithet = "El gato del bar"
                creature.habitat = "Barra de madera, de noche"
                creature.notes = "Me miró fijamente mientras me tomaba un vaso de leche."
                creature.tags = ["gato", "nocturno", "bar"]
                creature.isFavorite = true
                creature.placeName = "Madrid, España"
                creature.latitude = 40.4168
                creature.longitude = -3.7038
            }
        }
        try? context.save()
    }
}
