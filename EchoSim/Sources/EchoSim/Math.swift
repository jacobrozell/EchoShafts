import Foundation

public struct Vec2: Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }
}

public func vec(_ x: Double = 0, _ y: Double = 0) -> Vec2 { Vec2(x: x, y: y) }
public func add(_ a: Vec2, _ b: Vec2) -> Vec2 { Vec2(x: a.x + b.x, y: a.y + b.y) }
public func sub(_ a: Vec2, _ b: Vec2) -> Vec2 { Vec2(x: a.x - b.x, y: a.y - b.y) }
public func scale(_ a: Vec2, _ s: Double) -> Vec2 { Vec2(x: a.x * s, y: a.y * s) }
public func len(_ a: Vec2) -> Double { hypot(a.x, a.y) }
public func dist(_ a: Vec2, _ b: Vec2) -> Double { hypot(a.x - b.x, a.y - b.y) }
public func dist2(_ a: Vec2, _ b: Vec2) -> Double { let dx = a.x - b.x, dy = a.y - b.y; return dx * dx + dy * dy }
public func angleOf(_ a: Vec2) -> Double { atan2(a.y, a.x) }
public func fromAngle(_ rad: Double, _ length: Double = 1) -> Vec2 { Vec2(x: cos(rad) * length, y: sin(rad) * length) }
public func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { v < lo ? lo : v > hi ? hi : v }
public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

public func norm(_ a: Vec2) -> Vec2 {
    let l = hypot(a.x, a.y)
    return l > 1e-9 ? Vec2(x: a.x / l, y: a.y / l) : Vec2(x: 0, y: 0)
}

/// Smallest signed difference between two angles, in radians.
public func angleDiff(_ a: Double, _ b: Double) -> Double {
    var d = a - b
    while d > Double.pi { d -= Double.pi * 2 }
    while d < -Double.pi { d += Double.pi * 2 }
    return d
}

/// Distance from point p to segment ab.
public func distToSegment(_ p: Vec2, _ a: Vec2, _ b: Vec2) -> Double {
    let abx = b.x - a.x
    let aby = b.y - a.y
    let l2 = abx * abx + aby * aby
    if l2 == 0 { return dist(p, a) }
    let t = clamp(((p.x - a.x) * abx + (p.y - a.y) * aby) / l2, 0, 1)
    return hypot(p.x - (a.x + abx * t), p.y - (a.y + aby * t))
}

public func sign(_ n: Double) -> Double {
    if n > 0 { return 1 }
    if n < 0 { return -1 }
    return 0
}

/// Toward -infinity, then Int. Swift Int() truncates toward zero.
public func jsFloor(_ x: Double) -> Int { Int(floor(x)) }

/// Half toward +infinity, matching Math.round.
public func jsRound(_ x: Double) -> Double { floor(x + 0.5) }
public func jsRoundInt(_ x: Double) -> Int { Int(jsRound(x)) }

func imul32(_ a: UInt32, _ b: UInt32) -> UInt32 {
    UInt32(bitPattern: Int32(bitPattern: a) &* Int32(bitPattern: b))
}

public func hashSeed(_ str: String) -> UInt32 {
    var h: UInt32 = 0x811c9dc5
    for byte in str.utf8 {
        h ^= UInt32(byte)
        h = imul32(h, 0x01000193)
    }
    return h
}

public final class Rng {
    public private(set) var state: UInt32
    public init(seed: UInt32) { state = seed == 0 ? 0x9e3779b9 : seed }
    public convenience init(seed: Int) { self.init(seed: UInt32(bitPattern: Int32(truncatingIfNeeded: seed))) }

    public func next() -> Double {
        state = state &+ 0x6d2b79f5
        var t = state
        t = imul32(t ^ (t >> 15), t | 1)
        t ^= t &+ imul32(t ^ (t >> 7), t | 61)
        return Double(t ^ (t >> 14)) / 4294967296
    }

    public func range(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * next()
    }

    /// Inclusive integer range.
    public func int(_ lo: Int, _ hi: Int) -> Int {
        lo + jsFloor(next() * Double(hi - lo + 1))
    }

    public func chance(_ p: Double) -> Bool { next() < p }

    public func pick<T>(_ arr: [T]) -> T {
        arr[jsFloor(next() * Double(arr.count))]
    }

    public func weighted<T>(_ entries: [(T, Double)]) -> T {
        var total = 0.0
        for (_, w) in entries { total += w }
        var r = next() * total
        for (v, w) in entries {
            r -= w
            if r <= 0 { return v }
        }
        return entries[entries.count - 1].0
    }

    public func shuffle<T>(_ arr: inout [T]) -> [T] {
        if arr.count < 2 { return arr }
        var i = arr.count - 1
        while i > 0 {
            let j = jsFloor(next() * Double(i + 1))
            arr.swapAt(i, j)
            i -= 1
        }
        return arr
    }

    public func fork(_ salt: String) -> Rng { fork(hashSeed(salt)) }
    public func fork(_ salt: UInt32) -> Rng {
        Rng(seed: imul32(state ^ salt, 0x85ebca6b) ^ (salt >> 13))
    }
}

/// Insertion-ordered id bag. Removal does not reorder the survivors.
public final class OrderedBag<T> {
    private var order: [Int] = []
    private var items: [Int: T] = [:]

    public init() {}

    public var count: Int { order.count }
    public var isEmpty: Bool { order.isEmpty }

    public func get(_ id: Int) -> T? { items[id] }

    public func set(_ id: Int, _ value: T) {
        if items[id] == nil { order.append(id) }
        items[id] = value
    }

    public func remove(_ id: Int) {
        guard items.removeValue(forKey: id) != nil else { return }
        if let i = order.firstIndex(of: id) { order.remove(at: i) }
    }

    public var all: [T] {
        order.compactMap { items[$0] }
    }

    public func contains(_ id: Int) -> Bool { items[id] != nil }
}
