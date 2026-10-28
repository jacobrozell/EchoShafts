import Foundation

public final class Room {
    public var x: Int
    public var y: Int
    public var w: Int
    public var h: Int
    public var cx: Double
    public var cy: Double
    public init(x: Int, y: Int, w: Int, h: Int) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
        cx = Double(x) + Double(w) / 2
        cy = Double(y) + Double(h) / 2
    }
}

public struct DungeonLayout {
    public var map: TileMap
    public var rooms: [Room]
    public var start: Vec2
    public var bossRoom: Room
    public var bossPos: Vec2
    public var packSpots: [Vec2]
}

public func generateDungeon(seed: UInt32, width: Int, height: Int, rooms roomCount: Int) -> DungeonLayout {
    let rng = Rng(seed: seed)
    let W = width
    let H = height
    let map = TileMap(w: W, h: H)
    var rooms: [Room] = []
    var attempts = 0
    while rooms.count < roomCount && attempts < 600 {
        attempts += 1
        let w = rng.int(7, 14)
        let h = rng.int(6, 12)
        let x = rng.int(3, W - w - 4)
        let y = rng.int(3, H - h - 4)
        let r = Room(x: x, y: y, w: w, h: h)
        let clash = rooms.contains { o in
            x < o.x + o.w + 3 && x + w + 3 > o.x && y < o.y + o.h + 3 && y + h + 3 > o.y
        }
        if !clash { rooms.append(r) }
    }
    if rooms.isEmpty {
        let r = Room(x: 4, y: 4, w: 8, h: 8)
        rooms.append(r)
    }
    for r in rooms { carveBlob(map, r, rng) }

    var connectedOrder = [0]
    var connectedSet: Set<Int> = [0]
    var edges: [(Int, Int)] = []
    while connectedSet.count < rooms.count {
        var best: (Int, Int)?
        var bestD = Double.infinity
        for a in connectedOrder {
            var b = 0
            while b < rooms.count {
                if !connectedSet.contains(b) {
                    let dx = rooms[a].cx - rooms[b].cx
                    let dy = rooms[a].cy - rooms[b].cy
                    let d = dx * dx + dy * dy
                    if d < bestD {
                        bestD = d
                        best = (a, b)
                    }
                }
                b += 1
            }
        }
        guard let best else { break }
        connectedSet.insert(best.1)
        connectedOrder.append(best.1)
        edges.append(best)
    }
    let extra = max(1, Int(floor(Double(rooms.count) * 0.2)))
    var e = 0
    while e < extra {
        let a = rng.int(0, rooms.count - 1)
        let b = rng.int(0, rooms.count - 1)
        if a != b { edges.append((a, b)) }
        e += 1
    }
    for (a, b) in edges { carveTunnel(map, rooms[a], rooms[b], rng) }

    roughen(map, rng, 2)

    let start = Vec2(x: Double(jsFloor(rooms[0].cx)) + 0.5, y: Double(jsFloor(rooms[0].cy)) + 0.5)
    map.set(jsFloor(start.x), jsFloor(start.y), Int(Tile.floor.rawValue))
    let distances = floodDistances(map, start)
    for i in map.tiles.indices {
        if map.tiles[i] != Tile.rock.rawValue && distances[i] == -1 { map.tiles[i] = Tile.rock.rawValue }
    }
    var x = 0
    while x < W {
        map.set(x, 0, Int(Tile.rock.rawValue))
        map.set(x, H - 1, Int(Tile.rock.rawValue))
        x += 1
    }
    var y = 0
    while y < H {
        map.set(0, y, Int(Tile.rock.rawValue))
        map.set(W - 1, y, Int(Tile.rock.rawValue))
        y += 1
    }

    y = 1
    while y < H - 1 {
        x = 1
        while x < W - 1 {
            if map.get(x, y) == Int(Tile.rock.rawValue) {
                let open = countOpen(map, x, y)
                if open >= 2 && rng.chance(0.045) { map.set(x, y, Int(Tile.crystal.rawValue)) }
            }
            x += 1
        }
        y += 1
    }

    func roomDist(_ r: Room) -> Int {
        let i = jsFloor(r.cy) * W + jsFloor(r.cx)
        if i < 0 || i >= distances.count { return -1 }
        return distances[i]
    }
    var bossRoom = rooms[rooms.count - 1]
    var far = -1
    for r in rooms {
        let d = roomDist(r)
        if d > far {
            far = d
            bossRoom = r
        }
    }

    var packSpots: [Vec2] = []
    for (index, r) in rooms.enumerated() {
        if index == 0 { continue }
        let n = max(1, Int(jsRound(Double(r.w * r.h) / 45)))
        var k = 0
        while k < n {
            var tries = 0
            while tries < 12 {
                let p = Vec2(x: rng.range(Double(r.x + 1), Double(r.x + r.w - 1)), y: rng.range(Double(r.y + 1), Double(r.y + r.h - 1)))
                if !map.collides(p.x, p.y, 0.6) {
                    packSpots.append(p)
                    break
                }
                tries += 1
            }
            k += 1
        }
    }
    let corridorCount = rooms.count / 2
    var k = 0
    while k < corridorCount {
        var tries = 0
        while tries < 40 {
            let p = Vec2(x: Double(rng.int(2, W - 3)) + 0.5, y: Double(rng.int(2, H - 3)) + 0.5)
            if map.collides(p.x, p.y, 0.6) { tries += 1; continue }
            let di = distances[jsFloor(p.y) * W + jsFloor(p.x)]
            if di > 12 {
                packSpots.append(p)
                break
            }
            tries += 1
        }
        k += 1
    }
    packSpots.sort { a, b in
        distances[jsFloor(a.y) * W + jsFloor(a.x)] < distances[jsFloor(b.y) * W + jsFloor(b.x)]
    }
    let bossPos = map.nearestOpen(bossRoom.cx, bossRoom.cy, 1.05)
    return DungeonLayout(map: map, rooms: rooms, start: start, bossRoom: bossRoom, bossPos: bossPos, packSpots: packSpots)
}

