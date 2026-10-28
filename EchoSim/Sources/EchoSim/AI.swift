import Foundation

private let SEPARATION = 0.9
private let LEASH = 40.0

func updateMonsterAi(_ sim: Simulation, _ m: Monster, _ dt: Double) {
    var i = 0
    while i < m.abilityCds.count {
        if m.abilityCds[i] > 0 { m.abilityCds[i] -= dt * m.attackSpeedMult }
        i += 1
    }
    if m.stunLeft > 0 || m.forced != nil { return }
    if m.def.ai == .pet || m.ownerId != 0 { updatePet(sim, m, dt); return }
    if m.def.ai == .flee { updateFleer(sim, m, dt); return }

    if m.def.bossPhases && m.phase == 1 && m.hp < m.maxHp * 0.5 {
        m.phase = 2
        m.speedMult *= 1.15
        m.attackSpeedMult *= 1.35
    }

    guard let target = pickTarget(sim, m) else {
        if m.aggro {
            m.aggro = false
            m.targetId = 0
        }
        return
    }
    if !m.aggro { m.aggro = true; m.aggroAt = sim.time }
    m.targetId = target.id

    if let wind = m.windup {
        wind.left -= dt * m.attackSpeedMult
        if wind.ability.kind == .melee || wind.ability.kind == .projectile { wind.target = target.pos }
        if wind.left <= 0 {
            let ability = wind.ability
            let at = wind.target
            m.windup = nil
            resolveAbility(sim, m, ability, at, target)
            m.changedTick = sim.tick
        }
        return
    }

    let d = hypot(target.pos.x - m.pos.x, target.pos.y - m.pos.y)
    let los = d < 16 && sim.map.lineOfSight(m.pos, target.pos)
    if los {
        var pass = 0
        while pass < 2 {
            var i = 0
            while i < m.abilities.count {
                let a = m.abilities[i]
                if (pass == 0) == (a.kind == .melee) { i += 1; continue }
                if m.abilityCds[i] > 0 { i += 1; continue }
                if !inRange(a, d, m, target) { i += 1; continue }
                startWindup(sim, m, a, i, target)
                return
            }
            pass += 1
        }
    }

    var dir: Vec2?
    if let pref = m.def.preferredRange, los {
        if d < pref - 1.5 { dir = norm(Vec2(x: m.pos.x - target.pos.x, y: m.pos.y - target.pos.y)) }
        else if d > pref + 1.5 { dir = norm(Vec2(x: target.pos.x - m.pos.x, y: target.pos.y - m.pos.y)) }
        else {
            let a = angleOf(Vec2(x: m.pos.x - target.pos.x, y: m.pos.y - target.pos.y)) + m.strafeDir * 0.9
            let goal = Vec2(x: target.pos.x + cos(a) * pref, y: target.pos.y + sin(a) * pref)
            dir = norm(Vec2(x: goal.x - m.pos.x, y: goal.y - m.pos.y))
            if sim.rng.chance(0.01) { m.strafeDir *= -1 }
        }
    } else {
        let contact = m.radius + target.radius + 0.15
        if d <= contact { dir = nil }
        else if los && d < 7 { dir = norm(Vec2(x: target.pos.x - m.pos.x, y: target.pos.y - m.pos.y)) }
        else { dir = sim.field.descend(m.pos.x, m.pos.y) ?? (los ? norm(Vec2(x: target.pos.x - m.pos.x, y: target.pos.y - m.pos.y)) : nil) }
    }
    moveUnit(sim, m, dir, dt)
}

private func inRange(_ a: MonsterAbility, _ d: Double, _ m: Monster, _ t: Unit) -> Bool {
    switch a.kind {
    case .melee: return d <= a.range + m.radius + t.radius
    case .heal: return true
    case .pool: return a.range == 0 || d <= a.range
    default: return d <= a.range
    }
}

private func startWindup(_ sim: Simulation, _ m: Monster, _ a: MonsterAbility, _ index: Int, _ target: Unit) {
    if a.kind == .heal {
        let wounded = sim.units.query(m.pos.x, m.pos.y, a.radius).contains { u in
            guard let monster = u as? Monster else { return false }
            return monster.faction == .monsters && monster.hp < monster.maxHp * 0.8
        }
        if !wounded {
            m.abilityCds[index] = 1.5
            return
        }
    }
    m.abilityCds[index] = a.cooldown
    let tpos = (a.kind == .pool && a.range == 0) ? m.pos : target.pos
    m.windup = Windup(ability: a, index: index, left: a.windup, target: tpos)
    m.facing = angleOf(Vec2(x: target.pos.x - m.pos.x, y: target.pos.y - m.pos.y))
    m.changedTick = sim.tick
    let wind = a.windup / m.attackSpeedMult
    switch a.kind {
    case .slam:
        sim.emit(.tele(x: tpos.x, y: tpos.y, r: a.radius, d: wind, tx: nil, ty: nil, w: nil))
    case .pool:
        if a.windup > 0 { sim.emit(.tele(x: tpos.x, y: tpos.y, r: a.radius, d: wind, tx: nil, ty: nil, w: nil)) }
    case .charge:
        sim.emit(.tele(x: m.pos.x, y: m.pos.y, r: 0.8, d: wind, tx: tpos.x, ty: tpos.y, w: 0))
    case .nova, .summon, .heal:
        sim.emit(.cast(id: m.id, visual: a.kind.rawValue, x: m.pos.x, y: m.pos.y, tx: tpos.x, ty: tpos.y))
    default:
        break
    }
    if a.windup <= 0 {
        m.windup = nil
        resolveAbility(sim, m, a, tpos, target)
    }
}

