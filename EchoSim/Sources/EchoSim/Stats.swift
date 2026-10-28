import Foundation

public let BASE_CRIT_CHANCE = 0.05
public let BASE_CRIT_DAMAGE = 0.5

public struct DerivedStats {
    public var anchor: Double
    public var flesh: Double
    public var maxLife: Double
    public var armor: Double
    public var weaponMin: Double
    public var weaponMax: Double
    public var rangedMin: Double
    public var rangedMax: Double
    public var attacksPerSecond: Double
    public var critChance: Double
    public var critDamage: Double
    public var damagePct: Double
    public var eliteDamage: Double
    public var resourceGen: Double
    public var secondaryDamage: Double
    public var lifeOnHit: Double
    public var lifeRegen: Double
    public var moveSpeed: Double
    public var pickupRadius: Double
}

public func armorReduction(_ armor: Double, _ monsterLevel: Int) -> Double {
    armor / (armor + 50 * Double(monsterLevel) + 100)
}

public func deriveStats(_ save: Save) -> DerivedStats {
    let level = save.level
    let flesh = 10 + 3 * Double(level - 1)
    let anchor = flesh
    let vitality = 9 + 2 * Double(level - 1)
    var maxLife = jsRound(WARDEN.baseLife + WARDEN.lifePerLevel * Double(level - 1) + vitality * 5)
    if save.origin == "cataracta" { maxLife += 24 }
    let melee = GEAR_BY_ID[save.meleeId]
    let ranged = GEAR_BY_ID[save.rangedId]
    let weaponMin = melee?.damageMin ?? 8
    let weaponMax = melee?.damageMax ?? 12
    let rangedMin = ranged?.damageMin ?? 4
    let rangedMax = ranged?.damageMax ?? 6
    let armor = jsRound(WARDEN.baseArmor + Double(wornArmor(save)))
    return DerivedStats(
        anchor: anchor,
        flesh: flesh,
        maxLife: maxLife,
        armor: armor,
        weaponMin: weaponMin,
        weaponMax: weaponMax,
        rangedMin: rangedMin,
        rangedMax: rangedMax,
        attacksPerSecond: 1,
        critChance: BASE_CRIT_CHANCE,
        critDamage: BASE_CRIT_DAMAGE,
        damagePct: 0,
        eliteDamage: 0,
        resourceGen: 0,
        secondaryDamage: 0,
        lifeOnHit: 0,
        lifeRegen: maxLife * 0.004,
        moveSpeed: BASE_MOVE_SPEED,
        pickupRadius: BASE_PICKUP_RADIUS
    )
}
