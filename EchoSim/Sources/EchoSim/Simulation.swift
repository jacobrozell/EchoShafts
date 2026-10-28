import Foundation

public struct SimScaling {
    public var monsterLevel: Int
    public var lifeMult: Double
    public var damageMult: Double
    public init(monsterLevel: Int, lifeMult: Double, damageMult: Double) {
        self.monsterLevel = monsterLevel
        self.lifeMult = lifeMult
        self.damageMult = damageMult
    }
}

private let LOOT_LIFETIME = 300.0
private let FIELD_REBUILD_TICKS = 4
private let FIELD_RADIUS = 48
private let DORMANCY_CHECK_TICKS = 10
private let WAKE_RADIUS = 30.0

public final class Simulation {
    public var tick = 0
    public var time = 0.0
    public let map: TileMap
    public var spawnPoint: Vec2
    public var scaling: SimScaling
    public let peaceful: Bool
    public let rng: Rng
    public var events: [GameEvent] = []
    public var onMonsterKilled: (Monster, Player?) -> Void = { _, _ in }
    public var onPlayerDied: (Player) -> Void = { _ in }

    let entities = OrderedBag<Entity>()
    public let players = OrderedBag<Player>()
    public let monsters = OrderedBag<Monster>()
    public let projectiles = OrderedBag<Projectile>()
    public let zones = OrderedBag<GroundZone>()
    public let loot = OrderedBag<Globe>()
    var strikes: [DelayedStrike] = []
    let units = SpatialHash<Unit>(cellSize: 4)
    let all = SpatialHash<Entity>(cellSize: 6)
    let field: DistanceField
    private var nextId = 1
    private var deferred: [(id: Int, at: Double)] = []

    public init(map: TileMap, seed: UInt32, spawnPoint: Vec2, scaling: SimScaling, peaceful: Bool = false) {
        self.map = map
        self.spawnPoint = spawnPoint
        self.scaling = scaling
        self.peaceful = peaceful
        rng = Rng(seed: seed)
        field = DistanceField(map)
    }

    public func allocId() -> Int {
        let id = nextId
        nextId += 1
        return id
    }

    func emit(_ e: GameEvent) { events.append(e) }

    public func addPlayer(_ p: Player) {
        entities.set(p.id, p)
        players.set(p.id, p)
        p.changedTick = tick
    }

    public func remove(_ id: Int) {
        guard let e = entities.get(id) else { return }
        e.removed = true
        entities.remove(id)
        monsters.remove(id)
        projectiles.remove(id)
        zones.remove(id)
        loot.remove(id)
        if let m = e as? Monster, m.ownerId != 0 {
            players.get(m.ownerId)?.removePet(id)
        }
    }

    @discardableResult
    public func spawnMonster(_ defId: String, _ pos: Vec2, tier: EliteTier = .normal, affixes: [EliteAffixId] = [], name: String? = nil, ownerId: Int? = nil, ttl: Double? = nil, level: Int? = nil) -> Monster {
        guard let def = MONSTERS[defId] else {
            preconditionFailure("unknown monster \(defId)")
        }
        let level = level ?? scaling.monsterLevel
        var extra: [MonsterAbility] = []
        var lifeMult = 1.0
        var speedMult = 1.0
        var atkMult = 1.0
        var takenMult = 1.0
        for a in affixes {
            guard let ad = ELITE_AFFIXES[a] else { continue }
            if let ability = ad.ability { extra.append(ability) }
            lifeMult *= ad.lifeMult ?? 1
            speedMult *= ad.speedMult ?? 1
            atkMult *= ad.attackSpeedMult ?? 1
            takenMult *= ad.damageTakenMult ?? 1
        }
        let tierLife = tier == .champion ? 3.2 : tier == .rare ? 4.5 : tier == .minion ? 1.6 : 1
        let tierDmg = tier == .champion ? 1.3 : tier == .rare ? 1.5 : tier == .minion ? 1.1 : 1
        let owned = ownerId != nil
        let life: Double
        if owned && def.ai == .pet { life = 1 }
        else if owned { life = def.life }
        else { life = def.life * monsterLifeScale(level) * scaling.lifeMult * tierLife * lifeMult }
        let dmg = def.damage * monsterDamageScale(level) * scaling.damageMult * tierDmg
        let m = Monster(id: allocId(), pos: pos, def: def, level: level, damage: dmg, tier: tier, affixes: affixes, extra: extra)
        m.maxHp = max(1, jsRound(life))
        m.hp = m.maxHp
        m.speedMult = speedMult
        m.attackSpeedMult = atkMult
        m.damageTakenMult = takenMult
        if let name { m.name = name }
        if let ownerId {
            m.ownerId = ownerId
            m.faction = .players
            m.kind = "pet"
            m.dormant = false
            m.noReward = true
            players.get(ownerId)?.addPet(m.id)
        }
        if let ttl { m.expiresAt = time + ttl }
        m.changedTick = tick
        entities.set(m.id, m)
        monsters.set(m.id, m)
        return m
    }