private func resolveAbility(_ sim: Simulation, _ m: Monster, _ a: MonsterAbility, _ at: Vec2, _ target: Unit) {
    switch a.kind {
    case .melee:
        let d = hypot(target.pos.x - m.pos.x, target.pos.y - m.pos.y)
        sim.emit(.cast(id: m.id, visual: "swipe", x: m.pos.x, y: m.pos.y, tx: target.pos.x, ty: target.pos.y))
        if d <= a.range + m.radius + target.radius + 0.35, let player = target as? Player {
            _ = damagePlayer(sim, player, m.damage * a.coef, m)
        }
    case .projectile:
        let base = angleOf(Vec2(x: at.x - m.pos.x, y: at.y - m.pos.y))
        let n = a.count
        let spread = (a.spread * Double.pi) / 180
        var i = 0
        while i < n {
            let off = n == 1 ? 0 : -spread / 2 + (spread * Double(i)) / Double(n - 1)
            _ = sim.spawnProjectile(m.pos, fromAngle(base + off), speed: a.speed, range: a.range, radius: 0.3, faction: .monsters, ownerId: m.id, visual: a.visual, flat: m.damage * a.coef)
            i += 1
        }
    case .nova:
        var i = 0
        while i < a.count {
            _ = sim.spawnProjectile(m.pos, fromAngle((Double(i) / Double(a.count)) * Double.pi * 2 + sim.time), speed: a.speed, range: a.range, radius: 0.3, faction: .monsters, ownerId: m.id, visual: a.visual, flat: m.damage * a.coef)
            i += 1
        }
    case .slam:
        sim.emit(.fx(visual: "slam", x: at.x, y: at.y, r: a.radius, tx: nil, ty: nil))
        for u in sim.units.query(at.x, at.y, a.radius) {
            if let player = u as? Player { _ = damagePlayer(sim, player, m.damage * a.coef, m) }
        }
    case .charge:
        let dir = norm(Vec2(x: at.x - m.pos.x, y: at.y - m.pos.y))
        let dist = min(a.range, hypot(at.x - m.pos.x, at.y - m.pos.y) + 1.5)
        m.forced = ForcedMove(vx: dir.x * a.speed, vy: dir.y * a.speed, left: dist / a.speed, hit: HitSpec(flat: m.damage * a.coef, radius: m.radius + 0.4))
    case .summon:
        let alive = sim.monsters.all.filter { $0.def.id == a.monsterId && !$0.dead && $0.kind == "monster" }.count
        if alive > 30 { break }
        var i = 0
        while i < a.count {
            let pos = sim.scatter(m.pos, a.range)
            let s = sim.spawnMonster(a.monsterId, pos, level: m.level)
            s.dormant = false
            s.aggro = true
            s.targetId = target.id
            s.noReward = true
            sim.emit(.fx(visual: "summon_red", x: pos.x, y: pos.y, r: nil, tx: nil, ty: nil))
            i += 1
        }
    case .pool:
        _ = sim.spawnZone(at, radius: a.radius, duration: a.duration, faction: .monsters, ownerId: m.id, visual: "dust", flatPerSec: m.damage * a.coefPerSec)
    case .heal:
        sim.emit(.fx(visual: "chant", x: m.pos.x, y: m.pos.y, r: a.radius, tx: nil, ty: nil))
        for u in sim.units.query(m.pos.x, m.pos.y, a.radius) {
            if let monster = u as? Monster, monster.faction == .monsters { healUnit(sim, monster, monster.maxHp * a.pct) }
        }
    }
}

private func pickTarget(_ sim: Simulation, _ m: Monster) -> Player? {
    if m.targetId != 0, let current = sim.players.get(m.targetId), !current.dead {
        let d = hypot(current.pos.x - m.pos.x, current.pos.y - m.pos.y)
        if d < LEASH { return current }
    }
    var best: Player?
    var bestD = m.aggro ? LEASH : m.def.aggroRange
    for p in sim.players.all {
        if p.dead { continue }
        let d = hypot(p.pos.x - m.pos.x, p.pos.y - m.pos.y)
        if d < bestD && (m.aggro || sim.map.lineOfSight(m.pos, p.pos)) {
            best = p
            bestD = d
        }
    }
    if best == nil && !m.aggro {
        for u in sim.units.query(m.pos.x, m.pos.y, 6) {
            if let other = u as? Monster, other !== m, other.aggro, other.targetId != 0, let t = sim.players.get(other.targetId), !t.dead {
                return t
            }
        }
    }
    return best
}

