import Foundation
import Network
import EchoSim

private let agentPort: UInt16 = 4771

private struct RunLog {
    var kind = ""
    var outcome = ""
    var depth = 0
    var seed: UInt32 = 0
    var ticks = 0
    var seconds = 0.0
    var echo = 0.0
    var echoRequired = 0.0
    var level = 1
    var flesh = 0
    var stalls = 0
    var cut = false
}

/// Plays the Debug build through the same stick and buttons as a person.
final class AgentDriver {
    static let shared = AgentDriver()

    private weak var session: GameSession?
    private var mode = "off"
    private var tracking = false
    private var usingAgentSave = false
    private var restorePending = false
    private var listening = false
    private var listenError = ""
    private var started = false
    private var listener: NWListener?

    private var originChoice = "plate"
    private var style = "echo"
    private var untilKind = "time"
    private var deadline = 0.0
    private var startedAt = 0.0
    private var endReason = ""
    private var lastPulse = 0.0

    private var holdUntil = 0.0
    private var holdMx = 0.0
    private var holdMy = 0.0
    private var holdB = 0
    private var holdLock = 0
    private var resumePlay = false

    private var runs: [RunLog] = []
    private var issues: [String] = []
    private var stalls = 0
    private var endLevel = 0
    private var endFlesh = 0
    private var endTutorial = 0
    private var endVein = ""
    private var cutNext = false
    private var descents = 0
    private var didFlip = false
    private var didBoard = false
    private var bought = false

    private var waitKey = ""
    private var waitTime = 0.0
    private var draughtLeft = 0.0
    private var draughtArmed = false
    private var seen: [UInt8] = []
    private var seenW = 0
    private var seenH = 0
    private var seenToken = -1
    private var still = 0.0
    private var runStalls = 0
    private var biasLeft = 0.0
    private var biasSign = 1.0
    private var lastX = 0.0
    private var lastY = 0.0
    private var armedPos = false
    private var quiet = 0.0
    private var frozenTick = -1
    private var frozenFor = 0.0

    private let queue = DispatchQueue(label: "echoshafts.agent")

    private init() {}

    func attach(_ session: GameSession) {
        self.session = session
        guard !started else { return }
        started = true
        listen()
    }

    func pulse(_ session: GameSession) {
        self.session = session
        let now = ProcessInfo.processInfo.systemUptime
        if lastPulse == 0 { lastPulse = now }
        let dt = min(0.1, now - lastPulse)
        lastPulse = now

        if mode == "hold" {
            if now >= holdUntil {
                mode = resumePlay && now < deadline ? "play" : "off"
                resumePlay = false
                if mode == "off" { clear(session) }
            } else {
                session.input.mx = holdMx
                session.input.my = holdMy
                session.input.b = holdB
                session.input.lock = holdLock
                return
            }
        }

        guard mode == "play" else { return }
        if now >= deadline {
            stopPlay(session, reason: "time")
            return
        }
        if session.paused {
            issue("session paused")
            return
        }
        watchFreeze(session, dt)
        steer(session, dt)
    }

    func willSettle(_ session: GameSession, _ run: ShaftRun) {
        guard tracking else { return }
        let ticks = run.outcome == .clear ? run.clearTick : run.sim.tick
        runs.append(RunLog(
            kind: run.opts.kind.rawValue,
            outcome: run.outcome?.rawValue ?? "none",
            depth: run.opts.depth,
            seed: run.opts.seed,
            ticks: ticks,
            seconds: run.sim.time,
            echo: run.echo,
            echoRequired: run.echoRequired,
            level: session.save.level,
            flesh: session.save.flesh,
            stalls: runStalls,
            cut: cutNext
        ))
        stalls += runStalls
        noteEnd(session)
        cutNext = false
        runStalls = 0
        quiet = 0
        still = 0
        armedPos = false
        didBoard = false
        bought = false
        draughtArmed = false
        draughtLeft = 0
        let recent = runs.suffix(4)
        if recent.count == 4 && recent.allSatisfy({ $0.outcome == "death" && $0.echo < 1 }) {
            issue("four deaths with almost no echo")
        }
        let left = runs.suffix(3)
        if left.count == 3 && left.allSatisfy({ $0.outcome == "abandoned" && !$0.cut }) {
            issue("three shafts abandoned")
        }
        if untilKind == "shaft" || untilKind == "camp" {
            mode = "off"
            endReason = untilKind
            clear(session)
            if usingAgentSave { restorePending = true }
        }
    }