private func carveBlob(_ map: TileMap, _ r: Room, _ rng: Rng) {
    let rx = Double(r.w) / 2
    let ry = Double(r.h) / 2
    var y = r.y
    while y < r.y + r.h {
        var x = r.x
        while x < r.x + r.w {
            let nx = (Double(x) + 0.5 - r.cx) / rx
            let ny = (Double(y) + 0.5 - r.cy) / ry
            let d = nx * nx + ny * ny
            if d < 0.75 || (d < 1.05 && rng.chance(0.6)) { map.set(x, y, Int(Tile.floor.rawValue)) }
            x += 1
        }
        y += 1
    }
}

private func carveTunnel(_ map: TileMap, _ a: Room, _ b: Room, _ rng: Rng) {
    var x = a.cx
    var y = a.cy
    let width = rng.chance(0.5) ? 1 : 2
    var guardN = 0
    while (abs(x - b.cx) > 1 || abs(y - b.cy) > 1) && guardN < 800 {
        guardN += 1
        let dx = b.cx - x
        let dy = b.cy - y
        if rng.chance(0.75) {
            if abs(dx) > abs(dy) { x += sign(dx) } else { y += sign(dy) }
        } else if rng.chance(0.5) {
            x += rng.chance(0.5) ? 1 : -1
        } else {
            y += rng.chance(0.5) ? 1 : -1
        }
        x = max(2, min(Double(map.w - 3), x))
        y = max(2, min(Double(map.h - 3), y))
        var oy = -width + 1
        while oy <= width - 1 + 1 {
            var ox = -width + 1
            while ox <= width - 1 + 1 {
                map.set(jsFloor(x) + ox, jsFloor(y) + oy, Int(Tile.floor.rawValue))
                ox += 1
            }
            oy += 1
        }
    }
}

private func countOpen(_ map: TileMap, _ x: Int, _ y: Int) -> Int {
    var n = 0
    var oy = -1
    while oy <= 1 {
        var ox = -1
        while ox <= 1 {
            if (ox != 0 || oy != 0) {
                let t = map.get(x + ox, y + oy)
                if t != Int(Tile.rock.rawValue) && t != Int(Tile.crystal.rawValue) { n += 1 }
            }
            ox += 1
        }
        oy += 1
    }
    return n
}

private func roughen(_ map: TileMap, _ rng: Rng, _ passes: Int) {
    var p = 0
    while p < passes {
        var next = map.tiles
        var y = 2
        while y < map.h - 2 {
            var x = 2
            while x < map.w - 2 {
                let open = countOpen(map, x, y)
                let i = y * map.w + x
                if map.tiles[i] == Tile.rock.rawValue && open >= 5 && rng.chance(0.7) { next[i] = Tile.floor.rawValue }
                else if map.tiles[i] == Tile.floor.rawValue && open <= 2 { next[i] = Tile.rock.rawValue }
                x += 1
            }
            y += 1
        }
        map.tiles = next
        p += 1
    }
}

public func floodDistances(_ map: TileMap, _ from: Vec2) -> [Int] {
    var out = [Int](repeating: -1, count: map.w * map.h)
    var q = [Int](repeating: 0, count: map.w * map.h)
    let sx = jsFloor(from.x)
    let sy = jsFloor(from.y)
    if map.solidAt(sx, sy) { return out }
    let s = sy * map.w + sx
    out[s] = 0
    var head = 0
    var tail = 0
    q[tail] = s
    tail += 1
    while head < tail {
        let i = q[head]
        head += 1
        let x = i % map.w
        let y = (i - x) / map.w
        let n = [i - 1, i + 1, i - map.w, i + map.w]
        let ok = [x > 0, x < map.w - 1, y > 0, y < map.h - 1]
        var k = 0
        while k < 4 {
            let j = n[k]
            if ok[k] && out[j] == -1 {
                let jx = j % map.w
                let jy = (j - jx) / map.w
                if !map.solidAt(jx, jy) {
                    out[j] = out[i] + 1
                    q[tail] = j
                    tail += 1
                }
            }
            k += 1
        }
    }
    return out
}
