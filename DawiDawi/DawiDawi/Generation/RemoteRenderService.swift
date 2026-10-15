import UIKit

/// Cliente opcional para un servicio de IA de edición de imagen compatible con la API
/// `POST /v1/images/edits` de OpenAI (multipart: model, image, prompt → data[0].b64_json).
/// Se usa SOLO para re-dibujar el sujeto de la foto con estética PS1/N64. El prompt nunca
/// pide identificar, clasificar ni nombrar lo que aparece.
struct RemoteRenderService {
    let apiKey: String
    let model: String
    let endpoint: URL

    enum RemoteError: LocalizedError {
        case badEndpoint, http(Int, String), invalidResponse
        var errorDescription: String? {
            switch self {
            case .badEndpoint: return "El endpoint configurado no es una URL válida."
            case .http(let code, let message): return "El servicio respondió \(code): \(message)"
            case .invalidResponse: return "Respuesta inesperada del servicio de IA."
            }
        }
    }

    static let prompt = """
    Re-create the main living subject of this photo as a low-poly 3D character rendered like a \
    1997 PlayStation 1 / Nintendo 64 video game: few polygons, flat-shaded facets, small blurry \
    pixelated textures with visible texels, slight affine texture warping, vertex lighting, 240p look. \
    Keep its exact colors, markings, proportions and pose so it is clearly the same individual. \
    Full body, centered, standing on the ground, three-quarter view, on a plain flat light-grey background. \
    No text, no logos, no frame, no extra characters.
    """

    func stylize(photo: UIImage) async throws -> UIImage {
        guard endpoint.scheme?.hasPrefix("http") == true else { throw RemoteError.badEndpoint }
        let jpeg = photo.normalized(maxDimension: 1024).jpegData(compressionQuality: 0.88) ?? Data()
        let boundary = "DawiDawi-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("prompt", Self.prompt)
        field("size", "1024x1024")
        field("n", "1")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"creature.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: endpoint, timeoutInterval: 150)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RemoteError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
                ?? String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw RemoteError.http(http.statusCode, message)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["data"] as? [[String: Any]])?.first else { throw RemoteError.invalidResponse }

        if let b64 = first["b64_json"] as? String, let imageData = Data(base64Encoded: b64),
           let image = UIImage(data: imageData) {
            return image
        }
        if let urlString = first["url"] as? String, let url = URL(string: urlString) {
            let (imageData, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: imageData) { return image }
        }
        throw RemoteError.invalidResponse
    }
}
