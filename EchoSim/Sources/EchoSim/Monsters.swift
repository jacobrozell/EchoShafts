import Foundation

public enum MonsterAi: String { case melee, ranged, flee, pet, boss }
public enum MonsterFamily: String { case litany, pit, spirit, vessel }
public enum MonsterShape: String { case thrall, cultist, chanter, brute, crawler, mite, runner, wolf, boss }

public struct MonsterAbility {
    public enum Kind: String { case melee, projectile, nova, slam, charge, summon, pool, heal }
    public var kind: Kind
    public var cooldown: Double
    public var range: Double
    public var coef: Double
    public var windup: Double
    public var speed: Double
    public var count: Int
    public var spread: Double
    public var visual: String
    public var radius: Double
    public var coefPerSec: Double
    public var duration: Double
    public var pct: Double
    public var monsterId: String

    public init(kind: Kind, cooldown: Double = 0, range: Double = 0, coef: Double = 0, windup: Double = 0, speed: Double = 0, count: Int = 1, spread: Double = 0, visual: String = "", radius: Double = 0, coefPerSec: Double = 0, duration: Double = 0, pct: Double = 0, monsterId: String = "") {
        self.kind = kind
        self.cooldown = cooldown
        self.range = range
        self.coef = coef
        self.windup = windup
        self.speed = speed
        self.count = count
        self.spread = spread
        self.visual = visual
        self.radius = radius
        self.coefPerSec = coefPerSec
        self.duration = duration
        self.pct = pct
        self.monsterId = monsterId
    }
}

public struct MonsterDef {
    public let id: String
    public let name: String
    public let family: MonsterFamily
    public let ai: MonsterAi
    public let life: Double
    public let damage: Double
    public let speed: Double
    public let radius: Double
    public let xp: Double
    public let aggroRange: Double
    public let preferredRange: Double?
    public let abilities: [MonsterAbility]
    public let echo: Double
    public let dropMult: Double
    public let color: String
    public let shape: MonsterShape
    public let escapeAfter: Double?
    public let bossPhases: Bool
    public let unique: Bool
}

private func M(_ d: MonsterDef) -> MonsterDef { d }

public let MONSTER_ORDER: [String] = [
    "thrall", "initiate", "chanter", "deserter", "crawler", "mite", "tithe_runner", "spirit_wolf",
    "brother_varn", "hollow_foreman", "choir_of_scars", "mother_of_mites",
]

