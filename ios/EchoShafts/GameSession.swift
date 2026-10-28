import Foundation
import SwiftUI
import SpriteKit
import UIKit
import EchoSim

struct StickInput {
    var mx = 0.0
    var my = 0.0
    var b = 0
    var lock = 0
}

struct WedgeFlash {
    var facing: Double
    var until: TimeInterval
    var whiff: Bool
    var range: Double
    var arc: Double
}

enum Screen: Equatable {
    case none
    case descend
    case results
    case rack
    case board
}

let tutorialHints = [
    "Face them with the stick. Hold Melee. The pit counts what you drop. A miss counts nothing.",
    "The crossbow is the other hand. What you wear is the shot.",
    "Last practice shift. After this, the shaft is real. A Deep Vein is five minutes. The best one stays on this phone.",
]

final class GameSession: ObservableObject {
    @Published var save: Save
    @Published var screen: Screen = .none
    @Published var note = ""
    @Published var showHint = false
    @Published var hint = ""
    @Published var paused = false
    @Published var prompt = ""
    @Published var status = ""
    @Published var hudLife = 1.0
    @Published var hudEcho = 0.0
    @Published var hudText = ""
    @Published var inShaft = false
    @Published var stage: SKScene?
    @Published var resultTitle = ""
    @Published var resultDetail = ""
    @Published var offer: GearOffer?
    @Published var mapFrame = 0
    private var mapQueued = false

    var input = StickInput()
    var agentRun = 0
    var hitUntil: [Int: TimeInterval] = [:]
    var wedge: WedgeFlash?
    var hub: Hub?
    var run: ShaftRun?
    var campScene: CampScene?
    var shaftScene: ShaftScene?
    private var last = 0.0
    private var acc = 0.0
    private var settling = false
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    init() {
        save = SaveStore.load()
        if save.origin != nil { showCamp() }
    }

    func choose(_ origin: String) {
        chooseOrigin(save, origin)
        SaveStore.write(save)
        showCamp()
    }

    func showCamp() {
        if hub == nil { hub = Hub(save: save) }
        if campScene == nil, let hub { campScene = CampScene(session: self, map: hub.sim.map) }
        inShaft = false
        stage = campScene
        refreshStatus()
        refreshPrompt()
    }

    func advance(_ currentTime: TimeInterval) {
        if last == 0 { last = currentTime }
        let dt = min(0.1, currentTime - last)
        last = currentTime
        if screen != .none { return }
        if let run, run.outcome == nil, !paused {
            acc += dt
            var steps = 0
            while acc >= 0.05 && steps < 4 {
                acc -= 0.05
                steps += 1
                run.step(mx: input.mx, my: input.my, b: input.b, lock: input.lock)
                let events = run.sim.events
                run.sim.events.removeAll()
                handle(events, now: currentTime, playerId: run.player.id)
                input.lock = run.player.lockId
            }
            refreshHud()
            if steps > 0 { noteMap() }
            if run.outcome != nil { settle(run) }
            return
        }
        if run == nil, let hub, !paused {
            acc += dt
            var steps = 0
            while acc >= 0.05 && steps < 4 {
                acc -= 0.05
                steps += 1
                hub.step(mx: input.mx, my: input.my)
            }
            refreshPrompt()
            if steps > 0 { noteMap() }
        }
    }

    func begin(ranked: Bool, depth: Int) {
        let practice = !ranked && save.tutorial < 3
        var seed = UInt32.random(in: UInt32.min ... UInt32.max)
        if seed == 0 { seed = 1 }
        let kind: ShaftKind = ranked ? .deep : practice ? .tutorial : .echo
        agentRun += 1
        input = StickInput()
        acc = 0
        last = 0
        wedge = nil
        hitUntil.removeAll()
        let shaft = ShaftRun(save: save, kind: kind, seed: seed, depth: ranked ? depth : 0)
        run = shaft
        inShaft = true
        screen = .none
        showHint = practice
        hint = practice ? tutorialHints[min(save.tutorial, 2)] : ""
        let scene = ShaftScene(session: self, map: shaft.sim.map)
        shaftScene = scene
        stage = scene
        refreshHud()
    }

    func leave() {
        guard let run else { return }
        run.abandon()
        settle(run)
    }

