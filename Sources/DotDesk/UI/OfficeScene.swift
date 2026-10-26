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

    /// Floor area characters walk around. A spot inside one (a chair, a sofa seat) is entered and left from `exitUp`'s side.
    struct Obstacle {
        let rect: CGRect
        let exitUp: Bool
        var padded: CGRect { rect.insetBy(dx: -3, dy: -2) }
        func exit(_ x: CGFloat) -> CGPoint { CGPoint(x: x, y: exitUp ? padded.minY - 2 : padded.maxY + 2) }
    }

    /// Where a resting agent goes. Lounge spots fill in this order; once they are taken the rest nap at their own desk.
    enum RestSpot: Hashable { case sofa(Int), beanbag, desk }
    static let loungeSpots: [RestSpot] = [.sofa(0), .sofa(1), .beanbag]

    var size = CGSize(width: 240, height: 124)
    var seats: [String: Seat] = [:]
    var zones: [Zone] = []
    var obstacles: [Obstacle] = []
    var lounge = CGRect.zero
    var door = CGPoint.zero
    var corridorY: CGFloat = 0

    var sofa: CGRect { CGRect(x: lounge.minX + 16, y: lounge.minY + 6, width: 32, height: 16) }
    var beanbag: CGRect { CGRect(x: lounge.minX + 22, y: lounge.minY + 52, width: 20, height: 12) }

    /// Feet of someone resting there; seats put the feet at the front edge so the back rests against the backrest.
    func restFeet(_ spot: RestSpot, sessionKey: String) -> CGPoint? {
        switch spot {
        case .sofa(let i): return CGPoint(x: sofa.minX + 8 + CGFloat(i) * 16, y: sofa.maxY)
        case .beanbag: return CGPoint(x: beanbag.midX, y: beanbag.maxY - 1)
        case .desk: return seats[sessionKey]?.feet
        }
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
                    // Chair and desk together; the chair is reached from behind.
                    L.obstacles.append(Obstacle(rect: CGRect(x: cell.minX + 1, y: cell.minY + 22, width: 46, height: 44), exitUp: true))
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
        // Floor footprints of the lounge furniture drawn in `OfficeSimulation.render`.
        let lx = L.lounge.minX, ly = L.lounge.minY
        L.obstacles.append(Obstacle(rect: L.sofa, exitUp: false))
        L.obstacles.append(Obstacle(rect: L.beanbag, exitUp: false))
        L.obstacles.append(Obstacle(rect: CGRect(x: lx + 4, y: ly + 24, width: 12, height: 16), exitUp: false))
        L.obstacles.append(Obstacle(rect: CGRect(x: lx + 46, y: ly + 30, width: 16, height: 14), exitUp: false))
        if L.lounge.height > 90 {
            L.obstacles.append(Obstacle(rect: CGRect(x: lx + 4, y: L.lounge.maxY - 12, width: 16, height: 12), exitUp: false))
        }
        return L
    }

    // MARK: Walking routes

    /// Corner points from `start` to `end` that go around desks and furniture through the aisles.
    func route(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        var head: [CGPoint] = [], tail = [end]
        var a = start, b = end
        if let o = obstacles.first(where: { $0.padded.contains(start) }) { a = o.exit(start.x); head = [a] }
        if let o = obstacles.first(where: { $0.padded.contains(end) }) { b = o.exit(end.x); tail = [b, end] }
        guard let mid = gridPath(from: a, to: b) else {
            if abs(start.y - end.y) < 2 { return [end] }
            return [CGPoint(x: start.x, y: corridorY), CGPoint(x: end.x, y: corridorY), end]
        }
        var out: [CGPoint] = []
        for p in head + mid + tail {
            if let last = out.last, hypot(p.x - last.x, p.y - last.y) < 0.5 { continue }
            if out.count >= 2 {
                let q = out[out.count - 2], r = out[out.count - 1]
                if (abs(q.x - r.x) < 0.5 && abs(r.x - p.x) < 0.5) || (abs(q.y - r.y) < 0.5 && abs(r.y - p.y) < 0.5) { out.removeLast() }
            }
            out.append(p)
        }
        return out
    }

    /// A* over a 4px grid of free floor, with a cost per turn so paths stay on a few straight lines.
    private func gridPath(from a: CGPoint, to b: CGPoint) -> [CGPoint]? {
        let g: CGFloat = 4
        let cols = Int(size.width / g) + 1, rows = Int(size.height / g) + 1
        let blocked = obstacles.map(\.padded)
        var free = [Bool](repeating: false, count: cols * rows)
        for j in 0..<rows {
            for i in 0..<cols {
                let p = CGPoint(x: CGFloat(i) * g, y: CGFloat(j) * g)
                free[j * cols + i] = p.x >= 8 && p.x <= size.width - 8 && p.y >= OfficeLayout.wallH + 4 && p.y <= size.height - 2
                    && !blocked.contains { $0.contains(p) }
            }
        }
        func nearest(_ p: CGPoint) -> Int? {
            let ci = Int((p.x / g).rounded()), cj = Int((p.y / g).rounded())
            var best: (Int, CGFloat)?
            for j in cj - 2...cj + 2 where j >= 0 && j < rows {
                for i in ci - 2...ci + 2 where i >= 0 && i < cols && free[j * cols + i] {
                    let d = hypot(CGFloat(i) * g - p.x, CGFloat(j) * g - p.y)
                    if best == nil || d < best!.1 { best = (j * cols + i, d) }
                }
            }
            return best?.0
        }
        guard let s = nearest(a), let t = nearest(b) else { return nil }

        // State = node * 4 + heading (right, left, down, up).
        let steps = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let turnCost: Float = 8
        var cost = [Float](repeating: .infinity, count: cols * rows * 4)
        var parent = [Int32](repeating: -1, count: cols * rows * 4)
        var heap = MinHeap()
        let ti = t % cols, tj = t / cols
        func h(_ n: Int) -> Float { Float(abs(n % cols - ti) + abs(n / cols - tj)) * Float(g) }
        for d in 0..<4 { cost[s * 4 + d] = 0; heap.push(h(s), s * 4 + d) }
        var goal: Int?
        while let (f, st) = heap.pop() {
            let n = st / 4, d = st % 4
            if f - h(n) > cost[st] { continue }
            if n == t { goal = st; break }
            for (nd, (dx, dy)) in steps.enumerated() {
                let i = n % cols + dx, j = n / cols + dy
                guard i >= 0, i < cols, j >= 0, j < rows, free[j * cols + i] else { continue }
                let ns = (j * cols + i) * 4 + nd
                // The lane along the left wall is a squeeze; take it only when it is clearly shorter.
                let c = cost[st] + Float(g) + (nd == d ? 0 : turnCost) + (i * Int(g) < 12 ? 2 : 0)
                if c < cost[ns] { cost[ns] = c; parent[ns] = Int32(st); heap.push(c + h(j * cols + i), ns) }
            }
        }
        guard var st = goal else { return nil }

        var nodes: [CGPoint] = []
        while true {
            let n = st / 4
            nodes.append(CGPoint(x: CGFloat(n % cols) * g, y: CGFloat(n / cols) * g))
            let p = Int(parent[st])
            if p < 0 { break }
            st = p
        }
        nodes.reverse()
        var corners = [nodes[0]]
        for k in 1..<nodes.count {
            if k == nodes.count - 1 { corners.append(nodes[k]); break }
            let p = nodes[k - 1], q = nodes[k], r = nodes[k + 1]
            if (q.x - p.x != r.x - q.x) || (q.y - p.y != r.y - q.y) { corners.append(q) }
        }
        // Slide the first and last legs off the grid lines onto the real endpoints.
        let k = corners.count - 1
        if k == 0 { return [b] }
        if k == 1 {
            return abs(corners[0].x - corners[1].x) < 0.5 ? [CGPoint(x: a.x, y: b.y), b] : [CGPoint(x: b.x, y: a.y), b]
        }
        if abs(corners[0].x - corners[1].x) < 0.5 { corners[1].x = a.x } else { corners[1].y = a.y }
        if abs(corners[k - 1].x - corners[k].x) < 0.5 { corners[k - 1].x = b.x } else { corners[k - 1].y = b.y }
        corners[0] = a
        corners[k] = b
        return Array(corners.dropFirst())
    }
}

