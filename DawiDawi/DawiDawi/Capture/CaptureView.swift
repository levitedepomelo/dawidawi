import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation

/// Pantalla completa de captura: cámara → procesado → revelación.
struct CaptureView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject var flow = CaptureFlow()
    /// Se llama al terminar con la criatura guardada (para abrir su ficha).
    var onFinished: (Creature?) -> Void = { _ in }

    var body: some View {
        ZStack {
            switch flow.phase {
            case .camera:
                CameraHUDView(flow: flow, close: { dismiss() })
                    .transition(.opacity)
            case .generating:
                GeneratingView(photo: flow.photo, step: flow.step)
                    .transition(.opacity)
            case .reveal:
                if let creature = flow.creature, let stage = flow.stage {
                    RevealView(creature: creature, stage: stage, notice: flow.notice,
                               onDone: {
                                   onFinished(creature)
                                   dismiss()
                               },
                               onAnother: {
                                   withAnimation { flow.reset() }
                               })
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: flow.phase)
        .crt()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

// MARK: - Visor de cámara

struct CameraHUDView: View {
    @ObservedObject var flow: CaptureFlow
    let close: () -> Void

    @StateObject var camera = CameraModel()
    @ObservedObject var location = LocationProvider.shared
    @EnvironmentObject var settings: AppSettings
    @Environment(\.modelContext) var context
    @State var pickerItem: PhotosPickerItem?
    @State var flash = false
    @State var busy = false
    @State var toast: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.authorization == .authorized && camera.isAvailable {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                ViewfinderOverlay()
            } else {
                RetroBackground(floorColor: Retro.cyan)
                permissionPanel
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let toast {
                    Text(toast)
                        .font(.retro(12))
                        .foregroundStyle(Retro.cream)
                        .multilineTextAlignment(.center)
                        .retroPanel(fill: Retro.night.opacity(0.9), padding: 10)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if camera.isRunning {
                    BlinkingText(text: "▶ APUNTA A UNA CRIATURA", font: .retro(13))
                        .padding(.bottom, 14)
                        .shadow(color: .black, radius: 0, x: 2, y: 2)
                }
                bottomBar
            }

            if flash {
                Color.white.ignoresSafeArea().allowsHitTesting(false)
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .onAppear {
            if let message = flow.errorMessage {
                show(message)
                flow.errorMessage = nil
            }
        }
    }

    // MARK: Barras

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: { ChipSynth.shared.play(.back); close() }) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .black))
            }
            .buttonStyle(RetroButtonStyle(color: Retro.cream, compact: true))
            .accessibilityLabel("Cerrar cámara")

            Spacer()

            HStack(spacing: 6) {
                Circle().fill(camera.isRunning ? Color.red : Color.gray).frame(width: 9, height: 9)
                Text(camera.isRunning ? "REC" : "OFF").font(.retro(12))
            }
            .foregroundStyle(Retro.cream)
            .retroPanel(fill: Retro.night.opacity(0.85), padding: 8)

            Spacer()

            Button(action: toggleLocation) {
                Image(systemName: settings.saveLocation ? "location.fill" : "location.slash")
                    .font(.system(size: 16, weight: .black))
            }
            .buttonStyle(RetroButtonStyle(color: settings.saveLocation ? Retro.green : Retro.cream, compact: true))
            .accessibilityLabel(settings.saveLocation ? "Ubicación activada" : "Ubicación desactivada")

            Button(action: { camera.flashOn.toggle() }) {
                Image(systemName: camera.flashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 16, weight: .black))
            }
            .buttonStyle(RetroButtonStyle(color: camera.flashOn ? Retro.yellow : Retro.cream, compact: true))
            .accessibilityLabel("Flash")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 20, weight: .black))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(RetroButtonStyle(color: Retro.cyan, compact: true))
            .accessibilityLabel("Importar foto")

            Spacer()

            Button(action: shoot) {
                ShutterGraphic(busy: busy)
            }
            .buttonStyle(.plain)
            .disabled(!camera.isRunning || busy)
            .accessibilityLabel("Capturar")

            Spacer()

            Button(action: { ChipSynth.shared.play(.select); camera.flip() }) {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill").font(.system(size: 20, weight: .black))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(RetroButtonStyle(color: Retro.cyan, compact: true))
            .disabled(!camera.isRunning)
            .accessibilityLabel("Cambiar cámara")
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .padding(.top, 14)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private var permissionPanel: some View {
        VStack(spacing: 14) {
            Image(systemName: camera.isAvailable ? "camera.fill" : "camera.metering.unknown")
                .font(.system(size: 42, weight: .black))
                .foregroundStyle(Retro.yellow)
            if !camera.isAvailable {
                Text("CÁMARA NO DISPONIBLE")
                    .font(.retro(16))
                Text("Este dispositivo no tiene cámara (¿simulador?). Puedes importar una foto de tu fototeca.")
                    .font(.retro(12, weight: .semibold))
                    .multilineTextAlignment(.center)
            } else if camera.authorization == .denied || camera.authorization == .restricted {
                Text("SIN ACCESO A LA CÁMARA").font(.retro(16))
                Text("DawiDawi necesita la cámara para capturar criaturas. Actívala en Ajustes o importa una foto.")
                    .font(.retro(12, weight: .semibold))
                    .multilineTextAlignment(.center)
                Button("ABRIR AJUSTES") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(RetroButtonStyle())
            } else {
                Text("ENCENDIENDO CÁMARA...").font(.retro(14))
                ProgressView().tint(Retro.yellow)
            }
        }
        .foregroundStyle(Retro.cream)
        .retroPanel()
        .padding(28)
    }

    // MARK: Acciones

    private func shoot() {
        guard !busy else { return }
        busy = true
        ChipSynth.shared.play(.shutter)
        Haptics.tap(.heavy)
        flash = true
        Task {
            let image = await camera.capture()
            withAnimation(.easeOut(duration: 0.35)) { flash = false }
            busy = false
            if let image {
                camera.stop()
                flow.process(photo: image, context: context, settings: settings)
            } else {
                show("No se pudo tomar la foto. Inténtalo de nuevo.")
            }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            show("No se pudo abrir esa imagen.")
            return
        }
        ChipSynth.shared.play(.select)
        camera.stop()
        flow.process(photo: image, context: context, settings: settings)
    }

    private func toggleLocation() {
        ChipSynth.shared.play(.select)
        if settings.saveLocation {
            settings.saveLocation = false
            show("Ubicación desactivada")
        } else {
            settings.saveLocation = true
            if location.isDenied {
                show("La ubicación está bloqueada en Ajustes del iPhone. Se guardará sin lugar.")
            } else {
                location.requestPermissionIfNeeded()
                show("Se guardará el lugar de captura")
            }
        }
    }

    private func show(_ message: String) {
        withAnimation(.spring(response: 0.3)) { toast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            withAnimation { if toast == message { toast = nil } }
        }
    }
}

