import Foundation

public enum Faction { case players, monsters }

public enum EliteTier: String { case normal, champion, rare, minion, boss }

public enum AttackSlot { case melee, ranged }

public final class Dot {
    var dps: Double
    var left: Double
    var srcId: Int
    var kind: String
    init(dps: Double, left: Double, srcId: Int, kind: String) {
        self.dps = dps
        self.left = left
        self.srcId = srcId
        self.kind = kind
    }
}

public final class HitSpec {
    var coef: Double
    var flat: Double
    var radius: Double
    var applies: StatusDef?
    var hitIds: Set<Int>
    init(coef: Double = 0, flat: Double = 0, radius: Double, applies: StatusDef? = nil) {
        self.coef = coef
        self.flat = flat
        self.radius = radius
        self.applies = applies
        hitIds = []
    }
}

public final class ForcedMove {
    var vx: Double
    var vy: Double
    var left: Double
    var hit: HitSpec?
    init(vx: Double, vy: Double, left: Double, hit: HitSpec? = nil) {
        self.vx = vx
        self.vy = vy
        self.left = left
        self.hit = hit
    }
}

public final class Windup {
    var ability: MonsterAbility
    var index: Int
    var left: Double
    var target: Vec2
    init(ability: MonsterAbility, index: Int, left: Double, target: Vec2) {
        self.ability = ability
        self.index = index
        self.left = left
        self.target = target
    }
}

public final class DelayedStrike {
    var pos: Vec2
    var radius: Double
    var left: Double
    var faction: Faction
    var ownerId: Int
    var coef: Double
    var flat: Double
    var applies: StatusDef?
    var visual: String
    init(pos: Vec2, radius: Double, left: Double, faction: Faction, ownerId: Int, coef: Double, flat: Double, applies: StatusDef? = nil, visual: String) {
        self.pos = pos
        self.radius = radius
        self.left = left
        self.faction = faction
        self.ownerId = ownerId
        self.coef = coef
        self.flat = flat
        self.applies = applies
        self.visual = visual
    }
}

public class Entity {
    public let id: Int
    public var pos: Vec2
    public var radius: Double
    public var removed = false
    var changedTick = 0
    init(id: Int, pos: Vec2, radius: Double) {
        self.id = id
        self.pos = pos
        self.radius = radius
    }
}

public class Unit: Entity {
    public var hp: Double = 1
    public var maxHp: Double = 1
    public var facing: Double = 0
    public var dead = false
    public var faction: Faction = .monsters
    var slowPct: Double = 0
    var slowLeft: Double = 0
    var stunLeft: Double = 0
    var vulnerablePct: Double = 0
    var vulnerableLeft: Double = 0
    var dots: [Dot] = []
    var forced: ForcedMove?

    var slowMult: Double { slowLeft > 0 ? 1 - slowPct : 1 }

    func baseStateBits() -> Int {
        var s = 0
        if dead { s |= STATE.dead }
        if stunLeft > 0 { s |= STATE.stunned }
        if slowLeft > 0 { s |= STATE.slowed }
        if !dots.isEmpty { s |= STATE.dot }
        return s
    }
}

public struct PlayerInput {
    public var seq: Int
    public var mx: Double
    public var my: Double
    public var ax: Double
    public var ay: Double
    public var buttons: Int
    public var lock: Int
    public init(seq: Int = 0, mx: Double = 0, my: Double = 0, ax: Double = 0, ay: Double = 0, buttons: Int = 0, lock: Int = 0) {
        self.seq = seq
        self.mx = mx
        self.my = my
        self.ax = ax
        self.ay = ay
        self.buttons = buttons
        self.lock = lock
    }
}

public final class Player: Unit {
    public var input = PlayerInput()
    public var resource: Double = 0
    public var lockId = 0
    public var castLock: Double = 0
    public var potionCd: Double = 0
    public var buffs: [ActiveBuff] = []
    public var save: Save
    public var stats: DerivedStats
    public let accountName: String
    var prevButtons = 0
    var lastCombat = -999.0
    var pets: [Int] = []
    var regenCarry: Double = 0
    var summonLeft: Double = 0
    var dentrosReady: Double = 0
    var ackSeq = 0

    public init(id: Int, pos: Vec2, name: String, save: Save, stats: DerivedStats) {
        self.save = save
        self.stats = stats
        self.accountName = name
        super.init(id: id, pos: pos, radius: PLAYER_RADIUS)
        faction = .players
        maxHp = stats.maxLife
        hp = stats.maxLife
        resource = 0
    }

    var surging: Bool { resource >= ECHO_SURGE_THRESHOLD }

