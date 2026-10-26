import AppKit
import CoreGraphics
import ImageIO

protocol CharacterSkin: AnyObject {
    /// Returns the frame and whether it should be drawn mirrored.
    func frame(facing: Facing, pose: Pose, tick: Int) -> (CGImage, Bool)
    /// True for 16x32 office-worker sheets; false for free-form sprites (Pokémon).
    var isSheet: Bool { get }
    var hasCheerFrame: Bool { get }
}

/// A 16x32 sprite sheet in the Pixel Agents layout: rows down/up/right, columns
/// walk1, stand, walk2, type1, type2, read1, read2 (+ sleep, cheer for built-in sheets).
final class SheetSkin: CharacterSkin {
    private let frames: [[CGImage]]
    let isSheet = true
    var hasCheerFrame: Bool { frames[0].count > 8 }

    init?(sheet: CGImage) {
        let cols = sheet.width / 16, rows = sheet.height / 32
        guard cols >= 7, rows >= 3 else { return nil }
        var f: [[CGImage]] = []
        for r in 0..<3 {
            f.append((0..<cols).compactMap { sheet.crop($0 * 16, r * 32, 16, 32) })
        }
        frames = f
    }

    func frame(facing: Facing, pose: Pose, tick: Int) -> (CGImage, Bool) {
        let row: Int
        switch facing {
        case .down: row = 0
        case .up: row = 1
        case .right, .left: row = 2
        }
        let col: Int
        switch pose {
        case .stand: col = 1
        case .walk: col = [0, 1, 2, 1][(tick / 2) % 4]
        case .type: col = 3 + (tick / 2) % 2
        case .read: col = 5 + (tick / 8) % 2
        case .sleep: col = frames[row].count > 7 ? 7 : 1
        case .cheer: col = frames[row].count > 8 ? 8 : 1
        }
        let r = frames[row]
        return (r[min(col, r.count - 1)], facing == .left)
    }
}

/// Animated GIF / PNG sprite (Pokémon from PokeTokenBar). Frames are cropped to their shared opaque bounds.
final class AnimatedSkin: CharacterSkin {
    private let frames: [CGImage]
    private let delays: [Double]
    private let total: Double
    let isSheet = false
    let hasCheerFrame = false

    init?(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let n = CGImageSourceGetCount(src)
        var imgs: [CGImage] = []
        var ds: [Double] = []
        for i in 0..<n {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            imgs.append(img)
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            ds.append(max(d, 0.04))
        }
        guard !imgs.isEmpty else { return nil }
        let bounds = imgs.map { $0.opaqueBounds() }.reduce(CGRect.null) { $0.union($1) }
        frames = imgs.compactMap { $0.cropping(to: bounds) }
        delays = ds
        total = ds.reduce(0, +)
    }

    func frame(facing: Facing, pose: Pose, tick: Int) -> (CGImage, Bool) {
        // Pokémon front sprites face left; mirror when walking right.
        let flip = facing == .right
        if pose == .sleep || frames.count == 1 { return (frames[0], flip) }
        let speed = pose == .type ? 1.6 : 1
        var t = (Date().timeIntervalSinceReferenceDate * speed).truncatingRemainder(dividingBy: total)
        for (i, d) in delays.enumerated() {
            if t < d { return (frames[i], flip) }
            t -= d
        }
        return (frames[0], flip)
    }
}

struct CharacterChoice: Identifiable, Hashable {
    let ref: String
    let name: String
    let group: String
    var id: String { ref }
}

@MainActor
final class SpriteLibrary: ObservableObject {
    static let shared = SpriteLibrary()

    @Published private(set) var pixelAgentsDir: URL?
    @Published private(set) var pokemonDir: URL?
    private(set) var paCharacters: [CGImage] = []
    private(set) var pokemon: [(id: Int, name: String)] = []
    private var skinCache: [String: CharacterSkin] = [:]
    private var furnitureCache: [String: CGImage?] = [:]
    private let settings = SettingsStore.shared

    private init() { reload() }

