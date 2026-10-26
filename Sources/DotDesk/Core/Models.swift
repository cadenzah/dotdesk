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
    case delegating, planning, tool, waitingPermission, waitingInput
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
        case .thinking, .reading, .searching, .typing, .running, .browsing, .delegating, .planning, .tool:
            return true
        default:
            return false
        }
    }

    var needsUser: Bool { self == .waitingPermission || self == .waitingInput }

    var pose: Pose {
        switch self {
        case .typing, .running, .delegating, .tool, .planning: return .type
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
        case .waitingPermission: return .exclaim
        case .waitingInput: return .question
        case .done: return .check
        case .sleeping: return .zzz
        case .leaving: return nil
        }
    }
}

enum Pose { case stand, walk, type, read, sleep, sit, nap, cheer }
enum Facing { case down, up, right, left }

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
    var subagents: [SubAgent] = []
    var log: [LogEntry] = []
    var viaHooks = false
    var autoAllowThisSession = false
    var autoCharacter: String = "builtin:0"
    var autoNickname: String = ""

    mutating func addLog(_ text: String) {
        log.append(LogEntry(date: Date(), text: text))
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }

    mutating func setActivity(_ a: Activity, detail d: String? = nil) {
        if a != activity { activityChangedAt = Date() }
        activity = a
        if let d { detail = d }
    }
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
