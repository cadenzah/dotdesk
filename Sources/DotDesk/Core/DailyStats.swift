import Foundation
import Combine

/// What the agents got done on one day.
struct DayStats: Codable, Equatable {
    /// "yyyy-MM-dd" in local time.
    var day: String
    var sessions: Set<String> = []
    /// Who worked that day, by worker id, as they looked then.
    var crew: [String: CrewMember] = [:]
    var prompts = 0
    var turnsDone = 0
    var longTasks = 0
    var toolCalls = 0
    var files: Set<String> = []
    var testsPassed = 0
    var testsFailed = 0
    var outputTokens = 0
    /// Wall-clock time with at least one agent working.
    var busySeconds: Double = 0
    /// Working time added up over every agent, so two agents for an hour count two hours.
    var agentSeconds: Double = 0
    var busyByHour: [Double] = Array(repeating: 0, count: 24)
    var projectSeconds: [String: Double] = [:]
    var summaryShown = false

    init(day: String) { self.day = day }

    var isEmpty: Bool { prompts == 0 && busySeconds == 0 && turnsDone == 0 }
}

/// Running totals across every day, for unlocking office decorations.
struct Totals: Codable, Equatable {
    var busySeconds: Double = 0
    var prompts = 0
    var turnsDone = 0
    var longTasks = 0
    var testsPassed = 0
    var filesEdited = 0
    var activeDays = 0

    mutating func add(_ d: DayStats) {
        busySeconds += d.busySeconds
        prompts += d.prompts
        turnsDone += d.turnsDone
        longTasks += d.longTasks
        testsPassed += d.testsPassed
        filesEdited += d.files.count
        if d.busySeconds > 0 { activeDays += 1 }
    }
}

struct CrewMember: Codable, Equatable {
    var name: String
    var character: String
    var projectKey: String
}

/// Keeps a running tally of each day and stores the last month in stats.json.
@MainActor
final class DailyStats: ObservableObject {
    static let shared = DailyStats()

    @Published private(set) var today: DayStats
    /// Earlier days, oldest first, not including today.
    @Published private(set) var history: [DayStats] = []
    /// Days older than `history`, folded into totals.
    private var archived = Totals()
    /// Decorations earned so far and when.
    @Published private(set) var unlocked: [String: Date] = [:]
    /// The decoration just earned, shown for a few seconds.
    @Published private(set) var announcement: (decoration: Decoration, until: Date)?
    /// Set when the end-of-day summary should open.
    var onSummaryDue: (() -> Void)?

    private let url = Runtime.appSupport.appendingPathComponent("stats.json")
    private let store = SessionStore.shared
    private let settings = SettingsStore.shared
    private var timer: Timer?
    private var dirty = false
    private var lastSave = Date.distantPast
    private var lastBusyAt = Date.distantPast
    static let tick: TimeInterval = 5

    private init() {
        let data = try? Data(contentsOf: url)
        let file = data.flatMap { try? JSONDecoder.dotdesk.decode(StatsFile.self, from: $0) }
            ?? StatsFile(days: data.flatMap { try? JSONDecoder.dotdesk.decode([DayStats].self, from: $0) } ?? [])
        let key = Self.key(Date())
        today = file.days.first { $0.day == key } ?? DayStats(day: key)
        let older = file.days.filter { $0.day < key }
        history = Array(older.suffix(30))
        archived = file.archived
        for d in older.dropLast(30) { archived.add(d) }
        unlocked = file.unlocked
    }

