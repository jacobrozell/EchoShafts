import XCTest
@testable import EchoSim

final class SimTests: XCTestCase {
    func arena() -> TileMap {
        let m = TileMap(w: 40, h: 30)
        var y = 1
        while y < 29 {
            var x = 1
            while x < 39 {
                m.set(x, y, Int(Tile.floor.rawValue))
                x += 1
            }
            y += 1
        }
        return m
    }

    func warden(_ sim: Simulation, _ save: Save = newSave()) -> Player {
        let stats = deriveStats(save)
        let p = Player(id: sim.allocId(), pos: Vec2(x: 10, y: 15), name: "warden", save: save, stats: stats)
        sim.addPlayer(p)
        return p
    }

    func freshSim(_ seed: UInt32) -> Simulation {
        Simulation(map: arena(), seed: seed, spawnPoint: Vec2(x: 10, y: 15), scaling: SimScaling(monsterLevel: 1, lifeMult: 1, damageMult: 1))
    }

    func hasWhiff(_ events: [GameEvent]) -> Bool {
        for e in events {
            if case .fx(let visual, _, _, _, _, _) = e, visual == "whiff" { return true }
        }
        return false
    }

    func testWhiff() {
        let sim = freshSim(2)
        let p = warden(sim)
        let m = sim.spawnMonster("initiate", Vec2(x: 10, y: 22))
        let full = m.maxHp
        p.input = PlayerInput(seq: 1, mx: 1, my: 0, buttons: BTN.melee, lock: 0)
        sim.step()
        XCTAssertEqual(m.hp, full)
        XCTAssertTrue(hasWhiff(sim.events))
    }

    func testSoftLock() {
        let sim = freshSim(3)
        let p = warden(sim)
        let m = sim.spawnMonster("initiate", Vec2(x: 11.6, y: 15))
        p.input = PlayerInput(seq: 1, mx: 0, my: 0, buttons: BTN.melee, lock: m.id)
        sim.step()
        XCTAssertLessThan(m.hp, m.maxHp)
        XCTAssertEqual(p.lockId, m.id)

        let side = sim.spawnMonster("initiate", Vec2(x: 10, y: 17.2))
        p.input = PlayerInput(seq: 2, mx: 1, my: 0, buttons: BTN.melee, lock: side.id)
        let before = side.hp
        sim.step()
        XCTAssertEqual(p.lockId, 0)
        XCTAssertEqual(side.hp, before)
    }

    func testPracticeShaft() {
        let save = newSave()
        let run = ShaftRun(save: save, kind: .tutorial, seed: 5, depth: 0)
        let monsters = run.sim.monsters.all
        XCTAssertGreaterThan(monsters.count, 0)
        let anchor = deriveStats(save).anchor
        let swing = ((8.0 + 12.0) / 2) * 1.2 * (1 + anchor / 100)
        let cap = ceil(swing * 2)
        XCTAssertTrue(monsters.contains { $0.def.id == "chanter" })
        for m in monsters {
            XCTAssertTrue(m.def.id == "thrall" || m.def.id == "mite" || m.def.id == "chanter")
            XCTAssertLessThanOrEqual(m.maxHp, cap)
        }
        run.sim.killPlayer(run.player)
        XCTAssertEqual(save.flesh, 0)
    }

    func testCampFloodAndWalk() {
        let map = buildHub()
        let dist = floodDistances(map, Vec2(x: 20, y: 14))
        for station in STATIONS {
            let i = jsFloor(station.y) * map.w + jsFloor(station.x)
            XCTAssertNotEqual(dist[i], -1, station.name)
        }
        let hub = Hub(save: newSave())
        for _ in 0..<40 { hub.step(mx: 0, my: -1) }
        XCTAssertLessThan(hub.player.pos.y, 14)
        XCTAssertFalse(hub.sim.map.collides(hub.player.pos.x, hub.player.pos.y, 0.42))
    }

    func testEchoFingerprint() {
        func run() -> String {
            let save = newSave()
            let shaft = ShaftRun(save: save, kind: .echo, seed: 42, depth: 0)
            for i in 0..<60 {
                let b = i % 8 < 5 ? BTN.melee : BTN.ranged
                let mx: Double = i < 30 ? 1 : 0
                let my: Double = i < 30 ? 0 : 1
                shaft.step(mx: mx, my: my, b: b, lock: 0)
            }
            return shaft.fingerprint()
        }
        XCTAssertEqual(run(), run())
    }

