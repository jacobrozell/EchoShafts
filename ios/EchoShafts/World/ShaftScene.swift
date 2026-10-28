import SpriteKit
import EchoSim

final class ShaftScene: WorldScene {
    override func activePlayer() -> Player? { session.run?.player }
    override func activeSim() -> Simulation? { session.run?.sim }
}
