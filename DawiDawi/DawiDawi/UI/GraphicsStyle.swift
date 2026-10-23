import Foundation

/// Calidad gráfica de los modelos 3D (Ajustes → Gráficos).
///  - HD (por defecto): texturas de la foto en alta resolución con filtrado suave, piezas con bordes
///    redondeados, render a resolución nativa con antialiasing.
///  - Retro: texturas pixeladas, bloques duros y render a baja resolución (look PS1/N64 puro).
/// Se lee de UserDefaults para poder consultarlo desde cualquier hilo al construir los modelos.
enum GraphicsStyle {
    static let key = "gfx.style"

    static var isRetro: Bool { UserDefaults.standard.string(forKey: key) == "retro" }

    /// Tamaño máximo (px) de cada recorte de textura del muñeco.
    static var textureSize: Int { isRetro ? 64 : 192 }
}
