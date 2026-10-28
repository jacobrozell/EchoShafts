import Foundation

struct SpawnSummary {
    var monsters: Int
    var echoTotal: Double
    var elites: Int
}

func populateDungeon(_ sim: Simulation, _ layout: DungeonLayout, _ rng: Rng, _ density: Double = 1, _ lesson: Bool = false) -> SpawnSummary {
    var echoTotal = 0.0
    var count = 0
    var elites = 0
    let spots = layout.packSpots.filter { p in
        hypot(p.x - layout.start.x, p.y - layout.start.y) > (lesson ? 5 : 9) &&
            hypot(p.x - layout.bossRoom.cx, p.y - layout.bossRoom.cy) > 3
    }
    func add(_ m: Monster) {
        let mult: Double = m.tier == .champion ? 4 : m.tier == .rare ? 6 : m.tier == .minion ? 2 : 1
        echoTotal += m.def.echo * mult
        count += 1
    }
    if lesson {
        let ordered = spots.sorted { a, b in
            hypot(a.x - layout.start.x, a.y - layout.start.y) < hypot(b.x - layout.start.x, b.y - layout.start.y)
        }
        var i = 0
        while i < ordered.count {
            let ids: [String]
            if i == 1 || ordered.count < 2 {
                ids = ["chanter", "chanter"]
            } else if rng.chance(0.3) {
                ids = ["mite", "mite", "mite"]
            } else {
                ids = ["thrall", "thrall"]
            }
            for id in ids { add(sim.spawnMonster(id, sim.scatter(ordered[i], 1.3))) }
            i += 1
        }
        return SpawnSummary(monsters: count, echoTotal: echoTotal, elites: elites)
    }
    for spot in spots {
        let roll = rng.next()
        if roll < 0.09 * density {
            spawnChampionPack(sim, spot, rng).forEach(add)
            elites += 1
        } else if roll < 0.15 * density {
            spawnRarePack(sim, spot, rng).forEach(add)
            elites += 1
        } else {
            let pack = rng.weighted(PACK_TABLE)
            let n = max(1, Int(jsRound(Double(pack.count) * density)))
            var i = 0
            while i < n {
                add(sim.spawnMonster(pack[i % pack.count], sim.scatter(spot, 1.6)))
                i += 1
            }
        }
    }
    if spots.count > 4 && rng.chance(0.35) {
        let spot = spots[rng.int(jsFloor(Double(spots.count) / 3), spots.count - 1)]
        add(sim.spawnMonster("tithe_runner", spot))
    }
    return SpawnSummary(monsters: count, echoTotal: echoTotal, elites: elites)
}

private func rollAffixes(_ rng: Rng, _ n: Int) -> [EliteAffixId] {
    var all = ELITE_AFFIX_ORDER
    _ = rng.shuffle(&all)
    return Array(all.prefix(n))
}

private func eliteName(_ rng: Rng) -> String {
    "\(rng.pick(ELITE_NAME_FIRST)) \(rng.pick(ELITE_NAME_EPITHET))"
}

func spawnChampionPack(_ sim: Simulation, _ at: Vec2, _ rng: Rng) -> [Monster] {
    let affixes = rollAffixes(rng, 2)
    let type = rng.pick(["initiate", "deserter", "crawler", "chanter"])
    let n = type == "deserter" ? 3 : 4
    var out: [Monster] = []
    var i = 0
    while i < n {
        out.append(sim.spawnMonster(type, sim.scatter(at, 1.4), tier: .champion, affixes: affixes))
        i += 1
    }
    return out
}

func spawnRarePack(_ sim: Simulation, _ at: Vec2, _ rng: Rng) -> [Monster] {
    let affixes = rollAffixes(rng, 3)
    let type = rng.pick(["initiate", "deserter", "chanter"])
    var out: [Monster] = [sim.spawnMonster(type, at, tier: .rare, affixes: affixes, name: eliteName(rng))]
    let minion = type == "chanter" ? "thrall" : "initiate"
    var i = 0
    while i < 4 {
        out.append(sim.spawnMonster(minion, sim.scatter(at, 1.8), tier: .minion))
        i += 1
    }
    return out
}
