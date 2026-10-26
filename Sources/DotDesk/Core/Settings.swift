import Foundation
import Combine

enum CharacterSource: String, Codable, CaseIterable, Identifiable {
    case builtin, pixelAgents, pokemon
    var id: String { rawValue }
    var label: String {
        switch self {
        case .builtin: return "기본 도트 캐릭터"
        case .pixelAgents: return "Pixel Agents 캐릭터"
        case .pokemon: return "포켓몬 (PokeTokenBar)"
        }
    }
}

enum PetMode: String, Codable, CaseIterable, Identifiable {
    case roam, pinned
    var id: String { rawValue }
    var label: String { self == .roam ? "자유롭게 돌아다니기" : "제자리에 고정" }
}

struct PetSettings: Codable {
    var enabled = true
    var mode: PetMode = .roam
    var scale: Double = 3
    var showSpeech = true
    var hideWhenNoAgents = false
    var pinnedOrigin: [Double]?
    var roamBaseline: Double?
}

struct OfficeSettings: Codable {
    var enabled = true
    var alwaysOnTop = true
    var autoHide = false
    var frame: [Double]?
    var usePixelAgentsFurniture = true
}

struct PermissionSettings: Codable {
    var mode: PermissionMode = .passthrough
    var bubbleTimeout: Double = 120
    /// In auto-allow mode, still ask (via bubble) for shell commands matching these patterns.
    var askForDangerous = true
    var dangerousPatterns: [String] = [
        "rm -rf", "rm -fr", "sudo ", "git push --force", "git push -f", "git reset --hard",
        "git clean -f", "mkfs", "dd if=", "chmod -R 777", "> /dev/", "drop table", "drop database",
    ]
}

struct ProjectSettings: Codable, Equatable {
    var name: String?
    var colorHex: String?
    var character: String?
    var permissionMode: PermissionMode?
}

struct AccountSettings: Codable, Equatable {
    var label: String?
    var colorHex: String?
    var lastSeen: AccountInfo?
}

struct SessionOverride: Codable, Equatable {
    var name: String?
    var character: String?
    var lastSeen = Date()
}

struct AppSettings: Codable {
    var characterSource: CharacterSource = .builtin
    var pixelAgentsAssetsPath: String?
    var pokemonSpritesPath: String?
    var pokemonPreferShiny = false
    var pet = PetSettings()
    var office = OfficeSettings()
    var permissions = PermissionSettings()
    var projects: [String: ProjectSettings] = [:]
    var accounts: [String: AccountSettings] = [:]
    var sessions: [String: SessionOverride] = [:]
    var claudeConfigDirs: [String] = ["~/.claude"]
    var codexHomes: [String] = ["~/.codex"]
    var watchCodexRollouts = true
    var sleepAfterMinutes: Double = 5
    var forgetAfterMinutes: Double = 240
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var s: AppSettings {
        didSet { scheduleSave() }
    }

    private let url = Runtime.appSupport.appendingPathComponent("settings.json")
    private var saveWork: DispatchWorkItem?

    private init() {
        s = SettingsStore.load(from: url)
    }

    /// Settings files written by older versions may miss keys; overlay them onto defaults before decoding.
    private static func load(from url: URL) -> AppSettings {
        let defaults = AppSettings()
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = try? JSONSerialization.jsonObject(with: JSONEncoder.dotdesk.encode(defaults)) as? [String: Any]
        else { return defaults }
        let merged = deepMerge(base, saved)
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let s = try? JSONDecoder.dotdesk.decode(AppSettings.self, from: mergedData)
        else { return defaults }
        return s
    }

    private static func deepMerge(_ a: [String: Any], _ b: [String: Any]) -> [String: Any] {
        var out = a
        for (k, v) in b {
            if let av = a[k] as? [String: Any], let bv = v as? [String: Any], !av.isEmpty {
                out[k] = deepMerge(av, bv)
            } else {
                out[k] = v
            }
        }
        return out
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        try? FileManager.default.createDirectory(at: Runtime.appSupport, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.dotdesk.encode(s) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Convenience lookups

    func projectName(_ key: String) -> String {
        s.projects[key]?.name.flatMap { $0.isEmpty ? nil : $0 } ?? ProjectResolver.defaultName(for: key)
    }

    func projectColor(_ key: String) -> RGBA {
        if let hex = s.projects[key]?.colorHex, let c = RGBA(hex: hex) { return c }
        return Palette.project[Int(stableHash(key) % UInt64(Palette.project.count))]
    }

    func accountLabel(_ a: AccountInfo) -> String {
        let custom = s.accounts[a.key]?.label.flatMap { $0.isEmpty ? nil : $0 }
        return "\(a.provider.displayName) · \(custom ?? a.defaultLabel)"
    }

    func accountColor(_ a: AccountInfo) -> RGBA {
        if let hex = s.accounts[a.key]?.colorHex, let c = RGBA(hex: hex) { return c }
        return Palette.account[Int(stableHash(a.key) % UInt64(Palette.account.count))]
    }

    func permissionMode(forProject key: String) -> PermissionMode {
        s.projects[key]?.permissionMode ?? s.permissions.mode
    }

    func rememberAccount(_ a: AccountInfo) {
        if s.accounts[a.key]?.lastSeen != a {
            s.accounts[a.key, default: AccountSettings()].lastSeen = a
        }
    }

    func touchProject(_ key: String) {
        if s.projects[key] == nil { s.projects[key] = ProjectSettings() }
    }
}

extension JSONEncoder {
    static let dotdesk: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let dotdesk: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
