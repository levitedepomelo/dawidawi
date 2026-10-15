import SwiftUI

/// Pantalla de "procesado": la foto se va pixelando mientras una consola retro
/// muestra los pasos reales del pipeline.
struct GeneratingView: View {
    let photo: UIImage?
    let step: GenerationStep
    @EnvironmentObject var settings: AppSettings
    @State var mosaics: [UIImage] = []
    @State var scan: CGFloat = 0

    private var visibleSteps: [GenerationStep] {
        GenerationStep.allCases.filter { s in
            s != .done && (s != .remoteRender || settings.generationMode == .remote)
        }
    }

    private var mosaicIndex: Int {
        guard !mosaics.isEmpty else { return 0 }
        let order: [GenerationStep: Int] = [.preparing: 0, .remoteRender: 1, .extracting: 1, .pixelating: 2,
                                            .modeling: 3, .rollingRarity: 4, .done: 4]
        return min(mosaics.count - 1, order[step] ?? 0)
    }

    var body: some View {
        ZStack {
            RetroBackground(floorColor: Retro.cyan)
            VStack(spacing: 22) {
                ExtrudedText(text: "PROCESANDO", size: 34, fill: [Retro.cyan, Color(red: 0.1, green: 0.5, blue: 0.9)],
                             depthColor: Color(red: 0.05, green: 0.15, blue: 0.4))
                    .padding(.top, 30)

                ZStack {
                    if !mosaics.isEmpty {
                        PixelImage(image: mosaics[mosaicIndex], contentMode: .fill)
                            .frame(width: 240, height: 240)
                            .clipped()
                            .animation(.none, value: mosaicIndex)
                    } else if let photo {
                        Image(uiImage: photo).resizable().scaledToFill().frame(width: 240, height: 240).clipped()
                    }
                    // Línea de escaneo
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, Retro.cyan.opacity(0.85), .clear],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: 26)
                        .offset(y: -120 + scan * 240)
                        .blendMode(.screen)
                }
                .frame(width: 240, height: 240)
                .clipShape(Rectangle())
                .overlay(PixelRect(step: 4).strokeBorder(Retro.cream, lineWidth: 4))
                .shadow(color: .black.opacity(0.8), radius: 0, x: 6, y: 6)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleSteps, id: \.self) { s in
                        HStack(spacing: 8) {
                            Text(s.rawValue < step.rawValue ? "✓" : (s == step ? "▶" : "·"))
                                .foregroundStyle(s.rawValue < step.rawValue ? Retro.green : Retro.yellow)
                                .frame(width: 16)
                            Text(s.label.uppercased())
                                .foregroundStyle(s.rawValue <= step.rawValue ? Retro.cream : Retro.cream.opacity(0.35))
                            Spacer()
                            if s.rawValue < step.rawValue {
                                Text("OK").foregroundStyle(Retro.green)
                            } else if s == step {
                                BlinkingText(text: "...", font: .retro(12), color: Retro.yellow)
                            }
                        }
                        .font(.retro(12))
                    }
                    PixelBar(value: Double(step.rawValue) / Double(GenerationStep.done.rawValue),
                             segments: 20, color: Retro.cyan)
                        .padding(.top, 6)
                }
                .retroPanel(fill: Retro.night.opacity(0.92))
                .padding(.horizontal, 24)
                .animation(.easeOut(duration: 0.2), value: step)

                Spacer()
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { scan = 1 }
            buildMosaics()
        }
    }

    private func buildMosaics() {
        guard let photo, mosaics.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            let sizes: [CGFloat] = [96, 48, 32, 22, 16]
            let images = sizes.map { Self.downsample(photo, to: $0) }
            await MainActor.run { mosaics = images }
        }
    }

    nonisolated static func downsample(_ image: UIImage, to side: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let aspect = image.size.width / max(image.size.height, 1)
        let size = aspect > 1 ? CGSize(width: side * aspect, height: side) : CGSize(width: side, height: side / aspect)
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
