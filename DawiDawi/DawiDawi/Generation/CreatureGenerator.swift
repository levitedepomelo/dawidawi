import UIKit

enum GenerationStep: Int, CaseIterable {
    case preparing, remoteRender, extracting, pixelating, modeling, rollingRarity, done

    var label: String {
        switch self {
        case .preparing: return "Revelando el carrete"
        case .remoteRender: return "Enviando al estudio de IA"
        case .extracting: return "Recortando silueta"
        case .pixelating: return "Pixelando texturas"
        case .modeling: return "Modelando polígonos"
        case .rollingRarity: return "Agitando la rareza"
        case .done: return "¡Listo!"
        }
    }
}

struct GeneratedCreature {
    let photo: UIImage
    let sprite: CGImage
    let usedRemote: Bool
    /// Si el modo remoto falló y se usó el motor local, el motivo (para avisar al usuario).
    let remoteFallbackReason: String?
    /// JSON del muñeco diseñado por el escultor IA (si se usó y funcionó).
    var rig: Data? = nil
    /// Recorte del sujeto a buena resolución (texturas del muñeco) y su cara localizada por Vision.
    var cutout: CGImage? = nil
    var face: CGRect? = nil
}

enum GenerationError: LocalizedError {
    case unreadableImage
    var errorDescription: String? { "No se pudo procesar la foto. Prueba con otra." }
}

/// Pipeline: foto → (IA remota opcional) → recorte de sujeto → textura retro.
/// La malla 3D se construye al mostrar la criatura (es determinista y rápida).
enum CreatureGenerator {
    static func generate(photo: UIImage,
                         options: GenerationOptions,
                         progress: @escaping @MainActor (GenerationStep) -> Void) async throws -> GeneratedCreature {
        await progress(.preparing)
        let normalized = await Task.detached(priority: .userInitiated) { photo.normalized(maxDimension: 1280) }.value

        var source = normalized
        var usedRemote = false
        var fallbackReason: String?
        if options.mode == .remote {
            if let key = options.apiKey, let url = URL(string: options.remoteEndpoint) {
                await progress(.remoteRender)
                do {
                    let service = RemoteRenderService(apiKey: key, model: options.remoteModel, endpoint: url)
                    source = try await service.stylize(photo: normalized).normalized(maxDimension: 1280)
                    usedRemote = true
                } catch {
                    fallbackReason = error.localizedDescription
                }
            } else {
                fallbackReason = "Falta la API key: se usó el motor local."
            }
        }

        // Escultor IA: se lanza en paralelo con el recorte local
        var sculptTask: Task<Data, Error>?
        if options.mode == .sculptor {
            if let key = options.anthropicKey {
                await progress(.remoteRender)
                let reference = normalized
                sculptTask = Task { try await SculptorService(apiKey: key).sculpt(photo: reference) }
            } else {
                fallbackReason = "Falta la API key de Anthropic: se usó el motor local."
            }
        }

        await progress(.extracting)
        let resolution = options.textureResolution
        let finalSource = source
        let subject = await Task.detached(priority: .userInitiated) { SubjectExtractor.extractSubject(from: finalSource) }.value
        guard let subject else { throw GenerationError.unreadableImage }

        await progress(.pixelating)
        let sprite = await Task.detached(priority: .userInitiated) {
            RetroStylizer.makeSprite(from: subject, resolution: resolution)
        }.value
        guard let sprite else { throw GenerationError.unreadableImage }

        await progress(.modeling)
        var rig: Data?
        if let sculptTask {
            do {
                rig = try await sculptTask.value
                usedRemote = true
            } catch {
                fallbackReason = error.localizedDescription
            }
        }
        var result = GeneratedCreature(photo: normalized, sprite: sprite, usedRemote: usedRemote,
                                       remoteFallbackReason: fallbackReason)
        result.rig = rig
        let cut = await Task.detached(priority: .userInitiated) { () -> (CGImage?, CGRect?) in
            let small = SubjectExtractor.downscaled(subject, maxDimension: 384)
            return (small, small.flatMap(FaceLocator.faceRect(in:)))
        }.value
        result.cutout = cut.0
        result.face = cut.1
        return result
    }
}
