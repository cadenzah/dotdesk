import AppKit
import Combine
import SwiftUI

@MainActor
final class OfficeWindowController: NSObject, NSWindowDelegate {
    let sim = OfficeSimulation()
    private let panel: NSPanel
    private let settings = SettingsStore.shared
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 420, height: 250),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = "DotDesk 사무실"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = CGSize(width: 220, height: 140)
        panel.delegate = self
        let host = NSHostingView(rootView: OfficeView(sim: sim))
        host.sizingOptions = []
        panel.contentView = host

        if let f = settings.s.office.frame, f.count == 4 {
            panel.setFrame(CGRect(x: f[0], y: f[1], width: f[2], height: f[3]), display: false)
        } else if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: screen.maxX - 440, y: screen.minY + 20))
        }
        applyLevel()
        settings.$s.map(\.office.alwaysOnTop).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyLevel() }
        }.store(in: &cancellables)
    }

    private func applyLevel() {
        panel.level = settings.s.office.alwaysOnTop ? .floating : .normal
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        panel.orderFrontRegardless()
        sim.start()
    }

    func hide() {
        panel.orderOut(nil)
        sim.stop()
    }

    func windowWillClose(_ notification: Notification) {
        sim.stop()
        settings.s.office.enabled = false
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }

    private func saveFrame() {
        let f = panel.frame
        settings.s.office.frame = [f.minX, f.minY, f.width, f.height]
    }
}

struct OfficeView: View {
    @ObservedObject var sim: OfficeSimulation
    @ObservedObject private var store = SessionStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var integration = IntegrationStatus.shared
    @State private var selected: String?

