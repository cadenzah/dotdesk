import AppKit
import Combine
import CoreGraphics

/// Where desks, zones and the lounge go for the current set of sessions (pixel units).
struct OfficeLayout {
    static let deskW: CGFloat = 48, cellH: CGFloat = 80, wallH: CGFloat = 32, margin: CGFloat = 8, loungeW: CGFloat = 64

    struct Seat {
        let sessionKey: String
        let cell: CGRect
        var feet: CGPoint { CGPoint(x: cell.minX + 30, y: cell.minY + 48) }
        func helperFeet(_ i: Int) -> CGPoint { CGPoint(x: cell.minX + 10 + CGFloat(i) * 14, y: cell.minY + 78) }
    }

    struct Zone: Identifiable {
        let id: String
        let projectKey: String
        let rect: CGRect
    }

    var size = CGSize(width: 240, height: 124)
    var seats: [String: Seat] = [:]
    var zones: [Zone] = []
    var lounge = CGRect.zero
    var door = CGPoint.zero
    var corridorY: CGFloat = 0

    func loungeSpot(_ i: Int) -> CGPoint {
        let x = lounge.minX, y = lounge.minY
        if i < 2 { return CGPoint(x: x + 24 + CGFloat(i) * 16, y: y + 20) }
        let j = i - 2
        let perRow = 3
        return CGPoint(x: x + 14 + CGFloat(j % perRow) * 18, y: y + 52 + CGFloat(j / perRow) * 18)
    }

    static func make(sessions: [AgentSession], projectName: (String) -> String) -> OfficeLayout {
        var L = OfficeLayout()
        let seated = sessions.filter { $0.activity != .leaving }
        var groups: [(String, [AgentSession])] = []
        for s in seated {
            if let i = groups.firstIndex(where: { $0.0 == s.projectKey }) { groups[i].1.append(s) } else { groups.append((s.projectKey, [s])) }
        }
        groups.sort { projectName($0.0).localizedStandardCompare(projectName($1.0)) == .orderedAscending }

        let total = max(seated.count, 1)
        let cap = max(3, Int((Double(total).squareRoot() * 1.6).rounded(.up)))
        var rows: [[(String, [AgentSession])]] = [[]]
        var rowCount = 0
        for (key, list) in groups {
            for start in stride(from: 0, to: list.count, by: cap) {
                let chunk = Array(list[start..<min(start + cap, list.count)])
                if rowCount + chunk.count > cap, !rows[rows.count - 1].isEmpty {
                    rows.append([]); rowCount = 0
                }
                rows[rows.count - 1].append((key, chunk))
                rowCount += chunk.count
            }
        }

        var maxRowW: CGFloat = 0
        for (r, row) in rows.enumerated() {
            var x = margin
            let y = wallH + 4 + CGFloat(r) * cellH
            for (key, chunk) in row {
                let w = CGFloat(chunk.count) * deskW + 8
                L.zones.append(Zone(id: "\(key)#\(r)#\(x)", projectKey: key, rect: CGRect(x: x, y: y, width: w, height: cellH)))
                for (i, s) in chunk.enumerated() {
                    let cell = CGRect(x: x + 4 + CGFloat(i) * deskW, y: y, width: deskW, height: cellH)
                    L.seats[s.id] = Seat(sessionKey: s.id, cell: cell)
                }
                x += w + 4
            }
            maxRowW = max(maxRowW, x - 4 - margin)
        }
        let innerW = max(maxRowW, 3 * deskW + 8)
        let w = margin + innerW + margin + loungeW + margin
        let h = wallH + 4 + CGFloat(rows.count) * cellH + 4
        L.size = CGSize(width: w, height: h)
        L.lounge = CGRect(x: margin + innerW + margin, y: wallH + 4, width: loungeW, height: h - wallH - 8)
        L.door = CGPoint(x: margin + 13, y: wallH + 6)
        L.corridorY = wallH + 8
        return L
    }
}

/// Moves characters around the office and renders frames at ~12 fps while the office is visible.
@MainActor
final class OfficeSimulation: ObservableObject {
    enum Goal: Equatable { case seat, lounge(Int), door, helper(Int) }

    struct Actor {
        let id: String
        let sessionKey: String
        let subId: String?
        var pos: CGPoint
        var route: [CGPoint] = []
        var routeEnd: CGPoint?
        var facing: Facing = .down
        var goal: Goal = .seat
        var walking: Bool { !route.isEmpty }
    }

    struct Hit: Identifiable {
        let id: String
        let sessionKey: String
        let rect: CGRect
        let nameAnchor: CGPoint
    }

    @Published private(set) var frame: CGImage?
    @Published private(set) var layout = OfficeLayout()
    @Published private(set) var hits: [Hit] = []

