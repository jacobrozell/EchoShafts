import Foundation

final class SpatialHash<T: Entity> {
    private var cells: [Int: [T]] = [:]
    private let cellSize: Double

    init(cellSize: Double = 4) { self.cellSize = cellSize }

    private func key(_ cx: Int, _ cy: Int) -> Int {
        (cx + 32768) * 65536 + (cy + 32768)
    }

    func clear() { cells.removeAll(keepingCapacity: true) }

    func insert(_ e: T) {
        let k = key(jsFloor(e.pos.x / cellSize), jsFloor(e.pos.y / cellSize))
        if cells[k] == nil { cells[k] = [] }
        cells[k]?.append(e)
    }

    func query(_ x: Double, _ y: Double, _ r: Double, pad: Double = 1.5) -> [T] {
        let cs = cellSize
        let x0 = jsFloor((x - r - pad) / cs)
        let x1 = jsFloor((x + r + pad) / cs)
        let y0 = jsFloor((y - r - pad) / cs)
        let y1 = jsFloor((y + r + pad) / cs)
        var out: [T] = []
        var cy = y0
        while cy <= y1 {
            var cx = x0
            while cx <= x1 {
                if let c = cells[key(cx, cy)] {
                    for e in c {
                        let rr = r + e.radius
                        let dx = e.pos.x - x
                        let dy = e.pos.y - y
                        if dx * dx + dy * dy <= rr * rr { out.append(e) }
                    }
                }
                cx += 1
            }
            cy += 1
        }
        return out
    }
}
