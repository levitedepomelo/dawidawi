import UIKit

/// Ficheros de cada criatura en Application Support/Creatures/<uuid>/ (funciona sin conexión).
///  - photo.jpg   foto original (reducida)
///  - sprite.png  textura pixelada con transparencia (fuente del modelo 3D)
///  - thumb.png   render low-res del modelo 3D para la galería
enum CreatureStore {
    private static let cache = NSCache<NSString, UIImage>()

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Creatures", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = false
            var mutable = url
            try? mutable.setResourceValues(values)
        }
        return url
    }

    static func directory(for id: UUID) -> URL {
        let url = root.appendingPathComponent(id.uuidString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func photoURL(_ id: UUID) -> URL { directory(for: id).appendingPathComponent("photo.jpg") }
    static func spriteURL(_ id: UUID) -> URL { directory(for: id).appendingPathComponent("sprite.png") }
    static func thumbURL(_ id: UUID) -> URL { directory(for: id).appendingPathComponent("thumb.png") }
    static func rigURL(_ id: UUID) -> URL { directory(for: id).appendingPathComponent("rig.json") }

    static func saveRig(_ data: Data, id: UUID) throws {
        try data.write(to: rigURL(id), options: .atomic)
    }

    /// Muñeco del escultor IA guardado para esta criatura (si existe).
    static func rig(_ id: UUID) -> CreatureRig? {
        guard let data = try? Data(contentsOf: rigURL(id)) else { return nil }
        return CreatureRig.decode(data)
    }

    static func save(photo: UIImage, sprite: CGImage, thumb: UIImage?, id: UUID) throws {
        if let data = photo.jpegData(compressionQuality: 0.85) {
            try data.write(to: photoURL(id), options: .atomic)
        }
        if let data = UIImage(cgImage: sprite).pngData() {
            try data.write(to: spriteURL(id), options: .atomic)
        }
        if let thumb, let data = thumb.pngData() {
            try data.write(to: thumbURL(id), options: .atomic)
        }
        cache.removeAllObjects()
    }

    static func photo(_ id: UUID) -> UIImage? { load(photoURL(id)) }
    static func sprite(_ id: UUID) -> UIImage? { load(spriteURL(id)) }
    static func thumb(_ id: UUID) -> UIImage? { load(thumbURL(id)) ?? sprite(id) }

    private static func load(_ url: URL) -> UIImage? {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString, isDirectory: true))
        cache.removeAllObjects()
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: root)
        cache.removeAllObjects()
    }
}
