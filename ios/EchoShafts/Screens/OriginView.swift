import SwiftUI
import EchoSim

struct OriginView: View {
    @ObservedObject var session: GameSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where were you sent from?")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color(hex: 0xf3eadf))
            originButton("Silvarium", "The elders went north. The bow stayed.", "The shot is heavier.", "silvarium")
            originButton("Cataracta", "The garden is gone. The wolf is not.", "You last longer.", "cataracta")
            originButton("The Plate", "The chant is rationed. The pit is not.", "The swing is heavier.", "plate")
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func originButton(_ title: String, _ line: String, _ dim: String, _ id: String) -> some View {
        Button {
            session.choose(id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xf3eadf))
                Text(line)
                    .foregroundStyle(Color(hex: 0xf3eadf))
                Text(dim)
                    .foregroundStyle(Color(hex: 0xb7aa9c))
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(14)
            .background(Color(hex: 0x221b16))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x3a2e26), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(title)
    }
}
