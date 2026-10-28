import SpriteKit
import EchoSim

final class CampScene: WorldScene {
    override var showsStalls: Bool { true }
    override func activePlayer() -> Player? { session.hub?.player }
    override func activeSim() -> Simulation? { session.hub?.sim }
}
