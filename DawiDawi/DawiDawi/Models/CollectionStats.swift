import Foundation

/// Estadísticas calculadas SOLO sobre lo que el usuario ha capturado (no hay catálogo global).
struct CollectionStats {
    let total: Int
    let perRarity: [Rarity: Int]
    let tiersDiscovered: Int
    let dossierAverage: Double
    let favorites: Int
    let thisMonth: Int
    let currentStreak: Int
    let bestStreak: Int
    let highest: Rarity?
    let strongest: Creature?
    let first: Date?
    let last: Date?
    let placesVisited: Int

    /// % de colección propia completada:
    /// 50 % → rarezas descubiertas (6 niveles), 50 % → fichas rellenadas por ti.
    var completion: Double {
        guard total > 0 else { return 0 }
        return 0.5 * Double(tiersDiscovered) / Double(Rarity.allCases.count) + 0.5 * dossierAverage
    }

    init(_ creatures: [Creature]) {
        total = creatures.count
        var counts: [Rarity: Int] = [:]
        for c in creatures { counts[c.rarity, default: 0] += 1 }
        perRarity = counts
        tiersDiscovered = counts.keys.count
        dossierAverage = creatures.isEmpty ? 0 : creatures.map(\.dossierProgress).reduce(0, +) / Double(creatures.count)
        favorites = creatures.filter(\.isFavorite).count
        let cal = Calendar.current
        let now = Date()
        thisMonth = creatures.filter { cal.isDate($0.capturedAt, equalTo: now, toGranularity: .month) }.count
        highest = creatures.map(\.rarity).max()
        strongest = creatures.max { $0.totalPower < $1.totalPower }
        first = creatures.map(\.capturedAt).min()
        last = creatures.map(\.capturedAt).max()
        placesVisited = Set(creatures.compactMap { $0.placeName }).count

        // Rachas de días consecutivos con capturas
        let days = Set(creatures.map { cal.startOfDay(for: $0.capturedAt) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for d in days {
            if let p = previous, let next = cal.date(byAdding: .day, value: 1, to: p), cal.isDate(next, inSameDayAs: d) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = d
        }
        bestStreak = best
        var streak = 0
        var cursor = cal.startOfDay(for: now)
        let daySet = Set(days)
        if !daySet.contains(cursor), let y = cal.date(byAdding: .day, value: -1, to: cursor) { cursor = y }
        while daySet.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        currentStreak = streak
    }

    func count(_ r: Rarity) -> Int { perRarity[r] ?? 0 }
}
