import Foundation

public let HUB_SPAWN = Vec2(x: 20.5, y: 14.5)
public let HUB_REACH = 2.3

public struct Station {
    public let id: String
    public let name: String
    public let label: String
    public let x: Double
    public let y: Double
    public let color: String
    public init(id: String, name: String, label: String, x: Double, y: Double, color: String) {
        self.id = id
        self.name = name
        self.label = label
        self.x = x
        self.y = y
        self.color = color
    }
}

public let STATIONS: [Station] = [
    Station(id: "shaft", name: "The Shaft", label: "Descend", x: 20.5, y: 3.6, color: "#c8343c"),
    Station(id: "rack", name: "Rack", label: "Rack", x: 14.5, y: 19.6, color: "#f3eadf"),
    Station(id: "board", name: "Board", label: "Board", x: 32.5, y: 19.6, color: "#e9c49a"),
]

public func stationPrompt(_ station: Station, tutorial: Int) -> String {
    if station.id == "shaft" && tutorial < 3 { return "Enter" }
    return station.label
}

private struct Rect { var x: Int; var y: Int; var w: Int; var h: Int }

public func buildHub() -> TileMap {
    let map = TileMap(w: 40, h: 26)
    func fill(_ r: Rect, _ t: Int) {
        var y = r.y
        while y < r.y + r.h {
            var x = r.x
            while x < r.x + r.w {
                map.set(x, y, t)
                x += 1
            }
            y += 1
        }
    }
    let floor = Int(Tile.floor.rawValue)
    let road = Int(Tile.road.rawValue)
    let building = Int(Tile.building.rawValue)
    let plank = Int(Tile.plank.rawValue)
    let tree = Int(Tile.tree.rawValue)
    fill(Rect(x: 2, y: 2, w: 36, h: 22), floor)
    fill(Rect(x: 18, y: 1, w: 5, h: 4), road)
    fill(Rect(x: 19, y: 2, w: 3, h: 22), road)
    fill(Rect(x: 2, y: 13, w: 36, h: 3), road)
    fill(Rect(x: 4, y: 7, w: 6, h: 3), building)
    fill(Rect(x: 30, y: 7, w: 6, h: 3), building)
    fill(Rect(x: 17, y: 17, w: 6, h: 3), plank)
    for (x, y) in [(4, 4), (8, 5), (35, 4), (36, 16), (4, 22), (36, 22), (14, 8), (27, 8)] {
        map.set(x, y, tree)
    }
    return map
}

public final class Hub {
    public let sim: Simulation
    public let player: Player

    public init(save: Save) {
        let map = buildHub()
        sim = Simulation(map: map, seed: 1, spawnPoint: HUB_SPAWN, scaling: SimScaling(monsterLevel: 1, lifeMult: 1, damageMult: 0), peaceful: true)
        let stats = deriveStats(save)
        player = Player(id: sim.allocId(), pos: HUB_SPAWN, name: "warden", save: save, stats: stats)
        sim.addPlayer(player)
    }

    public func step(mx: Double, my: Double) {
        player.input = PlayerInput(seq: sim.tick, mx: mx, my: my)
        sim.step()
        sim.events.removeAll()
    }

    public func nearest() -> Station? {
        var best: Station?
        var bestD = HUB_REACH
        for station in STATIONS {
            let d = hypot(station.x - player.pos.x, station.y - player.pos.y)
            if d < bestD {
                bestD = d
                best = station
            }
        }
        return best
    }
}
