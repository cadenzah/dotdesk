import AppKit
import Combine
import SwiftUI

/// State the pet view renders. Updated by PetController on every tick.
@MainActor
final class PetModel: ObservableObject {
    @Published var frame: CGImage?
    @Published var displayScale: CGFloat = 3
    @Published var sessionKey: String?
    @Published var title = ""
    @Published var subtitle = ""
    @Published var showSpeech = false
    @Published var hovering = false
    @Published var permissions: [PendingPermission] = []
}

/// One floating character on the desktop. `sessionKey == nil` means "follow the most recently active agent".
@MainActor
final class PetController: NSObject {
    let pinnedSession: String?
    let model = PetModel()
    private let panel: NSPanel
    private var timer: Timer?
    private var tick = 0
    private var x: CGFloat = 0
    private var baseline: CGFloat = 0
    private var dir: CGFloat = 1
    private var pauseUntil = Date()
    private var walking = false
    private var dragging = false
    private var lastActivityKey = ""
    private var speechUntil = Date.distantPast
    /// What the pet does while its agent rests, and until when.
    private var restPlan: (pastime: OfficeSimulation.Pastime, until: Date)?
    /// The pet has no furniture, so only pastimes that need none.
    private static let pastimes: [OfficeSimulation.Pastime] = [.nap, .coffee, .game, .read, .stretch]
    private let store = SessionStore.shared
    private let settings = SettingsStore.shared
    private let sprites = SpriteLibrary.shared
    var onClose: (() -> Void)?

    static let windowSize = CGSize(width: 280, height: 320)
    static let canvas = CGSize(width: 40, height: 52)

