import AppKit
import ClimbCore

/// A pack contains only locally decoded PNG pixels and animation metadata.
final class AppearanceLibrary {
    static let spiderID = "builtin.spiderman"
    struct Entry {
        let id: String
        let name: String
        let pack: CharacterPack?
    }
    private let defaults: UserDefaults
    private let directory: URL
    private(set) var entries: [Entry] = []
    private(set) var selectedID: String
    var selected: Entry { entries.first { $0.id == selectedID } ?? entries[0] }

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sisyphus/Characters", isDirectory: true)
        selectedID = defaults.string(forKey: "appearanceID") ?? "builtin.akane"
        if let pack = Self.bundledCharacter() {
            entries.append(Entry(id: "builtin.akane", name: pack.manifest.name, pack: pack))
        }
        entries.append(Entry(id: Self.spiderID, name: "蜘蛛侠", pack: nil))
        entries.append(Entry(id: "builtin.climber", name: "原版小人", pack: nil))
        let installed = (try? FileManager.default.contentsOfDirectory(at: self.directory,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for url in installed.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let pack = try? CharacterPack.load(from: url.appendingPathComponent("character.json")) else { continue }
            entries.append(Entry(id: url.lastPathComponent, name: pack.manifest.name, pack: pack))
        }
        selectedID = selected.id
    }

    static func bundledCharacter() -> CharacterPack? {
        var roots = [Bundle.main.resourceURL].compactMap { $0 }
        #if DEBUG
        roots.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources"))
        #endif
        for root in roots {
            if let pack = try? CharacterPack.load(from: root.appendingPathComponent("Characters/Akane/character.json")) { return pack }
        }
        return nil
    }

    func select(_ id: String) {
        guard entries.contains(where: { $0.id == id }) else { return }
        selectedID = id; defaults.set(id, forKey: "appearanceID")
    }

    func importCharacter(from url: URL) throws {
        let pack = try CharacterPack.load(from: url)
        let installed = try pack.install(into: directory)
        let id = installed.deletingLastPathComponent().lastPathComponent
        entries.append(Entry(id: id, name: pack.manifest.name, pack: pack))
        select(id)
    }
}