    @discardableResult
    public func spawnProjectile(_ from: Vec2, _ dir: Vec2, speed: Double, range: Double, radius: Double, faction: Faction, ownerId: Int, visual: String, coef: Double = 0, flat: Double = 0, pierce: Int = 0, explodeRadius: Double = 0, applies: StatusDef? = nil, slot: AttackSlot? = nil) -> Projectile {
        let pr = Projectile(
            id: allocId(), pos: from, radius: radius,
            vel: Vec2(x: dir.x * speed, y: dir.y * speed), rangeLeft: range,
            faction: faction, ownerId: ownerId, visual: visual, coef: coef, flat: flat,
            pierce: pierce, explodeRadius: explodeRadius, applies: applies, slot: slot
        )
        entities.set(pr.id, pr)
        projectiles.set(pr.id, pr)
        return pr
    }

    @discardableResult
    func spawnZone(_ pos: Vec2, radius: Double, duration: Double, faction: Faction, ownerId: Int, visual: String, coefPerSec: Double = 0, flatPerSec: Double = 0, applies: StatusDef? = nil) -> GroundZone {
        let g = GroundZone(id: allocId(), pos: pos, radius: radius, left: duration, faction: faction, ownerId: ownerId, visual: visual, coefPerSec: coefPerSec, flatPerSec: flatPerSec, applies: applies)
        entities.set(g.id, g)
        zones.set(g.id, g)
        return g
    }

    public func scatter(_ at: Vec2, _ spread: Double = 1.4) -> Vec2 {
        var i = 0
        while i < 8 {
            let p = Vec2(x: at.x + rng.range(-spread, spread), y: at.y + rng.range(-spread, spread))
            if !map.collides(p.x, p.y, 0.3) && map.lineOfSight(at, p) { return p }
            i += 1
        }
        return at
    }

    public func dropGlobe(_ at: Vec2) {
        let g = Globe(id: allocId(), pos: scatter(at))
        entities.set(g.id, g)
        loot.set(g.id, g)
    }

    public func step() {
        let dt = TICK_SECONDS
        tick += 1
        time += dt
        rebuildHashes()
        if tick % FIELD_REBUILD_TICKS == 0 && !peaceful {
            var sources: [Vec2] = []
            for p in players.all where !p.dead { sources.append(p.pos) }
            field.build(sources, FIELD_RADIUS)
        }
        if tick % DORMANCY_CHECK_TICKS == 0 { updateDormancy() }
        for p in players.all {
            tickUnitTimers(self, p, dt)
            updatePlayer(self, p, dt)
        }
        for m in monsters.all {
            if m.removed || m.dormant || m.dead { continue }
            tickUnitTimers(self, m, dt)
            if m.hp <= 0 && !m.dead {
                killMonster(m, nil)
                continue
            }
            if time >= m.expiresAt {
                emit(.fx(visual: "vanish", x: m.pos.x, y: m.pos.y, r: nil, tx: nil, ty: nil))
                remove(m.id)
                continue
            }
            updateMonsterAi(self, m, dt)
        }
        updateForcedMoves(dt)
        updateProjectiles(dt)
        updateStrikes(dt)
        updateZones(dt)
        updateLoot(dt)
        flushDeferred()
    }

