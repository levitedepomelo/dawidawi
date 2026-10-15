import Foundation
import SwiftData

/// Una criatura de la colección personal. Todos los datos de texto los escribe el usuario:
/// la app nunca identifica, clasifica ni nombra lo que aparece en la foto.
@Model
final class Creature {
    @Attribute(.unique) var id: UUID = UUID()
    /// Número correlativo dentro de TU colección (#001, #002...). No es un catálogo global.
    var number: Int = 0
    var name: String = ""
    var epithet: String = ""
    var habitat: String = ""
    var notes: String = ""
    var tags: [String] = []
    var capturedAt: Date = Date()
    var rarityRaw: String = Rarity.common.rawValue
    var isFavorite: Bool = false
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
    /// "local" o "remote" según el motor que generó el modelo.
    var generator: String = "local"
    var seed: Int = 0
    var vitality: Int = 0
    var power: Int = 0
    var agility: Int = 0
    var charm: Int = 0

    init(id: UUID = UUID(),
         number: Int,
         name: String,
         capturedAt: Date = Date(),
         rarity: Rarity,
         generator: String,
         seed: Int) {
        self.id = id
        self.number = number
        self.name = name
        self.capturedAt = capturedAt
        self.rarityRaw = rarity.rawValue
        self.generator = generator
        self.seed = seed
        var rng = SeededGenerator(seed: UInt64(truncatingIfNeeded: seed))
        func roll() -> Int {
            let value = rarity.statBase + Int.random(in: -12...18, using: &rng)
            return min(99, max(1, value))
        }
        self.vitality = roll()
        self.power = roll()
        self.agility = roll()
        self.charm = roll()
    }

    var rarity: Rarity {
        get { Rarity(rawValue: rarityRaw) ?? .common }
        set { rarityRaw = newValue.rawValue }
    }

    var numberLabel: String { String(format: "#%03d", number) }

    var displayName: String { name.isEmpty ? "Criatura \(numberLabel)" : name }

    var totalPower: Int { vitality + power + agility + charm }

    var hasLocation: Bool { latitude != nil && longitude != nil }

    /// Progreso de la "ficha" que rellena el usuario (0...1). Alimenta el % de colección completada.
    var dossierProgress: Double {
        let checks: [Bool] = [
            !name.isEmpty && !name.hasPrefix("Criatura #"),
            !epithet.isEmpty,
            !habitat.isEmpty,
            !notes.isEmpty,
            !tags.isEmpty
        ]
        return Double(checks.filter { $0 }.count) / Double(checks.count)
    }

    static func defaultName(for number: Int) -> String {
        "Criatura " + String(format: "#%03d", number)
    }
}

/// Generador pseudoaleatorio con semilla (SplitMix64) para que los stats sean reproducibles.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
