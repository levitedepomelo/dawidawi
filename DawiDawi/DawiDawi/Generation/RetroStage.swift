import SceneKit
import UIKit
import Metal

/// Escenario 3D retro: suelo de ajedrez, pared de madera, niebla, luz vertex-lit y la criatura en una peana giratoria.
/// Inspirado en la estética de la imagen de referencia (render PS1/N64).
final class RetroStage {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let turntable = SCNNode()
    let creatureNode = SCNNode()
    let rarity: Rarity
    private(set) var triangleCount = 0

    init(sprite: CGImage, rarity: Rarity, seed: Int, meshDensity: Int, showcase: Bool) {
        self.rarity = rarity
        buildEnvironment()
        buildCreature(sprite: sprite, seed: seed, meshDensity: meshDensity)
        buildLights()
        if showcase { addSparkles() }
    }

    // MARK: Entorno

    private func buildEnvironment() {
        scene.background.contents = UIColor(red: 0.04, green: 0.05, blue: 0.12, alpha: 1)
        scene.fogColor = UIColor(red: 0.05, green: 0.05, blue: 0.10, alpha: 1)
        scene.fogStartDistance = 5
        scene.fogEndDistance = 15

        let floor = SCNPlane(width: 30, height: 30)
        let floorMat = Self.pixelMaterial(Self.checkerTexture)
        floorMat.diffuse.wrapS = .repeat
        floorMat.diffuse.wrapT = .repeat
        floorMat.diffuse.contentsTransform = SCNMatrix4MakeScale(30, 30, 1)
        floor.materials = [floorMat]
        let floorNode = SCNNode(geometry: floor)
        floorNode.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(floorNode)

        let wall = SCNPlane(width: 30, height: 12)
        let wallMat = Self.pixelMaterial(Self.woodTexture)
        wallMat.diffuse.wrapS = .repeat
        wallMat.diffuse.wrapT = .repeat
        wallMat.diffuse.contentsTransform = SCNMatrix4MakeScale(14, 3, 1)
        wall.materials = [wallMat]
        let wallNode = SCNNode(geometry: wall)
        wallNode.position = SCNVector3(0, 5.5, -3.2)
        scene.rootNode.addChildNode(wallNode)

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
        mesh.geometry.materials = [frontMat, backMat]
        creatureNode.geometry = mesh.geometry

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
    func snapshot(size: CGSize = CGSize(width: 132, height: 160)) -> UIImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        turntable.removeAllActions()
        turntable.eulerAngles.y = 0.35
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .none)
    }

    // MARK: Texturas procedurales

    static func pixelMaterial(_ contents: Any) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = contents
        m.diffuse.magnificationFilter = .nearest
        m.diffuse.minificationFilter = .nearest
        m.diffuse.mipFilter = .none
        m.lightingModel = .lambert
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

    static let checkerTexture: CGImage? = pixelImage(width: 2, height: 2) { x, y in
        (x + y) % 2 == 0 ? UIColor(white: 0.92, alpha: 1) : UIColor(white: 0.07, alpha: 1)
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