    private func rebuildHashes() {
        units.clear()
        all.clear()
        for e in entities.all {
            all.insert(e)
            if let u = e as? Unit, !u.dead { units.insert(u) }
        }
    }

    private func updateDormancy() {
        let ps = players.all
        for m in monsters.all where m.dormant {
            for p in ps {
                let dx = p.pos.x - m.pos.x
                let dy = p.pos.y - m.pos.y
                if dx * dx + dy * dy < WAKE_RADIUS * WAKE_RADIUS {
                    m.dormant = false
                    break
                }
            }
        }
    }

    private func updateForcedMoves(_ dt: Double) {
        var movers: [Unit] = []
        for p in players.all where p.forced != nil { movers.append(p) }
        for m in monsters.all where m.forced != nil { movers.append(m) }
        for u in movers {
            guard let f = u.forced, !u.dead else { continue }
            let step = min(dt, f.left)
            let before = u.pos
            u.pos = map.move(u.pos, f.vx * step, f.vy * step, u.radius)
            u.changedTick = tick
            f.left -= step
            let blocked = hypot(u.pos.x - before.x, u.pos.y - before.y) < 0.01
            if let hit = f.hit {
                let enemy: Faction = u.faction == .players ? .monsters : .players
                for t in units.query(u.pos.x, u.pos.y, hit.radius) {
                    if t.faction != enemy || t.dead || hit.hitIds.contains(t.id) { continue }
                    hit.hitIds.insert(t.id)
                    if let player = u as? Player, let monster = t as? Monster {
                        _ = playerHitMonster(self, player, monster, hit.coef, .melee, hit.applies)
                    } else if let monster = u as? Monster, let player = t as? Player {
                        _ = damagePlayer(self, player, hit.flat, monster)
                    }
                }
            }
            if f.left <= 0 || blocked { u.forced = nil }
        }
    }

    private func updateProjectiles(_ dt: Double) {
        for pr in projectiles.all {
            if pr.removed { continue }
            let dx = pr.vel.x * dt
            let dy = pr.vel.y * dt
            pr.pos = Vec2(x: pr.pos.x + dx, y: pr.pos.y + dy)
            pr.rangeLeft -= hypot(dx, dy)
            if map.solidPoint(pr.pos.x, pr.pos.y) || pr.rangeLeft <= 0 {
                if pr.explodeRadius > 0 { explode(pr) }
                remove(pr.id)
                continue
            }
            for t in units.query(pr.pos.x, pr.pos.y, pr.radius) {
                if t.dead || t.faction == pr.faction || pr.hitIds.contains(t.id) { continue }
                pr.hitIds.insert(t.id)
                if pr.explodeRadius > 0 {
                    explode(pr)
                    remove(pr.id)
                    break
                }
                projectileHit(pr, t)
                let current = pr.pierce
                pr.pierce -= 1
                if current <= 0 {
                    remove(pr.id)
                    break
                }
            }
        }
    }

    private func projectileHit(_ pr: Projectile, _ t: Unit) {
        if pr.faction == .players, let monster = t as? Monster {
            guard let owner = players.get(pr.ownerId) else { return }
            _ = playerHitMonster(self, owner, monster, pr.coef, pr.slot ?? .ranged, pr.applies)
            if pr.echoOnHit > 0 && pr.hitIds.count == 1 { gainResource(owner, pr.echoOnHit) }
        } else if pr.faction == .monsters, let player = t as? Player {
            _ = damagePlayer(self, player, pr.flat, monsters.get(pr.ownerId))
        }
    }

    private func explode(_ pr: Projectile) {
        emit(.fx(visual: "\(pr.visual)_boom", x: pr.pos.x, y: pr.pos.y, r: pr.explodeRadius, tx: nil, ty: nil))
        for t in units.query(pr.pos.x, pr.pos.y, pr.explodeRadius) {
            if t.dead || t.faction == pr.faction { continue }
            projectileHit(pr, t)
        }
    }

