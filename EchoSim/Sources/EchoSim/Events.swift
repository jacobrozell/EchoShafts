public let STATE = (
    dead: 1,
    winding: 2,
    stunned: 4,
    slowed: 8,
    immune: 16,
    surge: 32,
    dot: 64,
    shielded: 128
)

public enum GameEvent {
    case dmg(id: Int, amount: Double, crit: Bool, source: Int?, x: Double, y: Double)
    case heal(id: Int, amount: Double)
    case cast(id: Int, visual: String, x: Double, y: Double, tx: Double, ty: Double)
    case fx(visual: String, x: Double, y: Double, r: Double?, tx: Double?, ty: Double?)
    case tele(x: Double, y: Double, r: Double, d: Double, tx: Double?, ty: Double?, w: Double?)
    case die(id: Int, x: Double, y: Double)
    case lvl(id: Int)
    case say(id: Int, text: String)
}
