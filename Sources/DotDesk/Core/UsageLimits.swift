import Foundation

/// One plan usage window (5-hour, weekly, a model's weekly…) as the provider reports it.
struct LimitWindow: Equatable, Identifiable {
    let id: String
    var label: String
    /// Sort position: the session window first, then weekly ones.
    var order: Int
    /// 0...100.
    var percent: Double
    var resetsAt: Date?
    /// When the provider reported this value.
    var updatedAt: Date
    /// Came from a running agent (status line, rollout) rather than a cache file.
    var live: Bool

    func hasReset(_ now: Date = Date()) -> Bool { resetsAt.map { $0 <= now } ?? false }

    /// Used share to show: zero once the window has reset, until a new value comes in.
    func shownPercent(_ now: Date = Date()) -> Double { hasReset(now) ? 0 : percent }

    func isStale(_ now: Date = Date()) -> Bool { now.timeIntervalSince(updatedAt) > 15 * 60 }
}

/// Plan usage limits per account. Neither provider gives token counts, only how much of each window is used.
///
/// - Claude: the status line input (`rate_limits`, live while a CLI session runs, relayed by
///   dotdesk-statusline.sh) and `cachedUsageUtilization` in `.claude.json`, which Claude Code refreshes
///   when it looks the usage up. Tokens are never read.
/// - Codex: `rate_limits` on rollout `token_count` events.
@MainActor
final class UsageLimits: ObservableObject {
    static let shared = UsageLimits()

    /// Account key → windows by id.
    @Published private(set) var byAccount: [String: [String: LimitWindow]] = [:]

