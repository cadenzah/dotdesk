import AppKit
import Combine
import UserNotifications

/// Plays a sound and posts a macOS notification when an agent starts waiting for you or finishes a long turn.
/// Watches session activity changes, so it works the same for hooks and Codex rollout files.
@MainActor
final class AlertCenter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = AlertCenter()
    static let sounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
                         "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    enum Kind: String { case permission, question, done }

    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    private let store = SessionStore.shared
    private let settings = SettingsStore.shared
    private var last: [String: Activity] = [:]
    /// When the current turn started working, for "done" after a long task.
    private var workStart: [String: Date] = [:]
    /// Sessions already called again during the current wait.
    private var reminded: Set<String> = []
    private var lastSoundAt = Date.distantPast
    private var cancellables: Set<AnyCancellable> = []

    /// Nil when running without an app bundle (`swift run`), where the notification center can't be used.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func start() {
        if let center {
            center.delegate = self
            let allow = UNNotificationAction(identifier: "allow", title: "허용")
            let deny = UNNotificationAction(identifier: "deny", title: "거부", options: [.destructive])
            center.setNotificationCategories([
                UNNotificationCategory(identifier: "permission", actions: [allow, deny], intentIdentifiers: []),
            ])
            refreshStatus()
        }
        store.$sessions
            .sink { [weak self] sessions in
                MainActor.assumeIsolated { self?.diff(sessions) }
            }
            .store(in: &cancellables)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.remindLongWaits() }
        }
    }

    // MARK: Detecting moments

    private func diff(_ sessions: [String: AgentSession]) {
        for (id, s) in sessions where !Self.isDemo(id) {
            let prev = last[id] ?? .idle
            let now = s.activity
            guard now != prev else { continue }
            last[id] = now
            if now.isWorking, !prev.isWorking, !prev.needsUser { workStart[id] = Date() }
            if prev.needsUser, !now.needsUser {
                reminded.remove(id)
                center?.removeDeliveredNotifications(withIdentifiers: [Kind.permission, .question].map { "\(id)|\($0.rawValue)" })
            }
            let kind: Kind?
            switch now {
            case .waitingPermission: kind = .permission
            case .waitingInput: kind = .question
            case .done:
                let took = workStart[id].map { Date().timeIntervalSince($0) } ?? 0
                kind = took >= settings.s.alerts.doneAfterSeconds ? .done : nil
                workStart[id] = nil
            default: kind = nil
            }
            // The sessions publisher fires before the store is updated, and a permission card is added
            // right after its session; look again on the next turn of the run loop.
            if let kind { DispatchQueue.main.async { self.alert(kind, sessionKey: id) } }
        }
        for id in last.keys where sessions[id] == nil {
            last[id] = nil
            workStart[id] = nil
            reminded.remove(id)
        }
    }

    private func remindLongWaits() {
        let after = settings.s.alerts.callAfterSeconds
        guard after > 0 else { return }
        for s in store.sessions.values where s.activity.needsUser && !reminded.contains(s.id) && !Self.isDemo(s.id) {
            guard Date().timeIntervalSince(s.activityChangedAt) >= after else { continue }
            reminded.insert(s.id)
            if !isWatching(s) { playSound(for: s.activity == .waitingPermission ? .permission : .question) }
        }
    }

    /// True while a session has waited long enough that its pet should come and wave.
    func isCalling(_ s: AgentSession) -> Bool {
        let after = settings.s.alerts.callAfterSeconds
        return after > 0 && s.activity.needsUser && Date().timeIntervalSince(s.activityChangedAt) >= after
    }

    // MARK: Alerting

    private func alert(_ kind: Kind, sessionKey: String) {
        let a = settings.s.alerts
        guard let s = store.session(sessionKey) else { return }
        switch kind {
        case .permission: guard a.onPermission, s.activity == .waitingPermission else { return }
        case .question: guard a.onQuestion, s.activity == .waitingInput else { return }
        case .done: guard a.onDone else { return }
        }
        if isWatching(s) { return }
        playSound(for: kind)
        if a.notify { post(kind, s) }
    }

    /// The agent's app is in front, so you can already see it.
    private func isWatching(_ s: AgentSession) -> Bool {
        guard settings.s.alerts.skipWhenWatching, let o = s.origin,
              let front = NSWorkspace.shared.frontmostApplication else { return false }
        if let pid = o.appPid { return front.processIdentifier == pid }
        return o.appBundleId != nil && front.bundleIdentifier == o.appBundleId
    }

    private func playSound(for kind: Kind) {
        let a = settings.s.alerts
        guard a.sound, Date().timeIntervalSince(lastSoundAt) > 1.5 else { return }
        let name: String
        switch kind {
        case .permission: name = a.permissionSound
        case .question: name = a.questionSound
        case .done: name = a.doneSound
        }
        guard !name.isEmpty else { return }
        lastSoundAt = Date()
        Self.play(name)
    }

    static func play(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func post(_ kind: Kind, _ s: AgentSession) {
        guard let center, notificationStatus == .authorized || notificationStatus == .provisional else { return }
        let c = UNMutableNotificationContent()
        c.title = "\(store.nickname(s)) · \(settings.projectName(s.projectKey))"
        switch kind {
        case .permission: c.body = s.detail.isEmpty ? "허락을 기다려요" : "허락을 기다려요: \(s.detail)"
        case .question: c.body = s.detail.isEmpty ? "질문이 있어요" : "질문이 있어요: \(s.detail)"
        case .done: c.body = "일을 마쳤어요"
        }
        var info: [String: Any] = ["session": s.id]
        if kind == .permission, let p = store.permissions.first(where: { $0.sessionKey == s.id }) {
            info["permission"] = p.id.uuidString
            c.categoryIdentifier = "permission"
            c.body = "허락을 기다려요: \(p.summary)"
        }
        c.userInfo = info
        c.threadIdentifier = s.id
        // The sound is played by DotDesk so it follows the sound settings.
        c.sound = nil
        center.add(UNNotificationRequest(identifier: "\(s.id)|\(kind.rawValue)", content: c, trigger: nil))
    }

    // MARK: Authorization

    func refreshStatus() {
        center?.getNotificationSettings { s in
            let status = s.authorizationStatus
            DispatchQueue.main.async { self.notificationStatus = status }
        }
    }

    /// Asks macOS for permission the first time notifications are turned on.
    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert]) { _, _ in
            DispatchQueue.main.async { self.refreshStatus() }
        }
    }

    static func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func isDemo(_ key: String) -> Bool { key.contains(":demo-") }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let sessionKey = info["session"] as? String
        let permissionId = info["permission"] as? String
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let store = SessionStore.shared
                if let permissionId, action == "allow" || action == "deny",
                   let p = store.permissions.first(where: { $0.id.uuidString == permissionId }) {
                    store.resolve(p, action == "allow" ? .allow : .deny(nil))
                } else if action == UNNotificationDefaultActionIdentifier, let key = sessionKey, let s = store.session(key) {
                    WindowFocuser.focus(s)
                }
            }
            completionHandler()
        }
    }
}
