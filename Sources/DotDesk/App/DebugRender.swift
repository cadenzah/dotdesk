import AppKit
import SwiftUI

/// `DotDesk --render-preview <dir>` writes sprite sheets and scenes as PNGs for visual checks.
@MainActor
enum DebugRender {
    static func run(to dir: String) {
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for i in BuiltinCharacters.looks.indices {
            let sheet = BuiltinCharacters.sheet(look: i, shirt: Palette.project[i % Palette.project.count])
            write(sheet, scale: 6, to: out.appendingPathComponent("builtin-\(i).png"))
        }
        for i in 0..<8 {
            let sheet = BuiltinCharacters.sheet(BuiltinCharacters.randomLook(seed: stableHash("look:demo-\(i)")),
                                                shirt: Palette.project[i % Palette.project.count])
            write(sheet, scale: 6, to: out.appendingPathComponent("mix-\(i).png"))
        }
        let icons = PixelContext(PixelIcon.allCases.count * 16, 14)
        for (i, icon) in PixelIcon.allCases.enumerated() { icons.image(icon.bubble, CGFloat(i * 16), 0) }
        if let img = icons.makeImage() { write(img, scale: 6, to: out.appendingPathComponent("icons.png")) }
        renderOnboarding(to: out)
        renderView(AgentEditView(title: "콩이", subtitle: "dotdesk · Claude Code", name: "", namePlaceholder: "콩이",
                                 ref: "builtin:2", autoRef: "builtin:0", shirt: RGBA(0x4dabf7), save: { _, _ in }, cancel: {}),
                   width: 460, to: out.appendingPathComponent("agent-edit.png"))
        renderSummary(to: out)
        renderOffice(to: out)
        renderPetRests(to: out)
        for tab in SettingsTab.allCases {
            SettingsNavigation.shared.tab = tab
            let host = NSHostingView(rootView: SettingsView())
            host.frame = CGRect(x: 0, y: 0, width: 600, height: 480)
            let w = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            w.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("settings-\(tab.rawValue).png"))
            }
        }
    }

    /// The daily summary with a made-up day and week; the office renders after it pick up the whiteboard chart.
    private static func renderSummary(to out: URL) {
        var t = DayStats(day: DailyStats.key(Date()))
        t.prompts = 42; t.turnsDone = 38; t.longTasks = 2; t.toolCalls = 512
        t.files = Set((0..<23).map { "/tmp/f\($0).swift" })
        t.testsPassed = 7; t.testsFailed = 2; t.outputTokens = 186_000
        for (h, m) in [(9, 20), (10, 55), (11, 40), (13, 30), (14, 60), (15, 48), (16, 25), (17, 10)] { t.busyByHour[h] = Double(m * 60) }
        let hour = Calendar.current.component(.hour, from: Date())
        for back in 0..<6 { t.busyByHour[(hour - back + 24) % 24] = Double((60 - back * 8) * 60) }
        t.busySeconds = t.busyByHour.reduce(0, +)
        t.agentSeconds = t.busySeconds * 1.6
        t.projectSeconds = ["/Users/me/dotdesk": t.agentSeconds * 0.6, "/Users/me/api-server": t.agentSeconds * 0.3, "/Users/me/blog": t.agentSeconds * 0.1]
        for (i, (name, project)) in [("도토리", "/Users/me/dotdesk"), ("모찌", "/Users/me/dotdesk"), ("콩이", "/Users/me/api-server"), ("보리", "/Users/me/blog")].enumerated() {
            t.crew["w\(i)"] = CrewMember(name: name, character: BuiltinCharacters.mixRef(UInt64(i * 7919 + 13)), projectKey: project)
        }
        let cal = Calendar.current
        let history = (1..<7).reversed().compactMap { back -> DayStats? in
            guard let date = cal.date(byAdding: .day, value: -back, to: Date()), back != 3 else { return nil }
            var d = DayStats(day: DailyStats.key(date))
            d.prompts = 10 * back; d.busySeconds = Double([0, 7200, 16000, 0, 9000, 21000, 4000][back]); d.turnsDone = 8
            return d
        }
        DailyStats.shared.usePreview(today: t, history: history, unlocked: [.frame, .lights, .lamp, .trophies, .cat])
        renderView(DailySummaryView(), width: 460, to: out.appendingPathComponent("summary.png"))
        renderView(Form { DecorationList() }.formStyle(.grouped), width: 520, height: 380, to: out.appendingPathComponent("decorations.png"))
    }

    /// Welcome window and empty office, before and after the hooks are installed.
    private static func renderOnboarding(to out: URL) {
        let settings = SettingsStore.shared
        let real = settings.s.claudeConfigDirs
        let sim = OfficeSimulation()
        sim.advance(1)
        for (state, dirs) in [("connected", real), ("disconnected", [NSTemporaryDirectory() + "dotdesk-no-hooks"])] {
            settings.s.claudeConfigDirs = dirs
            IntegrationStatus.shared.refresh()
            renderView(WelcomeView {}, width: 480, to: out.appendingPathComponent("welcome-\(state).png"))
            renderView(OfficeView(sim: sim), width: 420, height: 250, to: out.appendingPathComponent("office-empty-\(state).png"))
        }
        settings.s.claudeConfigDirs = real
        IntegrationStatus.shared.refresh()
    }

    private static func renderView<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil, to url: URL) {
        let host = NSHostingView(rootView: view)
        let size = CGSize(width: width, height: height ?? host.fittingSize.height)
        host.frame = CGRect(origin: .zero, size: size)
        let w = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func renderOffice(to out: URL) {
        let store = SessionStore.shared
        store.toggleDemo()
        let sim = OfficeSimulation(planner: RestPlanner(seed: 7))
        for k in 0..<4 {
            store.demoStep()
            sim.advance(160)
            if let f = sim.frame { write(f, scale: 4, to: out.appendingPathComponent("office-\(k).png")) }
        }
        // Lounge: one sleeper up to four picking random spots, with a frame mid-walk and one settled.
        for (name, keys) in [("lounge-1", ["claude:demo-1"]), ("lounge-2", ["claude:demo-1", "claude:demo-2"]),
                             ("lounge-3", ["claude:demo-1", "claude:demo-2", "codex:demo-3"]),
                             ("lounge-4", ["claude:demo-1", "claude:demo-2", "codex:demo-3", "claude:demo-4"])] {
            store.demoStep()
            sim.advance(160)
            store.demoSleep(keys)
            sim.advance(14)
            if let f = sim.frame { write(f, scale: 4, to: out.appendingPathComponent("office-\(name)-walk.png")) }
            sim.advance(160)
            if let f = sim.frame { write(f, scale: 4, to: out.appendingPathComponent("office-\(name).png")) }
        }
        // Every pastime at least once, four sleepers per scene; rest-a again a moment later for the other stretch frame.
        let keys = ["claude:demo-1", "claude:demo-2", "codex:demo-3", "claude:demo-4"]
        let scenes: [(String, [(OfficeLayout.RestSpot, OfficeSimulation.Pastime)])] = [
            ("rest-a", [(.coffee, .coffee), (.plant, .water), (.window(0), .gaze), (.stretch, .stretch)]),
            ("rest-b", [(.sofa(0), .game), (.sofa(1), .nap), (.beanbag, .read), (.desk, .nap)]),
            ("rest-c", [(.sofa(0), .nap), (.beanbag, .nap), (.chat(1, 0), .chat), (.chat(1, 1), .chat)]),
        ]
        for (name, spots) in scenes {
            store.demoStep()
            sim.advance(160)
            store.demoSleep(keys)
            for (key, (spot, pastime)) in zip(keys, spots) { sim.debugRest(key, spot, pastime) }
            sim.advance(160)
            if let f = sim.frame { write(f, scale: 4, to: out.appendingPathComponent("office-\(name).png")) }
            if name == "rest-a" {
                sim.advance(10)
                if let f = sim.frame { write(f, scale: 4, to: out.appendingPathComponent("office-\(name)-2.png")) }
            }
        }
        // Two rows of desks, so the lounge is tall enough for the bookshelf.
        store.demoJoin("demo-5", cwd: "/tmp/dotdesk-demo/docs")
        store.demoStep()
        sim.advance(160)
        store.demoSleep(keys + ["claude:demo-5"])
        for (key, (spot, pastime)) in zip(keys + ["claude:demo-5"], [(OfficeLayout.RestSpot.bookshelf, OfficeSimulation.Pastime.browse),
                                                                     (.stretch, .stretch), (.coffee, .coffee), (.plant, .water), (.beanbag, .read)]) {
            sim.debugRest(key, spot, pastime)
        }
        sim.advance(200)
        if let f = sim.frame { write(f, scale: 4, to: out.appendingPathComponent("office-rest-tall.png")) }
        store.demoRemove("demo-5")
        // Same scene with other character sources.
        let paRefs = ["pa:0", "pa:3", "pa:5"], pokeRefs = SpriteLibrary.shared.pokemon.prefix(3).map { "poke:\($0.id)" }
        for (name, refs) in [("pa", paRefs), ("poke", Array(pokeRefs))] where !refs.isEmpty {
            for (i, key) in ["claude:demo-1", "claude:demo-2", "codex:demo-3"].enumerated() {
                store.setCharacter(key, refs[i % refs.count])
            }
            store.demoStep()
            sim.advance(10)
            if let f = sim.frame { write(f, scale: 4, to: out.appendingPathComponent("office-\(name).png")) }
        }
        // The lounge again, with Pixel Agents and Pokémon sitting on the sofa.
        for (name, refs) in [("pa", paRefs), ("poke", Array(pokeRefs))] where !refs.isEmpty {
            for (i, key) in ["claude:demo-1", "claude:demo-2"].enumerated() {
                store.setCharacter(key, refs[i % refs.count])
            }
            store.demoSleep(["claude:demo-1", "claude:demo-2"])
            sim.advance(160)
            if let f = sim.frame { write(f, scale: 4, to: out.appendingPathComponent("office-lounge-\(name).png")) }
        }
        for key in keys { store.setCharacter(key, nil) }
        // A new session in a project whose agents all rest takes over the one resting longest, who walks over from the
        // lounge; once the session they left works again, someone new comes in for it.
        func who() -> String {
            (keys + ["claude:demo-6"]).compactMap { store.session($0) }
                .map { s in "\(s.sessionId)=\(s.workerId == nil ? "-" : store.nickname(s))" }.joined(separator: " ")
        }
        store.demoSleep(["claude:demo-1", "claude:demo-2"])
        sim.advance(160)
        print("handover before:", who())
        store.demoJoin("demo-6", cwd: "/tmp/dotdesk-demo/web-app")
        sim.advance(14)
        if let f = sim.frame { write(f, scale: 4, to: out.appendingPathComponent("office-handover-walk.png")) }
        sim.advance(160)
        if let f = sim.frame { write(f, scale: 4, to: out.appendingPathComponent("office-handover.png")) }
        print("handover after:", who())
        store.demoStep()
        sim.advance(160)
        if let f = sim.frame { write(f, scale: 4, to: out.appendingPathComponent("office-handover-back.png")) }
        print("handover back:", who())
        store.demoRemove("demo-6")
    }

    /// The desktop pet while its agent rests, once per pastime the office can give it.
    private static func renderPetRests(to out: URL) {
        SessionStore.shared.demoSleep(["claude:demo-1"])
        let rests: [(OfficeLayout.RestSpot, OfficeSimulation.Pastime)] = [
            (.sofa(0), .nap), (.sofa(0), .game), (.beanbag, .read), (.coffee, .coffee),
            (.plant, .water), (.window(0), .gaze), (.stretch, .stretch), (.bookshelf, .browse),
        ]
        for (i, (spot, pastime)) in rests.enumerated() {
            RestPlanner.shared.debugRest("claude:demo-1", spot, pastime)
            let pet = PetController(pinnedSession: "claude:demo-1")
            pet.show()
            pet.close()
            print("pet-rest-\(i):", pet.model.title)
            if let f = pet.model.frame { write(f, scale: 6, to: out.appendingPathComponent("pet-rest-\(i).png")) }
        }
        // On the way to the sofa in the office.
        RestPlanner.shared.walking["claude:demo-1"] = (.rest(.sofa(0)), .right)
        let pet = PetController(pinnedSession: "claude:demo-1")
        pet.show()
        pet.close()
        RestPlanner.shared.walking = [:]
        print("pet-walk:", pet.model.title)
        if let f = pet.model.frame { write(f, scale: 6, to: out.appendingPathComponent("pet-walk.png")) }
    }

    /// 1024px app icon: the default character in front of a monitor.
    static func renderIcon(to path: String) {
        let p = PixelContext(64, 64)
        p.fill(4, 4, 56, 56, RGBA(0x4dabf7).lighter(0.55))
        p.fill(4, 44, 56, 16, OfficeArt.floorA)
        OfficeArt.monitor(p, 8, 30, activity: .typing, tick: 3, accent: RGBA(0x4dabf7))
        let skin = SheetSkin(sheet: BuiltinCharacters.sheet(look: 0, shirt: RGBA(0xff6b6b)))!
        let (img, _) = skin.frame(facing: .down, pose: .type, tick: 0)
        p.image(img, 30, 22)
        p.image(PixelIcon.pencil.bubble, 36, 10)
        guard let raw = p.makeImage() else { return }
        let size = 1024
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let inset: CGFloat = 100, r: CGFloat = 185
        let rect = CGRect(x: inset, y: inset, width: CGFloat(size) - 2 * inset, height: CGFloat(size) - 2 * inset)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.clip()
        ctx.interpolationQuality = .none
        ctx.draw(raw, in: rect.insetBy(dx: -rect.width / 14, dy: -rect.height / 14))
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    static func write(_ img: CGImage, scale: Int, to url: URL) {
        let w = img.width * scale, h = img.height * scale
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .none
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
