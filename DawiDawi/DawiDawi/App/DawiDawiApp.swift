import SwiftUI
import SwiftData

@main
struct DawiDawiApp: App {
    let container: ModelContainer
    @StateObject var settings = AppSettings.shared

    init() {
        // SwiftData guarda en Application Support: créala antes (evita avisos en el primer arranque)
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        do {
            container = try ModelContainer(for: Creature.self)
        } catch {
            fatalError("No se pudo abrir la colección de DawiDawi: \(error)")
        }
        RetroAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .preferredColorScheme(.light)
                .tint(Retro.yellow)
        }
        .modelContainer(container)
    }
}
