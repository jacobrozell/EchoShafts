import Foundation

public enum RunOutcome: String { case clear, death, timeout, abandoned }
public enum VesselState: String { case none, spawned, slain }

public struct ShaftOptions {
    public var kind: ShaftKind
    public var seed: UInt32
    public var depth: Int
    public init(kind: ShaftKind, seed: UInt32, depth: Int) {
        self.kind = kind
        self.seed = seed
        self.depth = depth
    }
}

public func fleshPayout(kind: ShaftKind, outcome: RunOutcome, echo: Double, echoRequired: Double, vessel: VesselState, depth: Int) -> Int {
    if kind == .tutorial || outcome == .clear || outcome == .abandoned { return 0 }
    if kind == .echo && outcome == .death {
        var n = 0
        if echoRequired > 0 && echo / echoRequired >= 0.5 { n += 1 }
        if vessel == .spawned || vessel == .slain { n += 1 }
        return min(2, n)
    }
    if kind == .deep && outcome == .death { return min(topRankCost(), max(0, depth)) }
    if kind == .deep && outcome == .timeout { return min(topRankCost(), max(0, depth)) / 2 }
    return 0
}

public final class ShaftRun {
    public let sim: Simulation
    public let player: Player
    public let save: Save
    public let opts: ShaftOptions
    public var echo = 0.0
    public var echoRequired = 0.0
    public var vessel: VesselState = .none
    public var vesselId = 0
    public var offer: GearOffer?
    public var offerRng: Rng
    public var outcome: RunOutcome?
    public var clearTick = 0
    public var fleshPaid = 0
    private let lootRng: Rng
    private let vesselRng: Rng
    private let rewardBonus: Double
    private let snapLevel: Int
    private let snapXp: Int

    public init(save: Save, kind: ShaftKind, seed: UInt32, depth: Int) {
        self.save = save
        opts = ShaftOptions(kind: kind, seed: seed, depth: depth)
        let size = shaftSize(kind)
        let layout = generateDungeon(seed: seed, width: size.width, height: size.height, rooms: size.rooms)
        // Surface life is tuned for a geared clear. The lesson mine is a smaller shaft
        // where a company swing drops a thrall in one or two hits.
        let scaling: (life: Double, damage: Double, reward: Double)
        if kind == .deep {
            let deep = deepVeinScaling(max(1, depth))
            scaling = (deep.lifeMult, deep.damageMult, deep.rewardBonus)
        } else if kind == .tutorial {
            scaling = (0.85, 0.4, 0)
        } else {
            scaling = (SURFACE_LIFE, SURFACE_DAMAGE, SURFACE_REWARD)
        }
        rewardBonus = scaling.reward
        let mixed = seed ^ 0x5eed
        sim = Simulation(
            map: layout.map,
            seed: mixed,
            spawnPoint: layout.start,
            scaling: SimScaling(monsterLevel: save.level, lifeMult: scaling.life, damageMult: scaling.damage)
        )
        lootRng = sim.rng.fork("loot")
        vesselRng = sim.rng.fork("vessel")
        offerRng = sim.rng.fork("offer")
        let summary = populateDungeon(sim, layout, sim.rng.fork("packs"), kind == .deep ? 1.05 : 1, kind == .tutorial)
        let fill = kind == .tutorial ? ECHO_FILL.tutorial : kind == .deep ? ECHO_FILL.deep : ECHO_FILL.echo
        echoRequired = Double(max(8, jsRoundInt(summary.echoTotal * fill)))
        snapLevel = save.level
        snapXp = save.xp
        let stats = deriveStats(save)
        player = Player(id: sim.allocId(), pos: layout.start, name: "warden", save: save, stats: stats)
        sim.addPlayer(player)
        sim.onMonsterKilled = { [weak self] m, _ in self?.onKill(m) }
        sim.onPlayerDied = { [weak self] _ in self?.finish(.death) }
    }