    private var actors: [String: Actor] = [:]
    private var tick = 0
    private var timer: Timer?
    private let store = SessionStore.shared
    private let settings = SettingsStore.shared
    private let sprites = SpriteLibrary.shared

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        step()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Runs the simulation without a timer (used by --render-preview).
    func advance(_ n: Int) { for _ in 0..<n { step() } }

    private func step() {
        tick += 1
        let sessions = store.activeSessions
        let L = OfficeLayout.make(sessions: sessions, projectName: settings.projectName)
        let byKey = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })

        // Spawn / retarget actors
        var sleepingIndex = 0
        var wanted = Set<String>()
        for s in sessions {
            wanted.insert(s.id)
            if actors[s.id] == nil { actors[s.id] = Actor(id: s.id, sessionKey: s.id, subId: nil, pos: L.door) }
            let goal: Goal
            if s.activity == .leaving { goal = .door }
            else if s.activity == .sleeping { goal = .lounge(sleepingIndex); sleepingIndex += 1 }
            else { goal = .seat }
            actors[s.id]?.goal = goal
            for (i, sub) in s.subagents.prefix(3).enumerated() where s.activity != .sleeping && s.activity != .leaving {
                let id = "\(s.id)#\(sub.id)"
                wanted.insert(id)
                if actors[id] == nil { actors[id] = Actor(id: id, sessionKey: s.id, subId: sub.id, pos: L.door) }
                actors[id]?.goal = .helper(i)
            }
        }
        for (id, a) in actors where !wanted.contains(id) {
            actors[id]?.goal = .door
            if a.goal == .door, !a.walking, hypot(a.pos.x - L.door.x, a.pos.y - L.door.y) < 2 {
                actors.removeValue(forKey: id)
            }
        }

        // Move
        for id in Array(actors.keys) {
            guard var a = actors[id] else { continue }
            let target: CGPoint
            switch a.goal {
            case .seat: target = L.seats[a.sessionKey]?.feet ?? L.door
            case .lounge(let i): target = L.loungeSpot(i)
            case .door: target = L.door
            case .helper(let i): target = L.seats[a.sessionKey]?.helperFeet(i) ?? L.door
            }
            if a.routeEnd.map({ hypot($0.x - target.x, $0.y - target.y) > 0.5 }) ?? true {
                a.routeEnd = target
                if abs(a.pos.y - target.y) < 2 {
                    a.route = [target]
                } else {
                    a.route = [CGPoint(x: a.pos.x, y: L.corridorY), CGPoint(x: target.x, y: L.corridorY), target]
                }
            }
            var budget: CGFloat = 2.6
            while budget > 0, let next = a.route.first {
                let dx = next.x - a.pos.x, dy = next.y - a.pos.y
                let d = hypot(dx, dy)
                if d <= budget {
                    a.pos = next
                    a.route.removeFirst()
                    budget -= d
                } else {
                    a.pos.x += dx / d * budget
                    a.pos.y += dy / d * budget
                    a.facing = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
                    budget = 0
                }
            }
            if !a.walking {
                if case .helper = a.goal { a.facing = .up } else { a.facing = .down }
            }
            actors[id] = a
            if a.goal == .door, !a.walking, !wanted.contains(id) { actors.removeValue(forKey: id) }
        }

        layout = L
        frame = render(L, byKey)
    }

    // MARK: Rendering

    private func render(_ L: OfficeLayout, _ sessions: [String: AgentSession]) -> CGImage? {
        let W = Int(L.size.width), H = Int(L.size.height)
        let p = PixelContext(W, H)
        OfficeArt.floor(p, W, H, from: Int(OfficeLayout.wallH))
        OfficeArt.wall(p, width: W, height: Int(OfficeLayout.wallH))
        OfficeArt.door(p, OfficeLayout.margin + 4, 4)
        var wx: CGFloat = 40
        while wx + 26 < L.lounge.minX - 8 { OfficeArt.window(p, wx, 6); wx += 56 }
        OfficeArt.clock(p, L.lounge.minX + 27, 10)

        for z in L.zones {
            OfficeArt.rug(p, CGRect(x: z.rect.minX, y: z.rect.minY + 22, width: z.rect.width, height: 50),
                          settings.projectColor(z.projectKey))
        }
        OfficeArt.rug(p, L.lounge.insetBy(dx: 0, dy: 2), RGBA(0xadb5bd))

        var draws: [(CGFloat, () -> Void)] = []
        var bubbles: [() -> Void] = []
        var newHits: [Hit] = []

        for (key, seat) in L.seats {
            let c = seat.cell
            let s = sessions[key]
            draws.append((c.minY + 30, { OfficeArt.chairBack(p, c.minX + 30, c.minY + 26) }))
            draws.append((c.minY + 62, { OfficeArt.desk(p, c.minX, c.minY + 40) }))
            draws.append((c.minY + 63, {
                OfficeArt.monitor(p, c.minX + 4, c.minY + 24, activity: self.actorSeated(key) ? s?.activity : nil,
                                  tick: self.tick, accent: s.map { self.settings.projectColor($0.projectKey) } ?? RGBA(0x868e96))
                if let acc = s?.account { OfficeArt.flag(p, c.minX + 40, c.minY + 29, self.settings.accountColor(acc)) }
            }))
        }

        // Lounge furniture
        let lx = L.lounge.minX, ly = L.lounge.minY
        draws.append((ly + 22, { OfficeArt.sofa(p, lx + 16, ly + 6) }))
        draws.append((ly + 40, { OfficeArt.coffee(p, lx + 4, ly + 24) }))
        draws.append((ly + 44, { OfficeArt.plant(p, lx + 46, ly + 28) }))
        if L.lounge.height > 90 { draws.append((L.lounge.maxY, { OfficeArt.bookshelf(p, lx + 4, L.lounge.maxY - 34) })) }

        for a in actors.values {
            guard let s = sessions[a.sessionKey] ?? store.session(a.sessionKey) else { continue }
            let sub = a.subId.flatMap { id in s.subagents.first { $0.id == id } }
            let activity = sub?.activity ?? s.activity
            let ref = characterRef(for: s, subId: a.subId)
            let skin = sprites.skin(for: ref, shirt: settings.projectColor(s.projectKey))
            let seated = a.goal == .seat && !a.walking
            let lounging: Bool = { if case .lounge = a.goal, !a.walking { return true }; return false }()
            var pose: Pose = a.walking ? .walk : (lounging ? .sleep : activity.pose)
            if pose == .cheer && !skin.hasCheerFrame { pose = .stand }
            if !seated && a.subId == nil && (pose == .type || pose == .read) { pose = .stand }
            let (img, flip) = skin.frame(facing: a.facing, pose: pose, tick: tick)

            var bounce: CGFloat = 0
            if !a.walking {
                if activity == .done { bounce = tick % 6 < 3 ? -2 : 0 }
                if activity == .waitingPermission || activity == .waitingInput { bounce = tick % 10 < 2 ? -1 : 0 }
            }
            let rect: CGRect
            if skin.isSheet {
                rect = CGRect(x: a.pos.x - 8, y: a.pos.y - 32 + bounce, width: 16, height: 32)
            } else {
                let box: CGFloat = a.subId == nil ? 26 : 18
                let k = min(box / CGFloat(img.width), box / CGFloat(img.height), 1)
                let w = CGFloat(img.width) * k, h = CGFloat(img.height) * k
                rect = CGRect(x: a.pos.x - w / 2, y: a.pos.y - h + (seated ? -6 : 0) + bounce, width: w, height: h)
            }
            let z = seated ? (L.seats[a.sessionKey]?.cell.minY ?? 0) + 61 : a.pos.y
            draws.append((z, { p.image(img, rect.minX, rect.minY, rect.width, rect.height, flipX: flip, smooth: !skin.isSheet) }))

            let headTop = skin.isSheet ? rect.minY + 7 : rect.minY
            if !a.walking, let icon = (lounging ? PixelIcon.zzz : activity.icon) {
                // Bubbles stay at the resting position instead of bobbing with the sprite.
                let bx = rect.midX - 2, by = headTop - 13 - bounce
                bubbles.append({ p.image(icon.bubble, bx, by) })
            }
            if a.subId == nil {
                newHits.append(Hit(id: a.id, sessionKey: a.sessionKey,
                                   rect: CGRect(x: rect.minX - 2, y: headTop - 2, width: rect.width + 4, height: rect.maxY - headTop + 2),
                                   nameAnchor: seated ? CGPoint(x: (L.seats[a.sessionKey]?.cell.midX ?? a.pos.x), y: (L.seats[a.sessionKey]?.cell.minY ?? 0) + 70)
                                       : CGPoint(x: a.pos.x, y: a.pos.y + 6)))
            }
        }

        for (_, d) in draws.sorted(by: { $0.0 < $1.0 }) { d() }
        for b in bubbles { b() }
        hits = newHits
        return p.makeImage()
    }

    private func actorSeated(_ key: String) -> Bool {
        guard let a = actors[key] else { return false }
        return a.goal == .seat && !a.walking
    }

    func characterRef(for s: AgentSession, subId: String?) -> String {
        let ref = store.characterRef(s)
        guard let subId else { return ref }
        let i = s.subagents.firstIndex { $0.id == subId } ?? 0
        let parts = ref.split(separator: ":")
        if parts.count >= 2, let n = Int(parts[1]), parts[0] == "builtin" || parts[0] == "pa" {
            return "\(parts[0]):\(n + 1 + i)"
        }
        return ref
    }
}
