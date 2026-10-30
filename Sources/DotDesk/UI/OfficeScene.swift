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

    /// Where a resting agent goes. Each spot holds one agent, except everyone's own desk.
    /// `chat(window, side)` is a pair of spots at a window where two agents stand and talk.
    enum RestSpot: Hashable { case sofa(Int), beanbag, desk, coffee, plant, window(Int), chat(Int, Int), stretch, bookshelf }

    var size = CGSize(width: 240, height: 124)
    var seats: [String: Seat] = [:]
    var zones: [Zone] = []
    var obstacles: [Obstacle] = []
    var lounge = CGRect.zero
    var door = CGPoint.zero
    var corridorY: CGFloat = 0
    /// Left edges of the windows on the office wall.
    var windows: [CGFloat] = []

    var hasBookshelf: Bool { lounge.height > 90 }

    /// Rest spots grouped by kind, so a wide office with many windows doesn't make window-gazing the usual pick.
    var restKinds: [[RestSpot]] {
        [[.sofa(0), .sofa(1)], [.beanbag], [.desk], [.coffee], [.plant], windows.indices.map { .window($0) },
         windows.indices.map { .chat($0, 0) }, [.stretch]] + (hasBookshelf ? [[.bookshelf]] : [])
    }

    var sofa: CGRect { CGRect(x: lounge.minX + 16, y: lounge.minY + 6, width: 32, height: 16) }
    /// Free stretches of wall between the door, the windows and the lounge, left to right.
    var wallGaps: [ClosedRange<CGFloat>] {
        var edges: [CGFloat] = [OfficeLayout.margin + 23]
        for w in windows { edges += [w, w + 26] }
        edges.append(lounge.minX - 4)
        return stride(from: 0, to: edges.count - 1, by: 2).compactMap { i in
            edges[i + 1] > edges[i] ? edges[i]...edges[i + 1] : nil
        }
    }

    /// Top-left of the floor lamp in the lounge, right of the beanbag.
    var lamp: CGPoint { CGPoint(x: lounge.minX + 27, y: lounge.minY + 50) }

    /// On the lounge wall, right of the clock.
    var whiteboard: CGRect { CGRect(x: lounge.minX + 17, y: 3, width: 44, height: 22) }
    var beanbag: CGRect { CGRect(x: lounge.minX + 4, y: lounge.minY + 60, width: 20, height: 12) }

    /// Feet of someone resting there; seats put the feet at the front edge so the back rests against the backrest.
    func restFeet(_ spot: RestSpot, sessionKey: String) -> CGPoint? {
        switch spot {
        case .sofa(let i): return CGPoint(x: sofa.minX + 8 + CGFloat(i) * 16, y: sofa.maxY)
        case .beanbag: return CGPoint(x: beanbag.midX, y: beanbag.maxY - 1)
        case .desk: return seats[sessionKey]?.feet
        case .coffee: return CGPoint(x: lounge.minX + 9, y: lounge.minY + 44)
        case .plant: return CGPoint(x: lounge.minX + 38, y: lounge.minY + 46)
        case .window(let i): return i < windows.count ? CGPoint(x: windows[i] + 13, y: OfficeLayout.wallH + 10) : nil
        case .chat(let i, let side): return i < windows.count ? CGPoint(x: windows[i] + 5 + CGFloat(side) * 16, y: OfficeLayout.wallH + 10) : nil
        case .stretch: return CGPoint(x: lounge.minX + 54, y: lounge.maxY - 10)
        case .bookshelf: return hasBookshelf ? CGPoint(x: lounge.minX + 28, y: lounge.maxY - 4) : nil
        }
    }

    /// Which way someone faces once they reach the spot.
    static func restFacing(_ spot: RestSpot) -> Facing {
        switch spot {
        case .window, .coffee: return .up
        case .plant, .chat(_, 0): return .right
        case .bookshelf, .chat: return .left
        default: return .down
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
        var wx: CGFloat = 40
        while wx + 26 < L.lounge.minX - 8 { L.windows.append(wx); wx += 56 }
        // Floor footprints of the lounge furniture drawn in `OfficeSimulation.render`.
        let lx = L.lounge.minX, ly = L.lounge.minY
        L.obstacles.append(Obstacle(rect: L.sofa, exitUp: false))
        L.obstacles.append(Obstacle(rect: L.beanbag, exitUp: false))
        L.obstacles.append(Obstacle(rect: CGRect(x: L.lamp.x, y: L.lamp.y + 17, width: 6, height: 5), exitUp: false))
        L.obstacles.append(Obstacle(rect: CGRect(x: lx + 2, y: ly + 8, width: 12, height: 16), exitUp: false))
        L.obstacles.append(Obstacle(rect: CGRect(x: lx + 46, y: ly + 30, width: 16, height: 14), exitUp: false))
        if L.hasBookshelf {
            L.obstacles.append(Obstacle(rect: CGRect(x: lx + 4, y: L.lounge.maxY - 12, width: 16, height: 12), exitUp: false))
        }
        return L
    }

    // MARK: Walking routes

    /// Corner points from `start` to `end` that go around desks and furniture through the aisles, and around `avoiding`.
    func route(from start: CGPoint, to end: CGPoint, avoiding: [CGRect] = []) -> [CGPoint] {
        var head: [CGPoint] = [], tail = [end]
        var a = start, b = end
        if let o = obstacles.first(where: { $0.padded.contains(start) }) { a = o.exit(start.x); head = [a] }
        if let o = obstacles.first(where: { $0.padded.contains(end) }) { b = o.exit(end.x); tail = [b, end] }
        guard let mid = gridPath(from: a, to: b, avoiding: avoiding) else {
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
    private func gridPath(from a: CGPoint, to b: CGPoint, avoiding: [CGRect]) -> [CGPoint]? {
        let g: CGFloat = 4
        let cols = Int(size.width / g) + 1, rows = Int(size.height / g) + 1
        let blocked = obstacles.map(\.padded) + avoiding
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
    enum Goal: Equatable {
        case seat, rest(OfficeLayout.RestSpot), door, helper(Int)

        /// Shown instead of the session's activity while walking there.
        var label: String {
            switch self {
            case .seat, .rest(.desk): return L("자리로 가는 중", "Heading to desk")
            case .rest(.sofa): return L("소파로 가는 중", "Heading to the sofa")
            case .rest(.beanbag): return L("빈백으로 가는 중", "Heading to the beanbag")
            case .rest(.coffee): return L("커피 머신으로 가는 중", "Heading for coffee")
            case .rest(.plant): return L("화분으로 가는 중", "Heading to the plant")
            case .rest(.window), .rest(.chat): return L("창가로 가는 중", "Heading to the window")
            case .rest(.stretch): return L("휴게실로 가는 중", "Heading to the lounge")
            case .rest(.bookshelf): return L("책장으로 가는 중", "Heading to the bookshelf")
            case .door: return L("퇴근하는 중", "Heading home")
            case .helper: return L("도우러 가는 중", "Going to help")
            }
        }
    }

    /// What a resting agent does at their spot; decides the pose, what they hold, the bubble and the tooltip.
    enum Pastime {
        case nap, game, read, coffee, water, gaze, chat, stretch, browse

        static func choices(at spot: OfficeLayout.RestSpot) -> [Pastime] {
            switch spot {
            case .sofa: return [.nap, .game]
            case .beanbag: return [.nap, .read]
            case .desk: return [.nap]
            case .coffee: return [.coffee]
            case .plant: return [.water]
            case .window: return [.gaze]
            case .chat: return [.chat]
            case .stretch: return [.stretch]
            case .bookshelf: return [.browse]
            }
        }

        var icon: PixelIcon {
            switch self {
            case .nap: return .zzz
            case .game: return .game
            case .read, .browse: return .book
            case .coffee: return .coffee
            case .water: return .droplet
            case .gaze: return OfficeArt.skyColor().1 ? .moon : .sun
            case .chat: return .talk
            case .stretch: return .sparkle
            }
        }

        /// `spot` is nil for the desktop pet, which has no furniture.
        func label(at spot: OfficeLayout.RestSpot? = nil) -> String {
            switch (self, spot) {
            case (.nap, .sofa?): return L("소파에서 낮잠 자는 중", "Napping on the sofa")
            case (.nap, .beanbag?): return L("빈백에서 조는 중", "Dozing on the beanbag")
            case (.nap, .desk?): return L("책상에 엎드려 자는 중", "Napping at the desk")
            case (.nap, _): return L("꾸벅꾸벅 조는 중", "Nodding off")
            case (.game, nil): return L("게임하는 중", "Playing games")
            case (.game, _): return L("소파에서 게임하는 중", "Gaming on the sofa")
            case (.read, nil): return L("책 읽는 중", "Reading")
            case (.read, _): return L("빈백에서 책 읽는 중", "Reading on the beanbag")
            case (.coffee, _): return L("커피 마시는 중", "Having coffee")
            case (.water, _): return L("화분에 물 주는 중", "Watering the plant")
            case (.gaze, _): return L("창밖 구경하는 중", "Gazing out the window")
            case (.chat, _): return L("창가에서 수다 떠는 중", "Chatting by the window")
            case (.stretch, _): return L("스트레칭하는 중", "Stretching")
            case (.browse, _): return L("책장에서 책 고르는 중", "Browsing the bookshelf")
            }
        }

        /// Pose, plus a facing while stretching. Nil for naps, whose pose depends on where they sleep.
        func pose(_ skin: CharacterSkin, tick: Int) -> (Pose, Facing?)? {
            switch self {
            case .nap: return nil
            case .game: return (.type, nil)
            case .read: return (.read, nil)
            case .stretch:
                // Arms up and down, or a twist from side to side for sheets without that frame.
                let phase = tick / 10 % 4
                return skin.hasCheerFrame ? (phase % 2 == 0 ? .stand : .cheer, nil) : (.stand, [Facing.down, .left, .down, .right][phase])
            default: return (.stand, nil)
            }
        }
    }

    /// A worker walking around (keyed by worker, so they keep their place when they take on another session), or a subagent.
    struct Actor {
        let id: String
        var sessionKey: String
        let subId: String?
        var pos: CGPoint
        var route: [CGPoint] = []
        var routeEnd: CGPoint?
        var facing: Facing = .down
        var goal: Goal = .seat
        /// Ticks since they last stopped walking.
        var still = 0
        /// A subagent who has been handed their work, and the tick until which they stay to hand results back.
        var briefed = false
        var returnUntil: Int?
        /// Until this tick they take turns talking; `talkPhase` says whose turn comes first.
        var talkUntil = 0
        var talkPhase = 0
        var walking: Bool { !route.isEmpty }
    }

    /// A sheet of paper or a paper plane flying between two people.
    struct Handoff {
        enum Item { case paper, plane }
        let from: String
        /// An actor to fly to, or a fixed spot (the door, for messages to someone not in the office).
        let to: String?
        let toPoint: CGPoint?
        let item: Item
        let start: Int
        var length: Int { item == .plane ? 20 : 12 }
    }

    struct Hit: Identifiable {
        let id: String
        let sessionKey: String
        let rect: CGRect
        let nameAnchor: CGPoint
        /// What a resting agent is up to, shown instead of the session's activity.
        var label: String?
    }

    @Published private(set) var frame: CGImage?
    @Published private(set) var layout = OfficeLayout()
    @Published private(set) var hits: [Hit] = []

    private var actors: [String: Actor] = [:]
    private var handoffs: [Handoff] = []
    private var messageSub: AnyCancellable?
    private let planner: RestPlanner
    /// Who was standing at a window when routes were last planned.
    private var lastGazers: Set<String> = []
    private var tick = 0
    private var timer: Timer?
    private let store = SessionStore.shared
    private let settings = SettingsStore.shared
    private let sprites = SpriteLibrary.shared

    /// The shared planner keeps the office in step with the desktop pet; --render-preview passes a seeded one.
    init(planner: RestPlanner? = nil) {
        self.planner = planner ?? .shared
        messageSub = store.messages.sink { [weak self] m in
            MainActor.assumeIsolated { self?.deliver(m) }
        }
    }

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
        planner.walking = [:]
    }

    /// Runs the simulation without a timer (used by --render-preview).
    func advance(_ n: Int) { for _ in 0..<n { step() } }

    /// Sends a sleeping agent to a given spot for good (used by --render-preview).
    func debugRest(_ key: String, _ spot: OfficeLayout.RestSpot, _ pastime: Pastime) {
        planner.debugRest(key, spot, pastime)
    }

    private func step() {
        tick += 1
        let sessions = store.activeSessions
        let L = OfficeLayout.make(sessions: sessions, projectName: settings.projectName)
        let byKey = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })

        planner.update(L)
        let rests = planner.rests

        // Spawn / retarget actors
        var wanted = Set<String>()
        for s in sessions {
            guard let wid = s.workerId else { continue }
            wanted.insert(wid)
            if actors[wid] == nil { actors[wid] = Actor(id: wid, sessionKey: s.id, subId: nil, pos: L.door) }
            actors[wid]?.sessionKey = s.id
            let goal: Goal
            if s.activity == .leaving { goal = .door }
            else if let r = rests[s.id] { goal = .rest(r.spot) }
            else { goal = .seat }
            actors[wid]?.goal = goal
            for (i, sub) in s.subagents.prefix(3).enumerated() where s.activity != .sleeping && s.activity != .leaving {
                let id = "\(s.id)#\(sub.id)"
                wanted.insert(id)
                if actors[id] == nil { actors[id] = Actor(id: id, sessionKey: s.id, subId: sub.id, pos: L.door) }
                actors[id]?.goal = .helper(i)
            }
        }
        for (id, a) in actors where !wanted.contains(id) {
            // A subagent done with their work hands the results back before heading out.
            if a.subId != nil, a.briefed, a.returnUntil == nil, !a.walking, case .helper = a.goal {
                actors[id]?.returnUntil = tick + 22
                if let main = mainActor(a.sessionKey) { converse(main, id, give: false) }
                continue
            }
            if let r = a.returnUntil, tick < r { continue }
            actors[id]?.goal = .door
            if a.goal == .door, !a.walking, hypot(a.pos.x - L.door.x, a.pos.y - L.door.y) < 2 {
                actors.removeValue(forKey: id)
            }
        }

        // People at a window (gazing or chatting) stand in the corridor; everyone else walks around them, re-planning when that changes.
        var gazers: [String: CGRect] = [:]
        for a in actors.values where !a.walking {
            switch a.goal {
            case .rest(.window), .rest(.chat): gazers[a.id] = CGRect(x: a.pos.x - 6, y: a.pos.y - 6, width: 12, height: 12)
            default: break
            }
        }
        if Set(gazers.keys) != lastGazers {
            lastGazers = Set(gazers.keys)
            for id in Array(actors.keys) where actors[id]?.walking == true { actors[id]?.routeEnd = nil }
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
                a.route = L.route(from: a.pos, to: target, avoiding: gazers.filter { $0.key != id }.map(\.value))
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
            a.still = a.walking ? 0 : a.still + 1
            if a.subId != nil, !a.walking, !a.briefed, case .helper = a.goal {
                // Just arrived at the desk: get briefed and take the papers.
                a.briefed = true
                actors[id] = a
                if let main = mainActor(a.sessionKey) { converse(main, id, give: true) }
                a = actors[id] ?? a
            }
            if !a.walking {
                switch a.goal {
                case .helper: a.facing = .up
                case .rest(let spot): a.facing = OfficeLayout.restFacing(spot)
                default: a.facing = .down
                }
            }
            actors[id] = a
            if a.goal == .door, !a.walking, !wanted.contains(id) { actors.removeValue(forKey: id) }
        }

        planner.walking = Dictionary(actors.values.filter { $0.subId == nil && $0.walking }.map { ($0.sessionKey, ($0.goal, $0.facing)) },
                                     uniquingKeysWith: { a, _ in a })
        layout = L
        frame = render(L, byKey)
    }

    // MARK: Handoffs

    private func mainActor(_ sessionKey: String) -> String? {
        actors.values.first { $0.sessionKey == sessionKey && $0.subId == nil }?.id
    }

    /// The main agent and a subagent talk in turn while papers change hands.
    private func converse(_ main: String, _ helper: String, give: Bool) {
        actors[main]?.talkUntil = tick + 36
        actors[main]?.talkPhase = give ? 0 : 1
        actors[helper]?.talkUntil = tick + 36
        actors[helper]?.talkPhase = give ? 1 : 0
        handoffs.append(Handoff(from: give ? main : helper, to: give ? helper : main, toPoint: nil, item: .paper, start: tick + 6))
    }

    /// A paper plane from the sender to whoever it names: one of their subagents, the main agent for a subagent's
    /// message, another agent in the same project, or out the door.
    private func deliver(_ m: AgentMessage) {
        guard let main = mainActor(m.sessionKey) else { return }
        let from = m.fromSub.map { "\(m.sessionKey)#\($0)" }.flatMap { actors[$0] != nil ? $0 : nil } ?? main
        var to: String?
        if m.fromSub != nil {
            to = main
        } else if let s = store.session(m.sessionKey) {
            let helpers = s.subagents.map { "\(s.id)#\($0.id)" }.filter { actors[$0] != nil }
            let named = s.subagents.first { $0.id == m.to || $0.type == m.to }.map { "\(s.id)#\($0.id)" }
            to = named.flatMap { actors[$0] != nil ? $0 : nil } ?? helpers.first
            if to == nil {
                let peer = store.activeSessions.filter { $0.id != s.id && $0.projectKey == s.projectKey && $0.activity != .leaving }
                    .max { $0.lastEventAt < $1.lastEventAt }
                to = peer.flatMap { mainActor($0.id) }
            }
        }
        handoffs.append(Handoff(from: from, to: to, toPoint: to == nil ? layout.door : nil, item: .plane, start: tick))
    }

    /// Where papers are passed: on the desk in front of someone seated, above the head of someone facing away
    /// (hands raised to take it), chest height otherwise.
    private func hand(_ id: String, _ L: OfficeLayout) -> CGPoint? {
        guard let a = actors[id] else { return nil }
        let seated = a.goal == .seat && !a.walking
        return CGPoint(x: a.pos.x, y: a.pos.y - (seated ? 9 : a.facing == .up ? 30 : 14))
    }

    private func drawHandoffs(_ p: PixelContext, _ L: OfficeLayout) {
        handoffs.removeAll { tick > $0.start + $0.length }
        for h in handoffs where tick >= h.start {
            guard let a = hand(h.from, L), let b = h.to.flatMap({ hand($0, L) }) ?? h.toPoint else { continue }
            let t = CGFloat(tick - h.start) / CGFloat(h.length)
            let x = a.x + (b.x - a.x) * t
            let y = a.y + (b.y - a.y) * t - sin(t * .pi) * (h.item == .plane ? 16 : 8)
            switch h.item {
            case .paper: OfficeArt.paper(p, x.rounded(), y.rounded())
            case .plane: OfficeArt.paperPlane(p, x.rounded(), y.rounded(), right: b.x >= a.x)
            }
        }
    }

    // MARK: Rendering

    private func render(_ L: OfficeLayout, _ sessions: [String: AgentSession]) -> CGImage? {
        let W = Int(L.size.width), H = Int(L.size.height)
        let p = PixelContext(W, H)
        OfficeArt.floor(p, W, H, from: Int(OfficeLayout.wallH))
        OfficeArt.wall(p, width: W, height: Int(OfficeLayout.wallH))
        OfficeArt.door(p, OfficeLayout.margin + 4, 4)
        for wx in L.windows { OfficeArt.window(p, wx, 6) }
        // Above the coffee machine, where the sofa sitters' bubbles don't cover it.
        OfficeArt.clock(p, L.lounge.minX + 3, 10)
        OfficeArt.whiteboard(p, L.whiteboard, busyByHour: DailyStats.shared.today.busyByHour)
        let stats = DailyStats.shared
        let decorate = settings.s.office.showDecorations
        func has(_ d: Decoration) -> Bool { decorate && stats.isUnlocked(d) }
        let gaps = L.wallGaps
        if has(.plaque), let g = gaps.first, g.upperBound - g.lowerBound >= 9 {
            OfficeArt.plaque(p, ((g.lowerBound + g.upperBound) / 2 - 4).rounded(), 11)
        }
        if has(.frame), gaps.count > 1 {
            OfficeArt.pictureFrame(p, ((gaps[1].lowerBound + gaps[1].upperBound) / 2 - 8).rounded(), 8)
        }
        if has(.trophies), gaps.count > 2, gaps[2].upperBound - gaps[2].lowerBound >= 24 {
            OfficeArt.trophyShelf(p, ((gaps[2].lowerBound + gaps[2].upperBound) / 2 - 11).rounded(), 9,
                                  count: max(1, Decoration.trophyCount(stats.totals)))
        }
        if has(.cat), let wx = L.windows.first { OfficeArt.windowCat(p, wx + 15, 18, tick: tick) }
        if has(.lights) { OfficeArt.stringLights(p, from: OfficeLayout.margin + 24, to: L.whiteboard.minX - 2, tick: tick) }

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
        if has(.lamp) { let lp = L.lamp; draws.append((lp.y + 22, { OfficeArt.floorLamp(p, lp.x, lp.y) })) }
        // Someone alone on the sofa lies down; a second sleeper makes them sit up.
        let sofaCount = actors.values.filter { if case .rest(.sofa) = $0.goal { return true }; return false }.count
        draws.append((ly + 24, { OfficeArt.coffee(p, lx + 2, ly + 8) }))
        draws.append((ly + 44, { OfficeArt.plant(p, lx + 46, ly + 28) }))
        if L.hasBookshelf { draws.append((L.lounge.maxY, { OfficeArt.bookshelf(p, lx + 4, L.lounge.maxY - 34) })) }

        for a in actors.values {
            guard let s = sessions[a.sessionKey] ?? store.session(a.sessionKey) else { continue }
            let sub = a.subId.flatMap { id in s.subagents.first { $0.id == id } }
            let activity = sub?.activity ?? s.activity
            let ref = characterRef(for: s, subId: a.subId)
            let skin = sprites.skin(for: ref, shirt: settings.projectColor(s.projectKey))
            let plan: RestPlanner.Rest? = { if case .rest(let spot) = a.goal, let r = planner.rests[a.sessionKey], r.spot == spot { return r }; return nil }()
            let rest = a.walking ? nil : plan
            let napping = a.goal == .rest(.desk) && !a.walking
            let seated = (a.goal == .seat || napping) && !a.walking
            let onSofa: Bool = { if case .rest(.sofa) = a.goal, !a.walking { return true }; return false }()
            let onBeanbag = a.goal == .rest(.beanbag) && !a.walking
            let lying = onSofa && rest?.pastime == .nap && sofaCount == 1 && skin.isSheet
            var facing = a.facing
            var pose: Pose
            if a.walking {
                pose = .walk
            } else if let rest {
                if let (p, f) = rest.pastime.pose(skin, tick: tick) {
                    pose = p
                    if let f { facing = f }
                } else {
                    pose = napping ? .nap : .sit
                }
                // Brews at the machine for a few seconds, then turns around with the mug.
                if rest.pastime == .coffee { facing = a.still < 48 ? .up : .down }
            } else {
                pose = activity.pose
            }
            let reaction = a.walking || a.subId != nil || rest != nil ? nil : s.activeReaction
            if reaction?.cheers == true { pose = tick / 3 % 2 == 0 ? .cheer : .stand }
            if pose == .cheer && !skin.hasCheerFrame { pose = .stand }
            if !seated && !onSofa && !onBeanbag && a.subId == nil && (pose == .type || pose == .read) { pose = .stand }
            var (img, flip) = skin.frame(facing: facing, pose: pose, tick: tick)
            if lying, let r = skin.frame(facing: .down, pose: .sleep, tick: tick).0.rotatedLeft() { (img, flip) = (r, false) }

            var bounce: CGFloat = 0
            if !a.walking {
                if activity == .done { bounce = tick % 6 < 3 ? -2 : 0 }
                if activity == .waitingPermission || activity == .waitingInput { bounce = tick % 10 < 2 ? -1 : 0 }
                if reaction?.cheers == true { bounce = tick / 3 % 2 == 0 ? -2 : 0 }
            }
            let shake: CGFloat = reaction?.shakes == true ? (tick % 2 == 0 ? -1 : 1) : 0
            let rect: CGRect
            if lying {
                // Head on the left armrest, body along the seat cushion.
                rect = CGRect(x: sofa.minX - 4, y: sofa.minY, width: 32, height: 16)
            } else if skin.isSheet {
                // Sinks a little into the beanbag, and slumps toward the desk when napping.
                let sink: CGFloat = onBeanbag ? 2 : napping ? 3 : 0
                rect = CGRect(x: a.pos.x - 8 + shake, y: a.pos.y - 32 + sink + bounce, width: 16, height: 32)
            } else {
                let box: CGFloat = a.subId == nil ? 26 : 18
                let k = min(box / CGFloat(img.width), box / CGFloat(img.height), 1)
                let w = CGFloat(img.width) * k, h = CGFloat(img.height) * k
                rect = CGRect(x: a.pos.x - w / 2 + shake, y: a.pos.y - h + (seated ? -6 : onSofa ? -4 : onBeanbag ? -2 : 0) + bounce, width: w, height: h)
            }
            let z = seated ? (L.seats[a.sessionKey]?.cell.minY ?? 0) + 61
                : onSofa ? sofa.maxY + 0.5 : onBeanbag ? beanbag.maxY + 0.5 : a.pos.y
            let hat = a.subId == nil && !lying && settings.s.showModelHats ? ModelHat(model: s.model ?? s.usage?.model) : nil
            let sweating = a.subId == nil && !lying && facing != .up && activity != .sleeping && activity != .compacting
                && (settings.contextFraction(s).map { $0 >= 0.8 } ?? false)
            draws.append((z, {
                p.image(img, rect.minX, rect.minY, rect.width, rect.height, flipX: flip, smooth: !skin.isSheet)
                hat?.draw(p, on: img, in: rect, flip: flip)
                if let rest, facing != .up { OfficeArt.held(rest.pastime, p, rect, sheet: skin.isSheet, tick: self.tick) }
                if sweating { OfficeArt.sweat(p, rect, sheet: skin.isSheet, tick: self.tick) }
                if reaction == .celebrate { OfficeArt.confetti(p, rect, tick: self.tick) }
            }))

            let headTop = lying ? rect.minY + 3 : skin.isSheet ? rect.minY + 7 : rect.minY
            // Chatters take turns talking.
            let silent: Bool = { if let rest, case .chat(_, let side) = rest.spot { return tick / 24 % 2 != side }; return false }()
            // Taking turns in a conversation: a talk bubble on your turn, nothing while you listen.
            let talking = a.talkUntil > tick && !a.walking
            let talkIcon: PixelIcon? = (tick / 12) % 2 == a.talkPhase ? .talk : nil
            if !a.walking, !silent, let icon = talking ? talkIcon : reaction?.icon ?? rest?.pastime.icon ?? activity.icon {
                // Bubbles stay at the resting position instead of bobbing with the sprite.
                let bx = lying ? rect.minX + 8 : rect.midX - 2, by = headTop - 13 - bounce
                bubbles.append({ p.image(icon.bubble, bx, by) })
            }
            if a.subId == nil {
                newHits.append(Hit(id: a.id, sessionKey: a.sessionKey,
                                   rect: CGRect(x: rect.minX - 2, y: headTop - 2, width: rect.width + 4, height: rect.maxY - headTop + 2),
                                   nameAnchor: seated ? CGPoint(x: (L.seats[a.sessionKey]?.cell.midX ?? a.pos.x), y: (L.seats[a.sessionKey]?.cell.minY ?? 0) + 70)
                                       : CGPoint(x: a.pos.x, y: a.pos.y + 6),
                                   label: a.walking ? a.goal.label : plan.map { $0.pastime.label(at: $0.spot) }))
            }
        }

        for (_, d) in draws.sorted(by: { $0.0 < $1.0 }) { d() }
        drawHandoffs(p, L)
        for b in bubbles { b() }
        hits = newHits
        return p.makeImage()
    }

    private func actorSeated(_ key: String) -> Bool {
        guard let a = actors.values.first(where: { $0.sessionKey == key && $0.subId == nil }) else { return false }
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

/// Decides what each resting agent does, for the office and the desktop pet alike, so both always show the same thing.
/// Runs whether or not the office is open, using the spots the office layout would have.
@MainActor
final class RestPlanner {
    static let shared = RestPlanner()

    struct Rest {
        let spot: OfficeLayout.RestSpot
        let pastime: OfficeSimulation.Pastime
        /// When the agent gets up and picks something else.
        let until: Date
    }

    private(set) var rests: [String: Rest] = [:]
    /// Who is walking across the office right now, where to and facing which way. Empty while the office is closed.
    var walking: [String: (goal: OfficeSimulation.Goal, facing: Facing)] = [:]
    private var rng: SplitMix64
    private var sleepers: Set<String> = []
    private var nextCheck = Date.distantPast
    private let store = SessionStore.shared
    private let settings = SettingsStore.shared

    /// A fixed seed makes rest choices repeatable (used by --render-preview).
    init(seed: UInt64 = .random(in: 0 ... .max)) {
        rng = SplitMix64(seed)
    }

    /// What a resting session is doing right now.
    func rest(for key: String) -> Rest? {
        update()
        return rests[key]
    }

    /// Resting agents do something random at a free spot, then move on to something else when it's time.
    /// The office passes its layout every frame; without one, it re-plans when someone starts or stops resting, else twice a second.
    func update(_ layout: OfficeLayout? = nil) {
        let sessions = store.activeSessions
        let sleeping = Set(sessions.filter { $0.activity == .sleeping }.map(\.id))
        let now = Date()
        guard layout != nil || sleeping != sleepers || now >= nextCheck else { return }
        sleepers = sleeping
        nextCheck = now.addingTimeInterval(0.5)
        rests = rests.filter { sleeping.contains($0.key) }
        guard !sleeping.isEmpty else { return }
        let L = layout ?? OfficeLayout.make(sessions: sessions, projectName: settings.projectName)
        for s in sessions where sleeping.contains(s.id) {
            if let r = rests[s.id], r.until > now, stillThere(r, key: s.id, in: L) { continue }
            pickRest(for: s.id, in: L, now: now)
        }
    }

    /// Sends a sleeping agent to a given spot for good (used by --render-preview).
    func debugRest(_ key: String, _ spot: OfficeLayout.RestSpot, _ pastime: OfficeSimulation.Pastime) {
        rests[key] = Rest(spot: spot, pastime: pastime, until: .distantFuture)
    }

    /// The spot still exists in this layout, and a chat still has someone on the other side.
    private func stillThere(_ r: Rest, key: String, in L: OfficeLayout) -> Bool {
        guard L.restFeet(r.spot, sessionKey: key) != nil else { return false }
        if case .chat(let i, let side) = r.spot { return rests.values.contains { $0.spot == .chat(i, 1 - side) } }
        return true
    }

    /// Sends them to a random kind of rest with a free spot (other than the one they're leaving), with something to do there.
    /// A chat at a window pulls in another resting agent as the other side.
    private func pickRest(for key: String, in L: OfficeLayout, now: Date) {
        let current = rests[key]?.spot
        let others = rests.filter { $0.key != key }
        let taken = Set(others.map(\.value.spot))
        // A window holds one gazer or one pair of chatters.
        let busyWindows = Set(taken.compactMap { spot -> Int? in
            switch spot {
            case .window(let i), .chat(let i, _): return i
            default: return nil
            }
        })
        func free(_ spot: OfficeLayout.RestSpot) -> Bool {
            switch spot {
            case .desk: return true
            case .window(let i): return !busyWindows.contains(i)
            case .chat(let i, _): return !busyWindows.contains(i) && !others.isEmpty
            default: return !taken.contains(spot)
            }
        }
        let kinds = L.restKinds.map { $0.filter { $0 != current && free($0) } }.filter { !$0.isEmpty }
        // Napping at the desk is the fallback, so it comes up less often than a trip to the lounge.
        let weights = kinds.map { $0 == [.desk] ? 0.35 : 1 }
        var roll = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
        let kind = kinds.indices.first { roll -= weights[$0]; return roll < 0 }.map { kinds[$0] }
        let spot = kind?.randomElement(using: &rng) ?? .desk
        let pastime = OfficeSimulation.Pastime.choices(at: spot).randomElement(using: &rng) ?? .nap
        // Naps last a while; everything else is a short break.
        let until = now.addingTimeInterval(pastime == .nap ? .random(in: 60...150, using: &rng) : .random(in: 20...50, using: &rng))
        rests[key] = Rest(spot: spot, pastime: pastime, until: until)
        if case .chat(let i, _) = spot, let partner = others.keys.randomElement(using: &rng) {
            rests[partner] = Rest(spot: .chat(i, 1), pastime: .chat, until: until)
        }
    }
}
