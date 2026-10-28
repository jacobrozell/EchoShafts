import SpriteKit
import UIKit
import EchoSim

enum TileArt {
    static let tile: CGFloat = 54
    static let colors = [
        "#2a1c12", "#3c332b", "#6a4030", "#145a86",
        "#6e4030", "#1e3418", "#7d5fd0", "#8d5a30",
    ]
    static let textures: [SKTexture] = colors.map { solid($0) }

    static func solid(_ hex: String) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            uiColor(hex).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }
}

func uiColor(_ hex: String) -> UIColor {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    var value: UInt64 = 0
    Scanner(string: s).scanHexInt64(&value)
    return UIColor(
        red: CGFloat((value >> 16) & 0xff) / 255,
        green: CGFloat((value >> 8) & 0xff) / 255,
        blue: CGFloat(value & 0xff) / 255,
        alpha: 1
    )
}

func nodePoint(_ x: Double, _ y: Double) -> CGPoint {
    CGPoint(x: x * TileArt.tile, y: -y * TileArt.tile)
}

enum WorldFrame {
    static let width: CGFloat = 800
    static let height: CGFloat = 400
    static let zoom: CGFloat = 1.25
    static var halfX: Double { Double(width * zoom / 2 / TileArt.tile) }
    static var halfY: Double { Double(height * zoom / 2 / TileArt.tile) }
}

class WorldScene: SKScene {
    let session: GameSession
    let map: TileMap
    var showsStalls: Bool { false }
    private var actors: [String: SKNode] = [:]
    private let wedgeNode = SKShapeNode()
    private var built = false

    init(session: GameSession, map: TileMap) {
        self.session = session
        self.map = map
        super.init(size: CGSize(width: WorldFrame.width, height: WorldFrame.height))
        scaleMode = .resizeFill
        backgroundColor = uiColor("#100d0b")
        anchorPoint = .zero
        let cameraNode = SKCameraNode()
        cameraNode.setScale(WorldFrame.zoom)
        camera = cameraNode
        addChild(cameraNode)
        wedgeNode.strokeColor = .clear
        wedgeNode.zPosition = 4000
        wedgeNode.isHidden = true
        addChild(wedgeNode)
    }

    required init?(coder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        if built { return }
        built = true
        buildTiles()
        if showsStalls { buildStalls() }
    }

    override func update(_ currentTime: TimeInterval) {
        session.advance(currentTime)
        redraw(currentTime)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !showsStalls, let touch = touches.first else { return }
        let p = touch.location(in: self)
        session.lock(at: Vec2(x: Double(p.x / TileArt.tile), y: Double(-p.y / TileArt.tile)))
    }

    func activePlayer() -> Player? { nil }
    func activeSim() -> Simulation? { nil }

    private func buildTiles() {
        let tile = TileArt.tile
        var y = 0
        while y < map.h {
            var x = 0
            while x < map.w {
                let id = map.get(x, y)
                let index = min(max(id, 0), TileArt.textures.count - 1)
                let sprite = SKSpriteNode(texture: TileArt.textures[index], size: CGSize(width: tile, height: tile))
                sprite.position = nodePoint(Double(x) + 0.5, Double(y) + 0.5)
                sprite.zPosition = 0
                addChild(sprite)
                if id == Int(Tile.tree.rawValue) {
                    let canopy = SKShapeNode(circleOfRadius: 16)
                    canopy.fillColor = uiColor("#2f7a32")
                    canopy.strokeColor = .clear
                    canopy.position = nodePoint(Double(x) + 0.5, Double(y) + 1)
                    canopy.zPosition = Double(y) + 0.9
                    addChild(canopy)
                }
                x += 1
            }
            y += 1
        }
    }