    init(pinnedSession: String?, startX: CGFloat? = nil) {
        self.pinnedSession = pinnedSession
        panel = NSPanel(contentRect: CGRect(origin: .zero, size: Self.windowSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "DotDesk 펫"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        let view = PetView(model: model, controller: self)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        panel.contentView = host

        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        if settings.s.pet.mode == .pinned, pinnedSession == nil, let o = settings.s.pet.pinnedOrigin, o.count == 2 {
            x = o[0]; baseline = o[1]
        } else {
            x = startX ?? (screen.maxX - Self.windowSize.width - 40)
            baseline = settings.s.pet.roamBaseline ?? (screen.minY - 6)
        }
        panel.setFrameOrigin(CGPoint(x: x, y: baseline))
    }

    func show() {
        panel.orderFrontRegardless()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        step()
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }

    // MARK: Target

    var session: AgentSession? {
        if let key = pinnedSession { return store.session(key) }
        return PetManager.shared.autoTarget()
    }

    // MARK: Loop

    private func step() {
        tick += 1
        let s = session
        if pinnedSession != nil, s == nil || s?.activity == .leaving || s?.workerId == nil {
            onClose?()
            return
        }
        let activity = s?.activity ?? .sleeping
        model.sessionKey = s?.id
        if activity == .sleeping, s != nil {
            if restPlan.map({ Date() >= $0.until }) ?? true {
                let next = Self.pastimes.filter { $0 != restPlan?.pastime }.randomElement() ?? .nap
                restPlan = (next, Date().addingTimeInterval(next == .nap ? .random(in: 60...150) : .random(in: 20...50)))
            }
        } else {
            restPlan = nil
        }
        let pastime = restPlan?.pastime
        model.permissions = store.permissions.filter { $0.sessionKey == s?.id }

        // Speech bubble: show briefly after each change, and keep it while the agent needs the user.
        let key = "\(s?.id ?? "-")|\(activity.rawValue)|\(s?.detail ?? "")"
        if key != lastActivityKey {
            lastActivityKey = key
            if s != nil, activity != .sleeping { speechUntil = Date().addingTimeInterval(6) }
        }
        if let s {
            let nick = store.nickname(s)
            model.title = "\(nick) · \(pastime?.label() ?? activity.label)"
            var parts: [String] = []
            if !s.detail.isEmpty { parts.append(s.detail) }
            parts.append(settings.projectName(s.projectKey))
            if let a = s.account { parts.append(settings.accountLabel(a)) }
            model.subtitle = parts.joined(separator: " · ")
        } else {
            model.title = "쉬는 중"
            model.subtitle = "일하는 에이전트가 없어요"
        }
        model.showSpeech = model.permissions.isEmpty
            && (model.hovering || (settings.s.pet.showSpeech && (Date() < speechUntil || activity.needsUser)))

        // Movement
        let busy = activity.isWorking || activity.needsUser || activity == .sleeping || activity == .done
        let screen = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        if settings.s.pet.mode == .roam, !dragging, !busy, !model.hovering {
            if Date() < pauseUntil {
                walking = false
            } else {
                walking = true
                x += dir * 1.4
                let minX = screen.minX - Self.windowSize.width / 2 + 30
                let maxX = screen.maxX - Self.windowSize.width / 2 - 30
                if x < minX { x = minX; dir = 1 }
                if x > maxX { x = maxX; dir = -1 }
                if tick % 24 == 0, Double.random(in: 0..<1) < 0.18 {
                    pauseUntil = Date().addingTimeInterval(.random(in: 1.5...5))
                    if Bool.random() { dir = -dir }
                }
            }
            panel.setFrameOrigin(CGPoint(x: x, y: baseline))
        } else {
            walking = false
        }

        // Frame
        let ref = s.map(store.characterRef) ?? "builtin:0"
        let shirt = s.map { settings.projectColor($0.projectKey) } ?? RGBA(0x868e96)
        let skin = sprites.skin(for: ref, shirt: shirt)
        var pose: Pose = walking ? .walk : activity.pose
        var facing: Facing = walking ? (dir > 0 ? .right : .left) : .down
        if !walking, let (p, f) = pastime?.pose(skin, tick: tick / 2) {
            pose = p
            if let f { facing = f }
        }
        if pose == .cheer && !skin.hasCheerFrame { pose = .stand }
        let (img, flip) = skin.frame(facing: facing, pose: pose, tick: tick / 2)
        let icon = pastime?.icon ?? activity.icon

        var bounce: CGFloat = 0
        if activity == .done { bounce = (tick / 3) % 4 < 2 ? -3 : 0 }
        if activity.needsUser { bounce = (tick / 4) % 6 == 0 ? -2 : 0 }
        if !skin.isSheet, activity.isWorking { bounce += (tick / 2) % 2 == 0 ? -1 : 0 }

        let scale = CGFloat(settings.s.pet.scale)
        if skin.isSheet {
            let p = PixelContext(Int(Self.canvas.width), Int(Self.canvas.height))
            let rest = CGRect(x: 12, y: 18, width: 16, height: 32)
            let r = rest.offsetBy(dx: 0, dy: bounce)
            p.image(img, r.minX, r.minY, flipX: flip)
            if let pastime, !walking { OfficeArt.held(pastime, p, r, sheet: true, tick: tick / 2) }
            // Anchor the bubble to the resting position so it doesn't bob along with the sprite.
            if let icon, !walking { p.image(icon.bubble, rest.midX - 1, rest.minY - 6) }
            model.frame = p.makeImage()
            model.displayScale = scale
        } else {
            // Pokémon sprites are drawn at native size on a larger canvas, then scaled down to match.
            let cw = 96, ch = 104
            let p = PixelContext(cw, ch)
            let k = min(72 / CGFloat(img.width), 72 / CGFloat(img.height), 1.5)
            let w = CGFloat(img.width) * k, h = CGFloat(img.height) * k
            let rest = CGRect(x: (CGFloat(cw) - w) / 2, y: CGFloat(ch) - 4 - h, width: w, height: h)
            let r = rest.offsetBy(dx: 0, dy: bounce * 2)
            p.image(img, r.minX, r.minY, w, h, flipX: flip)
            if let pastime, !walking { OfficeArt.held(pastime, p, r, sheet: false, tick: tick / 2) }
            // Anchor the bubble to the resting position so it doesn't bob along with the sprite.
            if let icon, !walking { p.image(icon.bubble, rest.midX + 4, max(0, rest.minY - 14), 30, 28) }
            model.frame = p.makeImage()
            model.displayScale = scale * Self.canvas.width / CGFloat(cw)
        }

        updateMousePassthrough()
    }

    /// Transparent parts of the window must not block clicks on whatever is underneath.
    private func updateMousePassthrough() {
        let m = NSEvent.mouseLocation
        let f = panel.frame
        let spriteW = Self.canvas.width * CGFloat(settings.s.pet.scale)
        let spriteH = Self.canvas.height * CGFloat(settings.s.pet.scale)
        let sprite = CGRect(x: f.midX - spriteW / 2, y: f.minY, width: spriteW, height: spriteH)
        var interactive = sprite.contains(m) || dragging
        if !model.permissions.isEmpty || model.showSpeech {
            let upper = CGRect(x: f.minX, y: sprite.maxY - 4, width: f.width, height: f.maxY - sprite.maxY + 4)
            interactive = interactive || (upper.contains(m) && !model.permissions.isEmpty) || (model.hovering && f.contains(m))
        }
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
        if !sprite.contains(m), model.hovering, !f.contains(m) { model.hovering = false }
    }

    // MARK: Interaction

    func beginDrag() { dragging = true }

    func drag(to origin: CGPoint) {
        panel.setFrameOrigin(origin)
        x = origin.x
        baseline = origin.y
    }

    func endDrag() {
        dragging = false
        if pinnedSession == nil {
            if settings.s.pet.mode == .pinned {
                settings.s.pet.pinnedOrigin = [x, baseline]
            } else {
                settings.s.pet.roamBaseline = baseline
            }
        }
    }

    var origin: CGPoint { panel.frame.origin }

    func menu() -> NSMenu {
        let m = NSMenu()
        if let s = session {
            m.addItem(withTitle: "\(store.nickname(s)) · \(settings.projectName(s.projectKey))", action: nil, keyEquivalent: "").isEnabled = false
            m.addItem(.separator())
            m.addItem(MenuAction("이 세션 자동 허용", checked: s.autoAllowThisSession) { [store] in
                let on = !s.autoAllowThisSession
                if on, !AutoAllowWarning.confirm("이 세션") { return }
                store.setAutoAllow(s.id, on)
            })
            m.addItem(MenuAction("캐릭터·이름 바꾸기…") { AppDelegate.shared?.editSession(s.id) })
        }
        m.addItem(MenuAction(settings.s.pet.mode == .roam ? "제자리에 고정" : "자유롭게 돌아다니기") { [settings] in
            settings.s.pet.mode = settings.s.pet.mode == .roam ? .pinned : .roam
            if settings.s.pet.mode == .pinned { settings.s.pet.pinnedOrigin = [self.x, self.baseline] }
        })
        m.addItem(MenuAction("사무실 열기") { AppDelegate.shared?.showOffice() })
        if pinnedSession != nil {
            m.addItem(MenuAction("이 펫 집어넣기") { [weak self] in self?.onClose?() })
        } else {
            m.addItem(MenuAction("펫 숨기기") { [settings] in settings.s.pet.enabled = false })
        }
        return m
    }
}

/// Owns the auto-follow pet plus any pets popped out for specific sessions.
@MainActor
final class PetManager {
    static let shared = PetManager()
    private var auto: PetController?
    private(set) var pinned: [String: PetController] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private let store = SessionStore.shared
    private let settings = SettingsStore.shared

    private init() {
        settings.$s.map(\.pet.enabled).removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.sync() }
        }.store(in: &cancellables)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
    }

