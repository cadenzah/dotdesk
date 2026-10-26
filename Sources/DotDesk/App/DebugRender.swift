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
        let icons = PixelContext(PixelIcon.allCases.count * 16, 14)
        for (i, icon) in PixelIcon.allCases.enumerated() { icons.image(icon.bubble, CGFloat(i * 16), 0) }
        if let img = icons.makeImage() { write(img, scale: 6, to: out.appendingPathComponent("icons.png")) }
        renderOffice(to: out)
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

    private static func renderOffice(to out: URL) {
        let store = SessionStore.shared
        let settings = SettingsStore.shared
        store.toggleDemo()
        let sim = OfficeSimulation()
        for k in 0..<4 {
            store.demoStep()
            sim.advance(160)
            if let f = sim.frame { write(f, scale: 4, to: out.appendingPathComponent("office-\(k).png")) }
        }
        // Same scene with other character sources.
        let paRefs = ["pa:0", "pa:3", "pa:5"], pokeRefs = SpriteLibrary.shared.pokemon.prefix(3).map { "poke:\($0.id)" }
        for (name, refs) in [("pa", paRefs), ("poke", Array(pokeRefs))] where !refs.isEmpty {
            for (i, key) in ["claude:demo-1", "claude:demo-2", "codex:demo-3"].enumerated() {
                settings.s.sessions[key] = SessionOverride(name: nil, character: refs[i % refs.count])
            }
            store.demoStep()
            sim.advance(10)
            if let f = sim.frame { write(f, scale: 4, to: out.appendingPathComponent("office-\(name).png")) }
        }
        settings.s.sessions = [:]
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