    func useStation() {
        guard let station = hub?.nearest() else { return }
        if station.id == "shaft" {
            if save.tutorial < 3 { begin(ranked: false, depth: 0) }
            else { screen = .descend }
        } else if station.id == "rack" {
            screen = .rack
        } else if station.id == "board" {
            screen = .board
        }
    }

    func flipHand() {
        save.handedness = save.handedness == "left" ? "right" : "left"
        SaveStore.write(save)
        objectWillChange.send()
    }

    func equipResult() {
        if let offer { equipOffer(save, offer) }
        offer = nil
        screen = .none
        SaveStore.write(save)
        refreshStatus()
    }

    func dismissResult() {
        offer = nil
        screen = .none
        refreshStatus()
    }

    func wear(_ id: String) {
        EchoSim.equipOwned(save, id)
        SaveStore.write(save)
        objectWillChange.send()
    }

    func buy(_ tree: String) {
        if buyRank(save, tree) {
            SaveStore.write(save)
            refreshStatus()
        }
    }

    func refund() {
        refundFlesh(save)
        SaveStore.write(save)
        refreshStatus()
    }

    func enterBackground() {
        if let run, run.opts.kind == .deep, run.outcome == nil {
            run.abandon()
            settle(run)
        } else if run != nil {
            paused = true
        }
        SaveStore.write(save)
    }

    func enterForeground() {
        paused = false
    }

    func hideHint() { showHint = false }

    func resetForAgent() {
        if let run, run.outcome == nil {
            run.abandon()
            settle(run)
        }
        SaveStore.agent = true
        run = nil
        hub = nil
        campScene = nil
        shaftScene = nil
        stage = nil
        inShaft = false
        screen = .none
        paused = false
        note = ""
        hint = ""
        showHint = false
        offer = nil
        prompt = ""
        resultTitle = ""
        resultDetail = ""
        input = StickInput()
        wedge = nil
        hitUntil.removeAll()
        acc = 0
        last = 0
        save = newSave()
        SaveStore.write(save)
        refreshStatus()
    }

    func restorePlayer() {
        SaveStore.agent = false
        run = nil
        hub = nil
        campScene = nil
        shaftScene = nil
        stage = nil
        inShaft = false
        screen = .none
        paused = false
        note = ""
        hint = ""
        showHint = false
        offer = nil
        prompt = ""
        input = StickInput()
        acc = 0
        last = 0
        save = SaveStore.load()
        if save.origin != nil { showCamp() }
        else { refreshStatus() }
    }

    func lock(at world: Vec2) {
        guard let run else { return }
        var best = 0
        var bestD = 1.8
        for m in run.sim.monsters.all {
            if m.dead || m.faction == .players { continue }
            let d = hypot(m.pos.x - world.x, m.pos.y - world.y)
            if d < bestD {
                bestD = d
                best = m.id
            }
        }
        if best != 0 { input.lock = best }
    }

    private func handle(_ events: [GameEvent], now: TimeInterval, playerId: Int) {
        var dealt = false
        var swung = false
        for event in events {
            switch event {
            case .cast(let id, let visual, _, _, _, _) where id == playerId && visual == "main":
                swung = true
                haptic.impactOccurred()
                if let run {
                    let swing = resolvedMelee(run.save)
                    wedge = WedgeFlash(facing: run.player.facing, until: now + 0.16, whiff: true, range: swing.range, arc: swing.arc)
                }
            case .cast(let id, let visual, _, _, _, _) where id == playerId && visual == "ranged":
                haptic.impactOccurred()
            case .dmg(let id, _, _, let source, _, _) where source == playerId:
                dealt = true
                haptic.impactOccurred()
                hitUntil[id] = now + 0.07
            case .fx(let visual, _, _, _, _, _) where visual == "vessel_rise":
                haptic.impactOccurred()
            default:
                break
            }
        }
        if swung, dealt, var flash = wedge {
            flash.whiff = false
            wedge = flash
        }
    }

