import Foundation
import Combine

/// Live state of every agent session DotDesk knows about, fed by hook events and Codex rollout files.
@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var sessions: [String: AgentSession] = [:]
    @Published private(set) var permissions: [PendingPermission] = []

    private let settings = SettingsStore.shared
    private var timer: Timer?

    static let nicknames = [
        "도토리", "모찌", "콩이", "보리", "호두", "두부", "라떼", "쿠키", "망고", "자두",
        "율무", "깨비", "솜이", "밤톨", "구름", "누룽지", "마루", "단추", "찹쌀", "초코",
    ]

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.maintain() }
        }
        loadWorkers()
    }

    /// Sessions with someone at their desk, which is every session on screen.
    var activeSessions: [AgentSession] {
        sessions.values.filter { $0.workerId != nil }
            .sorted { ($0.projectKey, $0.startedAt) < ($1.projectKey, $1.startedAt) }
    }

    // MARK: Display helpers

    func worker(_ s: AgentSession) -> Worker? {
        s.workerId.flatMap { settings.s.workers[$0] }
    }

    func nickname(_ s: AgentSession) -> String {
        guard let w = worker(s) else { return "에이전트" }
        return w.name.flatMap { $0.isEmpty ? nil : $0 } ?? w.autoNickname
    }

    func characterRef(_ s: AgentSession) -> String {
        worker(s)?.character
            ?? settings.s.projects[s.projectKey]?.character
            ?? worker(s)?.autoCharacter
            ?? "builtin:0"
    }

    /// Name and character for the worker at this session's desk; nil goes back to the automatic one.
    func customize(_ key: String, name: String?, character: String?) {
        guard let id = sessions[key]?.workerId else { return }
        settings.s.workers[id]?.name = name
        settings.s.workers[id]?.character = character
    }

    func setCharacter(_ key: String, _ ref: String?) {
        guard let id = sessions[key]?.workerId else { return }
        settings.s.workers[id]?.character = ref
    }

    func session(_ key: String) -> AgentSession? { sessions[key] }

    // MARK: Hook events

    func handleHook(_ req: HookRequest, responder: HookResponder) {
        let j = req.json
        let sid = j["session_id"] as? String ?? "unknown"
        let key = "\(req.provider.rawValue):\(sid)"
        let isNew = sessions[key] == nil
        var s = sessions[key] ?? makeSession(key: key, provider: req.provider, sessionId: sid, cwd: j["cwd"] as? String)
        s.viaHooks = true
        s.lastEventAt = Date()
        if var o = req.origin, o.pid != s.origin?.pid || o.tmuxPane != s.origin?.tmuxPane {
            WindowFocuser.resolve(&o)
            s.origin = o
        }
        if let cwd = j["cwd"] as? String, s.cwd == nil { updateCwd(&s, cwd) }
        if s.workerId == nil, req.event != "SessionEnd" { staff(&s, takeOver: isNew) }
        if let m = j["model"] as? String { s.model = m }
        if s.account == nil || req.event == "SessionStart" {
            let acc = AccountResolver.resolve(provider: req.provider, configDir: req.configDir)
            s.account = acc
            settings.rememberAccount(acc)
        }

        if let path = j["transcript_path"] as? String, !path.isEmpty, req.event != "SessionEnd" {
            UsageReader.shared.follow(sessionKey: key, path: path)
        }

        let agentId = j["agent_id"] as? String
        let agentType = j["agent_type"] as? String
        let toolName = j["tool_name"] as? String ?? ""
        let toolInput = j["tool_input"] as? [String: Any] ?? [:]
        var replyNow = true

        switch req.event {
        case "SessionStart":
            if s.activity == .leaving || s.activity == .sleeping || s.activity == .compacting { s.setActivity(.idle, detail: "") }
            s.addLog("세션 시작 (\(j["source"] as? String ?? "startup"))")
        case "UserPromptSubmit":
            var prompt = j["prompt"] as? String ?? ""
            if prompt.hasPrefix("<task-notification>") { prompt = "팀원 결과 확인" }
            s.setActivity(.thinking, detail: truncate(prompt, 40))
            s.doneUntil = nil
            if s.turnStartedAt == nil || !prompt.hasPrefix("팀원") { s.turnStartedAt = Date() }
            if !prompt.hasPrefix("팀원") { DailyStats.shared.recordPrompt(s) }
            s.addLog("요청: \(truncate(prompt, 60))")
        case "PreToolUse":
            let (a, d) = ActivityMapper.activity(forTool: toolName, input: toolInput)
            DailyStats.shared.recordTool(s, tool: toolName, input: toolInput)
            if let agentId, let i = s.subagents.firstIndex(where: { $0.id == agentId }) {
                s.subagents[i].activity = a
                s.subagents[i].detail = d
            } else {
                s.setActivity(a, detail: d)
            }
            s.addLog("\(a.label) · \(d)")
        case "PostToolUse", "PostToolUseFailure":
            if let agentId, let i = s.subagents.firstIndex(where: { $0.id == agentId }) {
                s.subagents[i].activity = .thinking
            } else if s.activity != .done {
                s.setActivity(.thinking)
            }
            if req.event == "PostToolUseFailure" { s.addLog("실패 · \(toolName)") }
            if agentId == nil, j["is_interrupt"] as? Bool != true {
                let failed = req.event == "PostToolUseFailure"
                let output = ActivityMapper.outputText(failed ? j["error"] : j["tool_response"])
                react(&s, command: ActivityMapper.shellCommand(tool: toolName, input: toolInput), failed: failed, output: output)
            }
        case "PermissionRequest":
            replyNow = false
            sessions[key] = s
            handlePermission(key: key, provider: req.provider, tool: toolName, input: toolInput,
                             agentType: agentType, responder: responder)
            return
        case "Notification":
            let type = j["notification_type"] as? String ?? ""
            let msg = j["message"] as? String ?? ""
            switch type {
            case "permission_prompt":
                s.setActivity(.waitingPermission, detail: truncate(msg, 40))
            case "agent_needs_input", "elicitation_dialog", "elicitation_url_dialog":
                s.setActivity(.waitingInput, detail: truncate(msg, 40))
            case "idle_prompt":
                if !s.activity.needsUser { s.setActivity(.idle, detail: "답장을 기다려요") }
            default:
                break
            }
            if !msg.isEmpty { s.addLog("알림 · \(truncate(msg, 60))") }
        case "Stop":
            s.setActivity(.done, detail: "")
            finishTurn(&s)
        case "Interrupt":
            s.setActivity(.idle, detail: "중단됨")
        case "SubagentStart":
            let id = agentId ?? UUID().uuidString
            if !s.subagents.contains(where: { $0.id == id }) {
                s.subagents.append(SubAgent(id: id, type: agentType ?? "subagent"))
            }
            s.addLog("팀원 합류 · \(agentType ?? "subagent")")
        case "SubagentStop":
            s.subagents.removeAll { $0.id == agentId }
            s.addLog("팀원 복귀 · \(agentType ?? "subagent")")
        case "PreCompact":
            let auto = (j["trigger"] as? String) == "auto"
            s.setActivity(.compacting, detail: auto ? "컨텍스트가 차서 정리 중" : "")
            s.addLog(auto ? "컨텍스트가 차서 대화를 정리해요" : "대화 정리")
        case "SessionEnd":
            s.setActivity(.leaving, detail: "")
            s.subagents.removeAll()
            s.addLog("세션 종료")
            UsageReader.shared.forget(key)
            release(s)
            dropPermissions(for: key)
        default:
            break
        }
        sessions[key] = s
        if replyNow { responder.reply() }
    }

    /// Long tasks earn a celebration.
    static let celebrateAfter: TimeInterval = 300

    /// Reacts to a finished tool call: a shake for failures, cheering when a test run passes.
    func react(_ s: inout AgentSession, command: String?, failed: Bool, output: String) {
        let isTest = command.map(ActivityMapper.isTestCommand) ?? false
        if isTest {
            let passed = !failed && !ActivityMapper.outputShowsTestFailure(output)
            DailyStats.shared.recordTest(s, passed: passed)
            if !passed {
                s.react(.testsFailed, for: 4)
                s.addLog("테스트 실패")
            } else {
                s.react(.testsPassed, for: 4)
                s.addLog("테스트 통과")
            }
        } else if failed {
            s.react(.oops, for: 2.5)
        }
    }

    /// The turn is over: done for a moment, longer and with confetti after a long task.
    func finishTurn(_ s: inout AgentSession) {
        let took = s.turnStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        s.turnStartedAt = nil
        DailyStats.shared.recordTurnDone(s, long: took >= Self.celebrateAfter)
        if took >= Self.celebrateAfter {
            s.react(.celebrate, for: 8)
            s.doneUntil = Date().addingTimeInterval(8)
            s.addLog("긴 작업 완료 (\(Int(took / 60))분)")
        } else {
            s.doneUntil = Date().addingTimeInterval(5)
            s.addLog("작업 완료")
        }
    }

    func setUsage(_ key: String, _ usage: ContextUsage) {
        guard let s = sessions[key], s.usage != usage else { return }
        // The first read of a transcript covers work from before DotDesk saw it; only count what comes after.
        if let before = s.usage?.outputTokens { DailyStats.shared.recordOutput(s, tokens: usage.outputTokens - before) }
        sessions[key]?.usage = usage
    }

    /// Activity reported from a Codex rollout file. Ignored once that session reports through hooks.
    func applyRollout(sessionId: String, cwd: String?, home: String, update: (inout AgentSession) -> Void) {
        let key = "codex:\(sessionId)"
        let isNew = sessions[key] == nil
        var s = sessions[key] ?? makeSession(key: key, provider: .codex, sessionId: sessionId, cwd: cwd)
        if s.viaHooks { return }
        if s.cwd == nil, let cwd { updateCwd(&s, cwd) }
        if s.account == nil {
            let acc = AccountResolver.resolve(provider: .codex, configDir: home == NSHomeDirectory() + "/.codex" ? nil : home)
            s.account = acc
            settings.rememberAccount(acc)
        }
        s.lastEventAt = Date()
        update(&s)
        if s.workerId == nil, s.activity != .leaving { staff(&s, takeOver: isNew) }
        sessions[key] = s
    }

    private func makeSession(key: String, provider: Provider, sessionId: String, cwd: String?) -> AgentSession {
        let project = cwd.map(ProjectResolver.projectKey) ?? "(unknown)"
        let s = AgentSession(id: key, provider: provider, sessionId: sessionId, cwd: cwd, projectKey: project)
        if cwd != nil { settings.touchProject(project) }
        return s
    }

    private func updateCwd(_ s: inout AgentSession, _ cwd: String) {
        s.cwd = cwd
        s.projectKey = ProjectResolver.projectKey(for: cwd)
        settings.touchProject(s.projectKey)
        // Someone hired before the folder was known belongs to this project now.
        if let id = s.workerId {
            settings.s.workers[id]?.projectKey = s.projectKey
            settings.s.workers[id]?.cwd = cwd
        }
    }

    // MARK: Workers

    /// Moves per-session customizations from older versions into workers and drops workers unseen for 30 days.
    private func loadWorkers() {
        var workers = settings.s.workers
        for (key, o) in settings.s.sessions where workers[key] == nil && (o.name != nil || o.character != nil) {
            workers[key] = Worker(id: key, projectKey: "", name: o.name, character: o.character, sessionKey: key, lastSeen: o.lastSeen)
        }
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        workers = workers.filter { $0.value.lastSeen > cutoff && !$0.key.contains(":demo-") }
        for id in workers.keys {
            workers[id]?.autoNickname = ""
            workers[id]?.autoCharacter = ""
        }
        settings.s.workers = workers
        settings.s.sessions = [:]
    }

    /// Puts someone at the session's desk: whoever worked for it before a relaunch, else a free worker of the project
    /// (one from the same folder first, which keeps the same face across /clear). A new session may also take over a
    /// resting session's worker, leaving that session off screen until it works again. Otherwise someone new is hired.
    private func staff(_ s: inout AgentSession, takeOver: Bool) {
        let key = s.id, cwd = s.cwd
        let holders = Dictionary(sessions.values.filter { $0.id != key }.compactMap { o in o.workerId.map { ($0, o) } },
                                 uniquingKeysWith: { a, _ in a })
        let project = settings.s.workers.values.filter {
            $0.projectKey == s.projectKey || ($0.projectKey.isEmpty && $0.sessionKey == key)
        }
        // Nobody works with them, or their session is on its way out.
        let free = project.filter { holders[$0.id].map { $0.activity == .leaving } ?? true }
        var pick = free.first { $0.sessionKey == key }
            ?? free.max { ($0.cwd == cwd ? 1 : 0, $0.lastSeen) < ($1.cwd == cwd ? 1 : 0, $1.lastSeen) }
        if pick == nil, takeOver {
            let resting = project.compactMap { w in holders[w.id].map { (w, $0) } }.filter { _, h in
                h.activity == .sleeping && !permissions.contains { $0.sessionKey == h.id }
            }
            pick = resting.min { $0.1.lastEventAt < $1.1.lastEventAt }?.0
        }
        var w = pick ?? hire(for: s)
        if let h = holders[w.id] {
            sessions[h.id]?.workerId = nil
            if h.activity != .leaving { sessions[h.id]?.addLog("\(withSubjectParticle(nickname(h))) 새 세션을 맡으러 갔어요") }
        }
        if w.autoCharacter.isEmpty || w.autoNickname.isEmpty { pickLook(&w) }
        let continued = w.sessionKey != nil && w.sessionKey != key
        w.projectKey = s.projectKey
        w.sessionKey = key
        if let cwd { w.cwd = cwd }
        w.lastSeen = Date()
        settings.s.workers[w.id] = w
        s.workerId = w.id
        if continued { s.addLog("\(withSubjectParticle(nickname(s))) 이어서 맡았어요") }
    }

    private func hire(for s: AgentSession) -> Worker {
        var id = s.id
        if settings.s.workers[id] != nil { id += "#" + UUID().uuidString.prefix(8) }
        return Worker(id: id, projectKey: s.projectKey)
    }

    /// Automatic name and look, avoiding ones already on screen.
    private func pickLook(_ w: inout Worker) {
        let others = sessions.values.compactMap(\.workerId).filter { $0 != w.id }.compactMap { settings.s.workers[$0] }
        if w.autoCharacter.isEmpty {
            w.autoCharacter = SpriteLibrary.shared.autoCharacter(seed: w.id, avoiding: Set(others.map(\.autoCharacter)))
        }
        if w.autoNickname.isEmpty {
            let used = Set(others.map(\.autoNickname))
            let names = Self.nicknames
            let start = Int(stableHash(w.id) % UInt64(names.count))
            w.autoNickname = (0..<names.count).map { names[(start + $0) % names.count] }.first { !used.contains($0) }
                ?? names[start]
        }
    }

    /// The session is done, so its worker is free for the next one in the project.
    private func release(_ s: AgentSession) {
        guard let id = s.workerId else { return }
        settings.s.workers[id]?.lastSeen = Date()
    }

    // MARK: Permissions

    private func handlePermission(key: String, provider: Provider, tool: String, input: [String: Any],
                                  agentType: String?, responder: HookResponder) {
        guard var s = sessions[key] else { responder.reply(); return }
        let summary = ActivityMapper.permissionSummary(tool: tool, input: input)
        var mode = settings.permissionMode(forProject: s.projectKey)
        if s.autoAllowThisSession { mode = .autoAllow }

        var reason: String?
        if mode == .autoAllow, settings.s.permissions.askForDangerous,
           let cmd = ActivityMapper.shellCommand(tool: tool, input: input)?.lowercased(),
           let hit = settings.s.permissions.dangerousPatterns.first(where: { !$0.isEmpty && cmd.contains($0.lowercased()) }) {
            mode = .bubble
            reason = "위험할 수 있는 명령(\(hit))이라 확인이 필요해요"
        }

        switch mode {
        case .autoAllow:
            s.addLog("자동 허용 · \(truncate(summary, 50))")
            sessions[key] = s
            responder.reply(Self.permissionBody(provider: provider, .allow))
        case .passthrough:
            s.setActivity(.waitingPermission, detail: truncate(summary, 40))
            sessions[key] = s
            responder.reply()
        case .bubble:
            s.setActivity(.waitingPermission, detail: truncate(summary, 40))
            sessions[key] = s
            let p = PendingPermission(sessionKey: key, provider: provider, toolName: tool, summary: summary,
                                      agentType: agentType, timeout: settings.s.permissions.bubbleTimeout,
                                      reason: reason) { decision in
                responder.reply(Self.permissionBody(provider: provider, decision))
            }
            responder.onAbandoned = { [weak self, weak p] in
                guard let self, let p else { return }
                p.resolve(.passthrough)
                self.permissions.removeAll { $0 === p }
            }
            permissions.append(p)
        }
    }

    func resolve(_ p: PendingPermission, _ decision: PermissionDecision, allowSession: Bool = false) {
        p.resolve(decision)
        permissions.removeAll { $0 === p }
        guard var s = sessions[p.sessionKey] else { return }
        switch decision {
        case .allow:
            s.addLog("허용 · \(truncate(p.summary, 50))")
            s.setActivity(.thinking)
        case .deny:
            s.addLog("거부 · \(truncate(p.summary, 50))")
            s.setActivity(.thinking)
        case .passthrough:
            break
        }
        if allowSession {
            s.autoAllowThisSession = true
            s.addLog("이 세션은 자동 허용으로 전환")
        }
        sessions[p.sessionKey] = s
        if allowSession {
            for other in permissions where other.sessionKey == p.sessionKey { resolve(other, .allow) }
        }
    }

    func setAutoAllow(_ key: String, _ on: Bool) {
        sessions[key]?.autoAllowThisSession = on
    }

    private func dropPermissions(for key: String) {
        for p in permissions where p.sessionKey == key { p.resolve(.passthrough) }
        permissions.removeAll { $0.sessionKey == key }
    }

    func releaseAllPermissions() {
        for p in permissions { p.resolve(.passthrough) }
        permissions.removeAll()
    }

    static func permissionBody(provider: Provider, _ d: PermissionDecision) -> Data {
        let decision: [String: Any]
        switch d {
        case .passthrough: return Data()
        case .allow: decision = ["behavior": "allow"]
        case .deny(let msg): decision = ["behavior": "deny", "message": msg ?? "DotDesk에서 사용자가 거부했어요."]
        }
        let obj: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    // MARK: Housekeeping

    private func maintain() {
        let now = Date()
        for p in permissions where now > p.deadline {
            p.resolve(.passthrough)
            sessions[p.sessionKey]?.addLog("응답 시간이 지나 에이전트 창으로 넘겼어요")
        }
        permissions.removeAll { $0.resolved }

        let sleepAfter = settings.s.sleepAfterMinutes * 60
        let forgetAfter = settings.s.forgetAfterMinutes * 60
        for (key, var s) in sessions {
            let quiet = now.timeIntervalSince(s.lastEventAt)
            var changed = false
            if s.activity == .done, let until = s.doneUntil, now > until {
                s.setActivity(.idle, detail: "답장을 기다려요")
                s.doneUntil = nil
                changed = true
            }
            if s.activity == .leaving, quiet > 6 {
                sessions.removeValue(forKey: key)
                continue
            }
            if quiet > forgetAfter {
                s.setActivity(.leaving)
                s.lastEventAt = now
                release(s)
                changed = true
            } else if quiet > (s.activity.isWorking ? max(sleepAfter * 3, 900) : sleepAfter),
                      s.activity != .sleeping, s.activity != .leaving,
                      !permissions.contains(where: { $0.sessionKey == key }) {
                // Hooks can be missed (agent crashed, hooks not installed for a tool); don't keep "working" forever.
                s.setActivity(.sleeping, detail: "")
                s.subagents.removeAll()
                changed = true
            }
            if changed { sessions[key] = s }
        }
    }

    // MARK: Demo

    private var demoTimer: Timer?

    func toggleDemo() {
        if let t = demoTimer {
            t.invalidate()
            demoTimer = nil
            for key in sessions.keys where key.hasPrefix("claude:demo-") || key.hasPrefix("codex:demo-") {
                sessions[key]?.setActivity(.leaving)
                sessions[key]?.lastEventAt = Date()
                if let s = sessions[key] { release(s) }
            }
            return
        }
        let demos: [(Provider, String, String)] = [
            (.claude, "demo-1", "/tmp/dotdesk-demo/web-app"),
            (.claude, "demo-2", "/tmp/dotdesk-demo/web-app"),
            (.codex, "demo-3", "/tmp/dotdesk-demo/api-server"),
            (.claude, "demo-4", "/tmp/dotdesk-demo/api-server"),
        ]
        for (p, id, cwd) in demos {
            let key = "\(p.rawValue):\(id)"
            var s = makeSession(key: key, provider: p, sessionId: id, cwd: nil)
            s.cwd = cwd
            s.projectKey = cwd
            s.account = AccountInfo(key: "demo:\(p.rawValue)", provider: p, email: "demo@example.com",
                                    orgName: p == .claude ? "Demo Org" : nil, plan: nil, configDir: "~")
            staff(&s, takeOver: false)
            sessions[key] = s
        }
        demoTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.demoStep() }
        }
    }

    /// Starts another demo session, staffed like a real new one (used by --render-preview).
    func demoJoin(_ id: String, cwd: String) {
        let key = "claude:\(id)"
        var s = makeSession(key: key, provider: .claude, sessionId: id, cwd: nil)
        s.cwd = cwd
        s.projectKey = cwd
        staff(&s, takeOver: true)
        sessions[key] = s
    }

    func demoRemove(_ id: String) {
        sessions.removeValue(forKey: "claude:\(id)")
    }

    private var demoStepIndex = 0

    func demoStep() {
        let script: [(Activity, String)] = [
            (.thinking, ""), (.reading, "App.swift"), (.searching, "TODO"), (.typing, "OfficeView.swift"),
            (.running, "swift build"), (.browsing, "developer.apple.com"), (.delegating, "Explore"),
            (.planning, "할 일 정리"), (.done, ""), (.idle, "답장을 기다려요"), (.waitingInput, "어떤 색이 좋을까요?"),
        ]
        for (i, key) in ["claude:demo-1", "claude:demo-2", "codex:demo-3", "claude:demo-4"].enumerated() {
            guard var s = sessions[key] else { continue }
            let (a, d) = script[(demoStepIndex + i * 3) % script.count]
            s.setActivity(a, detail: d)
            if s.workerId == nil { staff(&s, takeOver: false) }
            s.lastEventAt = Date()
            if a == .done { s.doneUntil = Date().addingTimeInterval(2) }
            if a == .delegating, s.subagents.isEmpty {
                s.subagents = [SubAgent(id: "sub-\(i)", type: "Explore", activity: .searching, detail: "*.swift")]
            } else if a != .delegating {
                s.subagents.removeAll()
            }
            s.addLog("\(a.label) \(d)")
            sessions[key] = s
        }
        demoStepIndex += 1
    }

    /// Puts the given demo sessions to sleep (used by --render-preview to show the lounge).
    func demoSleep(_ keys: [String]) {
        for key in keys {
            guard var s = sessions[key] else { continue }
            s.setActivity(.sleeping, detail: "")
            s.subagents.removeAll()
            sessions[key] = s
        }
    }

    var demoRunning: Bool { demoTimer != nil }
}