    func didSettle(_ session: GameSession) {
        guard restorePending else { return }
        restorePending = false
        usingAgentSave = false
        session.restorePlayer()
    }

    private func listen() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: agentPort) else { return }
        do {
            let server = try NWListener(using: params, on: port)
            server.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async { self?.noteListen(state) }
            }
            server.newConnectionHandler = { [weak self] conn in self?.serve(conn) }
            server.start(queue: queue)
            listener = server
        } catch {
            listenError = error.localizedDescription
        }
    }

    private func noteListen(_ state: NWListener.State) {
        switch state {
        case .ready:
            listening = true
            listenError = ""
        case .failed(let error):
            listening = false
            listenError = error.localizedDescription
        case .cancelled:
            listening = false
        default:
            break
        }
    }

    private func serve(_ conn: NWConnection) {
        let box = DataBox()
        conn.start(queue: queue)
        func read() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, done, error in
                if let data { box.data.append(data) }
                if box.data.count > 65536 { conn.cancel(); return }
                if httpReady(box.data) {
                    self.dispatch(conn, box.data)
                    return
                }
                if done || error != nil { conn.cancel(); return }
                read()
            }
        }
        read()
    }

    private func dispatch(_ conn: NWConnection, _ data: Data) {
        let parsed = parseHTTP(data)
        let work = { self.reply(conn, self.handle(parsed.method, parsed.path, parsed.body)) }
        if Thread.isMainThread { work() }
        else { DispatchQueue.main.sync(execute: work) }
    }

    private func handle(_ method: String, _ path: String, _ body: [String: Any]) -> [String: Any] {
        guard let session else { return ["ok": false, "error": "Echo Shafts is not in the foreground"] }
        if method == "GET" && path == "/health" {
            return ["ok": listening, "port": agentPort, "error": listenError]
        }
        if method == "GET" && (path == "/state" || path == "/report") { return state(session) }
        if method == "POST" && path == "/stop" {
            stopPlay(session, reason: "stop")
            return state(session)
        }
        if method == "POST" && path == "/input" {
            beginHold(session, body)
            return state(session)
        }
        if method == "POST" && path == "/act" {
            let name = str(body["button"]).isEmpty ? str(body["t"]) : str(body["button"])
            act(session, name, str(body["id"]))
            return state(session)
        }
        if method == "POST" && (path == "/play" || path == "/longevity") {
            beginPlay(session, path, body)
            return state(session)
        }
        return ["ok": false, "error": "unknown \(method) \(path)"]
    }

    private func beginPlay(_ session: GameSession, _ path: String, _ body: [String: Any]) {
        let longevity = path == "/longevity"
        let seconds = num(body["seconds"])
        let span = seconds <= 0 ? (longevity ? 180 : 20) : min(600, seconds)
        originChoice = validOrigin(str(body["origin"]))
        style = validStyle(str(body["style"]))
        untilKind = validUntil(str(body["until"]))
        let fresh = body["fresh"] == nil ? longevity : flag(body["fresh"])
        if fresh {
            tracking = false
            session.resetForAgent()
            usingAgentSave = true
            runs = []
            issues = []
            stalls = 0
            descents = 0
            didFlip = false
            didBoard = false
            bought = false
            endReason = ""
            endLevel = 1
            endFlesh = 0
            endTutorial = 0
            endVein = ""
            cutNext = false
            waitKey = ""
            waitTime = 0
            runStalls = 0
            quiet = 0
            armedPos = false
        }
        tracking = true
        startedAt = ProcessInfo.processInfo.systemUptime
        deadline = startedAt + span
        mode = "play"
        endReason = ""
    }

    private func beginHold(_ session: GameSession, _ body: [String: Any]) {
        var buttons = (body["b"] as? NSNumber)?.intValue ?? 0
        if flag(body["melee"]) { buttons |= BTN.melee }
        if flag(body["ranged"]) { buttons |= BTN.ranged }
        if flag(body["draught"]) { buttons |= BTN.draught }
        holdMx = num(body["mx"])
        holdMy = num(body["my"])
        holdB = buttons
        holdLock = (body["lock"] as? NSNumber)?.intValue ?? 0
        let seconds = min(8, max(0.05, num(body["seconds"]) <= 0 ? 0.2 : num(body["seconds"])))
        holdUntil = ProcessInfo.processInfo.systemUptime + seconds
        resumePlay = mode == "play"
        mode = "hold"
        session.input.mx = holdMx
        session.input.my = holdMy
        session.input.b = holdB
        session.input.lock = holdLock
    }

    private func act(_ session: GameSession, _ name: String, _ id: String) {
        switch name {
        case "origin", "silvarium", "cataracta", "plate":
            let pick = name == "origin" ? (id.isEmpty ? originChoice : id) : name
            session.choose(validOrigin(pick))
        case "station": session.useStation()
        case "descend": session.begin(ranked: false, depth: 0)
        case "vein": session.begin(ranked: true, depth: session.nextVeinDepth)
        case "again":
            if let best = session.save.veinBest { session.begin(ranked: true, depth: best.depth) }
        case "back": session.screen = .none
        case "equip": session.equipResult()
        case "dismiss": session.dismissResult()
        case "leave": session.leave()
        case "hint": session.hideHint()
        case "hand": session.flipHand()
        case "wear": if !id.isEmpty { session.wear(id) }
        case "buy": if !id.isEmpty { session.buy(id) }
        case "refund": session.refund()
        case "reset":
            mode = "off"
            tracking = false
            endReason = ""
            runs = []
            issues = []
            stalls = 0
            session.resetForAgent()
            usingAgentSave = true
        default:
            break
        }
    }

    private func stopPlay(_ session: GameSession, reason: String) {
        let now = ProcessInfo.processInfo.systemUptime
        if mode == "play" || mode == "hold" { endReason = reason }
        mode = "off"
        resumePlay = false
        cutNext = session.inShaft
        if usingAgentSave { restorePending = true }
        if session.inShaft { session.leave() }
        else if restorePending {
            restorePending = false
            usingAgentSave = false
            noteEnd(session)
            session.restorePlayer()
        }
        clear(session)
        if startedAt == 0 { startedAt = now }
    }

    private func steer(_ session: GameSession, _ dt: Double) {
        if session.save.origin == nil {
            session.input = StickInput()
            if ready("origin", 0.5, dt) { session.choose(originChoice) }
            return
        }
        switch session.screen {
        case .results:
            session.input = StickInput()
            if ready("result", 0.45, dt) {
                if session.offer != nil { session.equipResult() }
                else { session.dismissResult() }
            }
            return
        case .descend:
            session.input = StickInput()
            if ready("descend", 0.4, dt) { descend(session) }
            return
        case .rack:
            session.input = StickInput()
            steerRack(session, dt)
            return
        case .board:
            session.input = StickInput()
            if ready("board", 0.8, dt) {
                didBoard = true
                session.screen = .none
            }
            return
        case .none:
            break
        }
        if session.showHint {
            session.input = StickInput()
            if ready("hint", 1.1, dt) { session.hideHint() }
            return
        }
        if !didFlip {
            session.input = StickInput()
            if ready("hand", 0.35, dt) {
                session.flipHand()
                didFlip = true
            }
            return
        }
        if session.inShaft { fight(session, dt) }
        else { camp(session, dt) }
    }

    private func descend(_ session: GameSession) {
        descents += 1
        let vein = style == "vein" || (style == "mix" && descents % 3 == 0)
        if vein { session.begin(ranked: true, depth: session.nextVeinDepth) }
        else { session.begin(ranked: false, depth: 0) }
    }

    private func steerRack(_ session: GameSession, _ dt: Double) {
        if !bought, let tree = cheapest(session.save) {
            if ready("buy", 0.35, dt) {
                session.buy(tree)
                bought = true
            }
            return
        }
        if ready("rack", 0.35, dt) { session.screen = .none }
    }

    private func camp(_ session: GameSession, _ dt: Double) {
        guard let hub = session.hub else { return }
        let player = hub.player
        let goalId = campGoal(session.save)
        guard let station = STATIONS.first(where: { $0.id == goalId }) else { return }
        let goal = Vec2(x: station.x, y: station.y)
        if hub.nearest()?.id == goalId {
            session.input = StickInput()
            session.useStation()
            return
        }
        let step = stepToward(hub.sim.map, player.pos, goal) ?? norm(Vec2(x: goal.x - player.pos.x, y: goal.y - player.pos.y))
        apply(session, step, 0, 0, player, hub.sim.map, dt, wantMove: true)
    }

    private func campGoal(_ save: Save) -> String {
        if !bought && cheapest(save) != nil { return "rack" }
        if !didBoard && !runs.isEmpty && runs.count % 4 == 0 { return "board" }
        return "shaft"
    }

    private func fight(_ session: GameSession, _ dt: Double) {
        guard let run = session.run else { return }
        let player = run.player
        let map = run.sim.map
        if player.hp.isNaN || player.pos.x.isNaN {
            issue("player state is NaN")
            session.leave()
            return
        }
        let cap: Double = run.opts.kind == .tutorial ? 150 : run.opts.kind == .echo ? 480 : 10000
        if run.sim.time > cap {
            issue("\(run.opts.kind.rawValue) still open after \(Int(run.sim.time))s")
            session.leave()
            return
        }
        let hostiles = run.sim.monsters.all.filter { !$0.dead && $0.kind != "pet" }
        if hostiles.isEmpty && run.vessel != .spawned {
            quiet += dt
            if quiet > 5 {
                issue("no hostiles and no vessel at \(Int(run.sim.time))s")
                session.leave()
            } else {
                apply(session, Vec2(), drink(player, dt), 0, player, map, dt, wantMove: false)
            }
            return
        }
        quiet = 0
        noteSeen(map, player.pos, session.agentRun)
        let melee = resolvedMelee(session.save).range
        let shot = resolvedShot(session.save).range
        let onScreen = hostiles.filter { inView($0, player) }
        let inSight = onScreen.filter { map.lineOfSight(player.pos, $0.pos) }
        let drinkBit = drink(player, dt)
        if let foe = nearest(inSight, player) {
            let d = hypot(foe.pos.x - player.pos.x, foe.pos.y - player.pos.y)
            if d <= melee {
                apply(session, Vec2(), drinkBit | BTN.melee, foe.id, player, map, dt, wantMove: false)
                return
            }
            var buttons = drinkBit
            if d <= shot { buttons |= BTN.ranged }
            let step = stepToward(map, player.pos, foe.pos) ?? norm(Vec2(x: foe.pos.x - player.pos.x, y: foe.pos.y - player.pos.y))
            apply(session, step, buttons, foe.id, player, map, dt, wantMove: true)
            return
        }
        if let foe = nearest(onScreen, player) ?? (explore(map, player.pos) == nil ? nearest(hostiles, player) : nil) {
            let step = stepToward(map, player.pos, foe.pos) ?? norm(Vec2(x: foe.pos.x - player.pos.x, y: foe.pos.y - player.pos.y))
            apply(session, step, drinkBit, 0, player, map, dt, wantMove: true)
            return
        }
        if let step = explore(map, player.pos) {
            apply(session, step, drinkBit, 0, player, map, dt, wantMove: true)
            return
        }
        apply(session, Vec2(), drinkBit, 0, player, map, dt, wantMove: false)
    }

    private func apply(_ session: GameSession, _ dir: Vec2, _ buttons: Int, _ lock: Int, _ player: Player, _ map: TileMap, _ dt: Double, wantMove: Bool) {
        if !armedPos {
            armedPos = true
            lastX = player.pos.x
            lastY = player.pos.y
        }
        var heading = dir
        if biasLeft > 0 && (dir.x != 0 || dir.y != 0) {
            biasLeft -= dt
            heading = fromAngle(angleOf(dir) + biasSign * 1.35)
        }
        let moved = hypot(player.pos.x - lastX, player.pos.y - lastY)
        lastX = player.pos.x
        lastY = player.pos.y
        if wantMove && moved < 0.04 {
            still += dt
            if still > 1.15 {
                still = 0
                biasLeft = 0.65
                biasSign = -biasSign
                stalls += 1
                runStalls += 1
                if session.inShaft && runStalls == 8 {
                    issue("stuck in the shaft")
                    session.leave()
                    return
                }
                if !session.inShaft && runStalls == 8 {
                    issue("stuck in camp")
                    runStalls = 0
                }
            }
        } else if moved >= 0.04 {
            still = 0
        }
        if player.pos.x < -1 || player.pos.y < -1 || player.pos.x > Double(map.w) + 1 || player.pos.y > Double(map.h) + 1 {
            issue("player left the map")
        }
        session.input.mx = heading.x
        session.input.my = heading.y
        session.input.b = buttons
        session.input.lock = lock
    }

    private func drink(_ player: Player, _ dt: Double) -> Int {
        let low = player.maxHp > 0 && player.hp / player.maxHp < 0.45
        if low && player.potionCd <= 0 && draughtLeft <= 0 && !draughtArmed {
            draughtLeft = 0.16
            draughtArmed = true
        }
        if player.potionCd > 0 { draughtArmed = false }
        if draughtLeft > 0 {
            draughtLeft -= dt
            return BTN.draught
        }
        return 0
    }

    private func watchFreeze(_ session: GameSession, _ dt: Double) {
        guard session.screen == .none, session.stage != nil else {
            frozenFor = 0
            return
        }
        let tick = session.run?.sim.tick ?? session.hub?.sim.tick ?? -1
        if tick == frozenTick {
            frozenFor += dt
            if frozenFor > 5 {
                issue("sim tick frozen at \(tick)")
                if session.inShaft { session.leave() }
            }
        } else {
            frozenTick = tick
            frozenFor = 0
        }
    }

    private func noteSeen(_ map: TileMap, _ pos: Vec2, _ token: Int) {
        if seenW != map.w || seenH != map.h || seenToken != token {
            seenW = map.w
            seenH = map.h
            seenToken = token
            seen = [UInt8](repeating: 0, count: map.w * map.h)
            armedPos = false
            runStalls = 0
            quiet = 0
            still = 0
            biasLeft = 0
        }
        let x0 = max(0, jsFloor(pos.x - WorldFrame.halfX))
        let x1 = min(map.w - 1, jsFloor(pos.x + WorldFrame.halfX))
        let y0 = max(0, jsFloor(pos.y - WorldFrame.halfY))
        let y1 = min(map.h - 1, jsFloor(pos.y + WorldFrame.halfY))
        var y = y0
        while y <= y1 {
            var x = x0
            while x <= x1 {
                let i = y * map.w + x
                if seen[i] == 0 && !map.solidAt(x, y) && map.lineOfSight(pos, Vec2(x: Double(x) + 0.5, y: Double(y) + 0.5)) {
                    seen[i] = 1
                }
                x += 1
            }
            y += 1
        }
    }

    private func explore(_ map: TileMap, _ from: Vec2) -> Vec2? {
        let dist = floodDistances(map, from)
        var best = -1
        var bestD = Int.max
        var i = 0
        while i < dist.count {
            let d = dist[i]
            if d > 2 && d < bestD && i < seen.count && seen[i] == 0 && !map.solidAt(i % map.w, i / map.w) {
                bestD = d
                best = i
            }
            i += 1
        }
        guard best >= 0 else { return nil }
        let goal = Vec2(x: Double(best % map.w) + 0.5, y: Double(best / map.w) + 0.5)
        return stepToward(map, from, goal)
    }

    private func stepToward(_ map: TileMap, _ from: Vec2, _ goal: Vec2) -> Vec2? {
        let direct = norm(Vec2(x: goal.x - from.x, y: goal.y - from.y))
        if map.solidPoint(goal.x, goal.y) { return direct.x == 0 && direct.y == 0 ? nil : direct }
        let dist = floodDistances(map, goal)
        let cx = jsFloor(from.x)
        let cy = jsFloor(from.y)
        if cx < 0 || cy < 0 || cx >= map.w || cy >= map.h { return direct }
        let here = dist[cy * map.w + cx]
        if here < 0 { return direct }
        if here == 0 {
            if hypot(goal.x - from.x, goal.y - from.y) < 0.35 { return nil }
            return direct
        }
        let nbrs = [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)]
        var best: (Int, Int)?
        var bestD = here
        for n in nbrs {
            if n.0 < 0 || n.1 < 0 || n.0 >= map.w || n.1 >= map.h { continue }
            let d = dist[n.1 * map.w + n.0]
            if d >= 0 && d < bestD {
                bestD = d
                best = n
            }
        }
        guard let best else { return direct }
        return norm(Vec2(x: Double(best.0) + 0.5 - from.x, y: Double(best.1) + 0.5 - from.y))
    }

    private func inView(_ m: Monster, _ p: Player) -> Bool {
        abs(m.pos.x - p.pos.x) < WorldFrame.halfX && abs(m.pos.y - p.pos.y) < WorldFrame.halfY
    }

    private func nearest(_ list: [Monster], _ p: Player) -> Monster? {
        var best: Monster?
        var bestD = Double.infinity
        for m in list {
            let d = hypot(m.pos.x - p.pos.x, m.pos.y - p.pos.y)
            if d < bestD {
                bestD = d
                best = m
            }
        }
        return best
    }

    private func cheapest(_ save: Save) -> String? {
        var best: String?
        var cost = Int.max
        for tree in TREES {
            if let next = nextRankCost(save, tree.id), save.flesh >= next, next < cost {
                cost = next
                best = tree.id
            }
        }
        return best
    }

    private func ready(_ key: String, _ need: Double, _ dt: Double) -> Bool {
        if waitKey != key {
            waitKey = key
            waitTime = 0
        }
        waitTime += dt
        return waitTime >= need
    }

    private func clear(_ session: GameSession) {
        session.input = StickInput()
    }

    private func noteEnd(_ session: GameSession) {
        endLevel = session.save.level
        endFlesh = session.save.flesh
        endTutorial = session.save.tutorial
        if let best = session.save.veinBest {
            endVein = "depth \(best.depth) in \(best.ticks) ticks"
        }
    }

    private func issue(_ text: String) {
        if !issues.contains(text) { issues.append(text) }
    }

    private func state(_ session: GameSession) -> [String: Any] {
        let now = ProcessInfo.processInfo.systemUptime
        var out: [String: Any] = [
            "ok": true,
            "listening": listening,
            "port": agentPort,
            "error": listenError,
            "screen": screenName(session),
            "mode": mode,
            "agentSave": usingAgentSave,
            "origin": session.save.origin ?? "",
            "tutorial": session.save.tutorial,
            "level": session.save.level,
            "xp": session.save.xp,
            "flesh": session.save.flesh,
            "hand": session.save.handedness,
            "note": session.note,
            "prompt": session.prompt,
            "hint": session.showHint ? session.hint : "",
            "paused": session.paused,
            "inShaft": session.inShaft,
            "status": session.status,
            "hud": [
                "life": round2(session.hudLife),
                "echo": round2(session.hudEcho),
                "text": session.hudText,
            ],
            "offer": session.offer?.title ?? "",
            "report": reportJSON(now),
        ]
        if let player = session.run?.player ?? session.hub?.player {
            out["player"] = [
                "x": round2(player.pos.x),
                "y": round2(player.pos.y),
                "hp": round2(player.hp),
                "maxHp": round2(player.maxHp),
                "potion": round2(player.potionCd),
            ]
        }
        if !session.inShaft, let hub = session.hub {
            let player = hub.player
            var best: Station?
            var bestD = Double.infinity
            for station in STATIONS {
                let d = hypot(station.x - player.pos.x, station.y - player.pos.y)
                if d < bestD {
                    bestD = d
                    best = station
                }
            }
            if let best {
                out["nearest"] = ["id": best.id, "d": round2(bestD), "reach": bestD < HUB_REACH]
            }
        }
        if let run = session.run {
            let player = run.player
            let hostiles = run.sim.monsters.all.filter { !$0.dead && $0.kind != "pet" }
            let shown = hostiles
                .filter { inView($0, player) }
                .sorted { hypot($0.pos.x - player.pos.x, $0.pos.y - player.pos.y) < hypot($1.pos.x - player.pos.x, $1.pos.y - player.pos.y) }
                .prefix(8)
            out["foes"] = shown.map { foeJSON($0, player, run.sim.map) }
            out["shaft"] = [
                "kind": run.opts.kind.rawValue,
                "depth": run.opts.depth,
                "seed": Int(run.opts.seed),
                "time": round2(run.sim.time),
                "tick": run.sim.tick,
                "echo": round2(run.echo),
                "need": round2(run.echoRequired),
                "vessel": run.vessel.rawValue,
                "alive": hostiles.count,
                "outcome": run.outcome?.rawValue ?? "",
            ]
        } else {
            out["foes"] = []
        }
        return out
    }

    private func reportJSON(_ now: Double) -> [String: Any] {
        [
            "runs": runs.count,
            "deaths": runs.filter { $0.outcome == "death" }.count,
            "clears": runs.filter { $0.outcome == "clear" }.count,
            "timeouts": runs.filter { $0.outcome == "timeout" }.count,
            "abandoned": runs.filter { $0.outcome == "abandoned" }.count,
            "stalls": stalls,
            "issues": issues,
            "end": endReason,
            "left": mode == "play" ? max(0, round2(deadline - now)) : 0,
            "elapsed": startedAt == 0 ? 0 : round2(now - startedAt),
            "endLevel": endLevel,
            "endFlesh": endFlesh,
            "endTutorial": endTutorial,
            "endVein": endVein,
            "style": style,
            "origin": originChoice,
            "recent": runs.suffix(8).map { runJSON($0) },
        ]
    }

    private func runJSON(_ run: RunLog) -> [String: Any] {
        [
            "kind": run.kind,
            "outcome": run.outcome,
            "depth": run.depth,
            "seed": Int(run.seed),
            "ticks": run.ticks,
            "seconds": round2(run.seconds),
            "echo": round2(run.echo),
            "need": round2(run.echoRequired),
            "level": run.level,
            "flesh": run.flesh,
            "stalls": run.stalls,
            "cut": run.cut,
        ]
    }

    private func foeJSON(_ m: Monster, _ p: Player, _ map: TileMap) -> [String: Any] {
        [
            "id": m.id,
            "name": m.def.name,
            "tier": m.tier.rawValue,
            "d": round2(hypot(m.pos.x - p.pos.x, m.pos.y - p.pos.y)),
            "hp": round2(m.hp),
            "maxHp": round2(m.maxHp),
            "los": map.lineOfSight(p.pos, m.pos),
        ]
    }

    private func screenName(_ session: GameSession) -> String {
        if session.save.origin == nil { return "origin" }
        switch session.screen {
        case .descend: return "descend"
        case .results: return "results"
        case .rack: return "rack"
        case .board: return "board"
        case .none: return session.inShaft ? "shaft" : "camp"
        }
    }

    private func reply(_ conn: NWConnection, _ obj: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
    }
}

