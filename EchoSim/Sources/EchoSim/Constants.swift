import Foundation

public let TICK_RATE = 20
public let TICK_SECONDS = 1.0 / Double(TICK_RATE)

public let LEVEL_CAP = 20

public let PLAYER_RADIUS = 0.42
public let BASE_MOVE_SPEED = 5.2
public let PICKUP_RANGE = 2.4
public let BASE_PICKUP_RADIUS = 1.6

public let POTION_COOLDOWN = 30.0
public let POTION_HEAL_PCT = 0.6
public let GLOBE_HEAL_PCT = 0.2

public let DEEP_VEIN_SECONDS = 300.0

/// Melee, ranged, draught. Bits 4 and 8 are unused.
public enum BTN {
    public static let melee = 1
    public static let ranged = 2
    public static let draught = 16
}

/// Fraction of a shaft's echo total required before the Vessel.
public enum ECHO_FILL {
    public static let echo = 0.8
    public static let deep = 0.7
    public static let tutorial = 0.38
}
