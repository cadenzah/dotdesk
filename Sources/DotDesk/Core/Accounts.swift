import Foundation

/// Which login an agent session runs under. Only display fields are read; tokens are never stored or sent.
struct AccountInfo: Codable, Hashable {
    var key: String
    var provider: Provider
    var email: String?
    var orgName: String?
    var plan: String?
    var configDir: String

    var defaultLabel: String {
        if let org = orgName, !org.isEmpty, org != "Personal" {
            return org
        }
        return email ?? abbreviatePath(configDir)
    }
}

enum AccountResolver {
    private static var cache: [String: (Date, AccountInfo)] = [:]

    static func resolve(provider: Provider, configDir: String?) -> AccountInfo {
        switch provider {
        case .claude: return claude(configDir: configDir)
        case .codex: return codex(home: configDir)
        }
    }

    /// Claude Code keeps the logged-in account in ~/.claude.json (default) or $CLAUDE_CONFIG_DIR/.claude.json.
    private static func claude(configDir: String?) -> AccountInfo {
        let dir = configDir.map(expandPath) ?? NSHomeDirectory() + "/.claude"
        let file = configDir == nil ? NSHomeDirectory() + "/.claude.json" : dir + "/.claude.json"
        return cached(file) {
            let json = readJSON(file)
            let oa = json?["oauthAccount"] as? [String: Any]
            let email = oa?["emailAddress"] as? String
            let org = oa?["organizationName"] as? String
            let orgId = oa?["organizationUuid"] as? String ?? ""
            let accountId = oa?["accountUuid"] as? String ?? email ?? "apikey:\(dir)"
            return AccountInfo(key: "claude:\(accountId):\(orgId)", provider: .claude, email: email ?? (json == nil ? nil : L("API 키", "API key")),
                               orgName: org, plan: oa?["organizationType"] as? String, configDir: dir)
        }
    }

    /// Codex stores ChatGPT login tokens in $CODEX_HOME/auth.json; the id_token's claims carry email/plan/org.
    private static func codex(home: String?) -> AccountInfo {
        let dir = home.map(expandPath) ?? NSHomeDirectory() + "/.codex"
        let file = dir + "/auth.json"
        return cached(file) {
            let json = readJSON(file)
            let tokens = json?["tokens"] as? [String: Any]
            let claims = (tokens?["id_token"] as? String).flatMap(decodeJWT)
            let auth = claims?["https://api.openai.com/auth"] as? [String: Any]
            let email = claims?["email"] as? String
            let orgs = auth?["organizations"] as? [[String: Any]] ?? []
            let org = (orgs.first { $0["is_default"] as? Bool == true } ?? orgs.first)?["title"] as? String
            let accountId = auth?["chatgpt_account_id"] as? String ?? email ?? "apikey:\(dir)"
            return AccountInfo(key: "codex:\(accountId)", provider: .codex, email: email ?? (json == nil ? nil : L("API 키", "API key")),
                               orgName: org, plan: auth?["chatgpt_plan_type"] as? String, configDir: dir)
        }
    }

    private static func cached(_ file: String, _ make: () -> AccountInfo) -> AccountInfo {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: file)[.modificationDate] as? Date) ?? .distantPast
        if let (t, info) = cache[file], t == mtime { return info }
        let info = make()
        cache[file] = (mtime, info)
        return info
    }

    private static func readJSON(_ path: String) -> [String: Any]? {
        guard let d = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private static func decodeJWT(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let d = Data(base64Encoded: b64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
}

/// Maps a working directory to the project it belongs to (git root, with worktrees folded into their repo).
enum ProjectResolver {
    private static var cache: [String: String] = [:]

    static func projectKey(for cwd: String) -> String {
        if let k = cache[cwd] { return k }
        let k = resolve(cwd)
        cache[cwd] = k
        return k
    }

    static func defaultName(for key: String) -> String {
        if key == ClaudeAppChatWatcher.projectKey { return L("Claude 채팅", "Claude chats") }
        return (key as NSString).lastPathComponent
    }

    private static func resolve(_ cwd: String) -> String {
        let fm = FileManager.default
        var url = URL(fileURLWithPath: cwd).standardizedFileURL
        while url.path != "/" {
            let git = url.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git.path, isDirectory: &isDir) {
                if isDir.boolValue { return url.path }
                // Worktree: ".git" is a file pointing at <repo>/.git/worktrees/<name>.
                if let text = try? String(contentsOf: git, encoding: .utf8),
                   let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) {
                    let gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                    if let r = gitdir.range(of: "/.git/worktrees/") {
                        return String(gitdir[..<r.lowerBound])
                    }
                }
                return url.path
            }
            url.deleteLastPathComponent()
        }
        return cwd
    }
}