    public func step(mx: Double, my: Double, b: Int, lock: Int) {
        if outcome != nil { return }
        player.input = PlayerInput(seq: sim.tick, mx: jsRound(mx * 100) / 100, my: jsRound(my * 100) / 100, buttons: b, lock: lock)
        sim.step()
        evaluateEnd()
    }

    public func abandon() {
        if outcome != nil { return }
        outcome = .abandoned
        save.level = snapLevel
        save.xp = snapXp
        let stats = deriveStats(save)
        player.stats = stats
        player.maxHp = stats.maxLife
        player.hp = stats.maxLife
    }

    public func evaluateEnd() {
        if outcome != nil { return }
        if opts.kind == .deep && vessel != .slain && sim.time >= DEEP_VEIN_SECONDS { finish(.timeout) }
    }

    public func fingerprint() -> String {
        let alive = sim.monsters.all.filter { !$0.dead }.sorted { $0.id < $1.id }
        let ms = alive.map { m in
            "\(m.id):\(jsRoundInt(m.hp)):\(fixed(m.pos.x, 1)):\(fixed(m.pos.y, 1))"
        }.joined(separator: ",")
        return "\(sim.tick)|\(fixed(player.pos.x, 2))|\(fixed(player.pos.y, 2))|\(jsRoundInt(player.hp))|\(echo)|\(vessel.rawValue)|\(ms)"
    }

    private func onKill(_ m: Monster) {
        if m.noReward || m.kind == "pet" { return }
        let xp = applyXp(save.level, save.xp, killXp(m.def.xp, m.level, rewardBonus))
        save.level = xp.level
        save.xp = xp.xp
        if xp.levelsGained > 0 {
            let stats = deriveStats(save)
            let gained = stats.maxLife - player.maxHp
            player.stats = stats
            player.maxHp = stats.maxLife
            player.hp = min(stats.maxLife, player.hp + max(0, gained))
            sim.emit(.lvl(id: player.id))
        }
        if m.tier != .normal || lootRng.chance(0.07) { sim.dropGlobe(m.pos) }
        if m.id == vesselId {
            vessel = .slain
            finish(.clear)
            return
        }
        if vessel != .none { return }
        let mult: Double = m.tier == .champion ? 4 : m.tier == .rare ? 6 : m.tier == .minion ? 2 : 1
        echo += m.def.echo * mult
        if echo >= echoRequired { spawnVessel(m.pos) }
    }

    private func spawnVessel(_ near: Vec2) {
        let defId = vesselRng.pick(VESSEL_IDS)
        var pos = near
        var i = 0
        while i < 24 {
            let a = vesselRng.next() * Double.pi * 2
            let p = Vec2(x: near.x + cos(a) * 5, y: near.y + sin(a) * 5)
            if !sim.map.collides(p.x, p.y, 1.1) && sim.map.lineOfSight(near, p) {
                pos = p
                break
            }
            i += 1
        }
        let v = sim.spawnMonster(defId, pos, tier: .boss)
        v.dormant = false
        if opts.kind == .tutorial {
            v.maxHp = 48
            v.hp = 48
        }
        vesselId = v.id
        vessel = .spawned
        sim.emit(.fx(visual: "vessel_rise", x: pos.x, y: pos.y, r: 3, tx: nil, ty: nil))
        if let line = vesselLine(defId) {
            sim.emit(.say(id: v.id, text: line))
        }
    }

    private func finish(_ outcome: RunOutcome) {
        if self.outcome == .abandoned { return }
        if outcome == .death {
            self.outcome = .death
            pay()
            return
        }
        if self.outcome != nil { return }
        self.outcome = outcome
        if outcome == .clear {
            clearTick = sim.tick
            offer = rollClearOffer(save, offerRng)
        }
        pay()
    }

    private func pay() {
        guard let outcome else { return }
        let n = fleshPayout(kind: opts.kind, outcome: outcome, echo: echo, echoRequired: echoRequired, vessel: vessel, depth: opts.depth)
        fleshPaid = n
        save.flesh += n
    }
}

private func fixed(_ n: Double, _ places: Int) -> String {
    String(format: "%.\(places)f", n)
}
