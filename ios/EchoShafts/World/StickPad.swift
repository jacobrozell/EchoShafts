import SwiftUI

struct StickPad: View {
    @ObservedObject var session: GameSession
    @State private var knob = CGSize.zero

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x221b16))
                .overlay(Circle().stroke(Color(hex: 0x3a2e26), lineWidth: 1))
            Circle()
                .fill(Color(hex: 0xe9c49a))
                .frame(width: 36, height: 36)
                .offset(knob)
        }
        .frame(width: 112, height: 112)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let mag = hypot(dx, dy)
                    let clamped = min(40, mag)
                    if mag < 0.001 || clamped / 40 < 0.18 {
                        knob = .zero
                        session.input.mx = 0
                        session.input.my = 0
                    } else {
                        let scale = clamped / mag
                        knob = CGSize(width: dx * scale, height: dy * scale)
                        session.input.mx = (dx / mag) * (clamped / 40)
                        session.input.my = (dy / mag) * (clamped / 40)
                    }
                }
                .onEnded { _ in
                    knob = .zero
                    session.input.mx = 0
                    session.input.my = 0
                }
        )
        .accessibilityLabel("Stick")
    }
}
