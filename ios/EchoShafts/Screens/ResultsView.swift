import SwiftUI

struct ResultsView: View {
    @ObservedObject var session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(session.resultTitle)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color(hex: 0xf3eadf))
            if !session.resultDetail.isEmpty {
                Text(session.resultDetail)
                    .foregroundStyle(Color(hex: 0xb7aa9c))
            }
            if let offer = session.offer {
                ItemRow(name: offer.title, line: offer.line)
            }
            HStack(spacing: 12) {
                PanelButton(title: "Equip", primary: true) { session.equipResult() }
                PanelButton(title: "Not now") { session.dismissResult() }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: 0x140f0c))
    }
}