    var body: some View {
        GeometryReader { geo in
            let size = sim.layout.size
            let raw = min(geo.size.width / size.width, geo.size.height / size.height)
            let scale = raw >= 2 ? floor(raw) : raw
            let ox = (geo.size.width - size.width * scale) / 2
            let oy = (geo.size.height - size.height * scale) / 2

            ZStack(alignment: .topLeading) {
                OfficeArt.floorA.color
                if let img = sim.frame {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: size.width * scale, height: size.height * scale)
                        .offset(x: ox, y: oy)
                }
                ForEach(sim.layout.zones) { z in
                    Text(settings.projectName(z.projectKey))
                        .font(.system(size: max(9, 5 * scale), weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(settings.projectColor(z.projectKey).darker(0.15).color))
                        .frame(maxWidth: z.rect.width * scale, alignment: .leading)
                        .offset(x: ox + z.rect.minX * scale, y: oy + (z.rect.minY + 3) * scale)
                        .allowsHitTesting(false)
                }
                WhiteboardLabel(rect: sim.layout.whiteboard, scale: scale)
                    .offset(x: ox + sim.layout.whiteboard.minX * scale, y: oy + sim.layout.whiteboard.minY * scale)
                ForEach(sim.hits) { h in
                    if let s = store.session(h.sessionKey) {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: h.rect.width * scale, height: h.rect.height * scale)
                            .offset(x: ox + h.rect.minX * scale, y: oy + h.rect.minY * scale)
                            .help("\(store.nickname(s)) · \(h.label ?? s.activity.label)\(s.detail.isEmpty ? "" : " · \(s.detail)")")
                            .onTapGesture(count: 2) { WindowFocuser.focusOrBeep(s) }
                            .onTapGesture { selected = h.sessionKey }
                            .contextMenu { SessionMenu(session: s) }
                            .popover(isPresented: Binding(get: { selected == h.sessionKey }, set: { if !$0 { selected = nil } })) {
                                SessionDetail(sessionKey: h.sessionKey, restLabel: h.label)
                            }
                        VStack(spacing: 1) {
                            Text(store.nickname(s))
                                .font(.system(size: max(8, 4.2 * scale), weight: .medium))
                                .foregroundStyle(Color(white: 0.15))
                                .lineLimit(1)
                                .fixedSize()
                            if settings.s.showContextGauge, let u = s.usage, u.contextTokens != nil {
                                ContextGauge(usage: u, compact: true).frame(width: OfficeLayout.deskW * scale * 0.4)
                            }
                        }
                        .frame(width: OfficeLayout.deskW * scale)
                        .offset(x: ox + (h.nameAnchor.x - OfficeLayout.deskW / 2) * scale, y: oy + h.nameAnchor.y * scale - 6)
                        .allowsHitTesting(false)
                    }
                }
                if store.sessions.isEmpty {
                    VStack(spacing: 4) {
                        if integration.claudeConnected {
                            Text("조용한 사무실").font(.headline)
                            Text("에이전트가 일을 시작하면 출근해요").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("아직 에이전트와 연결되지 않았어요").font(.headline)
                            Text("훅을 설치하면 Claude Code가 일할 때 출근해요").font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Button("Claude Code 연결하기") { integration.installClaude() }
                                Button("자세히") { AppDelegate.shared?.showWelcome() }
                            }
                            .controlSize(.small)
                            .padding(.top, 4)
                            if let e = integration.lastError {
                                Text(e).font(.caption2).foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                if !store.permissions.isEmpty {
                    VStack(spacing: 6) {
                        Spacer()
                        ForEach(store.permissions.prefix(2)) { p in PermissionCard(p: p) }
                    }
                    .padding(8)
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Today's busy time written on the lounge whiteboard; click it for the day's summary.
struct WhiteboardLabel: View {
    let rect: CGRect
    let scale: CGFloat
    @ObservedObject private var stats = DailyStats.shared

    var body: some View {
        let d = stats.today
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
            if scale >= 2.5 {
                Text(d.busySeconds > 0 ? "오늘 \(formatDuration(d.busySeconds))" : "오늘")
                    .font(.system(size: 3.6 * scale, weight: .semibold))
                    .foregroundStyle(Color(white: 0.25))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.leading, 3 * scale)
                    .padding(.top, 1.5 * scale)
                    .frame(width: rect.width * scale, alignment: .leading)
            }
        }
        .frame(width: rect.width * scale, height: rect.height * scale)
        .help("오늘 \(formatDuration(d.busySeconds)) 일했어요 · 요청 \(d.prompts) · 고친 파일 \(d.files.count) · 테스트 통과 \(d.testsPassed)\n눌러서 오늘의 기록 보기")
        .onTapGesture { AppDelegate.shared?.showSummary() }
    }
}

struct SessionMenu: View {
    let session: AgentSession
    @ObservedObject private var store = SessionStore.shared
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        let s = session
        Text("\(store.nickname(s)) · \(settings.projectName(s.projectKey))")
        if WindowFocuser.canFocus(s) {
            Button("에이전트 창으로 가기") { WindowFocuser.focusOrBeep(s) }
        }
        Button("이름·캐릭터 바꾸기…") { AppDelegate.shared?.editSession(s.id) }
        Menu("캐릭터") {
            CharacterPickerMenu(current: store.characterRef(s)) { ref in
                store.setCharacter(s.id, ref)
            }
        }
        Button("이 캐릭터를 프로젝트 기본으로") {
            settings.s.projects[s.projectKey, default: ProjectSettings()].character = store.characterRef(s)
        }
        Divider()
        if PetManager.shared.pinned[s.id] == nil {
            Button("데스크톱 펫으로 꺼내기") { PetManager.shared.popOut(s.id) }
        } else {
            Button("펫 집어넣기") { PetManager.shared.putBack(s.id) }
        }
        Toggle("이 세션 자동 허용", isOn: Binding(get: { s.autoAllowThisSession }, set: { on in
            if on, !AutoAllowWarning.confirm("이 세션") { return }
            store.setAutoAllow(s.id, on)
        }))
        Divider()
        Button("프로젝트 설정…") { AppDelegate.shared?.showSettings(tab: .projects) }
    }
}

struct CharacterPickerMenu: View {
    let current: String
    let pick: (String) -> Void
    @ObservedObject private var sprites = SpriteLibrary.shared

    var body: some View {
        let groups = Dictionary(grouping: sprites.choices, by: \.group)
        ForEach(["기본 도트", "Pixel Agents", "포켓몬"], id: \.self) { g in
            if let list = groups[g], !list.isEmpty {
                Menu(g) {
                    ForEach(list) { c in
                        Button { pick(c.ref) } label: {
                            Text(c.ref == current ? "✓ \(c.name)" : c.name)
                        }
                    }
                }
            }
        }
    }
}

struct SessionDetail: View {
    let sessionKey: String
    /// What the agent is doing on their break, from the office scene.
    var restLabel: String?
    @ObservedObject private var store = SessionStore.shared
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        if let s = store.session(sessionKey) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(store.nickname(s)).font(.headline)
                    Text(restLabel ?? s.activity.label).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    Spacer()
                    if WindowFocuser.canFocus(s) {
                        Button("창으로 가기") { WindowFocuser.focusOrBeep(s) }
                            .controlSize(.small)
                            .help("에이전트가 일하는 터미널이나 앱 창을 앞으로 가져와요 (캐릭터를 더블클릭해도 돼요)")
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                    GridRow { Text("프로젝트").foregroundStyle(.secondary); Text(settings.projectName(s.projectKey)) }
                    if let a = s.account {
                        GridRow { Text("계정").foregroundStyle(.secondary); Text("\(settings.accountLabel(a))\(a.email.map { " (\($0))" } ?? "")") }
                    }
                    if let cwd = s.cwd { GridRow { Text("폴더").foregroundStyle(.secondary); Text(abbreviatePath(cwd)).lineLimit(1).truncationMode(.middle) } }
                    if let m = s.model ?? s.usage?.model { GridRow { Text("모델").foregroundStyle(.secondary); Text(m) } }
                    if let u = s.usage, u.contextTokens != nil || u.outputTokens > 0 {
                        GridRow {
                            Text("컨텍스트").foregroundStyle(.secondary)
                            if u.contextTokens != nil { ContextGauge(usage: u) } else { Text("정리한 뒤 다시 세는 중") }
                        }
                        GridRow { Text("출력 토큰").foregroundStyle(.secondary); Text(formatTokens(u.outputTokens)) }
                    }
                    if !s.subagents.isEmpty {
                        GridRow { Text("팀원").foregroundStyle(.secondary); Text(s.subagents.map { "\($0.type)(\($0.activity.label))" }.joined(separator: ", ")) }
                    }
                }
                .font(.caption)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(s.log.suffix(14).reversed()) { e in
                            HStack(alignment: .top, spacing: 6) {
                                Text(e.date, format: .dateTime.hour().minute().second()).foregroundStyle(.secondary)
                                Text(e.text).lineLimit(2)
                            }
                            .font(.system(size: 10))
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
            .padding(12)
            .frame(width: 320)
        } else {
            Text("퇴근했어요").padding()
        }
    }
}
