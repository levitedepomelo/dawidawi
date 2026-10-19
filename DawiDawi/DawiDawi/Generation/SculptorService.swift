import UIKit

/// Descripción de un muñeco low-poly por piezas primitivas, tal como la devuelve el escultor IA
/// (también se guarda como `rig.json` junto a cada criatura).
///
/// Sistema de coordenadas: la figura apoya en el suelo (y = 0), mide ~1,5 de alto, está centrada
/// en x = 0 y mira hacia +z (hacia la cámara). Las regiones de textura son rectángulos
/// normalizados [x0, y0, x1, y1] de la foto (origen arriba a la izquierda).
struct CreatureRig: Codable {
    struct Part: Codable {
        var name: String
        var shape: String            // box | wedge | pyramid | cylinder | cone | sphere
        var center: [Double]         // [x, y, z]
        var size: [Double]           // [ancho X, alto Y, fondo Z]
        var rotation: [Double]       // grados [x, y, z]
        var taper: Double            // escala de la cara superior (cajas, cuñas, conos)
        var color: String            // #RRGGBB
        var texture_region: [Double] // [x0, y0, x1, y1] en la foto (0…1)
        var texture_faces: String    // front | all | none
        var pivot: [Double]          // punto de unión (para animar)
        var animation: String        // none | sway | wag | flap | twitch | step | bob
    }
    var parts: [Part]

    static func decode(_ data: Data) -> CreatureRig? {
        guard let rig = try? JSONDecoder().decode(CreatureRig.self, from: data), !rig.parts.isEmpty else { return nil }
        return rig
    }
}

/// "Escultor IA": envía la foto a Claude (API de Anthropic) y recibe, como JSON validado por
/// esquema, el diseño de un muñeco low-poly de piezas con la región de la foto que texturiza cada una.
/// Inspirado en la técnica "IA que construye el modelo con primitivas a partir de una imagen".
/// El prompt prohíbe nombrar, identificar o clasificar al sujeto: solo se describe geometría.
struct SculptorService {
    let apiKey: String
    static let model = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    enum SculptError: LocalizedError {
        case http(Int, String), refused, invalidResponse
        var errorDescription: String? {
            switch self {
            case .http(let code, let message): return "El escultor IA respondió \(code): \(message)"
            case .refused: return "El escultor IA no pudo procesar esta foto."
            case .invalidResponse: return "Respuesta inesperada del escultor IA."
            }
        }
    }

    static let system = """
    You are a character modeler for a 1997-era video game (PlayStation 1 / Nintendo 64 look). \
    You build simple low-poly figurines out of textured primitive parts, like a fan-made model whose \
    blocky head carries the subject's real face from a photo. Never name, identify or classify the subject \
    in any field: part names must be generic descriptors such as "head", "snout", "left ear", "torso", \
    "front left leg", "tail", "left wing", "beak".
    """

    static let instruction = """
    Build a low-poly figurine of the main living subject of this photo using 6 to 20 primitive parts.

    Coordinates: the figure stands on the ground at y = 0, is about 1.5 units tall, is centered at x = 0 \
    and faces +z (toward the viewer). Keep the pose seen in the photo (sitting, standing, perched, flying). \
    Use slightly chibi proportions: a big head (about 35–45 % of the height) when the subject has a clear head. \
    Parts must touch or overlap so the figurine is one connected object; mirror left/right parts.

    For every part:
    - shape: box, wedge (box whose top narrows to an edge, good for snouts/beaks), pyramid (ears, horns), \
    cylinder (legs, necks, tails), cone, or sphere (low-poly ball for round bodies).
    - center, size ([width x, height y, depth z]) and rotation (degrees around x, y, z) in figure units.
    - taper: scale of the top face (1 = straight, 0.6 = narrower top).
    - texture_region: [x0, y0, x1, y1] normalized photo coordinates (0..1, origin top-left) of the photo \
    area that best shows that part's surface. For the head, frame the face tightly so it appears on the \
    front of the head. Use [0, 0, 0, 0] if the part is not visible in the photo.
    - texture_faces: "front" for the head and snout (photo on the front face, color elsewhere), "all" for \
    fur, feather or skin parts, "none" to use only the flat color.
    - color: dominant color of that part as #RRGGBB.
    - pivot: the point where the part attaches to the rest of the body (used for animation).
    - animation: "sway" for the head, "wag" for tails, "flap" for wings, "step" for legs, "none" for the \
    torso and everything else. Parts mounted on the head (ears, snout, beak, horns, eyes) must use \
    animation "sway" and exactly the same pivot as the head so they move together with it.
    """

    /// Esquema JSON de salida estructurada (output_config.format).
    static var schema: [String: Any] {
        let vec3: [String: Any] = ["type": "array", "items": ["type": "number"]]
        let part: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "shape": ["type": "string", "enum": ["box", "wedge", "pyramid", "cylinder", "cone", "sphere"]],
                "center": vec3, "size": vec3, "rotation": vec3,
                "taper": ["type": "number"],
                "color": ["type": "string"],
                "texture_region": ["type": "array", "items": ["type": "number"]],
                "texture_faces": ["type": "string", "enum": ["front", "all", "none"]],
                "pivot": vec3,
                "animation": ["type": "string", "enum": ["none", "sway", "wag", "flap", "twitch", "step", "bob"]]
            ],
            "required": ["name", "shape", "center", "size", "rotation", "taper", "color",
                         "texture_region", "texture_faces", "pivot", "animation"],
            "additionalProperties": false
        ]
        return [
            "type": "object",
            "properties": ["parts": ["type": "array", "items": part]],
            "required": ["parts"],
            "additionalProperties": false
        ]
    }

    /// Devuelve el JSON del rig (validado) listo para guardar como `rig.json`.
    func sculpt(photo: UIImage) async throws -> Data {
        guard let jpeg = photo.normalized(maxDimension: 1024).jpegData(compressionQuality: 0.85) else {
            throw SculptError.invalidResponse
        }
        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "system": Self.system,
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": Self.schema]
            ],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image",
                     "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
                    ["type": "text", "text": Self.instruction]
                ]
            ]]
        ]
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 240)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SculptError.invalidResponse }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String)
                ?? String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw SculptError.http(http.statusCode, message)
        }
        // Comprobar el motivo de parada antes de leer el contenido
        if (json?["stop_reason"] as? String) == "refusal" { throw SculptError.refused }
        let blocks = json?["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              let rigData = text.data(using: .utf8),
              CreatureRig.decode(rigData) != nil else { throw SculptError.invalidResponse }
        return rigData
    }
}
