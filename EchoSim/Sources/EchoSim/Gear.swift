import Foundation

public enum GearSlot: String { case melee, ranged, plate }

public struct SwingArc {
    public var range: Double
    public var arc: Double
    public var coef: Double
    public var echoOnHit: Double
    public var castTime: Double
}

public struct SwingShot {
    public var speed: Double
    public var range: Double
    public var coef: Double
    public var radius: Double
    public var count: Int
    public var spread: Double
    public var pierce: Int
    public var echoOnHit: Double
    public var castTime: Double
    public var visual: String
}

public enum Swing {
    case arc(SwingArc)
    case shot(SwingShot)
}

public struct GearDef {
    public let id: String
    public let name: String
    public let slot: GearSlot
    public let line: String
    public let damageMin: Double
    public let damageMax: Double
    public let swing: Swing?
    public let dentros: Bool
}

public struct RankDef {
    public let sentence: String
    public let wolfSentence: String?
}

public struct TreeDef {
    public let id: String
    public let title: String
    public let ranks: [RankDef]
}

let companyArc = SwingArc(range: 2.15, arc: 110, coef: 1.2, echoOnHit: 8, castTime: 0.42)

public let GEAR: [GearDef] = [
    GearDef(id: "company_pick", name: "Company Pick-Hammer", slot: .melee, line: "A company arc.", damageMin: 8, damageMax: 12, swing: .arc(companyArc), dentros: false),
    GearDef(id: "ulrics_pick_hammer", name: "Ulric's Pick-Hammer", slot: .melee, line: "A wider arc.", damageMin: 8, damageMax: 12, swing: .arc(SwingArc(range: 2.5, arc: 150, coef: 1.35, echoOnHit: 9, castTime: 0.42)), dentros: false),
    GearDef(id: "company_crossbow", name: "Company Crossbow", slot: .ranged, line: "A single bolt.", damageMin: 4, damageMax: 6, swing: .shot(SwingShot(speed: 14, range: 8, coef: 0.7, radius: 0.3, count: 1, spread: 0, pierce: 0, echoOnHit: 4, castTime: 0.35, visual: "bolt")), dentros: false),
    GearDef(id: "choir_needle", name: "Choir Needle", slot: .ranged, line: "The shot pierces.", damageMin: 4, damageMax: 7, swing: .shot(SwingShot(speed: 16, range: 9, coef: 1.15, radius: 0.34, count: 1, spread: 0, pierce: 2, echoOnHit: 7, castTime: 0.38, visual: "bolt")), dentros: false),
    GearDef(id: "suformins_fang", name: "Suformin's Fang", slot: .ranged, line: "Two fangs.", damageMin: 5, damageMax: 8, swing: .shot(SwingShot(speed: 16, range: 9, coef: 0.72, radius: 0.34, count: 2, spread: 12, pierce: 0, echoOnHit: 6, castTime: 0.38, visual: "fang")), dentros: false),
    GearDef(id: "company_plate", name: "Company Plate", slot: .plate, line: "", damageMin: 0, damageMax: 0, swing: nil, dentros: false),
    GearDef(id: "dentros_last_stand", name: "Dentros' Last Stand", slot: .plate, line: "Below 30% life, a short ward.", damageMin: 0, damageMax: 0, swing: nil, dentros: true),
]

public let GEAR_BY_ID: [String: GearDef] = {
    var m: [String: GearDef] = [:]
    for g in GEAR { m[g.id] = g }
    return m
}()

/// Named pieces that can drop. Company issue is not in this pool.
public let NAMED_GEAR_IDS = ["ulrics_pick_hammer", "choir_needle", "suformins_fang", "dentros_last_stand"]

public let TREES: [TreeDef] = [
    TreeDef(id: "melee", title: "Melee", ranks: [
        RankDef(sentence: "Heavier swings.", wolfSentence: nil),
        RankDef(sentence: "A wider swing.", wolfSentence: nil),
        RankDef(sentence: "The swing feeds you.", wolfSentence: nil),
    ]),
    TreeDef(id: "ranged", title: "Ranged", ranks: [
        RankDef(sentence: "Heavier shots.", wolfSentence: nil),
        RankDef(sentence: "The shot goes through.", wolfSentence: nil),
        RankDef(sentence: "A second shot.", wolfSentence: nil),
    ]),
    TreeDef(id: "summon", title: "Summon", ranks: [
        RankDef(sentence: "A mite follows.", wolfSentence: "A wolf follows."),
        RankDef(sentence: "The mite stays.", wolfSentence: "The wolf stays."),
        RankDef(sentence: "A pair of mites.", wolfSentence: "A pair of wolves."),
    ]),
]

public func treeById(_ id: String) -> TreeDef? { TREES.first { $0.id == id } }

/// Highest rank index on the catalogs. Depth pays at most this much Flesh.
public func topRankCost() -> Int { TREES.map { $0.ranks.count }.max() ?? 1 }

