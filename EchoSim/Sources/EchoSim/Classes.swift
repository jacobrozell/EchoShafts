import Foundation

public struct ResourceDef {
    public let id: String
    public let name: String
    public let max: Double
    public let regen: Double
    public let decayOutOfCombat: Double
    public let color: String
}

public struct ClassDef {
    public let id: String
    public let name: String
    public let anchor: String
    public let resource: ResourceDef
    public let baseLife: Double
    public let lifePerLevel: Double
    public let baseArmor: Double
    public let color: String
    public let accent: String
}

public let WARDEN = ClassDef(
    id: "warden",
    name: "Flesh-Warden",
    anchor: "flesh",
    resource: ResourceDef(id: "echo", name: "Echo", max: 100, regen: 0, decayOutOfCombat: 4, color: "#c8343c"),
    baseLife: 130,
    lifePerLevel: 16,
    baseArmor: 18,
    color: "#b8433c",
    accent: "#e9c49a"
)

/// Echo Surge: at 80 Echo the Warden deals more and takes more.
public let ECHO_SURGE_THRESHOLD = 80.0
public let ECHO_SURGE_DAMAGE = 0.2
public let ECHO_SURGE_VULNERABILITY = 0.1
