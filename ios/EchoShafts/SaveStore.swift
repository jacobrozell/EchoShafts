import Foundation
import EchoSim

enum SaveStore {
    /// Longevity runs write here so a test does not replace the phone's warden.
    static var agent = false

    static func fileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let name = agent ? "echo-shafts-agent.json" : "echo-shafts-warden.json"
        return base.appendingPathComponent(name)
    }

    static func load() -> Save {
        guard let data = try? Data(contentsOf: fileURL()) else { return newSave() }
        return loadSave(data: data)
    }

    static func write(_ save: Save) {
        try? saveData(save).write(to: fileURL(), options: .atomic)
    }
}