/// Binary min-heap of (priority, value) for the route search.
private struct MinHeap {
    private var items: [(Float, Int)] = []

    mutating func push(_ priority: Float, _ value: Int) {
        items.append((priority, value))
        var i = items.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            if items[p].0 <= items[i].0 { break }
            items.swapAt(p, i); i = p
        }
    }

    mutating func pop() -> (Float, Int)? {
        guard !items.isEmpty else { return nil }
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count, items[l].0 < items[m].0 { m = l }
                if r < items.count, items[r].0 < items[m].0 { m = r }
                if m == i { break }
                items.swapAt(m, i); i = m
            }
        }
        return top
    }
}

/// Moves characters around the office and renders frames at ~12 fps while the office is visible.
@MainActor
final class OfficeSimulation: ObservableObject {
    enum Goal: Equatable { case seat, rest(OfficeLayout.RestSpot), door, helper(Int) }

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
    private var restSpots: [String: OfficeLayout.RestSpot] = [:]
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

        // Resting agents keep their spot until they wake; a new one takes the first free lounge spot or naps at their desk.
        restSpots = restSpots.filter { byKey[$0.key]?.activity == .sleeping }
        for s in sessions where s.activity == .sleeping && restSpots[s.id] == nil {
            let taken = Set(restSpots.values)
            restSpots[s.id] = OfficeLayout.loungeSpots.first { !taken.contains($0) } ?? .desk
        }