    private let settings = SettingsStore.shared
    private let queue = DispatchQueue(label: "DotDesk.UsageLimits", qos: .utility)
    private var timer: Timer?

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readFiles() }
        }
        readFiles()
    }

    /// Windows to show for an account, session window first.
    func windows(_ account: AccountInfo?) -> [LimitWindow] {
        guard let key = account?.key, let w = byAccount[key] else { return [] }
        return w.values.sorted { ($0.order, $0.label) < ($1.order, $1.label) }
    }

    /// Made-up windows for --render-preview.
    func usePreview(_ account: String, _ windows: [LimitWindow]) {
        byAccount[account] = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
    }

    /// Keeps whichever report of each window is newer, so a week-old cache never overwrites a live value.
    private func merge(_ account: String, _ windows: [LimitWindow]) {
        var cur = byAccount[account] ?? [:]
        var changed = false
        for w in windows where (cur[w.id]?.updatedAt ?? .distantPast) <= w.updatedAt {
            if cur[w.id] != w { cur[w.id] = w; changed = true }
        }
        if changed { byAccount[account] = cur }
    }

    // MARK: Claude

    /// Status line input from dotdesk-statusline.sh.
    func applyStatusLine(_ json: [String: Any], configDir: String?) {
        guard let rl = json["rate_limits"] as? [String: Any] else { return }
        let account = AccountResolver.resolve(provider: .claude, configDir: configDir)
        settings.rememberAccount(account)
        let now = Date()
        var out: [LimitWindow] = []
        for (id, (label, order)) in Self.claudeWindows {
            guard let w = rl[id] as? [String: Any], let pct = Self.number(w["used_percentage"]) else { continue }
            out.append(LimitWindow(id: id, label: label, order: order, percent: pct,
                                   resetsAt: Self.date(w["resets_at"]), updatedAt: now, live: true))
        }
        merge(account.key, out)
    }

    nonisolated private static var claudeWindows: [String: (String, Int)] {
        ["five_hour": (L("5시간", "5-hour"), 0), "seven_day": (L("주간", "Weekly"), 1),
         "seven_day_opus": (L("주간 · Opus", "Weekly · Opus"), 2), "seven_day_sonnet": (L("주간 · Sonnet", "Weekly · Sonnet"), 2)]
    }

    private func readFiles() {
        let claudeDirs = settings.s.claudeConfigDirs.map { Self.configDirArg($0, default: "/.claude") }
        let codexHomes = settings.s.codexHomes.map { Self.configDirArg($0, default: "/.codex") }
        queue.async {
            let claude = claudeDirs.compactMap { dir in Self.readClaudeCache(configDir: dir).map { (dir, $0) } }
            let codex = codexHomes.compactMap { home in Self.latestCodexLimits(home: home ?? NSHomeDirectory() + "/.codex").map { (home, $0) } }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for (dir, windows) in claude {
                        let account = AccountResolver.resolve(provider: .claude, configDir: dir)
                        self.merge(account.key, windows)
                    }
                    for (home, windows) in codex {
                        self.merge(AccountResolver.resolve(provider: .codex, configDir: home).key, windows)
                    }
                }
            }
        }
    }

    /// The default folder is passed as nil, the way an unset CLAUDE_CONFIG_DIR / CODEX_HOME reaches the hook.
    nonisolated private static func configDirArg(_ dir: String, default name: String) -> String? {
        let full = expandPath(dir)
        return full == NSHomeDirectory() + name ? nil : full
    }

    nonisolated private static func readClaudeCache(configDir: String?) -> [LimitWindow]? {
        let file = configDir.map { $0 + "/.claude.json" } ?? NSHomeDirectory() + "/.claude.json"
        guard let data = FileManager.default.contents(atPath: file),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cache = json["cachedUsageUtilization"] as? [String: Any],
              let u = cache["utilization"] as? [String: Any],
              let fetched = number(cache["fetchedAtMs"]) else { return nil }
        // Written for whoever was signed in at the time.
        let account = (json["oauthAccount"] as? [String: Any])?["accountUuid"] as? String
        if let a = cache["accountUuid"] as? String, a != account { return nil }
        let at = Date(timeIntervalSince1970: fetched / 1000)
        var out: [LimitWindow] = []
        if let limits = u["limits"] as? [[String: Any]], !limits.isEmpty {
            for l in limits {
                guard let pct = number(l["percent"]) else { continue }
                let model = (((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String)
                let (id, label, order): (String, String, Int)
                switch l["kind"] as? String {
                case "session": (id, label, order) = ("five_hour", L("5시간", "5-hour"), 0)
                case "weekly_all": (id, label, order) = ("seven_day", L("주간", "Weekly"), 1)
                case let kind?:
                    guard let model else { continue }
                    (id, label, order) = ("\(kind):\(model)", L("주간 · \(model)", "Weekly · \(model)"), 2)
                case nil: continue
                }
                out.append(LimitWindow(id: id, label: label, order: order, percent: pct, resetsAt: date(l["resets_at"]),
                                       updatedAt: at, live: false))
            }
        } else {
            for (id, (label, order)) in claudeWindows {
                guard let w = u[id] as? [String: Any], let pct = number(w["utilization"]) else { continue }
                out.append(LimitWindow(id: id, label: label, order: order, percent: pct, resetsAt: date(w["resets_at"]),
                                       updatedAt: at, live: false))
            }
        }
        return out
    }

    // MARK: Codex

    /// `rate_limits` from a rollout `token_count` event.
    func applyCodex(_ rateLimits: [String: Any], home: String, at: Date) {
        let windows = Self.codexWindows(rateLimits, at: at, live: true)
        guard !windows.isEmpty else { return }
        let account = AccountResolver.resolve(provider: .codex, configDir: Self.configDirArg(home, default: "/.codex"))
        merge(account.key, windows)
    }

    nonisolated private static func codexWindows(_ rl: [String: Any], at: Date, live: Bool) -> [LimitWindow] {
        let limit = rl["limit_id"] as? String
        let prefix = limit == nil || limit == "codex" ? "" : "\(limit!):"
        var out: [LimitWindow] = []
        for (slot, order) in [("primary", 0), ("secondary", 1)] {
            guard let w = rl[slot] as? [String: Any], let pct = number(w["used_percent"]) else { continue }
            let minutes = number(w["window_minutes"]).map(Int.init)
            var reset = date(w["resets_at"])
            if reset == nil, let secs = number(w["resets_in_seconds"]) { reset = at.addingTimeInterval(secs) }
            let name = minutes.map(windowName) ?? (slot == "primary" ? L("기본", "Primary") : L("보조", "Secondary"))
            let label = prefix.isEmpty ? name : "\(name) · \(rl["limit_name"] as? String ?? limit!)"
            out.append(LimitWindow(id: prefix + (minutes.map { "w\($0)" } ?? slot), label: label, order: order + (prefix.isEmpty ? 0 : 2),
                                   percent: pct, resetsAt: reset, updatedAt: at, live: live))
        }
        return out
    }

    /// "5시간", "주간", "30일".
    nonisolated private static func windowName(_ minutes: Int) -> String {
        if minutes == 7 * 1440 { return L("주간", "Weekly") }
        if minutes % 1440 == 0 { return L("\(minutes / 1440)일", "\(minutes / 1440)-day") }
        if minutes % 60 == 0 { return L("\(minutes / 60)시간", "\(minutes / 60)-hour") }
        return L("\(minutes)분", "\(minutes)-min")
    }

    /// The last report in the newest rollout, for an account no Codex session is running under right now.
    nonisolated private static func latestCodexLimits(home: String) -> [LimitWindow]? {
        let fm = FileManager.default
        func newest(_ dir: String) -> String? {
            (try? fm.contentsOfDirectory(atPath: dir))?.filter { !$0.hasPrefix(".") }.max()
        }
        let root = home + "/sessions"
        guard let y = newest(root), let m = newest("\(root)/\(y)"), let d = newest("\(root)/\(y)/\(m)") else { return nil }
        let dir = "\(root)/\(y)/\(m)/\(d)"
        let files = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl") }
        let path = files.max { a, b in mtime("\(dir)/\(a)") < mtime("\(dir)/\(b)") }.map { "\(dir)/\($0)" }
        guard let path, let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        guard let end = try? h.seekToEnd() else { return nil }
        try? h.seek(toOffset: end > 1 << 20 ? end - (1 << 20) : 0)
        guard let data = try? h.readToEnd() else { return nil }
        let marker = Data("\"rate_limits\"".utf8)
        for line in data.split(separator: 0x0A).reversed() where line.range(of: marker) != nil {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let p = obj["payload"] as? [String: Any], let rl = p["rate_limits"] as? [String: Any] else { continue }
            let at = (obj["timestamp"] as? String).flatMap(parseISO) ?? mtime(path)
            let w = codexWindows(rl, at: at, live: false)
            if !w.isEmpty { return w }
        }
        return nil
    }

    nonisolated private static func mtime(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
    }

    // MARK: Values

    nonisolated private static func number(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }

    /// Epoch seconds or an ISO 8601 string.
    nonisolated static func date(_ v: Any?) -> Date? {
        if let n = number(v) { return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
        return (v as? String).flatMap(parseISO)
    }

    nonisolated static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// "2시간 14분 뒤", "3일 5시간 뒤".
func formatResetIn(_ date: Date, now: Date = Date()) -> String {
    let mins = max(0, Int(date.timeIntervalSince(now) / 60))
    let (d, h, m) = (mins / 1440, mins % 1440 / 60, mins % 60)
    if d > 0 { return h > 0 ? L("\(d)일 \(h)시간 뒤", "in \(d)d \(h)h") : L("\(d)일 뒤", "in \(d)d") }
    if h > 0 { return m > 0 ? L("\(h)시간 \(m)분 뒤", "in \(h)h \(m)m") : L("\(h)시간 뒤", "in \(h)h") }
    return mins > 0 ? L("\(m)분 뒤", "in \(m)m") : L("곧", "soon")
}

/// "3시간 전", "2일 전".
func formatAgo(_ date: Date, now: Date = Date()) -> String {
    let mins = max(0, Int(now.timeIntervalSince(date) / 60))
    if mins >= 1440 { return L("\(mins / 1440)일 전", "\(mins / 1440)d ago") }
    if mins >= 60 { return L("\(mins / 60)시간 전", "\(mins / 60)h ago") }
    return L("\(max(1, mins))분 전", "\(max(1, mins))m ago")
}
