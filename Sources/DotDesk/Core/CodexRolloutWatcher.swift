import Foundation

/// Follows Codex session rollouts ($CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl).
/// Works without hooks (Codex asks the user to trust new hooks via /hooks), at the cost of no permission control.
@MainActor
final class CodexRolloutWatcher {
    private struct Tail {
        var offset: UInt64
        var sessionId: String?
        var cwd: String?
        var partial = Data()
        /// Shell commands by call id, to tell test runs apart when their output arrives.
        var commands: [String: String] = [:]
    }

    private var tails: [String: Tail] = [:]
    private var timer: Timer?
    private let store = SessionStore.shared
    private let settings = SettingsStore.shared

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
        guard settings.s.watchCodexRollouts else { return }
        let fm = FileManager.default
        let now = Date()
        let cal = Calendar.current
        for home in settings.s.codexHomes.map(expandPath) {
            // Today and yesterday cover sessions that run past midnight.
            for dayOffset in [0, -1] {
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                let c = cal.dateComponents([.year, .month, .day], from: day)
                let dir = String(format: "%@/sessions/%04d/%02d/%02d", home, c.year!, c.month!, c.day!)
                guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for f in files where f.hasPrefix("rollout-") && f.hasSuffix(".jsonl") {
                    let path = dir + "/" + f
                    guard let attrs = try? fm.attributesOfItem(atPath: path),
                          let mtime = attrs[.modificationDate] as? Date,
                          let size = attrs[.size] as? UInt64 else { continue }
                    if tails[path] == nil {
                        // Only pick up sessions that are live right now.
                        guard now.timeIntervalSince(mtime) < 120 else { continue }
                        tails[path] = Tail(offset: 0)
                    }
                    if size > tails[path]!.offset { read(path, home: home, upTo: size) }
                }
            }
        }
        // Forget files that went quiet long ago.
        tails = tails.filter { path, _ in
            let m = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
            return now.timeIntervalSince(m) < 6 * 3600
        }
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
        let catchingUp = t.sessionId == nil
        DailyStats.shared.paused = catchingUp
        defer { DailyStats.shared.paused = false }
        for line in lines {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(obj, tail: &t, home: home)
        }
        if catchingUp, let sid = t.sessionId {
            store.applyRollout(sessionId: sid, cwd: t.cwd, home: home) { _ in }
        }
        if let sid = t.sessionId { UsageReader.shared.follow(sessionKey: "codex:\(sid)", path: path) }
        tails[path] = t
    }

    /// Output may be a plain string, a JSON string with `output`/`metadata`, or a list of text parts.
    private static func outputText(_ v: Any?) -> String {
        if let s = v as? String {
            if let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                var text = o["output"] as? String ?? ""
                if let code = (o["metadata"] as? [String: Any])?["exit_code"] as? Int { text = "Exit code: \(code)\n" + text }
                return text
            }
            return s
        }
        if let parts = v as? [[String: Any]] { return parts.compactMap { $0["text"] as? String }.joined(separator: "\n") }
        return ""
    }

    private static let exitPattern = try! NSRegularExpression(pattern: #"(?:Exit code:|exited with code)\s*(-?\d+)"#)

    private static func exitCode(_ text: String) -> Int? {
        guard let m = exitPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return Int(text[r])
    }

    private func handle(_ obj: [String: Any], tail t: inout Tail, home: String) {
        let type = obj["type"] as? String
        let p = obj["payload"] as? [String: Any] ?? [:]
        if type == "session_meta" {
            t.sessionId = p["id"] as? String ?? p["session_id"] as? String
            t.cwd = p["cwd"] as? String
            return
        }
        if type == "turn_context", let cwd = p["cwd"] as? String { t.cwd = cwd }
        guard let sid = t.sessionId else { return }
        let ptype = p["type"] as? String ?? ""

        var change: ((inout AgentSession) -> Void)?
        switch (type, ptype) {
        case ("event_msg", "task_started"), ("event_msg", "user_message"):
            let msg = p["message"] as? String ?? ""
            let starts = ptype == "task_started"
            change = { s in
                if !starts { DailyStats.shared.recordPrompt(s) }
                s.setActivity(.thinking, detail: truncate(msg, 40))
                if starts || s.turnStartedAt == nil { s.turnStartedAt = Date() }
                if !msg.isEmpty { s.addLog(L("요청: \(truncate(msg, 60))", "Request: \(truncate(msg, 60))")) }
            }
        case ("event_msg", "task_complete"):
            change = { [store] s in
                s.setActivity(.done, detail: "")
                store.finishTurn(&s)
            }
        case ("event_msg", "token_count"):
            if let rl = p["rate_limits"] as? [String: Any] {
                let at = (obj["timestamp"] as? String).flatMap(UsageLimits.parseISO) ?? Date()
                UsageLimits.shared.applyCodex(rl, home: home, at: at)
            }
        case ("event_msg", "turn_aborted"):
            change = { s in s.setActivity(.idle, detail: L("중단됨", "Interrupted")) }
        case ("event_msg", let e) where e.contains("approval_request"):
            change = { s in s.setActivity(.waitingPermission, detail: "") }
        case ("response_item", "function_call"), ("response_item", "custom_tool_call"), ("response_item", "local_shell_call"):
            let name = p["name"] as? String ?? (ptype == "local_shell_call" ? "shell" : "tool")
            var input: [String: Any] = [:]
            if let args = p["arguments"] as? String, let d = args.data(using: .utf8),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                input = o
            } else if let raw = p["input"] as? String {
                input = ["command": raw]
            } else if let action = p["action"] as? [String: Any] {
                input = action
            }
            if let id = p["call_id"] as? String, let cmd = ActivityMapper.shellCommand(tool: name, input: input) {
                t.commands[id] = cmd
                if t.commands.count > 200 { t.commands.removeAll() }
            }
            let (a, d) = ActivityMapper.activity(forTool: name, input: input)
            let message = name == "send_input" ? AgentMessage(sessionKey: "codex:\(sid)", fromSub: nil, to: input["id"] as? String) : nil
            let spawns = name == "spawn_agent"
            change = { [store] s in
                DailyStats.shared.recordTool(s, tool: name, input: input)
                if let message, !DailyStats.shared.paused { store.messages.send(message) }
                if spawns, s.activeReaction == nil { s.react(.briefing, for: 3) }
                s.setActivity(a, detail: d)
                s.addLog("\(a.label) · \(d)")
            }
        case ("response_item", "web_search_call"):
            change = { s in s.setActivity(.browsing, detail: L("웹 검색", "Web search")) }
        case ("response_item", "function_call_output"), ("response_item", "custom_tool_call_output"):
            let output = Self.outputText(p["output"])
            let command = (p["call_id"] as? String).flatMap { t.commands.removeValue(forKey: $0) }
            let failed = Self.exitCode(output).map { $0 != 0 } ?? false
            change = { [store] s in
                if s.activity != .done { s.setActivity(.thinking) }
                if command != nil || failed { store.react(&s, command: command, failed: failed, output: output) }
            }
        default:
            break
        }
        if let change {
            store.applyRollout(sessionId: sid, cwd: t.cwd, home: home, update: change)
        }
    }
}
