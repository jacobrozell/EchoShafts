public enum StatusDef {
    case slow(pct: Double, duration: Double)
    case stun(duration: Double)
    case bleed(coefPerSec: Double, duration: Double)
    case burn(coefPerSec: Double, duration: Double)
    case vulnerable(pct: Double, duration: Double)
}

public final class ActiveBuff {
    public let id: String
    public let name: String
    public var left: Double
    public var damagePct: Double
    public var damageReduction: Double
    public var moveSpeedPct: Double
    public var attackSpeedPct: Double
    public var immune: Bool
    public var regenPct: Double

    public init(id: String, name: String, left: Double, damagePct: Double = 0, damageReduction: Double = 0, moveSpeedPct: Double = 0, attackSpeedPct: Double = 0, immune: Bool = false, regenPct: Double = 0) {
        self.id = id
        self.name = name
        self.left = left
        self.damagePct = damagePct
        self.damageReduction = damageReduction
        self.moveSpeedPct = moveSpeedPct
        self.attackSpeedPct = attackSpeedPct
        self.immune = immune
        self.regenPct = regenPct
    }
}
