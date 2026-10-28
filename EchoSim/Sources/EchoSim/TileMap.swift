import Foundation

public enum Tile: UInt8 {
    case rock = 0
    case floor = 1
    case road = 2
    case water = 3
    case building = 4
    case tree = 5
    case crystal = 6
    case plank = 7
}

func tileSolid(_ t: Int) -> Bool {
    t == Int(Tile.rock.rawValue) || t == Int(Tile.water.rawValue) || t == Int(Tile.building.rawValue) || t == Int(Tile.tree.rawValue) || t == Int(Tile.crystal.rawValue)
}

public final class TileMap {
    public let w: Int
    public let h: Int
    public var tiles: [UInt8]

    public init(w: Int, h: Int, tiles: [UInt8]? = nil) {
        self.w = w
        self.h = h
        self.tiles = tiles ?? [UInt8](repeating: 0, count: w * h)
    }

    public func get(_ x: Int, _ y: Int) -> Int {
        if x < 0 || y < 0 || x >= w || y >= h { return Int(Tile.rock.rawValue) }
        return Int(tiles[y * w + x])
    }

    public func set(_ x: Int, _ y: Int, _ t: Int) {
        if x < 0 || y < 0 || x >= w || y >= h { return }
        tiles[y * w + x] = UInt8(t)
    }

    public func solidAt(_ tx: Int, _ ty: Int) -> Bool { tileSolid(get(tx, ty)) }

    public func solidPoint(_ x: Double, _ y: Double) -> Bool {
        solidAt(jsFloor(x), jsFloor(y))
    }

    public func nearestOpen(_ x: Double, _ y: Double, _ r: Double) -> Vec2 {
        if !collides(x, y, r) { return Vec2(x: x, y: y) }
        var rad = 1
        while rad <= 10 {
            var dy = -rad
            while dy <= rad {
                var dx = -rad
                while dx <= rad {
                    if abs(dx) != rad && abs(dy) != rad { dx += 1; continue }
                    let p = Vec2(x: Double(jsFloor(x) + dx) + 0.5, y: Double(jsFloor(y) + dy) + 0.5)
                    if !collides(p.x, p.y, r) { return p }
                    dx += 1
                }
                dy += 1
            }
            rad += 1
        }
        return Vec2(x: x, y: y)
    }

    public func collides(_ x: Double, _ y: Double, _ r: Double) -> Bool {
        let x0 = jsFloor(x - r)
        let x1 = jsFloor(x + r)
        let y0 = jsFloor(y - r)
        let y1 = jsFloor(y + r)
        if y0 > y1 || x0 > x1 { return false }
        var ty = y0
        while ty <= y1 {
            var tx = x0
            while tx <= x1 {
                if solidAt(tx, ty) { return true }
                tx += 1
            }
            ty += 1
        }
        return false
    }

    public func move(_ pos: Vec2, _ dx: Double, _ dy: Double, _ r: Double) -> Vec2 {
        let steps = max(1, Int(ceil(max(abs(dx), abs(dy)) / 0.2)))
        let sx = dx / Double(steps)
        let sy = dy / Double(steps)
        var x = pos.x
        var y = pos.y
        var i = 0
        while i < steps {
            if sx != 0 && !collides(x + sx, y, r) { x += sx }
            if sy != 0 && !collides(x, y + sy, r) { y += sy }
            i += 1
        }
        return Vec2(x: x, y: y)
    }

    public func lineOfSight(_ a: Vec2, _ b: Vec2) -> Bool {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let n = max(1, Int(ceil(hypot(dx, dy) / 0.25)))
        if n <= 1 { return true }
        var i = 1
        while i < n {
            if solidPoint(a.x + (dx * Double(i)) / Double(n), a.y + (dy * Double(i)) / Double(n)) { return false }
            i += 1
        }
        return true
    }

    public func castCircle(_ a: Vec2, _ b: Vec2, _ r: Double) -> Vec2 {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let n = max(1, Int(ceil(hypot(dx, dy) / 0.2)))
        var last = a
        var i = 1
        while i <= n {
            let p = Vec2(x: a.x + (dx * Double(i)) / Double(n), y: a.y + (dy * Double(i)) / Double(n))
            if collides(p.x, p.y, r) { break }
            last = p
            i += 1
        }
        return last
    }
}

public final class DistanceField {
    public static let FAR = 0xffff
    public var dist: [UInt16]
    private var queue: [Int]
    private let map: TileMap

    public init(_ map: TileMap) {
        self.map = map
        dist = [UInt16](repeating: UInt16(DistanceField.FAR), count: map.w * map.h)
        queue = [Int](repeating: 0, count: map.w * map.h)
    }

    public func build(_ sources: [Vec2], _ maxDist: Int) {
        for i in dist.indices { dist[i] = UInt16(DistanceField.FAR) }
        var head = 0
        var tail = 0
        for s in sources {
            let tx = jsFloor(s.x)
            let ty = jsFloor(s.y)
            if map.solidAt(tx, ty) { continue }
            let i = ty * map.w + tx
            if dist[i] == 0 { continue }
            dist[i] = 0
            queue[tail] = i
            tail += 1
        }
        let w = map.w
        let h = map.h
        let tiles = map.tiles
        while head < tail {
            let i = queue[head]
            head += 1
            let nd = Int(dist[i]) + 1
            if nd > maxDist { continue }
            let x = i % w
            let y = (i - x) / w
            for k in 0..<4 {
                var j = 0
                if k == 0 {
                    if x == 0 { continue }
                    j = i - 1
                } else if k == 1 {
                    if x == w - 1 { continue }
                    j = i + 1
                } else if k == 2 {
                    if y == 0 { continue }
                    j = i - w
                } else {
                    if y == h - 1 { continue }
                    j = i + w
                }
                if Int(dist[j]) <= nd || tileSolid(Int(tiles[j])) { continue }
                dist[j] = UInt16(nd)
                queue[tail] = j
                tail += 1
            }
        }
    }

    public func at(_ x: Double, _ y: Double) -> Int {
        let tx = jsFloor(x)
        let ty = jsFloor(y)
        if tx < 0 || ty < 0 || tx >= map.w || ty >= map.h { return DistanceField.FAR }
        return Int(dist[ty * map.w + tx])
    }

    public func descend(_ x: Double, _ y: Double) -> Vec2? {
        let tx = jsFloor(x)
        let ty = jsFloor(y)
        var best = at(x, y)
        if best == DistanceField.FAR || best == 0 { return nil }
        var bx = 0
        var by = 0
        var oy = -1
        while oy <= 1 {
            var ox = -1
            while ox <= 1 {
                if ox == 0 && oy == 0 { ox += 1; continue }
                if ox != 0 && oy != 0 && (map.solidAt(tx + ox, ty) || map.solidAt(tx, ty + oy)) { ox += 1; continue }
                let d = at(Double(tx + ox) + 0.5, Double(ty + oy) + 0.5)
                if d < best {
                    best = d
                    bx = ox
                    by = oy
                }
                ox += 1
            }
            oy += 1
        }
        if bx == 0 && by == 0 { return nil }
        let cx = Double(tx + bx) + 0.5 - x
        let cy = Double(ty + by) + 0.5 - y
        var l = hypot(cx, cy)
        if l == 0 { l = 1 }
        return Vec2(x: cx / l, y: cy / l)
    }
}