    func reload() {
        skinCache.removeAll()
        furnitureCache.removeAll()
        OfficeArt.resetCaches()

        pixelAgentsDir = settings.s.pixelAgentsAssetsPath.map { URL(fileURLWithPath: expandPath($0)) }
            .flatMap(Self.validPixelAgents) ?? Self.detectPixelAgents()
        paCharacters = []
        if let dir = pixelAgentsDir?.appendingPathComponent("characters"),
           let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for f in files.filter({ $0.hasPrefix("char_") && $0.hasSuffix(".png") }).sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                if let img = Self.loadImage(dir.appendingPathComponent(f)) { paCharacters.append(img) }
            }
        }

        let pokePath = settings.s.pokemonSpritesPath.map(expandPath)
            ?? NSHomeDirectory() + "/Library/Application Support/PokeTokenBar/sprites"
        pokemonDir = FileManager.default.fileExists(atPath: pokePath) ? URL(fileURLWithPath: pokePath) : nil
        pokemon = []
        if let dir = pokemonDir, let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            let ids = Set(files.compactMap { f -> Int? in Int(f.split(separator: "-").first ?? "") })
            let details = dir.deletingLastPathComponent().appendingPathComponent("pokemon-details-v1")
            for id in ids.sorted() {
                var name = "#\(id)"
                if let d = try? Data(contentsOf: details.appendingPathComponent("\(id).json")),
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let n = (o["details"] as? [String: Any])?["name"] as? String {
                    name = n.prefix(1).uppercased() + n.dropFirst()
                }
                pokemon.append((id, name))
            }
        }
        objectWillChange.send()
    }

    // MARK: Skins

    func skin(for ref: String, shirt: RGBA) -> CharacterSkin {
        let cacheKey = ref.hasPrefix("builtin:") ? "\(ref)|\(shirt.hex)" : ref
        if let s = skinCache[cacheKey] { return s }
        let skin = makeSkin(ref, shirt: shirt) ?? SheetSkin(sheet: BuiltinCharacters.sheet(look: 0, shirt: shirt))!
        skinCache[cacheKey] = skin
        return skin
    }

    private func makeSkin(_ ref: String, shirt: RGBA) -> CharacterSkin? {
        let parts = ref.split(separator: ":").map(String.init)
        guard parts.count >= 2, let n = Int(parts[1]) else { return nil }
        switch parts[0] {
        case "builtin":
            return SheetSkin(sheet: BuiltinCharacters.sheet(look: n, shirt: shirt))
        case "pa":
            guard !paCharacters.isEmpty else { return nil }
            return SheetSkin(sheet: paCharacters[n % paCharacters.count])
        case "poke":
            guard let dir = pokemonDir else { return nil }
            let shiny = parts.count > 2 && parts[2] == "shiny"
            let candidates = shiny ? ["\(n)-sha.gif", "\(n)-a.gif", "\(n)-s.png"] : ["\(n)-a.gif", "\(n)-s.png", "\(n)-sha.gif"]
            for c in candidates {
                let url = dir.appendingPathComponent(c)
                if FileManager.default.fileExists(atPath: url.path), let s = AnimatedSkin(url: url) { return s }
            }
            return nil
        default:
            return nil
        }
    }

    /// Picks a default character for a new session from the configured source, avoiding ones already on screen.
    func autoCharacter(seed: String, avoiding used: Set<String>) -> String {
        let pool = autoPool()
        let start = Int(stableHash(seed) % UInt64(pool.count))
        for i in 0..<pool.count where !used.contains(pool[(start + i) % pool.count]) {
            return pool[(start + i) % pool.count]
        }
        return pool[start]
    }

    private func autoPool() -> [String] {
        switch settings.s.characterSource {
        case .pixelAgents where !paCharacters.isEmpty:
            return paCharacters.indices.map { "pa:\($0)" }
        case .pokemon where !pokemon.isEmpty:
            let shiny = settings.s.pokemonPreferShiny ? ":shiny" : ""
            return pokemon.map { "poke:\($0.id)\(shiny)" }
        default:
            return BuiltinCharacters.looks.indices.map { "builtin:\($0)" }
        }
    }

    var choices: [CharacterChoice] {
        var out = BuiltinCharacters.looks.enumerated().map {
            CharacterChoice(ref: "builtin:\($0.offset)", name: $0.element.name, group: "기본 도트")
        }
        out += paCharacters.indices.map { CharacterChoice(ref: "pa:\($0)", name: "캐릭터 \($0 + 1)", group: "Pixel Agents") }
        out += pokemon.map { CharacterChoice(ref: "poke:\($0.id)", name: $0.name, group: "포켓몬") }
        return out
    }

    func displayName(_ ref: String) -> String {
        if ref.hasSuffix(":shiny") {
            return (choices.first { $0.ref == String(ref.dropLast(":shiny".count)) }?.name ?? ref) + " ✨"
        }
        return choices.first { $0.ref == ref }?.name ?? ref
    }

    func group(of ref: String) -> String? {
        let base = ref.hasSuffix(":shiny") ? String(ref.dropLast(":shiny".count)) : ref
        return choices.first { $0.ref == base }?.group
    }

    // MARK: Pixel Agents furniture

    func furniture(_ folder: String, _ file: String) -> CGImage? {
        guard settings.s.office.usePixelAgentsFurniture, let dir = pixelAgentsDir else { return nil }
        let key = "\(folder)/\(file)"
        if let c = furnitureCache[key] { return c }
        let img = Self.loadImage(dir.appendingPathComponent("furniture").appendingPathComponent(folder).appendingPathComponent(file))
        furnitureCache[key] = img
        return img
    }

    // MARK: Discovery

    private static func validPixelAgents(_ url: URL) -> URL? {
        let fm = FileManager.default
        for candidate in [url, url.appendingPathComponent("dist/assets"), url.appendingPathComponent("assets")] {
            if fm.fileExists(atPath: candidate.appendingPathComponent("characters").path) { return candidate }
        }
        return nil
    }

    /// Pixel Agents (MIT, characters based on the CC0 MetroCity pack) ships its assets inside the editor extension.
    static func detectPixelAgents() -> URL? {
        let home = NSHomeDirectory()
        let roots = [".vscode/extensions", ".vscode-insiders/extensions", ".cursor/extensions", ".windsurf/extensions"]
        var found: [URL] = []
        for r in roots {
            let dir = URL(fileURLWithPath: home).appendingPathComponent(r)
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for item in items where item.lowercased().hasPrefix("pablodelucca.pixel-agents-") {
                if let v = validPixelAgents(dir.appendingPathComponent(item)) { found.append(v) }
            }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedDescending }.first
    }

    static func loadImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