    func start() {
        lastBusyAt = Date()
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Today followed by earlier days, newest first.
    var recentDays: [DayStats] { [today] + history.reversed() }

    // MARK: Recording

    /// Set while replaying history (a Codex rollout read from the start), which was counted when it happened.
    var paused = false

    private func counts(_ s: AgentSession) -> Bool { !paused && !s.id.contains(":demo-") }

    func recordPrompt(_ s: AgentSession) {
        guard counts(s) else { return }
        update { $0.prompts += 1; $0.sessions.insert(s.id) }
    }

    func recordTool(_ s: AgentSession, tool: String, input: [String: Any]) {
        guard counts(s) else { return }
        let files = ActivityMapper.editedFiles(tool: tool, input: input)
        update { d in
            d.toolCalls += 1
            if d.files.count < 5000 { d.files.formUnion(files) }
        }
    }

    func recordTurnDone(_ s: AgentSession, long: Bool) {
        guard counts(s) else { return }
        update { $0.turnsDone += 1; if long { $0.longTasks += 1 } }
    }

    func recordTest(_ s: AgentSession, passed: Bool) {
        guard counts(s) else { return }
        update { if passed { $0.testsPassed += 1 } else { $0.testsFailed += 1 } }
    }

    func recordOutput(_ s: AgentSession, tokens: Int) {
        guard counts(s), tokens > 0 else { return }
        update { $0.outputTokens += tokens }
    }

    private func update(_ change: (inout DayStats) -> Void) {
        rollOver()
        change(&today)
        dirty = true
        checkUnlocks()
    }

    // MARK: Office growth

    var totals: Totals {
        var t = archived
        for d in history { t.add(d) }
        t.add(today)
        return t
    }

    func isUnlocked(_ d: Decoration) -> Bool { unlocked[d.rawValue] != nil }

    private func checkUnlocks() {
        let t = totals
        for d in Decoration.allCases where !isUnlocked(d) && d.isMet(t) {
            unlocked[d.rawValue] = Date()
            dirty = true
            announcement = (d, Date().addingTimeInterval(8))
            if settings.s.alerts.sound { AlertCenter.play("Hero") }
            store.logToAll("사무실에 \(withSubjectParticle(d.name)) 생겼어요")
        }
    }

    // MARK: Ticking

    private func step() {
        rollOver()
        let working = store.sessions.values.filter { counts($0) && $0.activity.isWorking }
        if !working.isEmpty {
            let hour = Calendar.current.component(.hour, from: Date())
            today.busySeconds += Self.tick
            today.busyByHour[hour] += Self.tick
            for s in working {
                today.agentSeconds += Self.tick
                today.projectSeconds[s.projectKey, default: 0] += Self.tick
                today.sessions.insert(s.id)
                if let w = s.workerId {
                    today.crew[w] = CrewMember(name: store.nickname(s), character: store.characterRef(s), projectKey: s.projectKey)
                }
            }
            lastBusyAt = Date()
            dirty = true
            checkUnlocks()
        }
        if let a = announcement, Date() > a.until { announcement = nil }
        if dirty, Date().timeIntervalSince(lastSave) > 30 { save() }
        checkSummary()
    }

    private func rollOver() {
        let key = Self.key(Date())
        guard today.day != key else { return }
        if !today.isEmpty {
            let all = history + [today]
            for d in all.dropLast(30) { archived.add(d) }
            history = Array(all.suffix(30))
        }
        today = DayStats(day: key)
        dirty = true
    }

    /// Opens the day's summary once, after the configured hour, when everyone has been quiet for a while.
    private func checkSummary() {
        let cfg = settings.s.summary
        guard cfg.autoShow, !today.summaryShown, today.busySeconds >= 600,
              Calendar.current.component(.hour, from: Date()) >= cfg.afterHour,
              Date().timeIntervalSince(lastBusyAt) >= cfg.quietMinutes * 60,
              !store.sessions.values.contains(where: { counts($0) && ($0.activity.isWorking || $0.activity.needsUser) })
        else { return }
        today.summaryShown = true
        dirty = true
        save()
        onSummaryDue?()
    }

    /// Shows made-up days instead of the saved ones, without touching stats.json (used by --render-preview).
    func usePreview(today t: DayStats, history h: [DayStats], unlocked u: [Decoration] = []) {
        today = t
        history = h
        unlocked = Dictionary(uniqueKeysWithValues: u.map { ($0.rawValue, Date()) })
    }

    func save() {
        let file = StatsFile(days: history + (today.isEmpty ? [] : [today]), archived: archived, unlocked: unlocked)
        guard let data = try? JSONEncoder.dotdesk.encode(file) else { return }
        try? FileManager.default.createDirectory(at: Runtime.appSupport, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        dirty = false
        lastSave = Date()
    }
}

private struct StatsFile: Codable {
    var days: [DayStats]
    var archived = Totals()
    var unlocked: [String: Date] = [:]
}

/// "3시간 12분", "45분", "30초".
func formatDuration(_ seconds: Double) -> String {
    let m = Int(seconds) / 60
    if m >= 60 { return m % 60 == 0 ? "\(m / 60)시간" : "\(m / 60)시간 \(m % 60)분" }
    if m > 0 { return "\(m)분" }
    return "\(Int(seconds))초"
}
