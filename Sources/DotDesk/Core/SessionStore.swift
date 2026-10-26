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
    }

    var activeSessions: [AgentSession] {
        sessions.values.sorted { ($0.projectKey, $0.startedAt) < ($1.projectKey, $1.startedAt) }
    }

    // MARK: Display helpers

    func nickname(_ s: AgentSession) -> String {
        settings.s.sessions[s.id]?.name.flatMap { $0.isEmpty ? nil : $0 } ?? s.autoNickname
    }

    func characterRef(_ s: AgentSession) -> String {
        settings.s.sessions[s.id]?.character
            ?? settings.s.projects[s.projectKey]?.character
            ?? s.autoCharacter
    }

    func session(_ key: String) -> AgentSession? { sessions[key] }

    // MARK: Hook events

    func handleHook(_ req: HookRequest, responder: HookResponder) {
        let j = req.json
        let sid = j["session_id"] as? String ?? "unknown"
        let key = "\(req.provider.rawValue):\(sid)"
        var s = sessions[key] ?? makeSession(key: key, provider: req.provider, sessionId: sid, cwd: j["cwd"] as? String)
        s.viaHooks = true
        s.lastEventAt = Date()
        if let cwd = j["cwd"] as? String, s.cwd == nil { updateCwd(&s, cwd) }
        if let m = j["model"] as? String { s.model = m }
        if s.account == nil || req.event == "SessionStart" {
            let acc = AccountResolver.resolve(provider: req.provider, configDir: req.configDir)
            s.account = acc
            settings.rememberAccount(acc)
        }

        let agentId = j["agent_id"] as? String
        let agentType = j["agent_type"] as? String
        let toolName = j["tool_name"] as? String ?? ""
        let toolInput = j["tool_input"] as? [String: Any] ?? [:]
        var replyNow = true

        switch req.event {
        case "SessionStart":
            if s.activity == .leaving || s.activity == .sleeping { s.setActivity(.idle) }
            s.addLog("세션 시작 (\(j["source"] as? String ?? "startup"))")
        case "UserPromptSubmit":
            var prompt = j["prompt"] as? String ?? ""
            if prompt.hasPrefix("<task-notification>") { prompt = "팀원 결과 확인" }
            s.setActivity(.thinking, detail: truncate(prompt, 40))
            s.doneUntil = nil
            s.addLog("요청: \(truncate(prompt, 60))")
        case "PreToolUse":
            let (a, d) = ActivityMapper.activity(forTool: toolName, input: toolInput)
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
            s.doneUntil = Date().addingTimeInterval(5)
            s.addLog("작업 완료")
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
            s.setActivity(.thinking, detail: "대화 정리 중")
        case "SessionEnd":
            s.setActivity(.leaving, detail: "")
            s.subagents.removeAll()
            s.addLog("세션 종료")
            dropPermissions(for: key)
        default:
            break
        }
        sessions[key] = s
        if replyNow { responder.reply() }
    }

    /// Activity reported from a Codex rollout file. Ignored once that session reports through hooks.
    func applyRollout(sessionId: String, cwd: String?, home: String, update: (inout AgentSession) -> Void) {
        let key = "codex:\(sessionId)"
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
        sessions[key] = s
    }

    private func makeSession(key: String, provider: Provider, sessionId: String, cwd: String?) -> AgentSession {
        let project = cwd.map(ProjectResolver.projectKey) ?? "(unknown)"
        var s = AgentSession(id: key, provider: provider, sessionId: sessionId, cwd: cwd, projectKey: project)
        let used = Set(sessions.values.map(\.autoCharacter))
        s.autoCharacter = SpriteLibrary.shared.autoCharacter(seed: key, avoiding: used)
        let usedNames = Set(sessions.values.map(\.autoNickname))
        let names = Self.nicknames
        let start = Int(stableHash(key) % UInt64(names.count))
        s.autoNickname = (0..<names.count).map { names[(start + $0) % names.count] }.first { !usedNames.contains($0) }
            ?? names[start]
        if cwd != nil { settings.touchProject(project) }
        return s
    }

    private func updateCwd(_ s: inout AgentSession, _ cwd: String) {
        s.cwd = cwd
        s.projectKey = ProjectResolver.projectKey(for: cwd)
        settings.touchProject(s.projectKey)
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
            }
            return
        }
        let demos: [(Provider, String, String)] = [
            (.claude, "demo-1", "/tmp/dotdesk-demo/web-app"),
            (.claude, "demo-2", "/tmp/dotdesk-demo/web-app"),
            (.codex, "demo-3", "/tmp/dotdesk-demo/api-server"),
        ]
        for (p, id, cwd) in demos {
            let key = "\(p.rawValue):\(id)"
            var s = makeSession(key: key, provider: p, sessionId: id, cwd: nil)
            s.cwd = cwd
            s.projectKey = cwd
            s.account = AccountInfo(key: "demo:\(p.rawValue)", provider: p, email: "demo@example.com",
                                    orgName: p == .claude ? "Demo Org" : nil, plan: nil, configDir: "~")
            sessions[key] = s
        }
        demoTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.demoStep() }
        }
    }

    private var demoStepIndex = 0

    func demoStep() {
        let script: [(Activity, String)] = [
            (.thinking, ""), (.reading, "App.swift"), (.searching, "TODO"), (.typing, "OfficeView.swift"),
            (.running, "swift build"), (.browsing, "developer.apple.com"), (.delegating, "Explore"),
            (.planning, "할 일 정리"), (.done, ""), (.idle, "답장을 기다려요"), (.waitingInput, "어떤 색이 좋을까요?"),
        ]
        for (i, key) in ["claude:demo-1", "claude:demo-2", "codex:demo-3"].enumerated() {
            guard var s = sessions[key] else { continue }
            let (a, d) = script[(demoStepIndex + i * 3) % script.count]
            s.setActivity(a, detail: d)
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
