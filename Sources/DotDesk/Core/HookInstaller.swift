import Foundation

/// Adds/removes DotDesk's relay in Claude Code's settings.json and Codex's hooks.json.
/// Only entries whose command mentions `dotdesk-hook` are ever touched.
enum HookInstaller {
    static let marker = "dotdesk-hook"

    static let claudeEvents = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Notification", "Stop", "SubagentStart", "SubagentStop", "PreCompact",
    ]
    static let codexEvents = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PermissionRequest", "Stop", "SubagentStart", "SubagentStop", "PreCompact", "Interrupt",
    ]

    static func claudeSettingsURL(configDir: String) -> URL {
        URL(fileURLWithPath: expandPath(configDir)).appendingPathComponent("settings.json")
    }

    static func codexHooksURL(home: String) -> URL {
        URL(fileURLWithPath: expandPath(home)).appendingPathComponent("hooks.json")
    }

    static func isInstalled(at url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    static func installClaude(configDir: String) throws {
        try install(at: claudeSettingsURL(configDir: configDir), provider: .claude, events: claudeEvents)
    }

    static func installCodex(home: String) throws {
        try install(at: codexHooksURL(home: home), provider: .codex, events: codexEvents)
    }

    static func uninstall(at url: URL) throws {
        guard var root = try readJSON(url) else { return }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.compactMap(stripOurs)
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try writeJSON(root, to: url)
    }

    private static func command(provider: Provider, event: String) -> String {
        "\"\(Runtime.hookScript.path)\" \(provider.rawValue) \(event)"
    }

    private static func install(at url: URL, provider: Provider, events: [String]) throws {
        var root = try readJSON(url) ?? [:]
        backupOnce(url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = (hooks[event] as? [[String: Any]] ?? []).compactMap(stripOurs)
            var entry: [String: Any] = ["type": "command", "command": command(provider: provider, event: event)]
            switch event {
            case "PermissionRequest": entry["timeout"] = 900
            case "SessionEnd", "Interrupt": entry["timeout"] = 3
            default: entry["timeout"] = 5
            }
            groups.append(["matcher": "", "hooks": [entry]])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSON(root, to: url)
    }

    /// Removes our hook entries from a matcher group; drops the group if nothing else is left.
    private static func stripOurs(_ group: [String: Any]) -> [String: Any]? {
        guard let list = group["hooks"] as? [[String: Any]] else { return group }
        let kept = list.filter { !(($0["command"] as? String)?.contains(marker) ?? false) }
        if kept.isEmpty { return nil }
        var g = group
        g["hooks"] = kept
        return g
    }

    private static func readJSON(_ url: URL) throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "DotDesk", code: 1, userInfo: [NSLocalizedDescriptionKey: L("\(url.lastPathComponent)이 JSON 객체가 아니에요", "\(url.lastPathComponent) isn't a JSON object")])
        }
        return obj
    }

    private static func writeJSON(_ obj: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func backupOnce(_ url: URL) {
        let backup = url.appendingPathExtension("dotdesk.backup")
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path), !fm.fileExists(atPath: backup.path) {
            try? fm.copyItem(at: url, to: backup)
        }
    }
}
