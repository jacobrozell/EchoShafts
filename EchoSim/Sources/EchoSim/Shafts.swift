import Foundation

public enum ShaftKind: String {
    case tutorial
    case echo
    case deep
}

public func deepVeinScaling(_ depth: Int) -> (lifeMult: Double, damageMult: Double, rewardBonus: Double) {
    let d = Double(depth - 1)
    return (
        lifeMult: 1.8 * pow(1.16, d),
        damageMult: 1.25 * pow(1.08, d),
        rewardBonus: 0.4 + Double(depth) * 0.12
    )
}

public func shaftSize(_ kind: ShaftKind) -> (width: Int, height: Int, rooms: Int) {
    if kind == .tutorial { return (44, 36, 4) }
    return (92, 80, 11)
}

/// Echo shaft scaling is the Surface row. Pressure tiers are not a 1.0 ladder.
public let SURFACE_LIFE = 5.0
public let SURFACE_DAMAGE = 0.8
public let SURFACE_REWARD = 0.0
