import Foundation

/// Follows Kiro agent sessions (~/.kiro/sessions/<workspace>/sess_*/messages.jsonl), written by the Kiro IDE
/// and kiro-cli alike. Kiro has no hooks DotDesk can install for every workspace, so this is read-only:
/// it shows what the agent does but can't answer permission requests.
@MainActor
final class KiroSessionWatcher {
    private struct Tail {
        let sessionId: String
        var cwd: String?
        var offset: UInt64 = 0
        var partial = Data()
        /// Shell commands by tool call id, to tell test runs apart when their result arrives.
        var commands: [String: String] = [:]
        /// What each tool call looked like, to go back to it once its approval is answered.
        var tools: [String: (Activity, String)] = [:]
        var caughtUp = false
        var leaseModified: Date?
    }

    private var tails: [String: Tail] = [:]
    private var timer: Timer?
    private let store = SessionStore.shared
    private let settings = SettingsStore.shared

    /// Kiro's bundle id, for when the session lease no longer leads to a running process.
    static let appBundleId = "dev.kiro.desktop"

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard settings.s.watchKiroSessions else { return }
        let fm = FileManager.default
        let now = Date()
        let home = expandPath(settings.s.kiroHome)
        let root = home + "/sessions"
        guard let workspaces = try? fm.contentsOfDirectory(atPath: root) else { return }
        for ws in workspaces where !ws.hasPrefix(".") {
            guard let items = try? fm.contentsOfDirectory(atPath: root + "/" + ws) else { continue }
            for item in items where item.hasPrefix("sess_") {
                let dir = root + "/" + ws + "/" + item
                let path = dir + "/messages.jsonl"
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let mtime = attrs[.modificationDate] as? Date,
                      let size = attrs[.size] as? UInt64 else { continue }
                if tails[path] == nil {
                    // Only pick up sessions that are live right now.
                    guard now.timeIntervalSince(mtime) < 120 else { continue }
                    tails[path] = Self.openTail(dir: dir, fallbackId: item)
                }
                if size < tails[path]!.offset { tails[path] = Self.openTail(dir: dir, fallbackId: item) }  // Rewritten.
                if size > tails[path]!.offset { read(path, home: home, upTo: size) }
            }
        }
        // Forget files that went quiet long ago.
        tails = tails.filter { path, _ in
            let m = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
            return now.timeIntervalSince(m) < 6 * 3600
        }
    }

    /// session.json names the session and the folders it works in.
    private static func openTail(dir: String, fallbackId: String) -> Tail {
        let meta = (try? Data(contentsOf: URL(fileURLWithPath: dir + "/session.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let id = meta["id"] as? String ?? fallbackId
        let cwd = (meta["workspacePaths"] as? [String])?.first ?? (meta["rootPaths"] as? [String])?.first
        return Tail(sessionId: id, cwd: cwd)
    }

    private func read(_ path: String, home: String, upTo size: UInt64) {
        guard var t = tails[path], let h = FileHandle(forReadingAtPath: path) else { return }
        defer { try? h.close() }
        try? h.seek(toOffset: t.offset)
        let data = h.readData(ofLength: Int(size - t.offset))
        t.offset += UInt64(data.count)
        var buf = t.partial + data
        var lines: [Data] = []
        while let nl = buf.firstIndex(of: 0x0A) {
            lines.append(buf[buf.startIndex..<nl])
            buf = Data(buf[buf.index(after: nl)...])
        }
        t.partial = buf
        // The first read replays the session so far; don't count that work as today's.
        let catchingUp = !t.caughtUp
        DailyStats.shared.paused = catchingUp
        defer { DailyStats.shared.paused = false }
        for line in lines {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(obj, tail: &t, home: home)
        }
        t.caughtUp = true
        let origin = leaseOrigin(home: home, tail: &t)
        store.applyRollout(provider: .kiro, sessionId: t.sessionId, cwd: t.cwd, home: home) { s in
            if let origin { s.origin = origin }
        }
        tails[path] = t
    }

    /// The session lease names the process running the agent (a Kiro helper, or kiro-cli in a terminal),
    /// which leads to the window to bring forward. Re-read only when the lease changes.
    private func leaseOrigin(home: String, tail t: inout Tail) -> SessionOrigin? {
        let path = home + "/session-leases/\(t.sessionId).lease"
        guard let mtime = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
              mtime != t.leaseModified else { return nil }
        t.leaseModified = mtime
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let lease = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var o = SessionOrigin(pid: (lease["pid"] as? NSNumber)?.int32Value ?? 0)
        if o.pid ?? 0 <= 1 { o.pid = nil }
        WindowFocuser.resolve(&o)
        if o.appPid == nil, (lease["clientName"] as? String) == "kiro-ide" { o.appBundleId = Self.appBundleId }
        return o.pid == nil && o.appBundleId == nil ? nil : o
    }

    private static let exitPattern = try! NSRegularExpression(pattern: #"Exit Code:\s*(-?\d+)"#, options: .caseInsensitive)

    private static func exitCode(_ text: String) -> Int? {
        guard let m = exitPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return Int(text[r])
    }

    private func handle(_ obj: [String: Any], tail t: inout Tail, home: String) {
        guard let p = obj["payload"] as? [String: Any], let type = p["type"] as? String else { return }

        var change: ((inout AgentSession) -> Void)?
        switch type {
        case "user":
            let msg = p["content"] as? String ?? ""
            change = { s in
                DailyStats.shared.recordPrompt(s)
                s.setActivity(.thinking, detail: truncate(msg, 40))
                if s.turnStartedAt == nil { s.turnStartedAt = Date() }
                if !msg.isEmpty { s.addLog(L("요청: \(truncate(msg, 60))", "Request: \(truncate(msg, 60))")) }
            }
        case "turn_start":
            change = { s in
                if s.activity == .done || s.activity == .idle || s.activity == .sleeping { s.setActivity(.thinking) }
                s.turnStartedAt = Date()
            }
        case "tool_call":
            let name = p["toolName"] as? String ?? "tool"
            let input = p["args"] as? [String: Any] ?? [:]
            let id = p["toolCallId"] as? String
            let (a, d) = ActivityMapper.activity(forTool: name, input: input)
            if let id {
                if let cmd = ActivityMapper.shellCommand(tool: name, input: input) { t.commands[id] = cmd }
                t.tools[id] = (a, d)
                if t.tools.count > 200 { t.tools.removeAll(); t.commands.removeAll() }
            }
            change = { s in
                DailyStats.shared.recordTool(s, tool: name, input: input)
                s.setActivity(a, detail: d)
                s.addLog("\(a.label) · \(d)")
            }
        case "pending_interaction":
            let approval = p["interactionType"] as? String == "tool_approval"
            let question = truncate(p["question"] as? String ?? "", 40)
            change = { s in s.setActivity(approval ? .waitingPermission : .waitingInput, detail: question) }
        case "interaction_resolved":
            let back = (p["modelToolUseId"] as? String).flatMap { t.tools[$0] }
            change = { s in
                guard s.activity == .waitingPermission || s.activity == .waitingInput else { return }
                if let back { s.setActivity(back.0, detail: back.1) } else { s.setActivity(.thinking) }
            }
        case "tool_result":
            let id = p["toolCallId"] as? String
            let output = p["content"] as? String ?? ""
            let command = id.flatMap { t.commands.removeValue(forKey: $0) }
            if let id { t.tools[id] = nil }
            let status = p["status"] as? String
            let failed = status == "failed" || (status != "denied" && (Self.exitCode(output).map { $0 != 0 } ?? false))
            change = { [store] s in
                if s.activity != .done { s.setActivity(.thinking) }
                if status == "denied" { s.addLog(L("거부됨", "Denied")); return }
                if command != nil || failed { store.react(&s, command: command, failed: failed, output: output) }
            }
        case "turn_end":
            let cancelled = p["stopReason"] as? String == "cancelled"
            change = { [store] s in
                if cancelled {
                    s.turnStartedAt = nil
                    s.setActivity(.idle, detail: L("중단됨", "Interrupted"))
                } else {
                    s.setActivity(.done, detail: "")
                    store.finishTurn(&s)
                }
            }
        default:
            break
        }
        if let change {
            store.applyRollout(provider: .kiro, sessionId: t.sessionId, cwd: t.cwd, home: home, update: change)
        }
    }
}