    private func buildStalls() {
        for station in STATIONS {
            let node = SKNode()
            node.position = nodePoint(station.x, station.y)
            node.zPosition = station.y
            let mark = SKShapeNode(circleOfRadius: 9)
            mark.fillColor = uiColor(station.color)
            mark.strokeColor = .clear
            node.addChild(mark)
            let label = SKLabelNode(text: station.name)
            label.fontName = "Helvetica"
            label.fontSize = 15
            label.fontColor = uiColor("#f6efe4")
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: 0.85 * TileArt.tile)
            node.addChild(label)
            addChild(node)
        }
    }

    private func redraw(_ now: TimeInterval) {
        guard let player = activePlayer(), let sim = activeSim() else { return }
        camera?.position = nodePoint(player.pos.x, player.pos.y)
        var live = Set<String>()
        syncPlayer(player, now: now, live: &live)
        for m in sim.monsters.all where !m.dead {
            syncMonster(m, player: player, now: now, live: &live)
        }
        for pr in sim.projectiles.all {
            syncProjectile(pr, live: &live)
        }
        for z in sim.zones.all {
            syncZone(z, live: &live)
        }
        for g in sim.loot.all {
            syncGlobe(g, live: &live)
        }
        for key in actors.keys where !live.contains(key) {
            actors[key]?.removeFromParent()
            actors[key] = nil
        }
        syncWedge(player, now: now)
    }

    private func node(for key: String, make: () -> SKNode) -> SKNode {
        if let existing = actors[key] { return existing }
        let created = make()
        actors[key] = created
        addChild(created)
        return created
    }

    private func syncPlayer(_ player: Player, now: TimeInterval, live: inout Set<String>) {
        let key = "player"
        live.insert(key)
        let radius = 0.42 * TileArt.tile
        let node = self.node(for: key) {
            let body = SKShapeNode(circleOfRadius: radius)
            body.strokeColor = .clear
            body.name = "body"
            let ring = SKShapeNode(circleOfRadius: radius + 3)
            ring.strokeColor = uiColor("#dc2832")
            ring.lineWidth = 2
            ring.fillColor = .clear
            ring.name = "echo"
            ring.isHidden = true
            let root = SKNode()
            root.addChild(body)
            root.addChild(ring)
            return root
        }
        node.position = nodePoint(player.pos.x, player.pos.y)
        node.zPosition = player.pos.y
        if let body = node.childNode(withName: "body") as? SKShapeNode {
            let flashed = (session.hitUntil[player.id] ?? 0) > now
            body.fillColor = flashed ? .white : uiColor("#e9c49a")
            body.alpha = player.dead ? 0.45 : 1
        }
        if let ring = node.childNode(withName: "echo") {
            ring.isHidden = player.resource < 80
        }
    }

    private func syncMonster(_ monster: Monster, player: Player, now: TimeInterval, live: inout Set<String>) {
        let key = "m\(monster.id)"
        live.insert(key)
        let diameter = CGFloat(monster.radius * 2) * TileArt.tile
        let node = self.node(for: key) {
            let body: SKNode
            if monster.def.shape == .boss {
                let square = SKSpriteNode(color: uiColor(monster.def.color), size: CGSize(width: diameter, height: diameter))
                square.zRotation = .pi / 4
                square.name = "body"
                body = square
            } else if monster.def.ai == .ranged {
                let r = diameter / 2
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: r))
                path.addLine(to: CGPoint(x: r * 0.72, y: 0))
                path.addLine(to: CGPoint(x: 0, y: -r))
                path.addLine(to: CGPoint(x: -r * 0.72, y: 0))
                path.closeSubpath()
                let diamond = SKShapeNode(path: path)
                diamond.fillColor = uiColor(monster.def.color)
                diamond.strokeColor = .clear
                diamond.name = "body"
                body = diamond
            } else {
                let circle = SKShapeNode(circleOfRadius: diameter / 2)
                circle.fillColor = uiColor(monster.def.color)
                circle.strokeColor = .clear
                circle.name = "body"
                body = circle
            }
            let ring = SKShapeNode(circleOfRadius: diameter / 2 + 3)
            ring.strokeColor = uiColor("#e9c49a")
            ring.lineWidth = 2
            ring.fillColor = .clear
            ring.name = "lock"
            ring.isHidden = true
            let root = SKNode()
            root.addChild(body)
            root.addChild(ring)
            return root
        }
        node.position = nodePoint(monster.pos.x, monster.pos.y)
        node.zPosition = monster.pos.y
        node.alpha = monster.kind == "pet" ? 0.82 : 1
        let flashed = (session.hitUntil[monster.id] ?? 0) > now
        if let circle = node.childNode(withName: "body") as? SKShapeNode {
            circle.fillColor = flashed ? .white : uiColor(monster.def.color)
        } else if let square = node.childNode(withName: "body") as? SKSpriteNode {
            square.color = flashed ? .white : uiColor(monster.def.color)
        }
        node.childNode(withName: "lock")?.isHidden = player.lockId != monster.id
        syncBar(on: node, hp: monster.hp, maxHp: monster.maxHp, boss: monster.tier == .boss, radius: diameter / 2)
    }

    private func syncProjectile(_ pr: Projectile, live: inout Set<String>) {
        let key = "p\(pr.id)"
        live.insert(key)
        let diameter = max(6, CGFloat(pr.radius * 2) * TileArt.tile)
        let node = self.node(for: key) {
            let circle = SKShapeNode(circleOfRadius: diameter / 2)
            circle.strokeColor = .clear
            circle.name = "body"
            return circle
        }
        node.position = nodePoint(pr.pos.x, pr.pos.y)
        node.zPosition = pr.pos.y
        let fill: UIColor
        if pr.visual == "fireball" { fill = uiColor("#ff8a2a") }
        else if pr.visual == "bloodbolt" { fill = uiColor("#ff3a4a") }
        else if pr.faction == .players { fill = uiColor("#f3eadf") }
        else { fill = uiColor("#d1263a") }
        (node as? SKShapeNode)?.fillColor = fill
    }

    private func syncZone(_ zone: GroundZone, live: inout Set<String>) {
        let key = "z\(zone.id)"
        live.insert(key)
        let radius = CGFloat(zone.radius) * TileArt.tile
        let node = self.node(for: key) {
            let circle = SKShapeNode(circleOfRadius: radius)
            circle.strokeColor = .clear
            circle.name = "body"
            return circle
        }
        node.position = nodePoint(zone.pos.x, zone.pos.y)
        node.zPosition = zone.pos.y - 0.5
        if zone.faction == .players {
            (node as? SKShapeNode)?.fillColor = uiColor("#e9c49a").withAlphaComponent(0.22)
        } else {
            (node as? SKShapeNode)?.fillColor = uiColor("#c85032").withAlphaComponent(0.28)
        }
    }

    private func syncGlobe(_ globe: Globe, live: inout Set<String>) {
        let key = "g\(globe.id)"
        live.insert(key)
        let node = self.node(for: key) {
            let circle = SKShapeNode(circleOfRadius: 5)
            circle.fillColor = uiColor("#7dcea0")
            circle.strokeColor = .clear
            return circle
        }
        node.position = nodePoint(globe.pos.x, globe.pos.y)
        node.zPosition = globe.pos.y
    }

    private func syncBar(on root: SKNode, hp: Double, maxHp: Double, boss: Bool, radius: CGFloat) {
        let show = boss || hp < maxHp
        root.childNode(withName: "track")?.removeFromParent()
        root.childNode(withName: "fill")?.removeFromParent()
        guard show, maxHp > 0 else { return }
        let width: CGFloat = boss ? 48 : 28
        let track = SKSpriteNode(color: uiColor("#1a120c"), size: CGSize(width: width, height: 4))
        track.name = "track"
        track.position = CGPoint(x: 0, y: radius + 8)
        track.zPosition = 2
        let ratio = CGFloat(max(0, min(1, hp / maxHp)))
        let fill = SKSpriteNode(color: uiColor(boss ? "#e0b04a" : "#d4544a"), size: CGSize(width: max(1, width * ratio), height: 4))
        fill.name = "fill"
        fill.position = CGPoint(x: -width / 2 + fill.size.width / 2, y: radius + 8)
        fill.zPosition = 3
        root.addChild(track)
        root.addChild(fill)
    }

    private func syncWedge(_ player: Player, now: TimeInterval) {
        guard let flash = session.wedge, flash.until > now else {
            wedgeNode.isHidden = true
            return
        }
        let arc = flash.arc * Double.pi / 180
        let half = arc / 2
        let reach = CGFloat(flash.range) * TileArt.tile
        let path = CGMutablePath()
        path.move(to: .zero)
        let steps = 14
        var i = 0
        while i <= steps {
            let a = flash.facing - half + arc * Double(i) / Double(steps)
            path.addLine(to: CGPoint(x: cos(a) * reach, y: -sin(a) * reach))
            i += 1
        }
        path.closeSubpath()
        wedgeNode.path = path
        wedgeNode.position = nodePoint(player.pos.x, player.pos.y)
        wedgeNode.zPosition = player.pos.y + 0.2
        wedgeNode.isHidden = false
        if flash.whiff {
            wedgeNode.fillColor = uiColor("#e9c49a").withAlphaComponent(0.16)
        } else {
            wedgeNode.fillColor = uiColor("#c8343c").withAlphaComponent(0.34)
        }
    }
}