public let MONSTERS: [String: MonsterDef] = {
    let all: [MonsterDef] = [
        M(MonsterDef(id: "thrall", name: "Echo Thrall", family: .litany, ai: .melee, life: 16, damage: 4, speed: 3.1, radius: 0.4, xp: 5, aggroRange: 9, preferredRange: nil, abilities: [MonsterAbility(kind: .melee, cooldown: 1.2, range: 1.0, coef: 1, windup: 0.3)], echo: 1, dropMult: 0.7, color: "#8a6f6a", shape: .thrall, escapeAfter: nil, bossPhases: false, unique: false)),
        M(MonsterDef(id: "initiate", name: "Litany Initiate", family: .litany, ai: .melee, life: 28, damage: 6, speed: 3.5, radius: 0.42, xp: 8, aggroRange: 10, preferredRange: nil, abilities: [MonsterAbility(kind: .melee, cooldown: 1.1, range: 1.1, coef: 1, windup: 0.3)], echo: 1.5, dropMult: 1, color: "#9c2f36", shape: .cultist, escapeAfter: nil, bossPhases: false, unique: false)),
        M(MonsterDef(id: "chanter", name: "Scar Chanter", family: .litany, ai: .ranged, life: 22, damage: 7, speed: 2.8, radius: 0.42, xp: 9, aggroRange: 11, preferredRange: 6, abilities: [MonsterAbility(kind: .projectile, cooldown: 2.2, range: 10, coef: 1, windup: 0.45, speed: 9, visual: "bloodbolt")], echo: 2, dropMult: 1.1, color: "#c43d63", shape: .chanter, escapeAfter: nil, bossPhases: false, unique: false)),
        M(MonsterDef(id: "deserter", name: "Blood-Plate Deserter", family: .litany, ai: .melee, life: 80, damage: 12, speed: 2.4, radius: 0.62, xp: 22, aggroRange: 9, preferredRange: nil, abilities: [
            MonsterAbility(kind: .melee, cooldown: 1.6, range: 1.4, coef: 1, windup: 0.45),
            MonsterAbility(kind: .slam, cooldown: 6, range: 3, coef: 1.8, windup: 0.9, radius: 2.4),
        ], echo: 4, dropMult: 1.6, color: "#6e1e24", shape: .brute, escapeAfter: nil, bossPhases: false, unique: false)),
        M(MonsterDef(id: "crawler", name: "Pit Crawler", family: .pit, ai: .melee, life: 24, damage: 6, speed: 4.1, radius: 0.45, xp: 8, aggroRange: 10, preferredRange: nil, abilities: [
            MonsterAbility(kind: .melee, cooldown: 1.0, range: 1.0, coef: 1, windup: 0.25),
            MonsterAbility(kind: .charge, cooldown: 5, range: 7, coef: 1.4, windup: 0.5, speed: 14),
        ], echo: 1.5, dropMult: 0.9, color: "#5b6b4a", shape: .crawler, escapeAfter: nil, bossPhases: false, unique: false)),
        M(MonsterDef(id: "mite", name: "Crystal Mite", family: .pit, ai: .melee, life: 9, damage: 3, speed: 4.4, radius: 0.3, xp: 3, aggroRange: 9, preferredRange: nil, abilities: [MonsterAbility(kind: .melee, cooldown: 0.9, range: 0.8, coef: 1, windup: 0.2)], echo: 0.5, dropMult: 0.4, color: "#4fb6e8", shape: .mite, escapeAfter: nil, bossPhases: false, unique: false)),
        M(MonsterDef(id: "tithe_runner", name: "Tithe-Runner", family: .litany, ai: .flee, life: 240, damage: 0, speed: 4.6, radius: 0.5, xp: 40, aggroRange: 8, preferredRange: nil, abilities: [], echo: 8, dropMult: 6, color: "#e0b04a", shape: .runner, escapeAfter: 22, bossPhases: false, unique: false)),
        M(MonsterDef(id: "spirit_wolf", name: "Spirit Wolf", family: .spirit, ai: .pet, life: 1, damage: 0, speed: 6, radius: 0.4, xp: 0, aggroRange: 9, preferredRange: nil, abilities: [MonsterAbility(kind: .melee, cooldown: 0.8, range: 1.1, coef: 0.6, windup: 0.15)], echo: 0, dropMult: 0, color: "#8fe3ff", shape: .wolf, escapeAfter: nil, bossPhases: false, unique: false)),
        M(MonsterDef(id: "brother_varn", name: "Brother Varn, the First Voice", family: .litany, ai: .boss, life: 1100, damage: 11, speed: 3.0, radius: 0.9, xp: 400, aggroRange: 14, preferredRange: nil, abilities: [
            MonsterAbility(kind: .melee, cooldown: 1.4, range: 1.8, coef: 1.2, windup: 0.35),
            MonsterAbility(kind: .nova, cooldown: 6, range: 14, coef: 0.9, windup: 0.8, speed: 8, count: 14, visual: "bloodbolt"),
            MonsterAbility(kind: .summon, cooldown: 13, range: 4, windup: 1.0, count: 4, monsterId: "thrall"),
            MonsterAbility(kind: .charge, cooldown: 9, range: 10, coef: 1.6, windup: 0.7, speed: 15),
        ], echo: 0, dropMult: 0, color: "#d1263a", shape: .boss, escapeAfter: nil, bossPhases: true, unique: true)),
        M(MonsterDef(id: "hollow_foreman", name: "The Hollow Foreman", family: .vessel, ai: .boss, life: 950, damage: 14, speed: 2.6, radius: 1.0, xp: 500, aggroRange: 16, preferredRange: nil, abilities: [
            MonsterAbility(kind: .melee, cooldown: 1.5, range: 2.0, coef: 1.3, windup: 0.45),
            MonsterAbility(kind: .slam, cooldown: 5, range: 6, coef: 2.2, windup: 1.0, radius: 3.2),
            MonsterAbility(kind: .charge, cooldown: 8, range: 12, coef: 1.8, windup: 0.8, speed: 16),
            MonsterAbility(kind: .summon, cooldown: 14, range: 4, windup: 1.0, count: 3, monsterId: "crawler"),
        ], echo: 0, dropMult: 0, color: "#7a2b18", shape: .boss, escapeAfter: nil, bossPhases: true, unique: true)),
        M(MonsterDef(id: "choir_of_scars", name: "Choir of Scars", family: .vessel, ai: .boss, life: 820, damage: 12, speed: 2.4, radius: 0.95, xp: 500, aggroRange: 16, preferredRange: 7, abilities: [
            MonsterAbility(kind: .projectile, cooldown: 1.8, range: 12, coef: 1, windup: 0.4, speed: 10, count: 5, spread: 40, visual: "bloodbolt"),
            MonsterAbility(kind: .nova, cooldown: 5, range: 15, coef: 0.8, windup: 0.9, speed: 7, count: 18, visual: "bloodbolt"),
            MonsterAbility(kind: .heal, cooldown: 12, windup: 1.2, radius: 10, pct: 0.06),
            MonsterAbility(kind: .summon, cooldown: 12, range: 5, windup: 1.0, count: 2, monsterId: "chanter"),
        ], echo: 0, dropMult: 0, color: "#a31d4f", shape: .boss, escapeAfter: nil, bossPhases: true, unique: true)),
        M(MonsterDef(id: "mother_of_mites", name: "Mother of Mites", family: .vessel, ai: .boss, life: 900, damage: 11, speed: 3.2, radius: 1.0, xp: 500, aggroRange: 16, preferredRange: nil, abilities: [
            MonsterAbility(kind: .melee, cooldown: 1.2, range: 1.8, coef: 1.1, windup: 0.3),
            MonsterAbility(kind: .summon, cooldown: 7, range: 4, windup: 0.8, count: 6, monsterId: "mite"),
            MonsterAbility(kind: .pool, cooldown: 6, range: 9, windup: 0.6, radius: 2.4, coefPerSec: 0.8, duration: 6),
            MonsterAbility(kind: .charge, cooldown: 9, range: 10, coef: 1.5, windup: 0.6, speed: 15),
        ], echo: 0, dropMult: 0, color: "#3c9fd0", shape: .boss, escapeAfter: nil, bossPhases: true, unique: true)),
    ]
    var map: [String: MonsterDef] = [:]
    for d in all { map[d.id] = d }
    return map
}()

