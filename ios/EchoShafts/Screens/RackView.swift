import SwiftUI
import EchoSim

struct RackView: View {
    @ObservedObject var session: GameSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Rack")
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0xb7aa9c))
                Text("What you are wearing")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xf3eadf))
                Text("Company issue. The rest was already down there.")
                    .foregroundStyle(Color(hex: 0xb7aa9c))
                worn("Melee", session.save.meleeId)
                ForEach(session.save.ownedMeleeIds.filter { $0 != session.save.meleeId }, id: \.self) { id in
                    equipRow(id)
                }
                worn("Ranged", session.save.rangedId)
                ForEach(session.save.ownedRangedIds.filter { $0 != session.save.rangedId }, id: \.self) { id in
                    equipRow(id)
                }
                worn("Plate", session.save.plateId)
                ForEach(session.save.ownedPlateIds.filter { $0 != session.save.plateId }, id: \.self) { id in
                    equipRow(id)
                }
                ForEach(GEAR.filter { !ownsGear(session.save, $0.id) }, id: \.id) { gear in
                    ItemRow(name: gear.name, line: gear.line, dimmed: true)
                }
                ForEach(TREES, id: \.id) { tree in
                    treeBlock(tree)
                }
                PanelButton(title: "Return the Flesh") { session.refund() }
                PanelButton(title: "Back") { session.screen = .none }
            }
            .padding(24)
        }
        .background(Color(hex: 0x140f0c))
    }

    private func worn(_ slot: String, _ id: String) -> some View {
        let gear = GEAR_BY_ID[id]
        let line = plateLine(id, gear?.line ?? "")
        return ItemRow(name: "\(slot) \(gear?.name ?? id)", line: line)
    }

    private func plateLine(_ id: String, _ line: String) -> String {
        guard id == session.save.plateId else { return line }
        let armor = wornArmor(session.save)
        if line.isEmpty { return "plate \(armor)" }
        return "\(line) plate \(armor)"
    }

    private func equipRow(_ id: String) -> some View {
        let gear = GEAR_BY_ID[id]
        return ItemRow(name: gear?.name ?? id, line: gear?.line ?? "", actionTitle: "Equip") {
            session.wear(id)
        }
    }

    private func treeBlock(_ tree: TreeDef) -> some View {
        let current = rankOf(session.save, tree.id)
        let cost = nextRankCost(session.save, tree.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(tree.title)
                .font(.headline)
                .foregroundStyle(Color(hex: 0xf3eadf))
            if current > 0 {
                ForEach(1...current, id: \.self) { rank in
                    Text(rankSentence(tree, rank, origin: session.save.origin))
                        .foregroundStyle(Color(hex: 0xf3eadf))
                }
            }
            if let cost {
                Text("\(rankSentence(tree, current + 1, origin: session.save.origin)) Flesh \(cost).")
                    .foregroundStyle(Color(hex: 0xb7aa9c))
                PanelButton(title: "Spend \(cost)", enabled: session.save.flesh >= cost) {
                    session.buy(tree.id)
                }
            }
        }
    }
}
