import SwiftUI
import UIKit

/// Rareza asignada al azar a cada criatura. No depende en absoluto de lo que aparece en la foto.
enum Rarity: String, CaseIterable, Codable, Identifiable, Comparable {
    case common, uncommon, rare, epic, legendary, mythic

    var id: String { rawValue }

    var tier: Int { Rarity.allCases.firstIndex(of: self) ?? 0 }

    static func < (lhs: Rarity, rhs: Rarity) -> Bool { lhs.tier < rhs.tier }

    var title: String {
        switch self {
        case .common: return "Común"
        case .uncommon: return "Poco común"
        case .rare: return "Raro"
        case .epic: return "Épico"
        case .legendary: return "Legendario"
        case .mythic: return "Mítico"
        }
    }

    var shout: String {
        switch self {
        case .common: return "¡COMÚN!"
        case .uncommon: return "¡POCO COMÚN!"
        case .rare: return "¡RARO!"
        case .epic: return "¡¡ÉPICO!!"
        case .legendary: return "¡¡LEGENDARIO!!"
        case .mythic: return "¡¡¡MÍTICO!!!"
        }
    }

    var shortCode: String {
        switch self {
        case .common: return "C"
        case .uncommon: return "PC"
        case .rare: return "R"
        case .epic: return "E"
        case .legendary: return "L"
        case .mythic: return "M"
        }
    }

    /// Probabilidad por defecto (en "pesos"; suman 100).
    var defaultWeight: Double {
        switch self {
        case .common: return 60
        case .uncommon: return 25
        case .rare: return 10
        case .epic: return 4
        case .legendary: return 0.9
        case .mythic: return 0.1
        }
    }

    var stars: Int { tier + 1 }

    var uiColor: UIColor {
        switch self {
        case .common: return UIColor(red: 0.80, green: 0.80, blue: 0.78, alpha: 1)
        case .uncommon: return UIColor(red: 0.36, green: 0.86, blue: 0.40, alpha: 1)
        case .rare: return UIColor(red: 0.25, green: 0.62, blue: 1.00, alpha: 1)
        case .epic: return UIColor(red: 0.72, green: 0.38, blue: 1.00, alpha: 1)
        case .legendary: return UIColor(red: 1.00, green: 0.76, blue: 0.16, alpha: 1)
        case .mythic: return UIColor(red: 1.00, green: 0.30, blue: 0.55, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    var darkColor: Color {
        switch self {
        case .common: return Color(red: 0.25, green: 0.25, blue: 0.28)
        case .uncommon: return Color(red: 0.06, green: 0.30, blue: 0.12)
        case .rare: return Color(red: 0.05, green: 0.16, blue: 0.40)
        case .epic: return Color(red: 0.22, green: 0.06, blue: 0.40)
        case .legendary: return Color(red: 0.40, green: 0.24, blue: 0.02)
        case .mythic: return Color(red: 0.40, green: 0.03, blue: 0.20)
        }
    }

    /// Gradiente del fondo de las tarjetas.
    var gradient: LinearGradient {
        if self == .mythic {
            return LinearGradient(colors: [.pink, .orange, .yellow, .green, .cyan, .purple],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [color.opacity(0.9), darkColor], startPoint: .top, endPoint: .bottom)
    }

    /// Factor base para las estadísticas de juego (VIT/FUE/AGI/ENC).
    var statBase: Int { 18 + tier * 13 }

    /// Cuántas sacudidas da la cápsula antes de abrirse (suspense).
    var shakeCount: Int { min(2 + tier, 7) }
}
