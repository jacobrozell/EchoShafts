import SwiftUI

struct CombatPad: View {
    @ObservedObject var session: GameSession

    var body: some View {
        HStack(spacing: 8) {
            HoldBit(session: session, title: "Melee", bit: 1)
            HoldBit(session: session, title: "Ranged", bit: 2)
            HoldBit(session: session, title: "Draught", bit: 16)
        }
    }
}

private struct HoldBit: View {
    @ObservedObject var session: GameSession
    var title: String
    var bit: Int

    var body: some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(hex: 0xf3eadf))
            .frame(minWidth: 64, minHeight: 52)
            .padding(.horizontal, 6)
            .background(Color(hex: 0x221b16))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x3a2e26), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in session.input.b |= bit }
                    .onEnded { _ in session.input.b &= ~bit }
            )
            .accessibilityLabel(title)
    }
}
