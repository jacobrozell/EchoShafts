import Foundation

private let COMBAT_TIMEOUT = 4.0

func tickUnitTimers(_ sim: Simulation, _ u: Unit, _ dt: Double) {
    if u.slowLeft > 0 { u.slowLeft -= dt }
    if u.stunLeft > 0 {
        u.stunLeft -= dt
        u.changedTick = sim.tick
    }
    if u.vulnerableLeft > 0 { u.vulnerableLeft -= dt }
    if !u.dots.isEmpty && !u.dead {
        var total = 0.0
        var src = 0
        for d in u.dots {
            let step = min(dt, d.left)
            total += d.dps * step
            d.left -= step
            src = d.srcId
        }
        u.dots = u.dots.filter { $0.left > 0 }
        if total > 0 {
            u.hp -= total
            u.changedTick = sim.tick
            if u.hp <= 0 {
                if let m = u as? Monster { sim.killMonster(m, sim.players.get(src)) }
                else if let p = u as? Player { sim.killPlayer(p) }
            }
        }
    }
}

func applyStatus(_ sim: Simulation, _ t: Unit, _ s: StatusDef, _ src: Player?, _ weaponAvg: Double = 0) {
    if t.dead { return }
    let ccMult: Double = {
        if let m = t as? Monster, m.tier == .boss { return 0.25 }
        if let m = t as? Monster, m.tier != .normal { return 0.6 }
        return 1
    }()
    switch s {
    case .slow(let pct, let duration):
        t.slowPct = max(t.slowLeft > 0 ? t.slowPct : 0, pct * (ccMult < 1 ? 0.7 : 1))
        t.slowLeft = max(t.slowLeft, duration)
    case .stun(let duration):
        t.stunLeft = max(t.stunLeft, duration * ccMult)
        if let m = t as? Monster, m.tier != .boss { m.windup = nil }
    case .vulnerable(let pct, let duration):
        t.vulnerablePct = pct
        t.vulnerableLeft = duration
    case .bleed(let coefPerSec, let duration), .burn(let coefPerSec, let duration):
        guard let src else { return }
        let kind = {
            if case .bleed = s { return "bleed" }
            return "burn"
        }()
        let dps = weaponAvg * coefPerSec * damageMultiplier(src, t as? Monster)
        if let existing = t.dots.first(where: { $0.kind == kind && $0.srcId == src.id }) {
            existing.dps = max(existing.dps, dps)
            existing.left = duration
        } else {
            t.dots.append(Dot(dps: dps, left: duration, srcId: src.id, kind: kind))
        }
    }
    t.changedTick = sim.tick
}

func damageMultiplier(_ p: Player, _ target: Monster?) -> Double {
    let st = p.stats
    var m = (1 + st.anchor / 100) * (1 + st.damagePct) * (1 + p.buffSum("damagePct"))
    if p.surging { m *= 1 + ECHO_SURGE_DAMAGE }
    if let target, target.tier != .normal { m *= 1 + st.eliteDamage }
    if let target, target.vulnerableLeft > 0 { m *= 1 + target.vulnerablePct }
    return m
}

func playerHitMonster(_ sim: Simulation, _ p: Player, _ t: Monster, _ coef: Double, _ slot: AttackSlot, _ applies: StatusDef? = nil) -> Double {
    if t.dead || t.kind == "pet" { return 0 }
    let st = p.stats
    let minD = slot == .ranged ? st.rangedMin : st.weaponMin
    let maxD = slot == .ranged ? st.rangedMax : st.weaponMax
    let roll = minD + sim.rng.next() * (maxD - minD)
    let crit = sim.rng.chance(st.critChance)
    var dmg = coef > 0 ? roll * coef * damageMultiplier(p, t) : 0
    if crit { dmg *= 1 + st.critDamage }
    dmg *= t.damageTakenMult
    dmg = jsRound(dmg)

    p.lastCombat = sim.time
    t.hitBy.insert(p.id)
    if !t.aggro && t.def.ai != .flee {
        t.aggro = true
        t.aggroAt = sim.time
        t.targetId = p.id
    }
    if t.def.ai == .flee && !t.aggro {
        t.aggro = true
        t.aggroAt = sim.time
    }
    if dmg > 0 {
        t.hp -= dmg
        t.changedTick = sim.tick
        sim.emit(.dmg(id: t.id, amount: dmg, crit: crit, source: p.id, x: t.pos.x, y: t.pos.y))
        if st.lifeOnHit > 0 { healUnit(sim, p, st.lifeOnHit, false) }
    }
    let weaponAvg = (st.weaponMin + st.weaponMax) / 2
    if let applies { applyStatus(sim, t, applies, p, weaponAvg) }
    if t.hp <= 0 { sim.killMonster(t, p) }
    return dmg
}

func petHitMonster(_ sim: Simulation, _ pet: Monster, _ t: Monster, _ coef: Double) {
    guard let owner = sim.players.get(pet.ownerId) else { return }
    _ = playerHitMonster(sim, owner, t, coef, .melee)
}

func addBuff(_ sim: Simulation, _ p: Player, _ b: ActiveBuff) {
    p.buffs = p.buffs.filter { $0.id != b.id }
    p.buffs.append(b)
    p.changedTick = sim.tick
    sim.emit(.fx(visual: "buff_\(b.id)", x: p.pos.x, y: p.pos.y, r: nil, tx: nil, ty: nil))
}

public func damagePlayer(_ sim: Simulation, _ p: Player, _ raw: Double, _ src: Monster?) -> Double {
    if p.dead || raw <= 0 { return 0 }
    if p.immune {
        sim.emit(.dmg(id: p.id, amount: 0, crit: false, source: src?.id, x: p.pos.x, y: p.pos.y))
        return 0
    }
    let level = src?.level ?? sim.scaling.monsterLevel
    var dmg = raw * (1 - armorReduction(p.stats.armor, level))
    dmg *= 1 - min(0.75, p.buffSum("damageReduction"))
    if p.surging { dmg *= 1 + ECHO_SURGE_VULNERABILITY }
    dmg = max(1, jsRound(dmg))
    p.hp -= dmg
    p.lastCombat = sim.time
    p.changedTick = sim.tick
    sim.emit(.dmg(id: p.id, amount: dmg, crit: false, source: src?.id, x: p.pos.x, y: p.pos.y))

    if p.save.plateId == "dentros_last_stand" && p.hp > 0 && p.hp / p.maxHp <= 0.3 && sim.time >= p.dentrosReady {
        p.dentrosReady = sim.time + 60
        addBuff(sim, p, ActiveBuff(id: "last_stand", name: "Last Stand", left: 4, damageReduction: 0.5))
        healUnit(sim, p, p.maxHp * 0.2)
    }

    if p.hp <= 0 { sim.killPlayer(p) }
    return dmg
}

func healUnit(_ sim: Simulation, _ u: Unit, _ amount: Double, _ announce: Bool = true) {
    if u.dead || amount <= 0 { return }
    let before = u.hp
    u.hp = min(u.maxHp, u.hp + amount)
    if u.hp != before {
        u.changedTick = sim.tick
        if announce && u.hp - before >= 1 {
            sim.emit(.heal(id: u.id, amount: jsRound(u.hp - before)))
        }
    }
}

func inCombat(_ sim: Simulation, _ p: Player) -> Bool {
    sim.time - p.lastCombat < COMBAT_TIMEOUT
}
