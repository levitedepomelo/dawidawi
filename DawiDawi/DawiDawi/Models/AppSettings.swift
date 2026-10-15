import Foundation
import SwiftUI

enum GenerationMode: String, CaseIterable, Identifiable {
    /// 100 % en el dispositivo: Vision (recorte de silueta) + pixelado + malla low-poly. Sin internet.
    case local
    /// Pide a un servicio de IA de imagen un render estilo PS1/N64 y luego lo convierte en modelo 3D local.
    case remote

    var id: String { rawValue }
    var title: String {
        switch self {
        case .local: return "Motor local"
        case .remote: return "IA remota + local"
        }
    }
}

/// Opciones que el pipeline de generación necesita (copia inmutable, segura entre hilos).
struct GenerationOptions: Sendable {
    var mode: GenerationMode
    var apiKey: String?
    var remoteModel: String
    var remoteEndpoint: String
    var textureResolution: Int
    var meshDensity: Int
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var weights: [Rarity: Double] { didSet { saveWeights() } }
    @Published var generationMode: GenerationMode { didSet { defaults.set(generationMode.rawValue, forKey: Keys.mode) } }
    @Published var remoteModel: String { didSet { defaults.set(remoteModel, forKey: Keys.model) } }
    @Published var remoteEndpoint: String { didSet { defaults.set(remoteEndpoint, forKey: Keys.endpoint) } }
    @Published var textureResolution: Int { didSet { defaults.set(textureResolution, forKey: Keys.texture) } }
    @Published var meshDensity: Int { didSet { defaults.set(meshDensity, forKey: Keys.mesh) } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Keys.sound); ChipSynth.shared.enabled = soundEnabled } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics); Haptics.enabled = hapticsEnabled } }
    @Published var crtEffect: Bool { didSet { defaults.set(crtEffect, forKey: Keys.crt) } }
    @Published var saveLocation: Bool { didSet { defaults.set(saveLocation, forKey: Keys.location) } }
    @Published var showTitleScreen: Bool { didSet { defaults.set(showTitleScreen, forKey: Keys.title) } }
    @Published private(set) var hasAPIKey: Bool

    static let defaultEndpoint = "https://api.openai.com/v1/images/edits"
    static let defaultModel = "gpt-image-1"

    private enum Keys {
        static let weights = "rarity.weights"
        static let mode = "gen.mode"
        static let model = "gen.model"
        static let endpoint = "gen.endpoint"
        static let texture = "gen.texture"
        static let mesh = "gen.mesh"
        static let sound = "fx.sound"
        static let haptics = "fx.haptics"
        static let crt = "fx.crt"
        static let location = "loc.enabled"
        static let title = "ui.title"
    }

    private init() {
        let d = UserDefaults.standard
        var loaded: [Rarity: Double] = [:]
        if let stored = d.dictionary(forKey: Keys.weights) as? [String: Double] {
            for r in Rarity.allCases { loaded[r] = stored[r.rawValue] ?? r.defaultWeight }
        } else {
            for r in Rarity.allCases { loaded[r] = r.defaultWeight }
        }
        weights = loaded
        generationMode = GenerationMode(rawValue: d.string(forKey: Keys.mode) ?? "") ?? .local
        remoteModel = d.string(forKey: Keys.model) ?? AppSettings.defaultModel
        remoteEndpoint = d.string(forKey: Keys.endpoint) ?? AppSettings.defaultEndpoint
        textureResolution = d.object(forKey: Keys.texture) as? Int ?? 80
        meshDensity = d.object(forKey: Keys.mesh) as? Int ?? 26
        soundEnabled = d.object(forKey: Keys.sound) as? Bool ?? true
        hapticsEnabled = d.object(forKey: Keys.haptics) as? Bool ?? true
        crtEffect = d.object(forKey: Keys.crt) as? Bool ?? true
        saveLocation = d.object(forKey: Keys.location) as? Bool ?? false
        showTitleScreen = d.object(forKey: Keys.title) as? Bool ?? true
        hasAPIKey = Keychain.read(Keychain.apiKeyAccount) != nil
        ChipSynth.shared.enabled = soundEnabled
        Haptics.enabled = hapticsEnabled
    }

    // MARK: Rarezas

    func weight(_ r: Rarity) -> Double { weights[r] ?? r.defaultWeight }

    var totalWeight: Double { Rarity.allCases.reduce(0) { $0 + max(0, weight($1)) } }

    /// Probabilidad normalizada (0...1).
    func probability(_ r: Rarity) -> Double {
        let total = totalWeight
        guard total > 0 else { return r == .common ? 1 : 0 }
        return max(0, weight(r)) / total
    }

    func resetWeights() {
        var w: [Rarity: Double] = [:]
        for r in Rarity.allCases { w[r] = r.defaultWeight }
        weights = w
    }

    /// Tirada de rareza con las probabilidades configuradas.
    func rollRarity() -> Rarity {
        var g = SystemRandomNumberGenerator()
        return Self.roll(weights: weights, using: &g)
    }

    nonisolated static func roll<G: RandomNumberGenerator>(weights: [Rarity: Double], using g: inout G) -> Rarity {
        let total = Rarity.allCases.reduce(0.0) { $0 + max(0, weights[$1] ?? 0) }
        guard total > 0 else { return .common }
        var r = Double.random(in: 0..<total, using: &g)
        for rarity in Rarity.allCases {
            r -= max(0, weights[rarity] ?? 0)
            if r < 0 { return rarity }
        }
        return .common
    }

    private func saveWeights() {
        var dict: [String: Double] = [:]
        for (k, v) in weights { dict[k.rawValue] = v }
        defaults.set(dict, forKey: Keys.weights)
    }

    // MARK: API key (Keychain)

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(Keychain.apiKeyAccount)
        } else {
            Keychain.save(trimmed, account: Keychain.apiKeyAccount)
        }
        hasAPIKey = Keychain.read(Keychain.apiKeyAccount) != nil
    }

    var generationOptions: GenerationOptions {
        GenerationOptions(mode: generationMode,
                          apiKey: Keychain.read(Keychain.apiKeyAccount),
                          remoteModel: remoteModel,
                          remoteEndpoint: remoteEndpoint,
                          textureResolution: textureResolution,
                          meshDensity: meshDensity)
    }
}
