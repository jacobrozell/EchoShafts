import SwiftUI
import EchoSim

struct MapMark {
    var x: Double
    var y: Double
    var color: String
    var ranged: Bool
}

struct MapPicture {
    var map: TileMap
    var px: Double
    var py: Double
    var marks: [MapMark]
}

struct Minimap: View {
    @ObservedObject var session: GameSession

    var body: some View {
        let picture = session.mapPicture()
        let frame = session.mapFrame
        Canvas { context, size in
            draw(context, size, picture, frame)
        }
        .id(frame)
        .frame(width: 156, height: 112)
        .background(Color(hex: 0x140f0c).opacity(0.9))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x3a2e26), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Map")
    }

    private func draw(_ context: GraphicsContext, _ size: CGSize, _ picture: MapPicture?, _ frame: Int) {
        guard let picture else { return }
        _ = frame
        let map = picture.map
        let cell = min(size.width / CGFloat(map.w), size.height / CGFloat(map.h))
        let ox = (size.width - cell * CGFloat(map.w)) / 2
        let oy = (size.height - cell * CGFloat(map.h)) / 2
        var y = 0
        while y < map.h {
            var x = 0
            while x < map.w {
                if !map.solidAt(x, y) {
                    let rect = CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell, width: max(1, cell), height: max(1, cell))
                    context.fill(Path(rect), with: .color(Color(hex: 0x4a3d34)))
                }
                x += 1
            }
            y += 1
        }
        for mark in picture.marks {
            let r = max(2, cell * (mark.ranged ? 1.6 : 1.05))
            let rect = CGRect(x: ox + CGFloat(mark.x) * cell - r / 2, y: oy + CGFloat(mark.y) * cell - r / 2, width: r, height: r)
            let color = Color(hex: hexValue(mark.color))
            if mark.ranged {
                var path = Path()
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                path.closeSubpath()
                context.fill(path, with: .color(color))
            } else {
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }
        }
        let pr = max(3, cell * 1.7)
        let player = CGRect(x: ox + CGFloat(picture.px) * cell - pr / 2, y: oy + CGFloat(picture.py) * cell - pr / 2, width: pr, height: pr)
        context.fill(Path(ellipseIn: player), with: .color(Color(hex: 0xe9c49a)))
    }
}

private func hexValue(_ text: String) -> UInt32 {
    var s = text
    if s.hasPrefix("#") { s.removeFirst() }
    return UInt32(s, radix: 16) ?? 0xf3eadf
}