private final class DataBox {
    var data = Data()
}

private func httpReady(_ data: Data) -> Bool {
    let sep = Data([13, 10, 13, 10])
    guard let range = data.range(of: sep) else { return false }
    let head = String(data: data.subdata(in: 0..<range.lowerBound), encoding: .utf8) ?? ""
    return data.count >= range.upperBound + headerLength(head)
}

private func headerLength(_ head: String) -> Int {
    for line in head.split(separator: "\r\n") {
        let lower = line.lowercased()
        if lower.hasPrefix("content-length:") {
            return Int(lower.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
        }
    }
    return 0
}

private func parseHTTP(_ data: Data) -> (method: String, path: String, body: [String: Any]) {
    let sep = Data([13, 10, 13, 10])
    guard let range = data.range(of: sep) else { return ("", "", [:]) }
    let head = String(data: data.subdata(in: 0..<range.lowerBound), encoding: .utf8) ?? ""
    let line = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
    let method = line.count > 0 ? String(line[0]) : ""
    let rawPath = line.count > 1 ? String(line[1]) : "/"
    let path = rawPath.split(separator: "?").first.map(String.init) ?? "/"
    var body: [String: Any] = [:]
    if data.count > range.upperBound {
        let raw = data.subdata(in: range.upperBound..<data.count)
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] {
            body = obj
        }
    }
    return (method, path, body)
}

private func num(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }
private func str(_ value: Any?) -> String { value as? String ?? "" }
private func flag(_ value: Any?) -> Bool { (value as? NSNumber)?.boolValue ?? false }
private func round2(_ n: Double) -> Double { (n * 100).rounded() / 100 }

private func validOrigin(_ raw: String) -> String {
    raw == "silvarium" || raw == "cataracta" || raw == "plate" ? raw : "plate"
}

private func validStyle(_ raw: String) -> String {
    raw == "vein" || raw == "mix" || raw == "echo" ? raw : "echo"
}

private func validUntil(_ raw: String) -> String {
    raw == "camp" || raw == "shaft" || raw == "time" ? raw : "time"
}