public func originArmor(_ origin: String?) -> Int {
    switch origin {
    case "silvarium": return 14
    case "cataracta": return 16
    case "plate": return 18
    default: return 0
    }
}

public func summonMonsterId(_ origin: String?) -> String {
    origin == "cataracta" ? "spirit_wolf" : "mite"
}

public func rankSentence(_ tree: TreeDef, _ rank: Int, origin: String?) -> String {
    let row = tree.ranks[rank - 1]
    if origin == "cataracta", let wolf = row.wolfSentence { return wolf }
    return row.sentence
}

public func ownsGear(_ save: Save, _ id: String) -> Bool {
    guard let g = GEAR_BY_ID[id] else { return false }
    switch g.slot {
    case .melee: return save.ownedMeleeIds.contains(id)
    case .ranged: return save.ownedRangedIds.contains(id)
    case .plate: return save.ownedPlateIds.contains(id)
    }
}

public func grantGear(_ save: Save, _ id: String) {
    guard let g = GEAR_BY_ID[id], !ownsGear(save, id) else { return }
    switch g.slot {
    case .melee: save.ownedMeleeIds.append(id)
    case .ranged: save.ownedRangedIds.append(id)
    case .plate: save.ownedPlateIds.append(id)
    }
}

func rank(_ save: Save, _ tree: String) -> Int { save.ranks[tree] ?? 0 }

public func resolvedMelee(_ save: Save) -> SwingArc {
    let gear = GEAR_BY_ID[save.meleeId]
    var swing = companyArc
    if case .arc(let arc) = gear?.swing { swing = arc }
    if save.origin == "plate" { swing.coef *= 1.10 }
    let r = rank(save, "melee")
    if r >= 1 { swing.coef *= 1.15 }
    if r >= 2 { swing.arc += 20 }
    return swing
}

public func resolvedShot(_ save: Save) -> SwingShot {
    var shot = SwingShot(speed: 14, range: 8, coef: 0.7, radius: 0.3, count: 1, spread: 0, pierce: 0, echoOnHit: 4, castTime: 0.35, visual: "bolt")
    if case .shot(let s) = GEAR_BY_ID[save.rangedId]?.swing { shot = s }
    if save.origin == "silvarium" { shot.coef *= 1.10 }
    let r = rank(save, "ranged")
    if r >= 1 { shot.coef *= 1.15 }
    if r >= 2 { shot.pierce += 1 }
    return shot
}

public func meleeCoef(_ save: Save) -> Double { resolvedMelee(save).coef }
public func rangedCoef(_ save: Save) -> Double { resolvedShot(save).coef }

public func rangedExtraShot(_ save: Save) -> Bool { rank(save, "ranged") >= 3 }
public func meleeFeeds(_ save: Save) -> Bool { rank(save, "melee") >= 3 }

public enum GearOffer: Equatable {
    case named(String)
    case plate(from: Int, to: Int)

    public var title: String {
        switch self {
        case .named(let id): return GEAR_BY_ID[id]?.name ?? id
        case .plate: return "Company Plate"
        }
    }

    public var line: String {
        switch self {
        case .named(let id): return GEAR_BY_ID[id]?.line ?? ""
        case .plate(let from, let to): return "Armor \(from) → \(to)"
        }
    }
}

/// Roll the one card when the Vessel dies. Showing a named card owns it.
public func rollClearOffer(_ save: Save, _ rng: Rng) -> GearOffer? {
    let unowned = NAMED_GEAR_IDS.filter { !ownsGear(save, $0) }
    if !unowned.isEmpty {
        if rng.chance(0.3) {
            let id = rng.pick(unowned)
            grantGear(save, id)
            return .named(id)
        }
        return nil
    }
    if save.plateId == "dentros_last_stand" { return nil }
    guard save.plateId == "company_plate" else { return nil }
    let cap = originArmor(save.origin) + save.level * 4
    if save.plateArmor < cap {
        return .plate(from: save.plateArmor, to: save.plateArmor + 3)
    }
    return nil
}

public func equipOffer(_ save: Save, _ offer: GearOffer) {
    switch offer {
    case .named(let id):
        guard let g = GEAR_BY_ID[id] else { return }
        switch g.slot {
        case .melee: save.meleeId = id
        case .ranged: save.rangedId = id
        case .plate: save.plateId = id
        }
    case .plate(_, let to):
        save.plateId = "company_plate"
        save.plateArmor = to
    }
}

public func equipOwned(_ save: Save, _ id: String) {
    guard ownsGear(save, id), let g = GEAR_BY_ID[id] else { return }
    switch g.slot {
    case .melee: save.meleeId = id
    case .ranged: save.rangedId = id
    case .plate: save.plateId = id
    }
}

public func wornArmor(_ save: Save) -> Int {
    if save.plateId == "dentros_last_stand" { return 22 }
    return save.plateArmor
}
