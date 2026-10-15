import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    var onCapture: () -> Void
    @Query(sort: \Creature.capturedAt) var creatures: [Creature]
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let stats = CollectionStats(creatures)
        ZStack {
            RetroBackground(floorColor: Retro.cyan, animated: false)
            ScrollView {
                VStack(spacing: 16) {
                    ExtrudedText(text: "ESTADÍSTICAS", size: 28,
                                 fill: [Retro.cyan, Color(red: 0.2, green: 0.45, blue: 1)],
                                 depthColor: Color(red: 0.05, green: 0.12, blue: 0.4), depth: 4)
                        .padding(.top, 10)

                    completionPanel(stats)
                    counters(stats)
                    rarityPanel(stats)
                    if !creatures.isEmpty {
                        activityPanel
                        luckPanel(stats)
                        recordsPanel(stats)
                    } else {
                        VStack(spacing: 12) {
                            Text("Aún no hay datos. ¡Captura tu primera criatura!")
                                .font(.retro(12, weight: .semibold))
                                .foregroundStyle(Retro.cream)
                                .multilineTextAlignment(.center)
                            Button(action: onCapture) { Label("CAPTURAR", systemImage: "camera.fill") }
                                .buttonStyle(RetroButtonStyle(color: Retro.magenta, textColor: Retro.cream))
                        }
                        .frame(maxWidth: .infinity)
                        .retroPanel()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Paneles

    private func completionPanel(_ stats: CollectionStats) -> some View {
        HStack(spacing: 18) {
            SegmentRing(progress: stats.completion, segments: 24, color: Retro.green)
                .frame(width: 112, height: 112)
                .overlay(
                    VStack(spacing: 0) {
                        Text("\(Int((stats.completion * 100).rounded()))%").font(.retro(24, weight: .black))
                        Text("COMPLETO").font(.retro(9))
                    }
                    .foregroundStyle(Retro.cream)
                )
            VStack(alignment: .leading, spacing: 8) {
                Text("TU COLECCIÓN").font(.retro(13)).foregroundStyle(Retro.yellow)
                metric("Rarezas descubiertas", "\(stats.tiersDiscovered)/6")
                metric("Fichas rellenadas", "\(Int((stats.dossierAverage * 100).rounded()))%")
                Text("50 % rarezas + 50 % fichas. Sin catálogo global: solo cuenta lo que tú encuentras.")
                    .font(.retro(9, weight: .semibold))
                    .foregroundStyle(Retro.cream.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroPanel()
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label.uppercased()).font(.retro(10)).foregroundStyle(Retro.cream.opacity(0.8))
            Spacer()
            Text(value).font(.retro(13)).foregroundStyle(Retro.green)
        }
    }

    private func counters(_ stats: CollectionStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            counter("CAPTURAS", "\(stats.total)", "camera.fill", Retro.yellow)
            counter("ESTE MES", "\(stats.thisMonth)", "calendar", Retro.cyan)
            counter("RACHA", "\(stats.currentStreak) d", "flame.fill", Retro.orange)
            counter("MEJOR RACHA", "\(stats.bestStreak) d", "trophy.fill", Retro.green)
            counter("FAVORITAS", "\(stats.favorites)", "heart.fill", Retro.magenta)
            counter("LUGARES", "\(stats.placesVisited)", "map.fill", Retro.cream)
        }
    }

    private func counter(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .black))
                Text(title).font(.retro(10))
            }
            .foregroundStyle(color)
            Text(value).font(.retro(24, weight: .black)).foregroundStyle(Retro.cream)
                .minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .retroPanel(padding: 12)
    }

    private func rarityPanel(_ stats: CollectionStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Por rareza", icon: "sparkles")
            Chart(Rarity.allCases) { r in
                BarMark(x: .value("Rareza", r.shortCode), y: .value("Cantidad", stats.count(r)))
                    .foregroundStyle(r.color)
                    .annotation(position: .top) {
                        Text("\(stats.count(r))").font(.retro(10)).foregroundStyle(Retro.cream)
                    }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Retro.cream.opacity(0.15))
                    AxisValueLabel().font(.retro(9)).foregroundStyle(Retro.cream.opacity(0.6))
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.retro(10)).foregroundStyle(Retro.cream)
                }
            }
            .frame(height: 170)

            HStack(spacing: 6) {
                ForEach(Rarity.allCases) { r in
                    VStack(spacing: 4) {
                        LowPolyCircle(sides: 6)
                            .fill(stats.count(r) > 0 ? r.color : Color.white.opacity(0.08))
                            .frame(width: 26, height: 26)
                            .overlay(Text(stats.count(r) > 0 ? "" : "?").font(.retro(11)).foregroundStyle(Retro.cream.opacity(0.4)))
                        Text(stats.count(r) > 0 ? r.title : "???")
                            .font(.retro(8))
                            .foregroundStyle(Retro.cream.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .retroPanel()
    }

    private struct DayCount: Identifiable {
        let day: Date
        let count: Int
        var id: Date { day }
    }

    private var lastTwoWeeks: [DayCount] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var counts: [Date: Int] = [:]
        for c in creatures { counts[cal.startOfDay(for: c.capturedAt), default: 0] += 1 }
        return (0..<14).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayCount(day: d, count: counts[d] ?? 0)
        }
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Últimos 14 días", icon: "calendar")
            Chart(lastTwoWeeks) { item in
                BarMark(x: .value("Día", item.day, unit: .day), y: .value("Capturas", item.count))
                    .foregroundStyle(Retro.yellow)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.retro(8)).foregroundStyle(Retro.cream.opacity(0.7))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Retro.cream.opacity(0.15))
                    AxisValueLabel().font(.retro(9)).foregroundStyle(Retro.cream.opacity(0.6))
                }
            }
            .frame(height: 130)
        }
        .retroPanel()
    }

    private func luckPanel(_ stats: CollectionStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Tu suerte", icon: "dice.fill")
            HStack {
                Text("RAREZA").frame(maxWidth: .infinity, alignment: .leading)
                Text("TÚ").frame(width: 70, alignment: .trailing)
                Text("ESPERADO").frame(width: 80, alignment: .trailing)
            }
            .font(.retro(9))
            .foregroundStyle(Retro.cyan)
            ForEach(Rarity.allCases) { r in
                let mine = stats.total > 0 ? Double(stats.count(r)) / Double(stats.total) : 0
                let expected = settings.probability(r)
                HStack {
                    Text(r.title).foregroundStyle(r.color).frame(maxWidth: .infinity, alignment: .leading)
                    Text(String(format: "%.1f%%", mine * 100))
                        .foregroundStyle(mine >= expected ? Retro.green : Retro.cream)
                        .frame(width: 70, alignment: .trailing)
                    Text(String(format: "%.2f%%", expected * 100))
                        .foregroundStyle(Retro.cream.opacity(0.7))
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.retro(11))
            }
        }
        .retroPanel()
    }

    private func recordsPanel(_ stats: CollectionStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Récords", icon: "crown.fill")
            if let highest = stats.highest {
                record("Rareza máxima", highest.title, highest.color)
            }
            if let strongest = stats.strongest {
                record("Más poderosa", "\(strongest.displayName) · \(strongest.totalPower)", Retro.orange)
            }
            if let first = stats.first {
                record("Primera captura", first.formatted(date: .abbreviated, time: .omitted), Retro.cream)
            }
            if let last = stats.last {
                record("Última captura", last.formatted(date: .abbreviated, time: .shortened), Retro.cream)
            }
        }
        .retroPanel()
    }

    private func record(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(alignment: .top) {
            Text(label.uppercased()).font(.retro(10)).foregroundStyle(Retro.cyan)
            Spacer()
            Text(value).font(.retro(12)).foregroundStyle(color).multilineTextAlignment(.trailing)
        }
    }
}

/// Anillo de progreso segmentado (look de HUD de los 90).
struct SegmentRing: View {
    let progress: Double
    var segments = 24
    var color: Color = Retro.green

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2
            let inner = outer * 0.72
            let lit = Int((progress * Double(segments)).rounded())
            for i in 0..<segments {
                let gap = 0.06
                let a0 = Double(i) / Double(segments) * 2 * .pi - .pi / 2 + gap
                let a1 = Double(i + 1) / Double(segments) * 2 * .pi - .pi / 2 - gap
                var p = Path()
                p.move(to: CGPoint(x: center.x + inner * cos(a0), y: center.y + inner * sin(a0)))
                p.addLine(to: CGPoint(x: center.x + outer * cos(a0), y: center.y + outer * sin(a0)))
                p.addLine(to: CGPoint(x: center.x + outer * cos(a1), y: center.y + outer * sin(a1)))
                p.addLine(to: CGPoint(x: center.x + inner * cos(a1), y: center.y + inner * sin(a1)))
                p.closeSubpath()
                ctx.fill(p, with: .color(i < lit ? color : Color.white.opacity(0.1)))
            }
        }
        .accessibilityLabel("Completado \(Int(progress * 100)) por ciento")
    }
}
