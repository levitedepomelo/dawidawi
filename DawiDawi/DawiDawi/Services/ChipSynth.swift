import AVFoundation
import UIKit

/// Sintetizador chiptune en tiempo real (ondas cuadrada/triangular/ruido como las consolas de 8-16 bits).
/// Todos los efectos se generan por código: no hay ficheros de audio que licenciar ni descargar.
final class ChipSynth {
    static let shared = ChipSynth()

    var enabled = true

    enum Wave { case square(Double), triangle, saw, noise }

    struct Note {
        var midi: Int?
        var beats: Double
        var wave: Wave
        var volume: Double
        var slideTo: Int?
        var decay: Double
    }

    enum SFX: Hashable {
        case blip, select, back, shutter, tick(Int), drop, open, star, save, error, fanfare(Rarity)
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let sampleRate: Double = 44_100
    private let format: AVAudioFormat
    private var cache: [SFX: AVAudioPCMBuffer] = [:]
    private let lock = NSLock()

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        for _ in 0..<5 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.8
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            _ = self?.startIfNeeded()
        }
    }

    /// Pre-renderiza los efectos en segundo plano para que la primera reproducción sea instantánea.
    func prewarm() {
        DispatchQueue.global(qos: .utility).async {
            var all: [SFX] = [.blip, .select, .back, .shutter, .drop, .open, .star, .save, .error]
            all += (0..<8).map { SFX.tick($0) }
            all += Rarity.allCases.map { SFX.fanfare($0) }
            for sfx in all { _ = self.buffer(for: sfx) }
        }
    }

    func play(_ sfx: SFX) {
        guard enabled, let buffer = buffer(for: sfx) else { return }
        DispatchQueue.main.async {
            guard self.startIfNeeded() else { return }
            let player = self.players[self.nextPlayer]
            self.nextPlayer = (self.nextPlayer + 1) % self.players.count
            player.stop()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    private func startIfNeeded() -> Bool {
        if engine.isRunning { return true }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            engine.prepare()
            try engine.start()
            return true
        } catch {
            return false
        }
    }

    // MARK: Render

    private func buffer(for sfx: SFX) -> AVAudioPCMBuffer? {
        lock.lock()
        if let cached = cache[sfx] { lock.unlock(); return cached }
        lock.unlock()
        let (voices, bpm) = Self.score(for: sfx)
        guard let rendered = render(voices, bpm: bpm) else { return nil }
        lock.lock()
        cache[sfx] = rendered
        lock.unlock()
        return rendered
    }

    private func render(_ voices: [[Note]], bpm: Double) -> AVAudioPCMBuffer? {
        let secondsPerBeat = 60 / bpm
        let lengths = voices.map { $0.reduce(0) { $0 + $1.beats * secondsPerBeat } }
        let total = (lengths.max() ?? 0) + 0.08
        let frames = AVAudioFrameCount(total * sampleRate)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) { channel[i] = 0 }

        var noiseState: UInt32 = 0xACE1
        for voice in voices {
            var cursor = 0
            for note in voice {
                let duration = note.beats * secondsPerBeat
                let count = Int(duration * sampleRate)
                defer { cursor += count }
                guard let midi = note.midi else { continue }
                let f0 = 440 * pow(2, Double(midi - 69) / 12)
                let f1 = note.slideTo.map { 440 * pow(2, Double($0 - 69) / 12) } ?? f0
                var phase = 0.0
                var lastStep = -1
                var noiseValue = 0.0
                for s in 0..<count where cursor + s < Int(frames) {
                    let t = Double(s) / sampleRate
                    let progress = Double(s) / Double(max(1, count))
                    let f = f0 + (f1 - f0) * progress
                    phase += f / sampleRate
                    let frac = phase - floor(phase)
                    var v: Double
                    switch note.wave {
                    case .square(let duty): v = frac < duty ? 1 : -1
                    case .triangle: v = 4 * abs(frac - 0.5) - 1
                    case .saw: v = 2 * frac - 1
                    case .noise:
                        let step = Int(phase * 4)
                        if step != lastStep {
                            lastStep = step
                            // LFSR de 16 bits, como el canal de ruido de las consolas
                            let bit = ((noiseState >> 0) ^ (noiseState >> 2) ^ (noiseState >> 3) ^ (noiseState >> 5)) & 1
                            noiseState = (noiseState >> 1) | (bit << 15)
                            noiseValue = (noiseState & 1) == 1 ? 1 : -1
                        }
                        v = noiseValue
                    }
                    let attack = min(1, t / 0.004)
                    let release = min(1, (duration - t) / 0.025)
                    let env = attack * max(0, release) * exp(-t * note.decay)
                    channel[cursor + s] += Float(v * note.volume * env)
                }
            }
        }
        for i in 0..<Int(frames) { channel[i] = max(-0.95, min(0.95, channel[i])) }
        return buffer
    }

    // MARK: Partituras

    private static func n(_ midi: Int?, _ beats: Double, _ wave: Wave = .square(0.5),
                          vol: Double = 0.22, slide: Int? = nil, decay: Double = 1.5) -> Note {
        Note(midi: midi, beats: beats, wave: wave, volume: vol, slideTo: slide, decay: decay)
    }

    private static func score(for sfx: SFX) -> ([[Note]], Double) {
        let sq = Wave.square(0.5), sq25 = Wave.square(0.25), sq12 = Wave.square(0.125)
        switch sfx {
        case .blip:
            return ([[n(88, 1, sq25, vol: 0.14, decay: 20)]], 1200)
        case .select:
            return ([[n(79, 1, sq25, vol: 0.16), n(91, 2, sq25, vol: 0.16, decay: 8)]], 1000)
        case .back:
            return ([[n(84, 1, sq25, vol: 0.14), n(72, 2, sq25, vol: 0.14, decay: 8)]], 1000)
        case .shutter:
            return ([[n(100, 1, .noise, vol: 0.35, decay: 25)],
                     [n(96, 0.5, sq12, vol: 0.12), n(84, 1, sq12, vol: 0.12, decay: 10)]], 400)
        case .tick(let level):
            let base = 60 + level * 4
            return ([[n(base, 1, sq25, vol: 0.2, slide: base + 7, decay: 6)],
                     [n(110, 0.5, .noise, vol: 0.12, decay: 30)]], 700)
        case .drop:
            return ([[n(88, 3, sq, vol: 0.16, slide: 55, decay: 2)],
                     [n(nil, 2.6), n(100, 0.6, .noise, vol: 0.3, decay: 20)]], 900)
        case .open:
            return ([[n(60, 4, sq25, vol: 0.18, slide: 96, decay: 1)],
                     [n(98, 4, .noise, vol: 0.3, decay: 4)]], 700)
        case .star:
            return ([[n(96, 1, sq25, vol: 0.12, decay: 10), n(103, 2, sq25, vol: 0.1, decay: 10)]], 1400)
        case .save:
            return ([[n(72, 1, sq25), n(76, 1, sq25), n(79, 1, sq25), n(84, 3, sq25, decay: 3)],
                     [n(48, 6, .triangle, vol: 0.3, decay: 1)]], 900)
        case .error:
            return ([[n(52, 2, sq, vol: 0.16), n(47, 4, sq, vol: 0.16, decay: 3)]], 700)
        case .fanfare(let rarity):
            return fanfare(rarity)
        }
    }

    private static func fanfare(_ rarity: Rarity) -> ([[Note]], Double) {
        let sq = Wave.square(0.5), sq25 = Wave.square(0.25)
        func seq(_ notes: [(Int?, Double)], _ wave: Wave, vol: Double = 0.2, decay: Double = 1.2) -> [Note] {
            notes.map { n($0.0, $0.1, wave, vol: vol, decay: decay) }
        }
        switch rarity {
        case .common:
            return ([seq([(72, 1), (76, 1), (79, 3)], sq25),
                     seq([(48, 5)], .triangle, vol: 0.32)], 480)
        case .uncommon:
            return ([seq([(72, 1), (76, 1), (79, 1), (84, 4)], sq25),
                     seq([(64, 1), (67, 1), (72, 1), (76, 4)], sq, vol: 0.1),
                     seq([(48, 3), (55, 4)], .triangle, vol: 0.32)], 480)
        case .rare:
            return ([seq([(67, 1), (72, 1), (76, 1), (79, 1), (84, 2), (83, 1), (84, 5)], sq25),
                     seq([(64, 1), (67, 1), (72, 1), (76, 1), (79, 2), (79, 1), (79, 5)], sq, vol: 0.1),
                     seq([(48, 2), (55, 2), (48, 2), (43, 1), (48, 5)], .triangle, vol: 0.34)], 440)
        case .epic:
            return ([seq([(69, 1), (72, 1), (76, 1), (81, 3), (79, 1), (81, 1), (84, 2), (88, 6)], sq25),
                     seq([(64, 1), (69, 1), (72, 1), (76, 3), (76, 1), (77, 1), (79, 2), (84, 6)], sq, vol: 0.1),
                     seq([(45, 3), (41, 3), (43, 3), (48, 8)], .triangle, vol: 0.34),
                     seq([(nil, 6), (100, 0.5), (nil, 1.5), (100, 0.5), (nil, 1.5), (100, 1)], .noise, vol: 0.18, decay: 12)], 400)
        case .legendary:
            return ([seq([(67, 0.5), (67, 0.5), (67, 0.5), (72, 3), (nil, 0.5), (70, 1), (72, 1), (74, 1), (76, 2), (79, 2), (84, 8)], sq25),
                     seq([(64, 0.5), (64, 0.5), (64, 0.5), (67, 3), (nil, 0.5), (65, 1), (67, 1), (70, 1), (72, 2), (76, 2), (79, 8)], sq, vol: 0.11),
                     seq([(48, 1.5), (48, 3), (nil, 0.5), (46, 3), (43, 4), (36, 8)], .triangle, vol: 0.36),
                     seq([(100, 0.5), (nil, 1), (100, 0.5), (nil, 3), (100, 0.5), (nil, 2.5), (100, 0.5), (nil, 1.5), (100, 0.5), (nil, 1.5), (98, 4)], .noise, vol: 0.2, decay: 8)], 360)
        case .mythic:
            let sweep = (0..<24).map { (Int?(60 + $0 * 2), 0.25) }
            let lead = sweep + [(nil, 0.5), (84, 2), (88, 2), (91, 2), (96, 2), (95, 1), (96, 1), (100, 10)]
            let harm = sweep.map { (Int?(($0.0 ?? 60) - 12), $0.1) } + [(nil, 0.5), (79, 2), (84, 2), (88, 2), (91, 2), (91, 1), (91, 1), (96, 10)]
            return ([seq(lead, sq25, vol: 0.19, decay: 0.8),
                     seq(harm, sq, vol: 0.09, decay: 0.8),
                     seq([(nil, 6.5), (36, 4), (43, 4), (48, 2), (36, 10)], .triangle, vol: 0.38, decay: 0.6),
                     seq([(nil, 6.5), (100, 0.5), (nil, 3.5), (100, 0.5), (nil, 3.5), (100, 0.5), (nil, 1.5), (96, 8)], .noise, vol: 0.22, decay: 6),
                     seq((0..<20).map { (Int?(96 + ($0 % 5) * 3), 0.5) }, Wave.square(0.125), vol: 0.06, decay: 4)], 420)
        }
    }
}

/// Vibraciones hápticas (respetando el ajuste del usuario).
enum Haptics {
    static var enabled = true

    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Ráfaga proporcional a la rareza.
    static func reveal(_ rarity: Rarity) {
        guard enabled else { return }
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        heavy.prepare()
        heavy.impactOccurred(intensity: 1)
        for i in 0..<rarity.tier {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(i + 1)) {
                UIImpactFeedbackGenerator(style: i % 2 == 0 ? .rigid : .medium).impactOccurred()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * Double(rarity.tier + 1)) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