func moveUnit(_ sim: Simulation, _ m: Monster, _ dir: Vec2?, _ dt: Double) {
    var vx = dir?.x ?? 0
    var vy = dir?.y ?? 0
    for u in sim.units.query(m.pos.x, m.pos.y, SEPARATION + m.radius) {
        if u === m || u.faction != m.faction { continue }
        let dx = m.pos.x - u.pos.x
        let dy = m.pos.y - u.pos.y
        var d = hypot(dx, dy)
        if d == 0 { d = 0.01 }
        let overlap = m.radius + u.radius + 0.1 - d
        if overlap > 0 {
            vx += (dx / d) * overlap * 2.5
            vy += (dy / d) * overlap * 2.5
        }
    }
    if vx == 0 && vy == 0 { return }
    let l = hypot(vx, vy)
    let sp = m.def.speed * m.speedMult * m.slowMult * dt
    let k = l > 1 ? sp / l : sp
    let before = m.pos
    m.pos = sim.map.move(m.pos, vx * k, vy * k, m.radius)
    if m.pos.x != before.x || m.pos.y != before.y {
        if let dir { m.facing = angleOf(dir) }
        m.changedTick = sim.tick
    }
}

private func updatePet(_ sim: Simulation, _ m: Monster, _ dt: Double) {
    guard let owner = sim.players.get(m.ownerId), !owner.dead else {
        sim.remove(m.id)
        return
    }
    let dOwner = hypot(owner.pos.x - m.pos.x, owner.pos.y - m.pos.y)
    if dOwner > 16 {
        m.pos = sim.scatter(owner.pos, 1.2)
        m.changedTick = sim.tick
        return
    }
    var target: Monster?
    var best = 9.0
    for u in sim.units.query(owner.pos.x, owner.pos.y, 9) {
        guard let monster = u as? Monster, monster.faction == .monsters, !monster.dead else { continue }
        let d = hypot(monster.pos.x - m.pos.x, monster.pos.y - m.pos.y)
        if d < best {
            best = d
            target = monster
        }
    }
    if let target, let bite = m.abilities.first, bite.kind == .melee {
        let reach = bite.range + m.radius + target.radius
        if best <= reach {
            if m.abilityCds[0] <= 0 {
                m.abilityCds[0] = bite.cooldown
                m.facing = angleOf(Vec2(x: target.pos.x - m.pos.x, y: target.pos.y - m.pos.y))
                sim.emit(.cast(id: m.id, visual: "bite", x: m.pos.x, y: m.pos.y, tx: target.pos.x, ty: target.pos.y))
                petHitMonster(sim, m, target, bite.coef)
            }
            return
        }
        moveUnit(sim, m, norm(Vec2(x: target.pos.x - m.pos.x, y: target.pos.y - m.pos.y)), dt)
        return
    }
    if dOwner > 2.5 { moveUnit(sim, m, norm(Vec2(x: owner.pos.x - m.pos.x, y: owner.pos.y - m.pos.y)), dt) }
}

private func updateFleer(_ sim: Simulation, _ m: Monster, _ dt: Double) {
    var nearest: Player?
    var nd = Double.infinity
    for p in sim.players.all {
        if p.dead { continue }
        let d = hypot(p.pos.x - m.pos.x, p.pos.y - m.pos.y)
        if d < nd {
            nd = d
            nearest = p
        }
    }
    if !m.aggro, nearest != nil, nd < m.def.aggroRange {
        m.aggro = true
        m.aggroAt = sim.time
    }
    guard m.aggro, let nearest else { return }
    if let escape = m.def.escapeAfter, sim.time - m.aggroAt > escape {
        sim.emit(.fx(visual: "escape", x: m.pos.x, y: m.pos.y, r: nil, tx: nil, ty: nil))
        sim.remove(m.id)
        return
    }
    var best: Vec2?
    var bestScore = -1.0
    var k = 0
    while k < 8 {
        let dir = fromAngle((Double(k) / 8) * Double.pi * 2)
        let probe = Vec2(x: m.pos.x + dir.x * 1.5, y: m.pos.y + dir.y * 1.5)
        if !sim.map.collides(probe.x, probe.y, m.radius) {
            let score = min(60, Double(sim.field.at(probe.x, probe.y))) + sim.rng.next() * 0.5
            if score > bestScore {
                bestScore = score
                best = dir
            }
        }
        k += 1
    }
    moveUnit(sim, m, best ?? norm(Vec2(x: m.pos.x - nearest.pos.x, y: m.pos.y - nearest.pos.y)), dt)
}
