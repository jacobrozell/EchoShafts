import Foundation

private let STICK_DEAD = 0.18
private let TURN_AWAY = 0.85

func updatePlayer(_ sim: Simulation, _ p: Player, _ dt: Double) {
    if p.dead { return }

    if p.castLock > 0 { p.castLock = max(0, p.castLock - dt) }
    if p.potionCd > 0 { p.potionCd = max(0, p.potionCd - dt) }
    if !p.buffs.isEmpty {
        for b in p.buffs {
            b.left -= dt
            if b.regenPct > 0 { healUnit(sim, p, p.maxHp * b.regenPct * dt, false) }
        }
        let before = p.buffs.count
        p.buffs = p.buffs.filter { $0.left > 0 }
        if before != p.buffs.count { p.changedTick = sim.tick }
    }
    if p.hp < p.maxHp {
        p.regenCarry += p.stats.lifeRegen * dt
        if p.regenCarry >= 1 {
            let whole = floor(p.regenCarry)
            p.regenCarry -= whole
            healUnit(sim, p, whole, false)
        }
    }
    if WARDEN.resource.decayOutOfCombat > 0 && !inCombat(sim, p) {
        p.resource = max(0, p.resource - WARDEN.resource.decayOutOfCombat * dt)
    }

    let mag = hypot(p.input.mx, p.input.my)
    let stickActive = mag > STICK_DEAD
    let stickAngle = stickActive ? angleOf(Vec2(x: p.input.mx, y: p.input.my)) : p.facing
    var lock = sim.monsters.get(p.input.lock)
    if lock == nil || lock!.dead || lock!.kind == "pet" { lock = nil }
    if let locked = lock, stickActive {
        let to = angleOf(Vec2(x: locked.pos.x - p.pos.x, y: locked.pos.y - p.pos.y))
        if abs(angleDiff(stickAngle, to)) > TURN_AWAY { lock = nil }
    }
    p.lockId = lock?.id ?? 0
    if let locked = lock {
        p.facing = angleOf(Vec2(x: locked.pos.x - p.pos.x, y: locked.pos.y - p.pos.y))
    } else if stickActive {
        p.facing = stickAngle
    }

    p.ackSeq = p.input.seq
    if p.forced == nil && p.stunLeft <= 0 && stickActive {
        let dir = norm(Vec2(x: p.input.mx, y: p.input.my))
        let sp = p.moveSpeed * dt
        p.pos = sim.map.move(p.pos, dir.x * sp, dir.y * sp, p.radius)
        p.changedTick = sim.tick
    }

    let pressed = p.input.buttons & ~p.prevButtons
    p.prevButtons = p.input.buttons
    if pressed & BTN.draught != 0 { _ = usePotion(sim, p) }
    tickSummon(sim, p, dt)

    if sim.peaceful || p.stunLeft > 0 || p.castLock > 0 || p.forced != nil { return }
    if p.input.buttons & BTN.melee != 0 { tryMelee(sim, p) }
    if p.castLock <= 0 && p.input.buttons & BTN.ranged != 0 { tryRanged(sim, p) }
}

func usePotion(_ sim: Simulation, _ p: Player) -> Bool {
    if p.dead || p.potionCd > 0 || p.hp >= p.maxHp { return false }
    p.potionCd = POTION_COOLDOWN
    healUnit(sim, p, p.maxHp * POTION_HEAL_PCT)
    sim.emit(.fx(visual: "potion", x: p.pos.x, y: p.pos.y, r: nil, tx: nil, ty: nil))
    return true
}

func gainResource(_ p: Player, _ amount: Double) {
    let res = WARDEN.resource
    p.resource = min(res.max, p.resource + amount * (1 + p.stats.resourceGen))
}

private func tryMelee(_ sim: Simulation, _ p: Player) {
    if p.castLock > 0 { return }
    let swing = resolvedMelee(p.save)
    let aps = max(0.25, p.stats.attacksPerSecond * (1 + p.buffSum("attackSpeedPct")))
    p.castLock = swing.castTime / aps
    let aim = aimPoint(p)
    sim.emit(.cast(id: p.id, visual: "main", x: p.pos.x, y: p.pos.y, tx: aim.x, ty: aim.y))
    let target = closestInArc(sim, p, swing.range, swing.arc)
    sim.emit(.fx(visual: target == nil ? "whiff" : "swing", x: p.pos.x, y: p.pos.y, r: swing.range, tx: aim.x, ty: aim.y))
    guard let target else { return }
    let dealt = playerHitMonster(sim, p, target, swing.coef, .melee)
    if dealt > 0 {
        gainResource(p, swing.echoOnHit)
        if meleeFeeds(p.save) { healUnit(sim, p, 2) }
    }
}