    func autoTarget() -> AgentSession? {
        store.sessions.values
            .filter { $0.activity != .leaving && $0.workerId != nil && pinned[$0.id] == nil }
            .max { a, b in
                // Prefer agents that need the user, then the most recently active one.
                (a.activity.needsUser ? 1 : 0, a.lastEventAt) < (b.activity.needsUser ? 1 : 0, b.lastEventAt)
            }
    }

    func sync() {
        let p = settings.s.pet
        let wantAuto = p.enabled && !(p.hideWhenNoAgents && autoTarget() == nil)
        if wantAuto, auto == nil {
            auto = PetController(pinnedSession: nil)
            auto?.show()
        } else if !wantAuto, let a = auto {
            a.close()
            auto = nil
        }
    }

    func popOut(_ key: String) {
        guard pinned[key] == nil else { return }
        let x = (auto?.origin.x ?? 400) - CGFloat(pinned.count + 1) * 90
        let c = PetController(pinnedSession: key, startX: x)
        c.onClose = { [weak self, weak c] in
            c?.close()
            self?.pinned.removeValue(forKey: key)
        }
        pinned[key] = c
        c.show()
    }

    func putBack(_ key: String) {
        pinned[key]?.onClose?()
    }

    func resetAuto() {
        auto?.close()
        auto = nil
        sync()
    }
}

