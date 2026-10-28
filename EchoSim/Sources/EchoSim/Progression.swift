import Foundation

public func xpToNext(_ level: Int) -> Int {
    Int(jsRound(40 * pow(Double(level), 1.35)))
}

public func killXp(_ base: Double, _ monsterLevel: Int, _ rewardBonus: Double) -> Int {
    Int(jsRound(base * (1 + 0.22 * Double(monsterLevel - 1)) * (1 + rewardBonus)))
}

public struct XpResult {
    public var level: Int
    public var xp: Int
    public var levelsGained: Int
}

public func applyXp(_ level: Int, _ xp: Int, _ gained: Int) -> XpResult {
    if level >= LEVEL_CAP || gained <= 0 { return XpResult(level: level, xp: xp, levelsGained: 0) }
    var level = level
    var xp = xp + gained
    var levelsGained = 0
    while level < LEVEL_CAP && xp >= xpToNext(level) {
        xp -= xpToNext(level)
        level += 1
        levelsGained += 1
    }
    if level >= LEVEL_CAP { xp = 0 }
    return XpResult(level: level, xp: xp, levelsGained: levelsGained)
}