    func buffSum(_ key: String) -> Double {
        var s = 0.0
        for b in buffs {
            switch key {
            case "damagePct": s += b.damagePct
            case "damageReduction": s += b.damageReduction
            case "moveSpeedPct": s += b.moveSpeedPct
            case "attackSpeedPct": s += b.attackSpeedPct
            case "regenPct": s += b.regenPct
            default: break
            }
        }
        return s
    }

    var immune: Bool { buffs.contains { $0.immune } }

    var moveSpeed: Double { stats.moveSpeed * (1 + buffSum("moveSpeedPct")) * slowMult }

    func addPet(_ id: Int) { if !pets.contains(id) { pets.append(id) } }
    func removePet(_ id: Int) { pets.removeAll { $0 == id } }

    func stateBits() -> Int {
        var s = baseStateBits()
        if immune { s |= STATE.immune }
        if surging { s |= STATE.surge }
        if buffSum("damageReduction") > 0 { s |= STATE.shielded }
        if castLock > 0 { s |= STATE.winding }
        return s
    }
}

public final class Monster: Unit {
    public let def: MonsterDef
    public var level: Int
    public var damage: Double
    public var tier: EliteTier
    public var affixes: [EliteAffixId]
    public var kind: String
    public var name: String
    public var ownerId = 0
    public var noReward = false
    var abilities: [MonsterAbility]
    var abilityCds: [Double]
    var windup: Windup?
    var targetId = 0
    var aggro = false
    var aggroAt = 0.0
    var speedMult = 1.0
    var attackSpeedMult = 1.0
    var damageTakenMult = 1.0
    var dormant = true
    var expiresAt = Double.infinity
    var phase = 1
    var strafeDir = 1.0
    var hitBy: Set<Int> = []

    public init(id: Int, pos: Vec2, def: MonsterDef, level: Int, damage: Double, tier: EliteTier, affixes: [EliteAffixId], extra: [MonsterAbility]) {
        self.def = def
        self.level = level
        self.damage = damage
        self.tier = tier
        self.affixes = affixes
        self.kind = def.ai == .pet ? "pet" : "monster"
        self.name = def.name
        self.abilities = def.abilities + extra
        self.abilityCds = []
        let radius = def.radius * ((tier == .champion || tier == .rare) ? 1.2 : 1)
        super.init(id: id, pos: pos, radius: radius)
        abilityCds = abilities.enumerated().map { i, a in
            a.kind == .melee ? 0 : a.cooldown * (0.4 + 0.15 * Double(i))
        }
        if def.ai == .pet { faction = .players }
    }
}

public final class Projectile: Entity {
    public var vel: Vec2
    public var rangeLeft: Double
    public var faction: Faction
    public var ownerId: Int
    public var visual: String
    public var coef: Double
    public var flat: Double
    public var pierce: Int
    public var explodeRadius: Double
    public var applies: StatusDef?
    public var slot: AttackSlot?
    public var echoOnHit: Double
    var hitIds: Set<Int> = []

    public init(id: Int, pos: Vec2, radius: Double, vel: Vec2, rangeLeft: Double, faction: Faction, ownerId: Int, visual: String, coef: Double, flat: Double, pierce: Int, explodeRadius: Double, applies: StatusDef?, slot: AttackSlot?, echoOnHit: Double = 0) {
        self.vel = vel
        self.rangeLeft = rangeLeft
        self.faction = faction
        self.ownerId = ownerId
        self.visual = visual
        self.coef = coef
        self.flat = flat
        self.pierce = pierce
        self.explodeRadius = explodeRadius
        self.applies = applies
        self.slot = slot
        self.echoOnHit = echoOnHit
        super.init(id: id, pos: pos, radius: radius)
    }
}

public final class GroundZone: Entity {
    public var left: Double
    public var faction: Faction
    public var ownerId: Int
    public var visual: String
    public var coefPerSec: Double
    public var flatPerSec: Double
    public var applies: StatusDef?
    public var slot: AttackSlot?
    var tickTimer = 0.0

    public init(id: Int, pos: Vec2, radius: Double, left: Double, faction: Faction, ownerId: Int, visual: String, coefPerSec: Double, flatPerSec: Double, applies: StatusDef?) {
        self.left = left
        self.faction = faction
        self.ownerId = ownerId
        self.visual = visual
        self.coefPerSec = coefPerSec
        self.flatPerSec = flatPerSec
        self.applies = applies
        super.init(id: id, pos: pos, radius: radius)
    }
}

public final class Globe: Entity {
    var age = 0.0
    public init(id: Int, pos: Vec2) {
        super.init(id: id, pos: pos, radius: 0.35)
    }
}
