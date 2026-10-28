import Foundation

public let CHARACTER_VERSION = 3

public struct VeinBest: Equatable {
    public var depth: Int
    public var ticks: Int
    public init(depth: Int, ticks: Int) {
        self.depth = depth
        self.ticks = ticks
    }
}

public final class Save {
    public var version: Int
    public var origin: String?
    public var tutorial: Int
    public var handedness: String
    public var level: Int
    public var xp: Int
    public var meleeId: String
    public var rangedId: String
    public var plateId: String
    public var plateArmor: Int
    public var ownedMeleeIds: [String]
    public var ownedRangedIds: [String]
    public var ownedPlateIds: [String]
    public var flesh: Int
    public var ranks: [String: Int]
    public var sawEcho: Bool
    public var veinBest: VeinBest?

    public init() {
        version = CHARACTER_VERSION
        origin = nil
        tutorial = 0
        handedness = "right"
        level = 1
        xp = 0
        meleeId = "company_pick"
        rangedId = "company_crossbow"
        plateId = "company_plate"
        plateArmor = 0
        ownedMeleeIds = ["company_pick"]
        ownedRangedIds = ["company_crossbow"]
        ownedPlateIds = ["company_plate"]
        flesh = 0
        ranks = [:]
        sawEcho = false
        veinBest = nil
    }
}

public func newSave() -> Save { Save() }

public func chooseOrigin(_ save: Save, _ origin: String) {
    guard save.origin == nil else { return }
    guard origin == "silvarium" || origin == "cataracta" || origin == "plate" else { return }
    save.origin = origin
    save.meleeId = "company_pick"
    save.rangedId = "company_crossbow"
    save.plateId = "company_plate"
    save.plateArmor = originArmor(origin)
    grantGear(save, "company_pick")
    grantGear(save, "company_crossbow")
    grantGear(save, "company_plate")
}

public func rankOf(_ save: Save, _ tree: String) -> Int { save.ranks[tree] ?? 0 }

public func nextRankCost(_ save: Save, _ tree: String) -> Int? {
    guard let def = treeById(tree) else { return nil }
    let current = rankOf(save, tree)
    if current >= def.ranks.count { return nil }
    return current + 1
}

public func buyRank(_ save: Save, _ tree: String) -> Bool {
    guard let cost = nextRankCost(save, tree), save.flesh >= cost else { return false }
    save.flesh -= cost
    save.ranks[tree] = rankOf(save, tree) + 1
    return true
}

/// Sets every rank key to 0 and refunds everything spent. Origin stays.
public func refundFlesh(_ save: Save) {
    var total = 0
    for key in Array(save.ranks.keys) {
        let r = save.ranks[key] ?? 0
        total += r * (r + 1) / 2
        save.ranks[key] = 0
    }
    save.flesh += total
}

public func beatsVein(_ best: VeinBest?, depth: Int, ticks: Int) -> Bool {
    guard let best else { return true }
    if depth > best.depth { return true }
    if depth == best.depth && ticks < best.ticks { return true }
    return false
}

private func jsonInt(_ value: Any?) -> Int? {
    if let i = value as? Int { return i }
    if let d = value as? Double { return Int(d) }
    if let n = value as? NSNumber { return n.intValue }
    return nil
}

public func loadSave(data: Data) -> Save {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return newSave() }
    guard jsonInt(obj["version"]) == CHARACTER_VERSION else { return newSave() }
    let save = newSave()
    if let origin = obj["origin"] as? String, origin == "silvarium" || origin == "cataracta" || origin == "plate" {
        save.origin = origin
    }
    if let tutorial = jsonInt(obj["tutorial"]) { save.tutorial = min(3, max(0, tutorial)) }
    if let hand = obj["handedness"] as? String, hand == "left" || hand == "right" { save.handedness = hand }
    if let level = jsonInt(obj["level"]) { save.level = max(1, min(LEVEL_CAP, level)) }
    if let xp = jsonInt(obj["xp"]) { save.xp = max(0, xp) }
    if let id = obj["meleeId"] as? String { save.meleeId = id }
    if let id = obj["rangedId"] as? String { save.rangedId = id }
    if let id = obj["plateId"] as? String { save.plateId = id }
    if let armor = jsonInt(obj["plateArmor"]) { save.plateArmor = armor }
    if let ids = obj["ownedMeleeIds"] as? [String] { save.ownedMeleeIds = ids }
    if let ids = obj["ownedRangedIds"] as? [String] { save.ownedRangedIds = ids }
    if let ids = obj["ownedPlateIds"] as? [String] { save.ownedPlateIds = ids }
    if let flesh = jsonInt(obj["flesh"]) { save.flesh = max(0, flesh) }
    if let ranks = obj["ranks"] as? [String: Any] {
        var parsed: [String: Int] = [:]
        for (k, v) in ranks { if let n = jsonInt(v) { parsed[k] = n } }
        save.ranks = parsed
    }
    if let saw = obj["sawEcho"] as? Bool { save.sawEcho = saw }
    if let best = obj["veinBest"] as? [String: Any], let depth = jsonInt(best["depth"]), let ticks = jsonInt(best["ticks"]) {
        save.veinBest = VeinBest(depth: depth, ticks: ticks)
    }
    return save
}

public func saveData(_ save: Save) -> Data {
    var obj: [String: Any] = [
        "version": save.version,
        "tutorial": save.tutorial,
        "handedness": save.handedness,
        "level": save.level,
        "xp": save.xp,
        "meleeId": save.meleeId,
        "rangedId": save.rangedId,
        "plateId": save.plateId,
        "plateArmor": save.plateArmor,
        "ownedMeleeIds": save.ownedMeleeIds,
        "ownedRangedIds": save.ownedRangedIds,
        "ownedPlateIds": save.ownedPlateIds,
        "flesh": save.flesh,
        "ranks": save.ranks,
        "sawEcho": save.sawEcho,
    ]
    if let origin = save.origin { obj["origin"] = origin }
    if let best = save.veinBest { obj["veinBest"] = ["depth": best.depth, "ticks": best.ticks] }
    return (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
}