private func tryRanged(_ sim: Simulation, _ p: Player) {
    if p.castLock > 0 { return }
    let shot = resolvedShot(p.save)
    let aps = max(0.25, p.stats.attacksPerSecond * (1 + p.buffSum("attackSpeedPct")))
    p.castLock = shot.castTime / aps
    let aim = aimPoint(p)
    sim.emit(.cast(id: p.id, visual: "ranged", x: p.pos.x, y: p.pos.y, tx: aim.x, ty: aim.y))
    fireVolley(sim, p, shot, shot.coef, shot.count, shot.spread)
    if rangedExtraShot(p.save) {
        let dir = fromAngle(p.facing + (8 * Double.pi / 180))
        let pr = sim.spawnProjectile(
            Vec2(x: p.pos.x + dir.x * 0.5, y: p.pos.y + dir.y * 0.5),
            dir,
            speed: shot.speed, range: shot.range, radius: shot.radius, faction: .players, ownerId: p.id,
            visual: shot.visual, coef: shot.coef * 0.5, pierce: shot.pierce, slot: .ranged
        )
        pr.echoOnHit = shot.echoOnHit
    }
}

private func fireVolley(_ sim: Simulation, _ p: Player, _ shot: SwingShot, _ coef: Double, _ count: Int, _ spreadDeg: Double) {
    let spread = spreadDeg * Double.pi / 180
    var i = 0
    while i < count {
        let off = count == 1 ? 0 : -spread / 2 + (spread * Double(i)) / Double(count - 1)
        let dir = fromAngle(p.facing + off)
        let pr = sim.spawnProjectile(
            Vec2(x: p.pos.x + dir.x * 0.5, y: p.pos.y + dir.y * 0.5),
            dir,
            speed: shot.speed, range: shot.range, radius: shot.radius, faction: .players, ownerId: p.id,
            visual: shot.visual, coef: coef, pierce: shot.pierce, slot: .ranged
        )
        pr.echoOnHit = shot.echoOnHit
        i += 1
    }
}

private func tickSummon(_ sim: Simulation, _ p: Player, _ dt: Double) {
    let r = rankOf(p.save, "summon")
    if r <= 0 || sim.peaceful { return }
    p.summonLeft -= dt
    if p.summonLeft > 0 { return }
    p.summonLeft = 8
    let cap = r >= 3 ? 2 : 1
    var alive = 0
    for id in p.pets {
        if let m = sim.monsters.get(id), !m.dead { alive += 1 }
    }
    if alive >= cap { return }
    let duration = r >= 2 ? 10.0 : 6.0
    let m = sim.spawnMonster(summonMonsterId(p.save.origin), sim.scatter(p.pos, 1.4), ownerId: p.id, ttl: duration, level: p.save.level)
    if r >= 2 {
        m.maxHp = max(1, jsRound(m.maxHp * 1.5))
        m.hp = m.maxHp
    }
    sim.emit(.fx(visual: "summon", x: p.pos.x, y: p.pos.y, r: 2, tx: nil, ty: nil))
}

private func aimPoint(_ p: Player) -> Vec2 {
    Vec2(x: p.pos.x + cos(p.facing) * 2, y: p.pos.y + sin(p.facing) * 2)
}

private func closestInArc(_ sim: Simulation, _ p: Player, _ range: Double, _ arcDeg: Double) -> Monster? {
    let half = (arcDeg / 2) * Double.pi / 180
    var best: Monster?
    var bestD = Double.infinity
    for u in sim.units.query(p.pos.x, p.pos.y, range) {
        guard let monster = u as? Monster, monster.kind != "pet", !monster.dead else { continue }
        let dx = monster.pos.x - p.pos.x
        let dy = monster.pos.y - p.pos.y
        let d = hypot(dx, dy)
        let close = d < monster.radius + p.radius + 0.25
        if !close && abs(angleDiff(angleOf(Vec2(x: dx, y: dy)), p.facing)) > half { continue }
        if !sim.map.lineOfSight(p.pos, monster.pos) { continue }
        if d < bestD {
            bestD = d
            best = monster
        }
    }
    return best
}