    private func settle(_ run: ShaftRun) {
        guard !settling else { return }
        settling = true
        defer { settling = false }
        let outcome = run.outcome
        if run.opts.kind == .tutorial && save.tutorial < 3 && outcome != .abandoned {
            save.tutorial += 1
        }
        let paid = run.fleshPaid
        var firstEcho = false
        if paid > 0 && !save.sawEcho {
            save.sawEcho = true
            firstEcho = true
        }
        switch outcome {
        case .clear:
            resultTitle = "The Vessel is down."
            if run.opts.kind == .deep {
                let seconds = Int(jsRound(Double(run.clearTick) / 20))
                if beatsVein(save.veinBest, depth: run.opts.depth, ticks: run.clearTick) {
                    save.veinBest = VeinBest(depth: run.opts.depth, ticks: run.clearTick)
                    resultDetail = "Depth \(run.opts.depth). \(seconds)s. It is the best on this phone."
                } else {
                    resultDetail = "Depth \(run.opts.depth). \(seconds)s."
                }
            } else {
                resultDetail = ""
            }
            offer = run.offer
            if run.offer != nil {
                screen = .results
                note = ""
            } else {
                note = resultDetail.isEmpty ? resultTitle : resultDetail
                screen = .none
            }
        case .death:
            let line = paid > 0 ? "The shaft ended. Flesh +\(paid)." : "The shaft ended."
            note = firstEcho ? "The shaft kept the shift. The echo stayed in you. \(line)" : line
            screen = .none
        case .timeout:
            let line = paid > 0 ? "The vein closed. Flesh +\(paid)." : "The vein closed."
            note = firstEcho ? "The shaft kept the shift. The echo stayed in you. \(line)" : line
            screen = .none
        case .abandoned:
            note = run.opts.kind == .deep ? "The vein closed. That run is not on the board." : "You left the shaft."
            screen = .none
        case nil:
            break
        }
        AgentDriver.shared.willSettle(self, run)
        self.run = nil
        inShaft = false
        showHint = false
        input = StickInput()
        acc = 0
        stage = campScene
        SaveStore.write(save)
        refreshStatus()
        refreshPrompt()
        AgentDriver.shared.didSettle(self)
    }

    func refreshStatus() {
        let next = "Lv \(save.level) · Flesh \(save.flesh)"
        if status != next { status = next }
    }

    func refreshPrompt() {
        let next = hub?.nearest().map { stationPrompt($0, tutorial: save.tutorial) } ?? ""
        if prompt != next { prompt = next }
    }

    func refreshHud() {
        guard let run else { return }
        let life = run.player.maxHp > 0 ? run.player.hp / run.player.maxHp : 0
        let echo = run.echo / max(1, run.echoRequired)
        if abs(hudLife - life) > 0.001 { hudLife = life }
        if abs(hudEcho - echo) > 0.001 { hudEcho = echo }
        let word: String
        switch run.vessel {
        case .spawned: word = "Vessel"
        case .slain: word = "Slain"
        case .none: word = "Echo"
        }
        let text: String
        if run.opts.kind == .deep {
            let seconds = max(0, Int(ceil(DEEP_VEIN_SECONDS - run.sim.time)))
            text = "\(word) · \(seconds)s"
        } else {
            text = word
        }
        if hudText != text { hudText = text }
    }

    var handTitle: String { save.handedness == "left" ? "Right hand" : "Left hand" }
    var nextVeinDepth: Int { (save.veinBest?.depth ?? 0) + 1 }

    func noteMap() {
        if mapQueued { return }
        mapQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.mapQueued = false
            self.mapFrame += 1
        }
    }

    func mapPicture() -> MapPicture? {
        let map: TileMap
        let player: Player
        var marks: [MapMark] = []
        if let run {
            map = run.sim.map
            player = run.player
            for m in run.sim.monsters.all where !m.dead && m.kind != "pet" {
                let d = hypot(m.pos.x - player.pos.x, m.pos.y - player.pos.y)
                if d < 18 {
                    marks.append(MapMark(x: m.pos.x, y: m.pos.y, color: m.def.color, ranged: m.def.ai == .ranged))
                }
            }
        } else if let hub {
            map = hub.sim.map
            player = hub.player
            for station in STATIONS {
                marks.append(MapMark(x: station.x, y: station.y, color: station.color, ranged: false))
            }
        } else {
            return nil
        }
        return MapPicture(map: map, px: player.pos.x, py: player.pos.y, marks: marks)
    }
}
