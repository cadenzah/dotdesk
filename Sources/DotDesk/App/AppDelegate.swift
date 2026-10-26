import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?

    private let settings = SettingsStore.shared
    private let store = SessionStore.shared
    private var server: EventServer!
    private(set) var serverPort: UInt16 = 0
    private var statusItem: NSStatusItem!
    private var office: OfficeWindowController!
    private var codexWatcher = CodexRolloutWatcher()
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var editWindow: NSWindow?
    private var summaryWindow: NSWindow?
    private let integration = IntegrationStatus.shared
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        Runtime.prepare()
        _ = SpriteLibrary.shared

        server = EventServer(token: Runtime.token)
        server.handler = { [weak self] req, responder in
            MainActor.assumeIsolated { self?.store.handleHook(req, responder: responder) }
        }
        server.snapshotHandler = { MainActor.assumeIsolated { AppDelegate.snapshotWindows() } }
        server.start(preferredPort: 47823) { [weak self] port in
            MainActor.assumeIsolated {
                self?.serverPort = port
                Runtime.writePort(port)
            }
        }

        setUpStatusItem()
        office = OfficeWindowController()
        _ = PetManager.shared
        AlertCenter.shared.start()
        DailyStats.shared.onSummaryDue = { [weak self] in self?.showSummary() }
        DailyStats.shared.start()
        codexWatcher.start()

        // Show/hide the office as settings and the set of sessions change.
        Publishers.CombineLatest(settings.$s.map { ($0.office.enabled, $0.office.autoHide) }.removeDuplicates(by: ==),
                                 store.$sessions.map(\.isEmpty).removeDuplicates())
            .sink { [weak self] prefs, empty in
                DispatchQueue.main.async { self?.syncOffice(enabled: prefs.0, autoHide: prefs.1, empty: empty) }
            }
            .store(in: &cancellables)

        store.$sessions.combineLatest(store.$permissions, integration.$claudeConnected)
            .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.updateStatusTitle() }
            .store(in: &cancellables)

        if !integration.claudeConnected, !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            UserDefaults.standard.set(true, forKey: "didShowWelcome")
            showWelcome()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.releaseAllPermissions()
        Runtime.removePort()
        settings.saveNow()
        DailyStats.shared.save()
    }

    /// Writes each visible window to ~/.dotdesk/snapshots (no screen-recording permission needed).
    static func snapshotWindows() {
        let dir = Runtime.dir.appendingPathComponent("snapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (i, w) in NSApp.windows.enumerated() where w.isVisible {
            guard let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
            v.cacheDisplay(in: v.bounds, to: rep)
            let name = w.title.isEmpty ? "window-\(i)" : w.title.replacingOccurrences(of: " ", with: "-")
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
        }
        let state = SessionStore.shared.activeSessions.map { s -> [String: Any] in
            ["id": s.id, "project": s.projectKey, "activity": s.activity.rawValue, "detail": s.detail,
             "account": s.account.map { SettingsStore.shared.accountLabel($0) } ?? "",
             "subagents": s.subagents.map(\.type), "log": s.log.map(\.text),
             "origin": [
                 "pid": s.origin?.pid.map(String.init), "app": s.origin?.appBundleId,
                 "appPid": s.origin?.appPid.map(String.init), "tty": s.origin?.tty, "tmuxPane": s.origin?.tmuxPane,
             ].compactMapValues { $0 },
             "usage": [
                 "context": s.usage?.contextTokens.map(String.init),
                 "window": s.usage.map { String($0.window(SettingsStore.shared.s.contextWindow)) },
                 "output": s.usage.map { String($0.outputTokens) }, "model": s.usage?.model,
             ].compactMapValues { $0 }]
        }
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("state.json"))
        }
    }

    private func syncOffice(enabled: Bool, autoHide: Bool, empty: Bool) {
        let want = enabled && !(autoHide && empty)
        if want, !office.isVisible { office.show() }
        if !want, office.isVisible { office.hide() }
    }

    func showOffice() {
        settings.s.office.enabled = true
        office.show()
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let skin = SheetSkin(sheet: BuiltinCharacters.sheet(look: 0, shirt: RGBA(0x4dabf7)))!
        let (frame, _) = skin.frame(facing: .down, pose: .stand, tick: 0)
        if let face = frame.crop(1, 4, 14, 17) {
            let img = NSImage(cgImage: face, size: CGSize(width: 14, height: 17))
            statusItem.button?.image = img
        }
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateStatusTitle() {
        let working = store.sessions.values.filter { $0.activity.isWorking }.count
        let waiting = store.sessions.values.filter { $0.activity.needsUser }.count
        var t = integration.claudeConnected ? "" : " ⚠︎"
        if working > 0 { t += " \(working)" }
        if waiting > 0 { t += " ✋\(waiting)" }
        statusItem.button?.title = t
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        integration.refresh()
        if !integration.claudeConnected {
            menu.addItem(MenuAction(L("⚠︎ Claude Code와 연결되지 않았어요 — 연결하기…", "⚠︎ Not connected to Claude Code — Connect…")) { [weak self] in self?.showWelcome() })
            menu.addItem(.separator())
        }
        let sessions = store.activeSessions.filter { $0.activity != .leaving }
        if sessions.isEmpty {
            menu.addItem(withTitle: L("일하는 에이전트가 없어요", "No agents working"), action: nil, keyEquivalent: "").isEnabled = false
        }
        for s in sessions {
            let item = NSMenuItem(title: "\(store.nickname(s)) · \(settings.projectName(s.projectKey)) — \(s.activity.label)", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            if let a = s.account { sub.addItem(withTitle: settings.accountLabel(a), action: nil, keyEquivalent: "").isEnabled = false }
            if !s.detail.isEmpty { sub.addItem(withTitle: s.detail, action: nil, keyEquivalent: "").isEnabled = false }
            if let u = s.usage, let tokens = u.contextTokens, let f = settings.contextFraction(s) {
                let window = u.window(settings.s.contextWindow)
                sub.addItem(withTitle: L("컨텍스트 \(Int((f * 100).rounded()))% (\(formatTokens(tokens))/\(formatTokens(window)))",
                                           "Context \(Int((f * 100).rounded()))% (\(formatTokens(tokens))/\(formatTokens(window)))"),
                            action: nil, keyEquivalent: "").isEnabled = false
            }
            sub.addItem(.separator())
            if WindowFocuser.canFocus(s) {
                sub.addItem(MenuAction(L("에이전트 창으로 가기", "Go to agent's window")) { WindowFocuser.focusOrBeep(s) })
            }
            if PetManager.shared.pinned[s.id] == nil {
                sub.addItem(MenuAction(L("데스크톱 펫으로 꺼내기", "Pop out as desktop pet")) { PetManager.shared.popOut(s.id) })
            } else {
                sub.addItem(MenuAction(L("펫 집어넣기", "Put pet back")) { PetManager.shared.putBack(s.id) })
            }
            sub.addItem(MenuAction(L("이 세션 자동 허용", "Auto-approve this session"), checked: s.autoAllowThisSession) { [store] in
                store.setAutoAllow(s.id, !s.autoAllowThisSession)
            })
            sub.addItem(MenuAction(L("이름·캐릭터 바꾸기…", "Change name & character…")) { [weak self] in self?.editSession(s.id) })
            item.submenu = sub
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(MenuAction(L("사무실 창", "Office window"), checked: office.isVisible) { [weak self] in
            guard let self else { return }
            self.settings.s.office.enabled = !self.office.isVisible
        })
        menu.addItem(MenuAction(L("데스크톱 펫", "Desktop pet"), checked: settings.s.pet.enabled) { [settings] in
            settings.s.pet.enabled.toggle()
        })
        let modeItem = NSMenuItem(title: L("펫 움직임", "Pet movement"), action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for m in PetMode.allCases {
            modeMenu.addItem(MenuAction(m.label, checked: settings.s.pet.mode == m) { [settings] in settings.s.pet.mode = m })
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)
        let permItem = NSMenuItem(title: L("권한 요청", "Permission requests"), action: nil, keyEquivalent: "")
        let permMenu = NSMenu()
        for m in PermissionMode.allCases {
            permMenu.addItem(MenuAction(m.label, checked: settings.s.permissions.mode == m) { [settings] in settings.s.permissions.mode = m })
        }
        permItem.submenu = permMenu
        menu.addItem(permItem)
        menu.addItem(MenuAction(L("오늘의 기록…", "Today's log…")) { [weak self] in self?.showSummary() })
        menu.addItem(MenuAction(L("알림 소리", "Alert sound"), checked: settings.s.alerts.sound) { [settings] in
            settings.s.alerts.sound.toggle()
        })
        menu.addItem(.separator())
        menu.addItem(MenuAction(L("데모 에이전트", "Demo agent"), checked: store.demoRunning) { [store] in store.toggleDemo() })
        menu.addItem(MenuAction(L("설정…", "Settings…")) { [weak self] in self?.showSettings(tab: nil) })
        menu.addItem(.separator())
        menu.addItem(MenuAction(L("DotDesk 종료", "Quit DotDesk")) { NSApp.terminate(nil) })
    }

    // MARK: Windows

    func showSummary() {
        if summaryWindow == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 600),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: DailySummaryView())
            host.sizingOptions = [.preferredContentSize]
            w.contentView = host
            w.center()
            summaryWindow = w
        }
        summaryWindow?.title = L("오늘의 기록", "Today's log")
        NSApp.activate(ignoringOtherApps: true)
        summaryWindow?.makeKeyAndOrderFront(nil)
    }

    func showWelcome() {
        if welcomeWindow == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 460),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: WelcomeView { [weak w] in w?.close() })
            w.contentView = host
            w.setContentSize(host.fittingSize)
            w.center()
            welcomeWindow = w
        }
        welcomeWindow?.title = L("DotDesk 시작하기", "Welcome to DotDesk")
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    func showSettings(tab: SettingsTab?) {
        if let tab { SettingsNavigation.shared.tab = tab }
        if settingsWindow == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 480),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            settingsWindow = w
        }
        settingsWindow?.title = L("DotDesk 설정", "DotDesk Settings")
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Window to rename an agent and pick its character.
    func editSession(_ key: String) {
        guard let s = store.session(key) else { return }
        editWindow?.close()
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = L("에이전트 꾸미기", "Customize agent")
        w.isReleasedWhenClosed = false
        let view = AgentEditView(
            title: store.nickname(s),
            subtitle: "\(settings.projectName(s.projectKey)) · \(s.provider.displayName)",
            name: store.worker(s)?.name ?? "",
            namePlaceholder: store.worker(s)?.autoNickname ?? "",
            ref: store.worker(s)?.character,
            autoRef: settings.s.projects[s.projectKey]?.character ?? store.worker(s)?.autoCharacter ?? "builtin:0",
            shirt: settings.projectColor(s.projectKey),
            save: { [weak self, weak w] name, ref in
                self?.store.customize(key, name: name.isEmpty ? nil : name, character: ref)
                w?.close()
            },
            cancel: { [weak w] in w?.close() })
        let host = NSHostingView(rootView: view)
        w.contentView = host
        w.setContentSize(host.fittingSize)
        w.center()
        editWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
