import SwiftUI
import SpriteKit

struct PlayView: View {
    @ObservedObject var session: GameSession

    var body: some View {
        ZStack {
            if let stage = session.stage {
                SpriteView(scene: stage)
                    .id(session.inShaft ? "shaft" : "camp")
                    .ignoresSafeArea()
            }
            if session.screen == .none {
                controls
            }
            switch session.screen {
            case .descend: DescendView(session: session)
            case .results: ResultsView(session: session)
            case .rack: RackView(session: session)
            case .board: RankView(session: session)
            case .none: EmptyView()
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                if session.inShaft {
                    bar(session.hudLife, Color(hex: 0xc8343c))
                    bar(session.hudEcho, Color(hex: 0xe9c49a))
                    Text(session.hudText)
                        .foregroundStyle(Color(hex: 0xf3eadf))
                        .font(.caption)
                } else {
                    Text(session.status)
                        .foregroundStyle(Color(hex: 0xf3eadf))
                }
                Spacer()
                Minimap(session: session)
            }
            if !session.note.isEmpty && !session.inShaft {
                Text(session.note)
                    .foregroundStyle(Color(hex: 0xb7aa9c))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            if session.showHint {
                Button(session.hint) { session.hideHint() }
                    .font(.body)
                    .foregroundStyle(Color(hex: 0xf3eadf))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(10)
                    .background(Color(hex: 0x221b16))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x3a2e26), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack(alignment: .bottom) {
                if session.save.handedness == "left" {
                    CombatPad(session: session)
                    Spacer()
                    StickPad(session: session)
                } else {
                    StickPad(session: session)
                    Spacer()
                    CombatPad(session: session)
                }
            }
            HStack(spacing: 8) {
                if session.inShaft {
                    PanelButton(title: "Leave") { session.leave() }
                }
                PanelButton(title: session.handTitle) { session.flipHand() }
                if !session.inShaft && !session.prompt.isEmpty {
                    PanelButton(title: session.prompt, primary: true) { session.useStation() }
                }
                Spacer()
            }
        }
        .padding(12)
    }

    private func bar(_ fraction: Double, _ color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: 0x1a120c))
                Rectangle().fill(color).frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))))
            }
        }
        .frame(width: 120, height: 10)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}
