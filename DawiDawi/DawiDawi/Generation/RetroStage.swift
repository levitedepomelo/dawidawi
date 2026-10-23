import SceneKit
import UIKit
import Metal

/// Escenario 3D retro: suelo de ajedrez, pared de madera, niebla, luz vertex-lit y la criatura en una peana giratoria.
/// Inspirado en la estética de la imagen de referencia (render PS1/N64).
/// `@unchecked Sendable`: se construye una sola vez (a veces en segundo plano) y a partir de ahí solo
/// la usa el hilo principal y el render de SceneKit.
final class RetroStage: @unchecked Sendable {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let turntable = SCNNode()
    let creatureNode = SCNNode()
    let rarity: Rarity
    private(set) var triangleCount = 0
    private let rig: CreatureRig?
    private let photo: UIImage?
    private let cutout: CGImage?
    private let face: CGRect?

    init(sprite: CGImage, rarity: Rarity, seed: Int, meshDensity: Int, showcase: Bool,
         rig: CreatureRig? = nil, photo: UIImage? = nil, cutout: CGImage? = nil, face: CGRect? = nil) {
        self.rig = rig
        self.photo = photo
        self.cutout = cutout
        self.face = face
        self.rarity = rarity
        buildEnvironment()
        buildCreature(sprite: sprite, seed: seed, meshDensity: meshDensity)
        buildLights()
        if showcase { addSparkles() }
    }

    // MARK: Entorno

