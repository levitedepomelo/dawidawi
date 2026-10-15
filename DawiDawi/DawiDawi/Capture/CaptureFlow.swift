import SwiftUI
import SwiftData
import CoreLocation

/// Orquesta el flujo completo: foto → generación → rareza → guardado → revelación.
@MainActor
final class CaptureFlow: ObservableObject {
    enum Phase: Equatable { case camera, generating, reveal }

    @Published var phase: Phase = .camera
    @Published var step: GenerationStep = .preparing
    @Published var photo: UIImage?
    @Published var creature: Creature?
    @Published var stage: RetroStage?
    @Published var errorMessage: String?
    @Published var notice: String?

    private var locationTask: Task<CLLocation?, Never>?

    func process(photo: UIImage, context: ModelContext, settings: AppSettings) {
        guard phase == .camera else { return }
        self.photo = photo
        self.phase = .generating
        self.step = .preparing
        self.notice = nil
        self.errorMessage = nil

        // La ubicación se pide en paralelo y solo si el usuario la activó.
        if settings.saveLocation && LocationProvider.shared.isAuthorized {
            locationTask = Task { await LocationProvider.shared.currentLocation() }
        } else {
            locationTask = nil
        }

        let options = settings.generationOptions
        let meshDensity = settings.meshDensity
        Task {
            let started = Date()
            do {
                let generated = try await CreatureGenerator.generate(photo: photo, options: options) { [weak self] step in
                    self?.step = step
                }
                // Tirada de rareza: puro azar con las probabilidades configuradas.
                self.step = .rollingRarity
                let rarity = DemoMode.forcedRarity ?? settings.rollRarity()
                let (creature, stage) = try Self.persist(generated, rarity: rarity, context: context,
                                                         meshDensity: meshDensity)

                // Suspense mínimo para que la animación de "procesado" se luzca
                let elapsed = Date().timeIntervalSince(started)
                if elapsed < 2.4 { try? await Task.sleep(nanoseconds: UInt64((2.4 - elapsed) * 1_000_000_000)) }

                if let reason = generated.remoteFallbackReason {
                    self.notice = "IA remota no disponible — usado el motor local. (\(reason))"
                }
                self.creature = creature
                self.stage = stage
                self.step = .done
                self.phase = .reveal

                await self.attachLocation(to: creature, context: context)
            } catch {
                ChipSynth.shared.play(.error)
                Haptics.error()
                self.errorMessage = error.localizedDescription
                self.phase = .camera
            }
        }
    }

    /// Numera, guarda ficheros e inserta la criatura. Devuelve también su escenario 3D de exhibición.
    @discardableResult
    static func persist(_ generated: GeneratedCreature, rarity: Rarity, capturedAt: Date = Date(),
                        context: ModelContext, meshDensity: Int) throws -> (Creature, RetroStage) {
        let seed = Int.random(in: 1...Int(Int32.max))
        let count = (try? context.fetchCount(FetchDescriptor<Creature>())) ?? 0
        let maxNumber = (try? context.fetch(FetchDescriptor<Creature>(sortBy: [SortDescriptor(\.number, order: .reverse)])).first?.number) ?? 0
        let number = max(count, maxNumber) + 1

        let creature = Creature(number: number,
                                name: Creature.defaultName(for: number),
                                capturedAt: capturedAt,
                                rarity: rarity,
                                generator: generated.usedRemote ? "remote" : "local",
                                seed: seed)

        let stage = RetroStage(sprite: generated.sprite, rarity: rarity, seed: seed,
                               meshDensity: meshDensity, showcase: true)
        let thumbStage = RetroStage(sprite: generated.sprite, rarity: rarity, seed: seed,
                                    meshDensity: meshDensity, showcase: false)
        let thumb = thumbStage.snapshot()

        try CreatureStore.save(photo: generated.photo, sprite: generated.sprite, thumb: thumb, id: creature.id)
        context.insert(creature)
        try context.save()
        return (creature, stage)
    }

    private func attachLocation(to creature: Creature, context: ModelContext) async {
        guard let task = locationTask, let location = await task.value else { return }
        creature.latitude = location.coordinate.latitude
        creature.longitude = location.coordinate.longitude
        try? context.save()
        if let name = await LocationProvider.shared.placeName(for: location) {
            creature.placeName = name
            try? context.save()
        }
    }

    func reset() {
        phase = .camera
        photo = nil
        creature = nil
        stage = nil
        step = .preparing
        notice = nil
    }
}