    private func updateStrikes(_ dt: Double) {
        var keep: [DelayedStrike] = []
        for s in strikes {
            s.left -= dt
            if s.left > 0 {
                keep.append(s)
                continue
            }
            emit(.fx(visual: s.visual, x: s.pos.x, y: s.pos.y, r: s.radius, tx: nil, ty: nil))
            for t in units.query(s.pos.x, s.pos.y, s.radius) {
                if t.dead || t.faction == s.faction { continue }
                if s.faction == .players, let monster = t as? Monster, let owner = players.get(s.ownerId) {
                    _ = playerHitMonster(self, owner, monster, s.coef, .melee, s.applies)
                } else if s.faction == .monsters, let player = t as? Player {
                    _ = damagePlayer(self, player, s.flat, monsters.get(s.ownerId))
                    if let applies = s.applies { applyStatus(self, player, applies, nil) }
                }
            }
        }
        strikes = keep
    }

    private func updateZones(_ dt: Double) {
        for z in zones.all {
            if z.removed { continue }
            z.left -= dt
            if z.left <= 0 {
                remove(z.id)
                continue
            }
            z.tickTimer -= dt
            if z.tickTimer > 0 { continue }
            z.tickTimer = 0.5
            for t in units.query(z.pos.x, z.pos.y, z.radius) {
                if t.dead || t.faction == z.faction { continue }
                if z.faction == .players, let monster = t as? Monster, let owner = players.get(z.ownerId) {
                    _ = playerHitMonster(self, owner, monster, z.coefPerSec * 0.5, z.slot ?? .melee, z.applies)
                } else if z.faction == .monsters, let player = t as? Player {
                    _ = damagePlayer(self, player, z.flatPerSec * 0.5, nil)
                }
            }
        }
    }

    private func updateLoot(_ dt: Double) {
        for l in loot.all {
            if l.removed { continue }
            l.age += dt
            if l.age > LOOT_LIFETIME {
                remove(l.id)
                continue
            }
            for p in players.all {
                if p.dead { continue }
                let r = p.stats.pickupRadius + l.radius
                let dx = p.pos.x - l.pos.x
                let dy = p.pos.y - l.pos.y
                if dx * dx + dy * dy > r * r { continue }
                healUnit(self, p, p.maxHp * GLOBE_HEAL_PCT)
                emit(.fx(visual: "globe", x: l.pos.x, y: l.pos.y, r: nil, tx: nil, ty: nil))
                remove(l.id)
                break
            }
        }
    }

    public func killMonster(_ m: Monster, _ killer: Player?) {
        if m.dead { return }
        m.dead = true
        m.hp = 0
        m.windup = nil
        m.forced = nil
        m.changedTick = tick
        emit(.die(id: m.id, x: m.pos.x, y: m.pos.y))
        if m.affixes.contains(.volatile) {
            strikes.append(DelayedStrike(pos: m.pos, radius: 2.4, left: 1.0, faction: .monsters, ownerId: m.id, coef: 0, flat: m.damage * 1.6, visual: "volatile"))
            emit(.tele(x: m.pos.x, y: m.pos.y, r: 2.4, d: 1.0, tx: nil, ty: nil, w: nil))
        }
        if m.kind != "pet" { onMonsterKilled(m, killer) }
        deferred.append((m.id, time + 0.6))
    }

    private func flushDeferred() {
        let now = time
        deferred = deferred.filter { d in
            if d.at > now { return true }
            remove(d.id)
            return false
        }
    }

    public func killPlayer(_ p: Player) {
        if p.dead { return }
        p.dead = true
        p.hp = 0
        p.forced = nil
        p.castLock = 0
        p.dots = []
        p.changedTick = tick
        for petId in p.pets { remove(petId) }
        p.pets.removeAll()
        emit(.die(id: p.id, x: p.pos.x, y: p.pos.y))
        onPlayerDied(p)
    }
}