    private func buildEnvironment() {
        scene.background.contents = Self.skyTexture
        scene.fogColor = UIColor(red: 0.80, green: 0.93, blue: 1.0, alpha: 1)
        scene.fogStartDistance = 4
        scene.fogEndDistance = 13

        let floor = SCNPlane(width: 30, height: 30)
        let floorMat = Self.pixelMaterial(Self.checkerTexture as Any, crisp: true)
        floorMat.diffuse.wrapS = .repeat
        floorMat.diffuse.wrapT = .repeat
        floorMat.diffuse.contentsTransform = SCNMatrix4MakeScale(30, 30, 1)
        floor.materials = [floorMat]
        let floorNode = SCNNode(geometry: floor)
        floorNode.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(floorNode)

        let shadow = SCNPlane(width: 1.5, height: 0.7)
        let shadowMat = SCNMaterial()
        shadowMat.diffuse.contents = Self.shadowTexture
        shadowMat.lightingModel = .constant
        shadowMat.writesToDepthBuffer = false
        shadowMat.diffuse.magnificationFilter = .nearest
        shadow.materials = [shadowMat]
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.eulerAngles.x = -.pi / 2
        shadowNode.position = SCNVector3(0, 0.004, 0)
        shadowNode.renderingOrder = -1
        scene.rootNode.addChildNode(shadowNode)

        let camera = SCNCamera()
        camera.fieldOfView = 40
        camera.zNear = 0.1
        camera.zFar = 40
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.0, 3.5)
        cameraNode.look(at: SCNVector3(0, 0.72, 0))
        scene.rootNode.addChildNode(cameraNode)
    }

    private func buildCreature(sprite: CGImage, seed: Int, meshDensity: Int) {
        scene.rootNode.addChildNode(turntable)
        turntable.addChildNode(creatureNode)

        // 1) Muñeco diseñado por el escultor IA  2) muñeco automático por piezas  3) silueta inflada
        let figure: FigureBuilder.Figure?
        if let rig, let photo, let sculpted = RigBuilder.build(rig: rig, photo: photo) {
            figure = sculpted
        } else if (UserDefaults.standard.string(forKey: "gen.style") ?? "figure") == "figure" {
            figure = FigureBuilder.build(sprite: sprite, cutout: cutout, face: face, seed: seed)
        } else {
            figure = nil
        }
        if let figure {
            triangleCount = figure.triangleCount
            creatureNode.addChildNode(figure.node)
            let scale = min(1.55 / max(figure.height, 0.01), 2.0 / max(figure.width, 0.01))
            creatureNode.scale = SCNVector3(scale, scale, scale)
            let base = scale
            let hop = SCNAction.customAction(duration: 1.8) { node, elapsed in
                let t = Float(elapsed / 1.8) * 2 * .pi
                node.scale = SCNVector3(base * (1 - 0.012 * sin(t)), base * (1 + 0.03 * sin(t)), base)
            }
            creatureNode.runAction(.repeatForever(hop), forKey: "breathe")
            startSpin()
            return
        }

        guard let mesh = MeshBuilder.build(sprite: sprite, grid: meshDensity, seed: seed) else {
            // Sin silueta usable: tarjeta plana (alternativa 2D)
            let plane = SCNPlane(width: 1.3, height: 1.3)
            let mat = Self.pixelMaterial(sprite)
            mat.isDoubleSided = true
            mat.transparencyMode = .aOne
            plane.materials = [mat]
            creatureNode.geometry = plane
            creatureNode.position = SCNVector3(0, 0.65, 0)
            return
        }
        triangleCount = mesh.triangleCount
        let texture = RetroStylizer.dilatedOpaque(sprite) ?? sprite
        let frontMat = Self.pixelMaterial(texture)
        let backMat = Self.pixelMaterial(texture)
        backMat.multiply.contents = UIColor(white: 0.72, alpha: 1)
        for part in mesh.parts {
            part.geometry.materials = [frontMat, backMat]
            let node = SCNNode(geometry: part.geometry)
            // Pivote en el punto de unión → la pieza gira "desde" el cuerpo
            node.pivot = SCNMatrix4MakeTranslation(part.anchor.x, part.anchor.y, 0)
            node.position = SCNVector3(part.anchor.x, part.anchor.y, part.zOffset)
            if part.zOffset < 0 {
                // Pata trasera: un poco más oscura, como sombreado de vértices
                let darker = Self.pixelMaterial(texture)
                darker.multiply.contents = UIColor(white: 0.8, alpha: 1)
                let geometry = part.geometry.copy() as! SCNGeometry
                geometry.materials = [darker, backMat]
                node.geometry = geometry
            }
            Self.animate(node, part: part)
            creatureNode.addChildNode(node)
        }

        let scale = min(1.55 / max(mesh.height, 0.01), 2.0 / max(mesh.width, 0.01))
        creatureNode.pivot = SCNMatrix4MakeTranslation(mesh.centerX, mesh.minY, 0)
        creatureNode.scale = SCNVector3(scale, scale, scale)

        // Respiración idle (escala Y)
        let base = scale
        let breathe = SCNAction.customAction(duration: 1.8) { node, elapsed in
            let t = Float(elapsed / 1.8) * 2 * .pi
            let s = base * (1 + 0.025 * sin(t))
            node.scale = SCNVector3(base * (1 - 0.01 * sin(t)), s, base)
        }
        creatureNode.runAction(.repeatForever(breathe), forKey: "breathe")
        startSpin()
    }

    /// Animación idle de cada pieza según su tipo (pura forma, sin saber qué animal es).
    private static func animate(_ node: SCNNode, part: MeshBuilder.Part) {
        let axis: SCNVector3
        let amplitude: Float
        let period: Double
        switch part.kind {
        case .body: return
        case .leg: axis = SCNVector3(0, 0, 1); amplitude = 0.10; period = 1.4
        case .top: axis = SCNVector3(0, 0, 1); amplitude = 0.07; period = 2.3
        case .side: axis = SCNVector3(0, 1, 0); amplitude = 0.28; period = 1.1
        }
        let phase = part.phase
        let action = SCNAction.customAction(duration: period) { n, elapsed in
            let t = Float(elapsed / period) * 2 * .pi + phase
            n.rotation = SCNVector4(axis.x, axis.y, axis.z, amplitude * sin(t))
        }
        node.runAction(.repeatForever(action), forKey: "idle")
    }

    private func buildLights() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        ambient.light?.color = UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 850
        key.light?.color = UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 1)
        key.eulerAngles = SCNVector3(-0.85, 0.55, 0)
        scene.rootNode.addChildNode(key)

        if rarity >= .rare {
            let rim = SCNNode()
            rim.light = SCNLight()
            rim.light?.type = .omni
            rim.light?.color = rarity.uiColor
            rim.light?.intensity = CGFloat(300 + rarity.tier * 220)
            rim.light?.attenuationStartDistance = 0.5
            rim.light?.attenuationEndDistance = 4
            rim.position = SCNVector3(0, 1.4, -1.2)
            scene.rootNode.addChildNode(rim)
        }
    }

    private func addSparkles() {
        guard rarity >= .uncommon else { return }
        let ps = SCNParticleSystem()
        ps.particleImage = Self.squareParticle
        ps.birthRate = CGFloat(4 + rarity.tier * 7)
        ps.particleLifeSpan = 2.4
        ps.particleLifeSpanVariation = 0.8
        ps.particleSize = 0.035
        ps.particleSizeVariation = 0.015
        ps.particleColor = rarity.uiColor
        if rarity == .mythic {
            ps.particleColorVariation = SCNVector4(180, 0.2, 0.2, 0)
        }
        ps.emitterShape = SCNBox(width: 1.8, height: 0.05, length: 1.0, chamferRadius: 0)
        ps.emittingDirection = SCNVector3(0, 1, 0)
        ps.spreadingAngle = 18
        ps.particleVelocity = 0.45
        ps.particleVelocityVariation = 0.2
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        ps.isAffectedByGravity = false
        let node = SCNNode()
        node.position = SCNVector3(0, 0.05, 0)
        node.addParticleSystem(ps)
        scene.rootNode.addChildNode(node)
    }

    // MARK: Animaciones

    func startSpin(duration: TimeInterval = 9) {
        turntable.removeAction(forKey: "spin")
        turntable.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: duration)), forKey: "spin")
    }

    func stopSpin() { turntable.removeAction(forKey: "spin") }

    /// Entrada triunfal: aparece desde la nada con salto.
    func playEntrance() {
        turntable.scale = SCNVector3(0.01, 0.01, 0.01)
        turntable.position = SCNVector3(0, 0.6, 0)
        let grow = SCNAction.scale(to: 1, duration: 0.45)
        grow.timingMode = .easeOut
        let fall = SCNAction.move(to: SCNVector3(0, 0, 0), duration: 0.45)
        fall.timingMode = .easeIn
        let hopUp = SCNAction.moveBy(x: 0, y: 0.18, z: 0, duration: 0.14)
        hopUp.timingMode = .easeOut
        let hopDown = SCNAction.moveBy(x: 0, y: -0.18, z: 0, duration: 0.14)
        hopDown.timingMode = .easeIn
        turntable.runAction(.sequence([.group([grow, fall]), hopUp, hopDown]))
    }

    // MARK: Snapshot (miniatura de la galería)

    /// Render offscreen a baja resolución → miniatura auténticamente pixelada.
    @MainActor
    func snapshot(size: CGSize = GraphicsStyle.isRetro ? CGSize(width: 132, height: 160) : CGSize(width: 264, height: 320)) -> UIImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        turntable.removeAllActions()
        turntable.eulerAngles.y = 0.35
        return renderer.snapshot(atTime: 0, with: size,
                                 antialiasingMode: GraphicsStyle.isRetro ? .none : .multisampling4X)
    }

    // MARK: Texturas procedurales

    /// Material texturizado. En estilo Retro (o con `crisp`) usa filtrado "vecino más cercano";
    /// en HD, filtrado lineal con mipmaps y un brillo especular suave.
    static func pixelMaterial(_ contents: Any, crisp: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = contents
        if crisp || GraphicsStyle.isRetro {
            m.diffuse.magnificationFilter = .nearest
            m.diffuse.minificationFilter = .nearest
            m.diffuse.mipFilter = .none
            m.lightingModel = .lambert
        } else {
            m.diffuse.magnificationFilter = .linear
            m.diffuse.minificationFilter = .linear
            m.diffuse.mipFilter = .linear
            m.lightingModel = .blinn
            m.specular.contents = UIColor(white: 0.12, alpha: 1)
            m.shininess = 0.25
        }
        m.locksAmbientWithDiffuse = true
        return m
    }

    private static func pixelImage(width: Int, height: Int, _ painter: (Int, Int) -> UIColor) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            for y in 0..<height {
                for x in 0..<width {
                    painter(x, y).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return image.cgImage
    }

    /// Césped en cuadros (dos verdes), como los jardines de los menús de mediados de los 2000.
    static let checkerTexture: CGImage? = pixelImage(width: 2, height: 2) { x, y in
        (x + y) % 2 == 0 ? UIColor(red: 0.50, green: 0.85, blue: 0.28, alpha: 1)
                         : UIColor(red: 0.36, green: 0.72, blue: 0.20, alpha: 1)
    }

    /// Cielo degradado para el fondo de la escena.
    static let skyTexture: CGImage? = pixelImage(width: 1, height: 32) { _, y in
        let t = CGFloat(y) / 31
        return UIColor(red: 0.16 + 0.62 * t, green: 0.52 + 0.40 * t, blue: 0.93 + 0.07 * t, alpha: 1)
    }

    static let woodTexture: CGImage? = {
        var rng = SeededGenerator(seed: 42)
        let grain = (0..<16).map { _ in Double.random(in: -0.08...0.08, using: &rng) }
        let noise = (0..<(16 * 32)).map { _ in Double.random(in: -0.05...0.05, using: &rng) }
        return pixelImage(width: 16, height: 32) { x, y in
            let band = (x / 2) % 2 == 0 ? 0.0 : -0.09
            let knot = (x == 5 && (y % 13 < 3)) || (x == 12 && (y % 17 < 2)) ? -0.25 : 0
            let v = 1 + band + grain[x] + noise[y * 16 + x] + knot
            return UIColor(red: 0.74 * v, green: 0.55 * v, blue: 0.14 * v, alpha: 1)
        }
    }()

    static let shadowTexture: CGImage? = pixelImage(width: 16, height: 8) { x, y in
        let dx = (Double(x) + 0.5 - 8) / 8, dy = (Double(y) + 0.5 - 4) / 4
        let d = dx * dx + dy * dy
        return UIColor(white: 0, alpha: d < 1 ? (d < 0.45 ? 0.55 : 0.3) : 0)
    }

    static let squareParticle: UIImage = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }()
}
