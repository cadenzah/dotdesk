import Foundation

enum Provider: String, Codable, CaseIterable {
    case claude, codex

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

/// What a character is doing right now. Drives pose, bubble icon and office placement.
enum Activity: String, Codable {
    case idle, thinking, reading, searching, typing, running, browsing
    case delegating, planning, tool, compacting, waitingPermission, waitingInput
    case done, sleeping, leaving

    var label: String {
        switch self {
        case .idle: return "대기 중"
        case .thinking: return "생각 중"
        case .reading: return "읽는 중"
        case .searching: return "찾는 중"
        case .typing: return "작성 중"
        case .running: return "실행 중"
        case .browsing: return "웹 탐색 중"
        case .delegating: return "팀원 호출 중"
        case .planning: return "계획 중"
        case .tool: return "도구 사용 중"
        case .compacting: return "대화 정리 중"
        case .waitingPermission: return "허락을 기다려요"
        case .waitingInput: return "질문이 있어요"
        case .done: return "완료!"
        case .sleeping: return "쉬는 중"
        case .leaving: return "퇴근 중"
        }
    }

    /// Agent is busy (not waiting on the user and not resting).
    var isWorking: Bool {
        switch self {
        case .thinking, .reading, .searching, .typing, .running, .browsing, .delegating, .planning, .tool, .compacting:
            return true
        default:
            return false
        }
    }

    var needsUser: Bool { self == .waitingPermission || self == .waitingInput }

    var pose: Pose {
        switch self {
        case .typing, .running, .delegating, .tool, .planning, .compacting: return .type
        case .reading, .searching, .browsing: return .read
        case .sleeping: return .sleep
        case .done: return .cheer
        default: return .stand
        }
    }

    var icon: PixelIcon? {
        switch self {
        case .idle: return nil
        case .thinking: return .dots
        case .reading: return .book
        case .searching: return .magnifier
        case .typing: return .pencil
        case .running: return .terminal
        case .browsing: return .globe
        case .delegating: return .people
        case .planning: return .checklist
        case .tool: return .wrench
        case .compacting: return .box
        case .waitingPermission: return .exclaim
        case .waitingInput: return .question
        case .done: return .check
        case .sleeping: return .zzz
        case .leaving: return nil
        }
    }
}

/// How a character reacts to how things went.
enum Reaction {
    /// A tool call failed: a confused shake.
    case oops
    case testsPassed
    case testsFailed
    /// Finished a long task: cheering with confetti.
    case celebrate

    var icon: PixelIcon {
        switch self {
        case .oops: return .oops
        case .testsPassed: return .sparkle
        case .testsFailed: return .cross
        case .celebrate: return .party
        }
    }

    var label: String {
        switch self {
        case .oops: return "앗, 실패했어요"
        case .testsPassed: return "테스트 통과!"
        case .testsFailed: return "테스트가 실패했어요"
        case .celebrate: return "긴 작업을 끝냈어요!"
        }
    }

    var cheers: Bool { self == .testsPassed || self == .celebrate }
    var shakes: Bool { self == .oops || self == .testsFailed }
}

enum Pose { case stand, walk, type, read, sleep, sit, nap, cheer }
enum Facing { case down, up, right, left }

/// How full the agent's context window is, read from its transcript.
struct ContextUsage: Equatable {
    /// Tokens in the latest request (prompt plus reply). Nil right after compaction until the next reply.
    var contextTokens: Int?
    /// From Codex's own report; nil for Claude, whose window is guessed (see `window(settings:)`).
    var reportedWindow: Int?
    var model: String?
    /// Largest context seen, to tell a 1M window from a 200K one.
    var peakTokens = 0
    /// Tokens generated over the whole session.
    var outputTokens = 0

    func window(_ setting: Int) -> Int {
        if let w = reportedWindow, w > 0 { return w }
        if setting > 0 { return setting }
        if model?.contains("[1m]") == true || peakTokens > 200_000 { return 1_000_000 }
        return 200_000
    }

    func fraction(_ setting: Int) -> Double? {
        contextTokens.map { min(1, Double($0) / Double(window(setting))) }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date: Date
    let text: String
}

struct SubAgent: Identifiable {
    let id: String
    var type: String
    var activity: Activity = .thinking
    var detail: String = ""
    var startedAt = Date()
}

struct AgentSession: Identifiable {
    /// "provider:sessionId"
    let id: String
    let provider: Provider
    let sessionId: String
    var cwd: String?
    var projectKey: String
    var account: AccountInfo?
    var activity: Activity = .idle
    var detail: String = ""
    var model: String?
    var startedAt = Date()
    var lastEventAt = Date()
    var activityChangedAt = Date()
    var doneUntil: Date?
    /// When the user's latest request came in, to tell a long task from a quick reply.
    var turnStartedAt: Date?
    /// A short reaction to a tool result or a finished task, shown until `reactionUntil`.
    var reaction: Reaction?
    var reactionUntil = Date.distantPast
    var subagents: [SubAgent] = []
    var log: [LogEntry] = []
    var usage: ContextUsage?
    var viaHooks = false
    var origin: SessionOrigin?
    var autoAllowThisSession = false
    /// The worker on screen for this session. Nil once a newer session in the project took them over while this one rested.
    var workerId: String?