final class MenuAction: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

// MARK: - Views

struct PetView: View {
    @ObservedObject var model: PetModel
    let controller: PetController

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            ForEach(model.permissions) { p in
                PermissionCard(p: p, compact: true)
            }
            if model.showSpeech {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.title).font(.system(size: 11, weight: .semibold))
                    Text(model.subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.15)))
                .frame(maxWidth: 260)
                .transition(.opacity)
            }
            if let img = model.frame {
                Image(decorative: img, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: CGFloat(img.width) * model.displayScale, height: CGFloat(img.height) * model.displayScale)
                    .overlay(DragHandle(controller: controller, hovering: $model.hovering))
            }
        }
        .frame(width: PetController.windowSize.width, height: PetController.windowSize.height, alignment: .bottom)
        .animation(.easeInOut(duration: 0.2), value: model.showSpeech)
    }
}

/// Click opens the menu, drag moves the window, hover shows the speech bubble.
struct DragHandle: NSViewRepresentable {
    let controller: PetController
    @Binding var hovering: Bool

    func makeNSView(context: Context) -> HandleView {
        let v = HandleView()
        v.controller = controller
        v.onHover = { hovering = $0 }
        return v
    }

    func updateNSView(_ v: HandleView, context: Context) {
        v.controller = controller
        v.onHover = { hovering = $0 }
    }

    final class HandleView: NSView {
        weak var controller: PetController?
        var onHover: ((Bool) -> Void)?
        private var grab: CGPoint = .zero
        private var start: CGPoint = .zero
        private var moved = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }

        override func mouseEntered(with event: NSEvent) { MainActor.assumeIsolated { onHover?(true) } }
        override func mouseExited(with event: NSEvent) { MainActor.assumeIsolated { onHover?(false) } }

        override func mouseDown(with event: NSEvent) {
            MainActor.assumeIsolated {
                guard let c = controller else { return }
                start = NSEvent.mouseLocation
                grab = CGPoint(x: start.x - c.origin.x, y: start.y - c.origin.y)
                moved = false
                c.beginDrag()
            }
        }

        override func mouseDragged(with event: NSEvent) {
            MainActor.assumeIsolated {
                let m = NSEvent.mouseLocation
                if hypot(m.x - start.x, m.y - start.y) > 3 { moved = true }
                if moved { controller?.drag(to: CGPoint(x: m.x - grab.x, y: m.y - grab.y)) }
            }
        }

        override func mouseUp(with event: NSEvent) {
            MainActor.assumeIsolated {
                guard let c = controller else { return }
                c.endDrag()
                if !moved { NSMenu.popUpContextMenu(c.menu(), with: event, for: self) }
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            MainActor.assumeIsolated {
                guard let c = controller else { return }
                NSMenu.popUpContextMenu(c.menu(), with: event, for: self)
            }
        }
    }
}

struct PermissionCard: View {
    let p: PendingPermission
    var compact = false
    @ObservedObject private var store = SessionStore.shared

    var body: some View {
        let s = store.session(p.sessionKey)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                Text("\(withSubjectParticle(s.map(store.nickname) ?? "에이전트"))\(p.agentType.map { " (\($0))" } ?? "") 허락을 기다려요")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            Text(p.summary)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(compact ? 3 : 5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
            if let r = p.reason {
                Text(r).font(.system(size: 10)).foregroundStyle(.red)
            }
            HStack(spacing: 6) {
                Button("허용") { store.resolve(p, .allow) }
                    .keyboardShortcut(.defaultAction)
                Button("거부") { store.resolve(p, .deny(nil)) }
                Button("이 세션 자동 허용") {
                    if AutoAllowWarning.confirm("이 세션") { store.resolve(p, .allow, allowSession: true) }
                }
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text("\(max(0, Int(p.deadline.timeIntervalSince(ctx.date))))s")
                        .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)
        }
        .padding(9)
        .frame(width: compact ? 260 : nil)
        .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.7), lineWidth: 1.5))
    }
}