    func testOriginsAndVersion() {
        let armors = ["silvarium", "cataracta", "plate"].map { id -> Int in
            let save = newSave()
            chooseOrigin(save, id)
            XCTAssertEqual(save.meleeId, "company_pick")
            XCTAssertEqual(save.rangedId, "company_crossbow")
            XCTAssertTrue(save.ownedMeleeIds.contains("company_pick"))
            XCTAssertTrue(save.ownedRangedIds.contains("company_crossbow"))
            XCTAssertTrue(save.ownedPlateIds.contains("company_plate"))
            return save.plateArmor
        }
        XCTAssertEqual(armors, [14, 16, 18])
        let blob = #"{"version":2,"id":"warden"}"#.data(using: .utf8)!
        let loaded = loadSave(data: blob)
        XCTAssertNil(loaded.origin)
        XCTAssertEqual(loaded.version, CHARACTER_VERSION)
    }

    func testRangedAndUnusedBits() {
        let sim = freshSim(1)
        let p = warden(sim)
        let m = sim.spawnMonster("initiate", Vec2(x: 12, y: 15))
        p.input = PlayerInput(seq: 1, mx: 1, my: 0, buttons: BTN.ranged, lock: 0)
        sim.step()
        let spawned = !sim.projectiles.all.isEmpty
        let damaged = m.hp < m.maxHp
        XCTAssertTrue(spawned || damaged)

        let sim2 = freshSim(1)
        let p2 = warden(sim2)
        let m2 = sim2.spawnMonster("initiate", Vec2(x: 12, y: 15))
        let full = m2.maxHp
        p2.input = PlayerInput(seq: 1, buttons: 4)
        sim2.step()
        p2.input = PlayerInput(seq: 2, buttons: 8)
        sim2.step()
        XCTAssertEqual(m2.hp, full)
        XCTAssertTrue(sim2.projectiles.all.isEmpty)
        XCTAssertFalse(sim2.events.contains { event in
            if case .cast = event { return true }
            return false
        })
    }

    func testNamedOfferOnce() {
        var hitting: UInt32 = 1
        var s: UInt32 = 1
        while s < 500 {
            let rng = Rng(seed: s)
            if rng.chance(0.3) { hitting = s; break }
            s += 1
        }
        let save = newSave()
        chooseOrigin(save, "silvarium")
        let run = ShaftRun(save: save, kind: .echo, seed: 1, depth: 0)
        run.offerRng = Rng(seed: hitting)
        let v = run.sim.spawnMonster("hollow_foreman", run.player.pos, tier: .boss)
        run.vesselId = v.id
        run.vessel = .spawned
        run.sim.killMonster(v, run.player)
        guard case .named(let first) = run.offer else {
            XCTFail("expected a named offer, got \(String(describing: run.offer))")
            return
        }
        XCTAssertTrue(ownsGear(save, first))

        let run2 = ShaftRun(save: save, kind: .echo, seed: 2, depth: 0)
        run2.offerRng = Rng(seed: hitting)
        let v2 = run2.sim.spawnMonster("hollow_foreman", run2.player.pos, tier: .boss)
        run2.vesselId = v2.id
        run2.vessel = .spawned
        run2.sim.killMonster(v2, run2.player)
        if case .named(let second) = run2.offer {
            XCTAssertNotEqual(second, first)
        }
    }

    func testPlateBumpAndDentros() {
        let save = newSave()
        chooseOrigin(save, "cataracta")
        for id in NAMED_GEAR_IDS { grantGear(save, id) }
        save.plateId = "company_plate"
        save.plateArmor = 16
        save.level = 1
        let offer = rollClearOffer(save, Rng(seed: 1))
        XCTAssertEqual(offer, .plate(from: 16, to: 19))

        save.plateArmor = originArmor(save.origin) + save.level * 4
        XCTAssertNil(rollClearOffer(save, Rng(seed: 1)))

        save.plateId = "dentros_last_stand"
        save.plateArmor = 22
        save.level = 3
        XCTAssertNil(rollClearOffer(save, Rng(seed: 1)))
    }

    func testDentrosWard() {
        let sim = freshSim(1)
        let save = newSave()
        chooseOrigin(save, "plate")
        save.plateId = "dentros_last_stand"
        grantGear(save, "dentros_last_stand")
        let p = warden(sim, save)
        p.hp = p.maxHp * 0.3
        let before = p.hp
        _ = damagePlayer(sim, p, 10, nil)
        XCTAssertEqual(p.buffs.filter { $0.id == "last_stand" }.count, 1)
        let after = p.hp
        XCTAssertGreaterThan(after, before - 10)
        _ = damagePlayer(sim, p, 10, nil)
        XCTAssertLessThan(p.hp, after)
        XCTAssertEqual(p.buffs.filter { $0.id == "last_stand" }.count, 1)
    }

