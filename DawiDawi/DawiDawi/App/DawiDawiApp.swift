import SwiftUI
import SwiftData

@main
struct DawiDawiApp: App {
    let container: ModelContainer
    @StateObject var settings = AppSettings.shared

    init() {
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