    mutating func addLog(_ text: String) {
        log.append(LogEntry(date: Date(), text: text))
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }

    var activeReaction: Reaction? { Date() < reactionUntil ? reaction : nil }

    mutating func react(_ r: Reaction, for seconds: TimeInterval) {
        reaction = r
        reactionUntil = Date().addingTimeInterval(seconds)
    }

    mutating func setActivity(_ a: Activity, detail d: String? = nil) {
        if a != activity { activityChangedAt = Date() }
        activity = a
        if let d { detail = d }
    }
}

/// The process and terminal an agent runs in, as reported by the hook relay.
struct SessionOrigin: Equatable {
    /// Parent of the hook relay: the agent itself or a shell it spawned.
    var pid: Int32?
    /// `__CFBundleIdentifier` inherited from the app the agent was started in.
    var appBundleId: String?
    /// `$TMUX` (socket path, server pid, session) and `$TMUX_PANE` when running inside tmux.
    var tmux: String?
    var tmuxPane: String?
    /// Filled in by WindowFocuser from the process tree.
    var tty: String?
    var appPid: Int32?

    init(pid: Int32) { self.pid = pid }

    init?(headers: [String: String]) {
        func value(_ name: String) -> String? { headers[name].flatMap { $0.isEmpty ? nil : $0 } }
        pid = value("x-dotdesk-pid").flatMap { Int32($0) }.flatMap { $0 > 1 ? $0 : nil }
        appBundleId = value("x-dotdesk-app")
        tmux = value("x-dotdesk-tmux")
        tmuxPane = value("x-dotdesk-tmux-pane")
        if pid == nil, appBundleId == nil, tmuxPane == nil { return nil }
    }
}

/// A character at a desk. Sessions come and go, so a worker whose session ended or is resting takes on
/// the next new session in the same project, keeping their name and look.
struct Worker: Codable, Identifiable {
    let id: String
    /// Empty for workers carried over from per-session settings, until their session shows up again.
    var projectKey: String
    /// Picked again on each launch, so a changed character source applies.
    var autoNickname = ""
    var autoCharacter = ""
    var name: String?
    var character: String?
    /// The session they last worked for.
    var sessionKey: String?
    /// Where that session ran, so a session started right there (after /clear) gets them back first.
    var cwd: String?
    /// When they last started or finished working for a session.
    var lastSeen = Date()
}

enum PermissionMode: String, Codable, CaseIterable, Identifiable {
    case passthrough, bubble, autoAllow
    var id: String { rawValue }

    var label: String {
        switch self {
        case .passthrough: return "에이전트 창에서 직접 응답"
        case .bubble: return "펫 말풍선에서 응답"
        case .autoAllow: return "자동 허용 (바이패스)"
        }
    }
}

enum PermissionDecision {
    case allow
    case deny(String?)
    case passthrough
}

final class PendingPermission: Identifiable {
    let id = UUID()
    let sessionKey: String
    let provider: Provider
    let toolName: String
    let summary: String
    let agentType: String?
    let createdAt = Date()
    let deadline: Date
    var reason: String?
    fileprivate(set) var resolved = false
    private let respond: (PermissionDecision) -> Void

    init(sessionKey: String, provider: Provider, toolName: String, summary: String, agentType: String?,
         timeout: TimeInterval, reason: String?, respond: @escaping (PermissionDecision) -> Void) {
        self.sessionKey = sessionKey
        self.provider = provider
        self.toolName = toolName
        self.summary = summary
        self.agentType = agentType
        self.deadline = Date().addingTimeInterval(timeout)
        self.reason = reason
        self.respond = respond
    }

    func resolve(_ d: PermissionDecision) {
        guard !resolved else { return }
        resolved = true
        respond(d)
    }
}

/// Stable 64-bit FNV-1a; Swift's hashValue is randomized per launch.
func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 {
        h ^= UInt64(b)
        h = h &* 0x100000001b3
    }
    return h
}

func abbreviatePath(_ p: String) -> String {
    let home = NSHomeDirectory()
    return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
}

func expandPath(_ p: String) -> String {
    (p as NSString).expandingTildeInPath
}

/// Appends 이/가 depending on whether the last Hangul syllable has a final consonant.
func withSubjectParticle(_ name: String) -> String {
    guard let last = name.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return name + "가" }
    return name + ((last.value - 0xAC00) % 28 == 0 ? "가" : "이")
}

func truncate(_ s: String, _ n: Int) -> String {
    let oneLine = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    return oneLine.count > n ? String(oneLine.prefix(n - 1)) + "…" : oneLine
}