/// Botón de disparo low-poly.
struct ShutterGraphic: View {
    var busy: Bool
    @State var spin = false
    var body: some View {
        ZStack {
            LowPolyCircle(sides: 12).fill(Retro.shadow).offset(y: 5)
            LowPolyCircle(sides: 12).fill(Retro.cream)
            LowPolyCircle(sides: 12).strokeBorderCompat(Retro.night, lineWidth: 3)
            LowPolyCircle(sides: 10)
                .fill(LinearGradient(colors: [Retro.magenta, Color(red: 0.7, green: 0.05, blue: 0.3)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(10)
            LowPolyCircle(sides: 6)
                .stroke(Retro.cream.opacity(0.85), lineWidth: 3)
                .padding(24)
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .frame(width: 84, height: 84)
        .opacity(busy ? 0.6 : 1)
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}

extension Shape {
    /// strokeBorder solo existe en InsettableShape; esto da un borde equivalente para Shape genéricas.
    func strokeBorderCompat(_ color: Color, lineWidth: CGFloat) -> some View {
        self.stroke(color, lineWidth: lineWidth).padding(lineWidth / 2)
    }
}

/// Marco del visor: esquinas, retícula y datos de "escáner".
struct ViewfinderOverlay: View {
    @State var pulse = false
    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 34
            let rect = CGRect(x: inset, y: geo.size.height * 0.16,
                              width: geo.size.width - inset * 2, height: geo.size.height * 0.56)
            let len: CGFloat = 34
            ZStack {
                Path { p in
                    for (corner, dx, dy) in [(CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
                                             (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
                                             (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
                                             (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0)] {
                        p.move(to: CGPoint(x: corner.x + len * dx, y: corner.y))
                        p.addLine(to: corner)
                        p.addLine(to: CGPoint(x: corner.x, y: corner.y + len * dy))
                    }
                }
                .stroke(Retro.yellow, style: StrokeStyle(lineWidth: 5, lineCap: .square))
                .shadow(color: .black, radius: 0, x: 2, y: 2)

                LowPolyCircle(sides: 8)
                    .stroke(Retro.cream.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                    .frame(width: pulse ? 86 : 70, height: pulse ? 86 : 70)
                    .position(x: rect.midX, y: rect.midY)
                Rectangle().fill(Retro.cream.opacity(0.8)).frame(width: 18, height: 2).position(x: rect.midX, y: rect.midY)
                Rectangle().fill(Retro.cream.opacity(0.8)).frame(width: 2, height: 18).position(x: rect.midX, y: rect.midY)

                Text("DAWI-SCAN v1.0")
                    .font(.retro(10))
                    .foregroundStyle(Retro.yellow)
                    .shadow(color: .black, radius: 0, x: 1, y: 1)
                    .position(x: rect.minX + 58, y: rect.maxY + 14)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