    func testEchoFlesh() {
        func echo() -> ShaftRun { ShaftRun(save: newSave(), kind: .echo, seed: 7, depth: 0) }
        var run = echo()
        run.echo = run.echoRequired * 0.49
        run.sim.killPlayer(run.player)
        XCTAssertEqual(run.outcome, .death)
        XCTAssertEqual(run.save.flesh, 0)

        run = echo()
        run.echo = run.echoRequired * 0.5
        run.sim.killPlayer(run.player)
        XCTAssertEqual(run.save.flesh, 1)

        run = echo()
        run.echo = run.echoRequired
        run.vessel = .spawned
        run.sim.killPlayer(run.player)
        XCTAssertEqual(run.save.flesh, 2)

        run = echo()
        let v = run.sim.spawnMonster("hollow_foreman", run.player.pos, tier: .boss)
        run.vesselId = v.id
        run.vessel = .spawned
        run.sim.killMonster(v, run.player)
        XCTAssertEqual(run.outcome, .clear)
        XCTAssertEqual(run.save.flesh, 0)
    }

    func testVeinFlesh() {
        let save = newSave()
        save.veinBest = VeinBest(depth: 9, ticks: 100)
        let run = ShaftRun(save: save, kind: .deep, seed: 3, depth: 3)
        run.sim.killPlayer(run.player)
        XCTAssertEqual(save.flesh, 3)
        XCTAssertEqual(save.veinBest, VeinBest(depth: 9, ticks: 100))

        let save10 = newSave()
        let run10 = ShaftRun(save: save10, kind: .deep, seed: 4, depth: 10)
        run10.sim.killPlayer(run10.player)
        XCTAssertEqual(save10.flesh, 3)

        let saveT = newSave()
        let runT = ShaftRun(save: saveT, kind: .deep, seed: 5, depth: 3)
        runT.sim.time = DEEP_VEIN_SECONDS
        runT.evaluateEnd()
        XCTAssertEqual(runT.outcome, .timeout)
        XCTAssertEqual(saveT.flesh, 1)

        let saveA = newSave()
        let runA = ShaftRun(save: saveA, kind: .deep, seed: 6, depth: 3)
        runA.abandon()
        XCTAssertEqual(runA.outcome, .abandoned)
        XCTAssertEqual(saveA.flesh, 0)
    }

    func testMeleeRankRefund() {
        let save = newSave()
        save.flesh = 1
        let base = meleeCoef(save)
        XCTAssertTrue(buyRank(save, "melee"))
        XCTAssertEqual(meleeCoef(save), base * 1.15, accuracy: 1e-9)
        XCTAssertEqual(save.flesh, 0)
        refundFlesh(save)
        XCTAssertEqual(save.flesh, 1)
        XCTAssertEqual(rankOf(save, "melee"), 0)
        XCTAssertEqual(meleeCoef(save), base, accuracy: 1e-9)
    }

    func testSummon() {
        let quiet = freshSim(9)
        let none = newSave()
        chooseOrigin(none, "plate")
        let p0 = warden(quiet, none)
        for _ in 0..<10 {
            p0.input = PlayerInput()
            quiet.step()
        }
        XCTAssertTrue(quiet.monsters.all.filter { $0.ownerId == p0.id }.isEmpty)

        func check(_ origin: String, _ expect: String) {
            let sim = freshSim(9)
            let save = newSave()
            chooseOrigin(save, origin)
            save.flesh = 1
            XCTAssertTrue(buyRank(save, "summon"))
            let p = warden(sim, save)
            for _ in 0..<10 {
                p.input = PlayerInput()
                sim.step()
            }
            let pets = sim.monsters.all.filter { $0.ownerId == p.id && !$0.dead }
            XCTAssertEqual(pets.count, 1, origin)
            XCTAssertEqual(pets.first?.def.id, expect)
            for _ in 0..<40 {
                p.input = PlayerInput()
                sim.step()
            }
            let still = sim.monsters.all.filter { $0.ownerId == p.id && !$0.dead }
            XCTAssertEqual(still.count, 1, origin)
        }
        check("plate", "mite")
        check("silvarium", "mite")
        check("cataracta", "spirit_wolf")
    }

    func testOriginPads() {
        let sil = newSave()
        chooseOrigin(sil, "silvarium")
        XCTAssertEqual(rangedCoef(sil), 0.7 * 1.10, accuracy: 1e-9)
        XCTAssertEqual(sil.plateArmor, 14)

        let plate = newSave()
        chooseOrigin(plate, "plate")
        XCTAssertEqual(meleeCoef(plate), 1.2 * 1.10, accuracy: 1e-9)
        XCTAssertEqual(plate.plateArmor, 18)

        let cat = newSave()
        chooseOrigin(cat, "cataracta")
        let lifeSil = deriveStats(sil).maxLife
        let lifePlate = deriveStats(plate).maxLife
        let lifeCat = deriveStats(cat).maxLife
        XCTAssertEqual(lifeSil, lifePlate)
        XCTAssertEqual(lifeCat, lifeSil + 24)

        sil.flesh = 3
        XCTAssertTrue(buyRank(sil, "melee"))
        let origin = sil.origin
        refundFlesh(sil)
        XCTAssertEqual(sil.origin, origin)
    }
}
