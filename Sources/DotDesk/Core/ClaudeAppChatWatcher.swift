import AppKit
import ApplicationServices

/// Follows chats in the Claude desktop app's Chat tab, which run on Anthropic's servers and so never
/// fire hooks or leave files behind. With Accessibility access it reads the app's window: in the chat
/// sidebar a running chat's row carries a spinner (an AXGroup with a label) and a finished one an icon
/// (an AXImage). Telling them apart by role keeps this working whatever language the app is in.
/// The sidebar only lists chats while the app shows the Chat tab; in the Code tab nothing changes here.
@MainActor
final class ClaudeAppChatWatcher {
    nonisolated static let bundleId = "com.anthropic.claudefordesktop"
    /// All chats sit together in one office area.
    nonisolated static let projectKey = "claude-app:chats"

    private struct Chat {
        let sessionId: String
        var running = false
    }

    /// Chats seen running while DotDesk watched, by their title in the sidebar.
    private var chats: [String: Chat] = [:]
    private var timer: Timer?
    private var reading = false
    /// The Claude process whose web content we asked to expose to Accessibility.
    private var exposedPid: pid_t?
    private let store = SessionStore.shared
    private let settings = SettingsStore.shared
    private let queue = DispatchQueue(label: "dotdesk.claude-app-chats", qos: .utility)

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard !reading, AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleId).first(where: { !$0.isTerminated })
        else { return }
        let pid = app.processIdentifier
        guard settings.s.watchClaudeAppChats else {
            if exposedPid == pid { queue.async { Self.expose(pid, false) } }
            exposedPid = nil
            return
        }
        let expose = exposedPid != pid
        exposedPid = pid
        reading = true
        queue.async { [weak self] in
            // Electron builds the accessibility tree of its web content only when asked.
            if expose { Self.expose(pid, true) }
            let snapshot = Self.read(pid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.reading = false
                    if let snapshot { self?.apply(snapshot) }
                }
            }
        }
    }

    // MARK: Turning rows into sessions

    private func apply(_ snap: Snapshot) {
        let titles = Set(snap.rows.map(\.title))
        let running = snap.rows.filter(\.running).map(\.title)
        // The first title is a placeholder that gets replaced once Claude names the chat.
        var renamed = chats.filter { $0.value.running && !titles.contains($0.key) }.map(\.key)

        for title in running {
            var chat: Chat
            if let c = chats[title] {
                chat = c
            } else if let old = renamed.first {
                renamed.removeFirst()
                chat = chats.removeValue(forKey: old)!
            } else {
                chat = Chat(sessionId: "app-" + String(stableHash(title + "\(Date().timeIntervalSince1970)"), radix: 36))
            }
            let starts = !chat.running
            let (activity, detail) = snap.openTitle == title ? snap.openActivity : (.thinking, truncate(title, 40))
            store.applyAppChat(sessionId: chat.sessionId) { s in
                if starts {
                    DailyStats.shared.recordPrompt(s)
                    s.turnStartedAt = Date()
                    s.addLog(L("요청: \(truncate(title, 60))", "Request: \(truncate(title, 60))"))
                }
                s.setActivity(activity, detail: detail)
            }
            chat.running = true
            chats[title] = chat
        }

        // Finished, or gone from the list (deleted) without being renamed.
        for (title, chat) in chats where chat.running && !running.contains(title) && (titles.contains(title) || renamed.contains(title)) {
            store.applyAppChat(sessionId: chat.sessionId) { [store] s in
                s.setActivity(.done, detail: "")
                store.finishTurn(&s)
            }
            chats[title]?.running = false
        }
        // Forget chats whose session has left the office.
        chats = chats.filter { _, c in c.running || store.session("claude:\(c.sessionId)") != nil }
    }

    // MARK: Reading the window (off the main thread)

    private struct Row {
        let title: String
        let running: Bool
    }

    private struct Snapshot {
        var rows: [Row] = []
        /// Title of the chat open in the main area, and what its status line says it is doing.
        var openTitle: String?
        var openActivity: (Activity, String) = (.thinking, "")
    }

    private struct Node {
        let depth: Int
        let role: String
        let label: String
        let value: String
    }

    nonisolated private static func expose(_ pid: pid_t, _ on: Bool) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
    }

    /// Nil when the chat sidebar isn't on screen (Code tab, sidebar closed, no window).
    nonisolated private static func read(_ pid: pid_t) -> Snapshot? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        guard let windows = copy(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        for w in windows {
            guard let web = chatWebArea(in: w) else { continue }
            let snap = parse(flatten(web))
            if !snap.rows.isEmpty { return snap }
        }
        return nil
    }

    nonisolated private static func copy(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }

    /// The claude.ai page inside the app's own shell page, unless it is showing the Code tab.
    nonisolated private static func chatWebArea(in window: AXUIElement) -> AXUIElement? {
        var stack: [(AXUIElement, Int)] = [(window, 0)]
        var visited = 0
        while let (e, depth) = stack.popLast(), visited < 3000 {
            visited += 1
            if copy(e, kAXRoleAttribute) as? String == "AXWebArea",
               let url = copy(e, kAXURLAttribute) as? URL, url.host == "claude.ai" {
                return url.path.hasPrefix("/epitaxy") ? nil : e
            }
            guard depth < 20, let kids = copy(e, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            stack.append(contentsOf: kids.reversed().map { ($0, depth + 1) })
        }
        return nil
    }

    nonisolated private static func flatten(_ root: AXUIElement) -> [Node] {
        let names = [kAXRoleAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute, kAXChildrenAttribute] as CFArray
        var nodes: [Node] = []
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        while let (e, depth) = stack.popLast(), nodes.count < 20000 {
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(e, names, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
                  let v = values as? [Any], v.count == 5 else { continue }
            let role = v[0] as? String ?? ""
            let label = (v[1] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? v[2] as? String ?? ""
            nodes.append(Node(depth: depth, role: role, label: label, value: v[3] as? String ?? ""))
            // Text and images have nothing below them worth reading.
            guard role != "AXStaticText", role != "AXImage", depth < 80, let kids = v[4] as? [AXUIElement] else { continue }
            stack.append(contentsOf: kids.reversed().map { ($0, depth + 1) })
        }
        return nodes
    }

    nonisolated private static func parse(_ nodes: [Node]) -> Snapshot {
        var snap = Snapshot()
        var headings: [String] = []
        var statuses = Set<String>()
        for (i, n) in nodes.enumerated() {
            switch n.role {
            case "AXHeading":
                if !n.label.isEmpty { headings.append(n.label) }
            case "AXStaticText":
                if n.value.count <= 24 { statuses.insert(n.value.trimmingCharacters(in: .whitespaces)) }
            case "AXButton":
                // A chat row: a button holding the title, plus a spinner while running or an icon once done.
                var title: String?
                var spinner = false, icon = false
                for m in nodes[(i + 1)...].prefix(40) {
                    if m.depth <= n.depth { break }
                    if m.role == "AXStaticText", title == nil, !m.value.isEmpty { title = m.value }
                    if m.role == "AXGroup", !m.label.isEmpty { spinner = true }
                    if m.role == "AXImage", !m.label.isEmpty { icon = true }
                }
                if let title, spinner || icon { snap.rows.append(Row(title: title, running: spinner)) }
            default:
                break
            }
        }
        let titles = Set(snap.rows.map(\.title))
        snap.openTitle = headings.first(where: titles.contains)
        if let title = snap.openTitle, let a = statusActivity(statuses) {
            snap.openActivity = (a, a == .browsing ? L("웹 검색", "Web search") : truncate(title, 40))
        } else if let title = snap.openTitle {
            snap.openActivity = (.thinking, truncate(title, 40))
        }
        return snap
    }

    /// The status line under a reply that's still coming.
    nonisolated private static func statusActivity(_ texts: Set<String>) -> Activity? {
        func has(_ words: [String]) -> Bool { texts.contains { t in words.contains { t.localizedCaseInsensitiveContains($0) } } }
        if has(["웹 검색 중", "검색 중", "Searching"]) { return .browsing }
        if has(["작성 중", "Writing"]) { return .typing }
        if has(["생각 중", "Thinking"]) { return .thinking }
        return nil
    }
}
