import SwiftUI
import EchoSim

struct DescendView: View {
    @ObservedObject var session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The Shaft")
                .font(.caption)
                .foregroundStyle(Color(hex: 0xb7aa9c))
            Text("Descend")
                .font(.title.weight(.semibold))
                .foregroundStyle(Color(hex: 0xf3eadf))
            Text(levelLine)
                .foregroundStyle(Color(hex: 0xb7aa9c))
            PanelButton(title: "Descend", primary: true) {
                session.begin(ranked: false, depth: 0)
            }
            PanelButton(title: "Deep Vein \(session.nextVeinDepth)", primary: true) {
                session.begin(ranked: true, depth: session.nextVeinDepth)
            }
            if let best = session.save.veinBest {
                PanelButton(title: "Again at \(best.depth)") {
                    session.begin(ranked: true, depth: best.depth)
                }
            }
            PanelButton(title: "Back") { session.screen = .none }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: 0x140f0c))
    }

    private var levelLine: String {
        if session.save.level < 20 {
            return "Lv \(session.save.level) · \(session.save.xp) / \(xpToNext(session.save.level))"
        }
        return "Lv \(session.save.level)"
    }
}