        // Spawn / retarget actors
        var wanted = Set<String>()
        for s in sessions {
            wanted.insert(s.id)
            if actors[s.id] == nil { actors[s.id] = Actor(id: s.id, sessionKey: s.id, subId: nil, pos: L.door) }
            let goal: Goal
            if s.activity == .leaving { goal = .door }
            else if let spot = restSpots[s.id] { goal = .rest(spot) }
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
            case .rest(let spot): target = L.restFeet(spot, sessionKey: a.sessionKey) ?? L.door
            case .door: target = L.door
            case .helper(let i): target = L.seats[a.sessionKey]?.helperFeet(i) ?? L.door
            }
            if a.routeEnd.map({ hypot($0.x - target.x, $0.y - target.y) > 0.5 }) ?? true {
                a.routeEnd = target
                a.route = L.route(from: a.pos, to: target)
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
        let sofa = L.sofa, beanbag = L.beanbag
        draws.append((sofa.maxY, { OfficeArt.sofa(p, sofa.minX, sofa.minY) }))
        draws.append((beanbag.maxY, { OfficeArt.beanbag(p, beanbag.minX, beanbag.minY) }))
        // Someone alone on the sofa lies down; a second sleeper makes them sit up.
        let sofaCount = actors.values.filter { if case .rest(.sofa) = $0.goal { return true }; return false }.count
        draws.append((ly + 40, { OfficeArt.coffee(p, lx + 4, ly + 24) }))
        draws.append((ly + 44, { OfficeArt.plant(p, lx + 46, ly + 28) }))
        if L.lounge.height > 90 { draws.append((L.lounge.maxY, { OfficeArt.bookshelf(p, lx + 4, L.lounge.maxY - 34) })) }

        for a in actors.values {
            guard let s = sessions[a.sessionKey] ?? store.session(a.sessionKey) else { continue }
            let sub = a.subId.flatMap { id in s.subagents.first { $0.id == id } }
            let activity = sub?.activity ?? s.activity
            let ref = characterRef(for: s, subId: a.subId)
            let skin = sprites.skin(for: ref, shirt: settings.projectColor(s.projectKey))
            let napping = a.goal == .rest(.desk) && !a.walking
            let seated = (a.goal == .seat || napping) && !a.walking
            let resting: Bool = { if case .rest = a.goal, !a.walking { return true }; return false }()
            let onSofa: Bool = { if case .rest(.sofa) = a.goal, !a.walking { return true }; return false }()
            let onBeanbag = a.goal == .rest(.beanbag) && !a.walking
            let lying = onSofa && sofaCount == 1 && skin.isSheet
            var pose: Pose = a.walking ? .walk : napping ? .nap : (onSofa || onBeanbag) ? .sit : activity.pose
            if pose == .cheer && !skin.hasCheerFrame { pose = .stand }
            if !seated && a.subId == nil && (pose == .type || pose == .read) { pose = .stand }
            var (img, flip) = skin.frame(facing: a.facing, pose: pose, tick: tick)
            if lying, let r = skin.frame(facing: .down, pose: .sleep, tick: tick).0.rotatedLeft() { (img, flip) = (r, false) }

            var bounce: CGFloat = 0
            if !a.walking {
                if activity == .done { bounce = tick % 6 < 3 ? -2 : 0 }
                if activity == .waitingPermission || activity == .waitingInput { bounce = tick % 10 < 2 ? -1 : 0 }
            }
            let rect: CGRect
            if lying {
                // Head on the left armrest, body along the seat cushion.
                rect = CGRect(x: sofa.minX - 4, y: sofa.minY, width: 32, height: 16)
            } else if skin.isSheet {
                // Sinks a little into the beanbag, and slumps toward the desk when napping.
                let sink: CGFloat = onBeanbag ? 2 : napping ? 3 : 0
                rect = CGRect(x: a.pos.x - 8, y: a.pos.y - 32 + sink + bounce, width: 16, height: 32)
            } else {
                let box: CGFloat = a.subId == nil ? 26 : 18
                let k = min(box / CGFloat(img.width), box / CGFloat(img.height), 1)
                let w = CGFloat(img.width) * k, h = CGFloat(img.height) * k
                rect = CGRect(x: a.pos.x - w / 2, y: a.pos.y - h + (seated ? -6 : onSofa ? -4 : onBeanbag ? -2 : 0) + bounce, width: w, height: h)
            }
            let z = seated ? (L.seats[a.sessionKey]?.cell.minY ?? 0) + 61
                : onSofa ? sofa.maxY + 0.5 : onBeanbag ? beanbag.maxY + 0.5 : a.pos.y
            draws.append((z, { p.image(img, rect.minX, rect.minY, rect.width, rect.height, flipX: flip, smooth: !skin.isSheet) }))

            let headTop = lying ? rect.minY + 3 : skin.isSheet ? rect.minY + 7 : rect.minY
            if !a.walking, let icon = (resting ? PixelIcon.zzz : activity.icon) {
                // Bubbles stay at the resting position instead of bobbing with the sprite.
                let bx = lying ? rect.minX + 8 : rect.midX - 2, by = headTop - 13 - bounce
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
        if ref.hasPrefix("mix:") { return BuiltinCharacters.mixRef(stableHash("\(ref)/\(i + 1)")) }
        let parts = ref.split(separator: ":")
        if parts.count >= 2, let n = Int(parts[1]), parts[0] == "builtin" || parts[0] == "pa" {
            return "\(parts[0]):\(n + 1 + i)"
        }
        return ref
    }
}