/// Vessels that can rise. Brother Varn is not in this game.
public let VESSEL_IDS = ["hollow_foreman", "choir_of_scars", "mother_of_mites"]

public func vesselLine(_ id: String) -> String? {
    switch id {
    case "hollow_foreman": return "Count the heads. The count is wrong."
    case "choir_of_scars": return "We were seven miners. Now we are one song."
    case "mother_of_mites": return "They came out of the seam. They do not come back."
    default: return nil
    }
}

public let PACK_TABLE: [([String], Double)] = [
    (["thrall", "thrall", "thrall", "thrall", "initiate"], 10),
    (["initiate", "initiate", "chanter"], 10),
    (["initiate", "chanter", "chanter", "thrall", "thrall"], 8),
    (["deserter", "thrall", "thrall"], 6),
    (["crawler", "crawler", "crawler"], 7),
    (["mite", "mite", "mite", "mite", "mite", "mite"], 6),
    (["deserter", "chanter", "chanter"], 4),
]

public enum EliteAffixId: String, CaseIterable {
    case frenzied, chanting, volatile, echoing, plated, dusttrail
}

public struct EliteAffixDef {
    public let id: EliteAffixId
    public let name: String
    public let lifeMult: Double?
    public let speedMult: Double?
    public let attackSpeedMult: Double?
    public let damageTakenMult: Double?
    public let ability: MonsterAbility?
}

public let ELITE_AFFIX_ORDER: [EliteAffixId] = [.frenzied, .chanting, .volatile, .echoing, .plated, .dusttrail]

public let ELITE_AFFIXES: [EliteAffixId: EliteAffixDef] = [
    .frenzied: EliteAffixDef(id: .frenzied, name: "Frenzied", lifeMult: nil, speedMult: 1.35, attackSpeedMult: 1.4, damageTakenMult: nil, ability: nil),
    .chanting: EliteAffixDef(id: .chanting, name: "Chanting", lifeMult: nil, speedMult: nil, attackSpeedMult: nil, damageTakenMult: nil, ability: MonsterAbility(kind: .heal, cooldown: 6, windup: 0.6, radius: 7, pct: 0.12)),
    .volatile: EliteAffixDef(id: .volatile, name: "Volatile", lifeMult: nil, speedMult: nil, attackSpeedMult: nil, damageTakenMult: nil, ability: nil),
    .echoing: EliteAffixDef(id: .echoing, name: "Echoing", lifeMult: nil, speedMult: nil, attackSpeedMult: nil, damageTakenMult: nil, ability: MonsterAbility(kind: .nova, cooldown: 5, range: 10, coef: 0.7, windup: 0.6, speed: 7, count: 8, visual: "bloodbolt")),
    .plated: EliteAffixDef(id: .plated, name: "Plated", lifeMult: 1.5, speedMult: nil, attackSpeedMult: nil, damageTakenMult: 0.75, ability: nil),
    .dusttrail: EliteAffixDef(id: .dusttrail, name: "Dust-Trailed", lifeMult: nil, speedMult: nil, attackSpeedMult: nil, damageTakenMult: nil, ability: MonsterAbility(kind: .pool, cooldown: 4, range: 0, windup: 0, radius: 1.6, coefPerSec: 0.6, duration: 5)),
]

public let ELITE_NAME_FIRST = ["Hessan", "Marl", "Tovric", "Ysel", "Brannoc", "Odda", "Corvin", "Senna", "Halvard", "Mirela", "Dusk", "Arvo"]
public let ELITE_NAME_EPITHET = ["the Many-Voiced", "Scar-Singer", "the Unrotated", "Plate-Wed", "the Warm Below", "Who Bled First", "the Unbound", "Red-Thread", "Echo-Drunk", "the Hollow"]

public func monsterLifeScale(_ level: Int) -> Double { pow(1.16, Double(level - 1)) }
public func monsterDamageScale(_ level: Int) -> Double { pow(1.115, Double(level - 1)) }
