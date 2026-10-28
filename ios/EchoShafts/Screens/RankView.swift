import SwiftUI

struct RankView: View {
    @ObservedObject var session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Board")
                .font(.caption)
                .foregroundStyle(Color(hex: 0xb7aa9c))
            Text("This phone")
                .font(.title.weight(.semibold))
                .foregroundStyle(Color(hex: 0xf3eadf))
            if let best = session.save.veinBest {
                let seconds = Int((Double(best.ticks) / 20).rounded())
                Text("Depth \(best.depth) · \(seconds)s")
                    .foregroundStyle(Color(hex: 0xf3eadf))
            } else {
                Text("No vein cleared yet.")
                    .foregroundStyle(Color(hex: 0xf3eadf))
            }
            Text("A deeper clear wins. The same depth wins by being faster.")
                .foregroundStyle(Color(hex: 0xb7aa9c))
            PanelButton(title: "Back") { session.screen = .none }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: 0x140f0c))
    }
}
