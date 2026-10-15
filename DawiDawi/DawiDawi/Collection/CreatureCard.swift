import SwiftUI

/// Tarjeta de la galería: miniatura renderizada del modelo 3D + marco según rareza.
struct CreatureCard: View {
    let creature: Creature

    var body: some View {
        let rarity = creature.rarity
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(rarity.gradient)
                if let thumb = CreatureStore.thumb(creature.id) {
                    PixelImage(image: thumb, contentMode: .fill)
                }
                HStack {
                    Text(creature.numberLabel)
                        .font(.retro(9))
                        .foregroundStyle(Retro.cream)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Rectangle().fill(Retro.night.opacity(0.85)))
                    Spacer()
                    if creature.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Retro.magenta)
                            .shadow(color: .black, radius: 0, x: 1, y: 1)
                    }
                }
                .padding(5)
            }
            .aspectRatio(0.82, contentMode: .fit)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(creature.displayName)
                    .font(.retro(11))
                    .foregroundStyle(Retro.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                StarsRow(count: rarity.stars, size: 7, color: rarity == .mythic ? Retro.magenta : Retro.yellow)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Retro.night)
        }
        .clipShape(PixelRect(step: 3))
        .modifier(RarityFrame(rarity: rarity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(creature.displayName), \(rarity.title), \(creature.numberLabel)")
    }
}

/// Marco animado: brillo para legendarios, arcoíris giratorio para míticos.
struct RarityFrame: ViewModifier {
    let rarity: Rarity
    @State var animate = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if rarity == .mythic {
                    PixelRect(step: 3)
                        .strokeBorder(AngularGradient(colors: [.pink, .orange, .yellow, .green, .cyan, .purple, .pink],
                                                      center: .center),
                                      lineWidth: 4)
                        .hueRotation(.degrees(animate ? 360 : 0))
                } else {
                    PixelRect(step: 3).strokeBorder(rarity.color, lineWidth: rarity >= .epic ? 4 : 3)
                }
            }
            .shadow(color: rarity >= .legendary ? rarity.color.opacity(animate ? 0.9 : 0.3) : .clear,
                    radius: rarity >= .legendary ? 10 : 0)
            .background(PixelRect(step: 3).fill(Retro.shadow).offset(x: 4, y: 4))
            .onAppear {
                guard rarity >= .legendary else { return }
                withAnimation(.linear(duration: rarity == .mythic ? 3 : 1.2).repeatForever(autoreverses: rarity != .mythic)) {
                    animate = true
                }
            }
    }
}
