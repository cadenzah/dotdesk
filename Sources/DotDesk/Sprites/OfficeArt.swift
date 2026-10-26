import CoreGraphics
import Foundation

/// Hand-drawn office furniture. When the Pixel Agents asset folder is available some pieces
/// are replaced by its sprites; everything here works without it.
@MainActor
enum OfficeArt {
    static let floorA = RGBA(0xeadfcd), floorB = RGBA(0xe2d5c0), floorLine = RGBA(0xd6c6ad)
    static let wall = RGBA(0xf4ecdd), wallTrim = RGBA(0xcdb89b), wallShadow = RGBA(0xb9a283)
    static let woodTop = RGBA(0xc8915a), woodFront = RGBA(0xa8713f), woodDark = RGBA(0x7d5230)
    private static var deskTop: CGFloat?

    static func resetCaches() { deskTop = nil }

    static func floor(_ p: PixelContext, _ w: Int, _ h: Int, from y0: Int) {
        p.fill(0, CGFloat(y0), CGFloat(w), CGFloat(h - y0), floorA)
        var row = 0
        for y in stride(from: y0, to: h, by: 8) {
            if row % 2 == 1 { p.fill(0, CGFloat(y), CGFloat(w), 8, floorB) }
            p.fill(0, CGFloat(y + 7), CGFloat(w), 1, floorLine)
            let offset = row % 2 == 0 ? 0 : 16
            for x in stride(from: offset, to: w, by: 32) { p.fill(CGFloat(x), CGFloat(y), 1, 7, floorLine) }
            row += 1
        }
    }

    static func wall(_ p: PixelContext, width w: Int, height h: Int) {
        p.fill(0, 0, CGFloat(w), CGFloat(h), wall)
        p.fill(0, CGFloat(h - 6), CGFloat(w), 4, wallTrim)
        p.fill(0, CGFloat(h - 2), CGFloat(w), 2, wallShadow)
    }

    nonisolated static func skyColor(_ date: Date = Date()) -> (RGBA, Bool) {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 6..<17: return (RGBA(0x9ad1ff), false)
        case 17..<19: return (RGBA(0xffb38a), false)
        default: return (RGBA(0x2b3a67), true)
        }
    }

    static func window(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat) {
        let (sky, night) = skyColor()
        p.fill(x, y, 26, 18, RGBA(0xffffff))
        p.fill(x + 2, y + 2, 22, 14, sky)
        if night {
            for (sx, sy) in [(4, 4), (13, 7), (19, 3), (8, 11)] { p.fill(x + CGFloat(sx), y + CGFloat(sy), 1, 1, RGBA(0xfff3bf)) }
        } else {
            p.fill(x + 5, y + 5, 6, 2, RGBA(0xffffff)); p.fill(x + 7, y + 4, 3, 1, RGBA(0xffffff))
        }
        p.fill(x + 12, y + 2, 2, 14, RGBA(0xffffff))
        p.fill(x - 1, y + 18, 28, 2, wallTrim)
    }

    static func door(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat) {
        p.fill(x - 1, y - 1, 20, 29, wallShadow)
        p.fill(x, y, 18, 28, RGBA(0x9c6b3f))
        p.fill(x + 2, y + 2, 14, 11, RGBA(0xb07d4e))
        p.fill(x + 2, y + 15, 14, 11, RGBA(0xb07d4e))
        p.fill(x + 14, y + 14, 2, 2, RGBA(0xffd43b))
    }

    static func clock(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat) {
        if let img = SpriteLibrary.shared.furniture("CLOCK", "CLOCK.png") { p.image(img, x, y); return }
        p.fill(x + 1, y, 8, 10, RGBA(0x495057)); p.fill(x, y + 1, 10, 8, RGBA(0x495057))
        p.fill(x + 1, y + 1, 8, 8, RGBA(0xffffff))
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        p.fill(x + 4, y + 2, 1, 3, RGBA(0x212529))
        let m = (now.minute ?? 0) / 15
        let hands: [(CGFloat, CGFloat)] = [(4, 2), (5, 4), (4, 5), (2, 4)]
        p.fill(x + hands[m].0, y + hands[m].1, 2, 1, RGBA(0xe03131))
    }

    static func rug(_ p: PixelContext, _ r: CGRect, _ color: RGBA) {
        let base = color.mix(RGBA(0xffffff), 0.62)
        p.fill(r.minX, r.minY, r.width, r.height, base)
        p.fill(r.minX + 2, r.minY + 2, r.width - 4, 1, color.mix(RGBA(0xffffff), 0.35))
        p.fill(r.minX + 2, r.maxY - 3, r.width - 4, 1, color.mix(RGBA(0xffffff), 0.35))
    }

    static func chairBack(_ p: PixelContext, _ cx: CGFloat, _ top: CGFloat) {
        p.fill(cx - 9, top + 1, 18, 14, RGBA(0x3b4252))
        p.fill(cx - 8, top, 16, 1, RGBA(0x3b4252))
        p.fill(cx - 7, top + 2, 14, 10, RGBA(0x4c566a))
    }

    static func desk(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat) {
        if let img = SpriteLibrary.shared.furniture("DESK", "DESK_FRONT.png") {
            // Align the sprite's visible top edge with our desk surface.
            if deskTop == nil { deskTop = img.opaqueBounds().minY }
            p.image(img, x, y - (deskTop ?? 0))
            return
        }
        p.fill(x + 1, y, 46, 9, woodTop)
        p.fill(x + 1, y, 46, 1, woodTop.lighter(0.3))
        p.fill(x + 1, y + 9, 46, 13, woodFront)
        p.fill(x + 1, y + 21, 46, 1, woodDark)
        p.fill(x + 4, y + 12, 18, 1, woodDark)
        p.fill(x + 26, y + 12, 18, 1, woodDark)
        p.fill(x + 12, y + 15, 2, 1, RGBA(0xffd43b)); p.fill(x + 34, y + 15, 2, 1, RGBA(0xffd43b))
        p.fill(x + 2, y + 22, 3, 4, woodDark); p.fill(x + 43, y + 22, 3, 4, woodDark)
    }

    /// Monitor with a screen that shows what the agent is doing.
    static func monitor(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat, activity: Activity?, tick: Int, accent: RGBA) {
        p.fill(x + 6, y + 12, 4, 4, RGBA(0x495057))
        p.fill(x + 3, y + 15, 10, 2, RGBA(0x343a40))
        p.fill(x, y, 16, 13, RGBA(0x343a40))
        let sx = x + 1, sy = y + 1, sw: CGFloat = 14, sh: CGFloat = 10
        guard let a = activity, a != .sleeping, a != .leaving else {
            p.fill(sx, sy, sw, sh, RGBA(0x1a1b26)); return
        }
        func lines(_ bg: RGBA, _ colors: [RGBA], scroll: Bool) {
            p.fill(sx, sy, sw, sh, bg)
            let off = scroll ? tick / 3 : 0
            for i in 0..<4 {
                let seed = Int(stableHash("\(i + off)") % 9)
                p.fill(sx + 1 + CGFloat(seed % 3), sy + 1 + CGFloat(i * 2 + 1), CGFloat(5 + seed), 1, colors[(i + off) % colors.count])
            }
        }
        switch a {
        case .typing, .planning:
            lines(RGBA(0x1e2233), [RGBA(0xff8fab), RGBA(0x74c0fc), RGBA(0xffd43b), RGBA(0x8ce99a)], scroll: true)
        case .running, .tool, .delegating:
            lines(RGBA(0x0b0f14), [RGBA(0x51e07a), RGBA(0x2f9e44)], scroll: true)
        case .reading, .searching:
            lines(RGBA(0xf8f9fa), [RGBA(0xadb5bd), RGBA(0xced4da)], scroll: a == .searching)
            if a == .searching { p.fill(sx + 9, sy + 2 + CGFloat(tick / 2 % 6), 4, 2, RGBA(0xffd43b)) }
        case .browsing:
            p.fill(sx, sy, sw, sh, RGBA(0xe7f5ff))
            p.fill(sx, sy, sw, 2, RGBA(0x4dabf7))
            p.fill(sx + 2, sy + 4, 6, 4, RGBA(0xa5d8ff)); p.fill(sx + 9, sy + 4, 3, 1, RGBA(0xadb5bd)); p.fill(sx + 9, sy + 6, 3, 1, RGBA(0xadb5bd))
        case .thinking:
            p.fill(sx, sy, sw, sh, RGBA(0x1e2233))
            if tick / 4 % 2 == 0 { p.fill(sx + 2, sy + 7, 2, 2, RGBA(0xf8f9fa)) }
        case .waitingPermission, .waitingInput:
            p.fill(sx, sy, sw, sh, tick / 4 % 2 == 0 ? RGBA(0xffa94d) : RGBA(0xffd8a8))
            p.fill(sx + 6, sy + 2, 2, 4, RGBA(0x862e00)); p.fill(sx + 6, sy + 7, 2, 1, RGBA(0x862e00))
        case .done:
            p.fill(sx, sy, sw, sh, RGBA(0x8ce99a))
            p.fill(sx + 4, sy + 5, 2, 2, RGBA(0x2b8a3e)); p.fill(sx + 6, sy + 6, 2, 2, RGBA(0x2b8a3e)); p.fill(sx + 8, sy + 3, 2, 3, RGBA(0x2b8a3e))
        default:
            p.fill(sx, sy, sw, sh, accent.mix(RGBA(0x1e2233), 0.7))
        }
    }

    static func flag(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat, _ color: RGBA) {
        p.fill(x, y, 1, 11, RGBA(0x495057))
        p.fill(x + 1, y, 6, 4, color)
        p.fill(x + 1, y + 4, 4, 1, color.darker(0.2))
    }

    static func plant(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat) {
        if let img = SpriteLibrary.shared.furniture("PLANT", "PLANT.png") { p.image(img, x, y - CGFloat(img.height) + 16); return }
        p.fill(x + 4, y + 8, 8, 8, RGBA(0xd9480f)); p.fill(x + 3, y + 8, 10, 2, RGBA(0xe8590c))
        p.fill(x + 2, y, 5, 8, RGBA(0x37b24d)); p.fill(x + 8, y - 2, 5, 10, RGBA(0x2f9e44)); p.fill(x + 5, y - 5, 5, 8, RGBA(0x51cf66))
    }

    static func sofa(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat) {
        if let img = SpriteLibrary.shared.furniture("SOFA", "SOFA_FRONT.png") { p.image(img, x, y); return }
        p.fill(x, y, 32, 8, RGBA(0x5c7cfa)); p.fill(x, y + 8, 32, 8, RGBA(0x4c6ef5))
        p.fill(x, y + 4, 3, 12, RGBA(0x3b5bdb)); p.fill(x + 29, y + 4, 3, 12, RGBA(0x3b5bdb))
        p.fill(x + 15, y + 8, 1, 6, RGBA(0x3b5bdb))
    }

    /// A round floor cushion with a dent where someone sits.
    static func beanbag(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat) {
        let base = RGBA(0xf59f00), light = RGBA(0xffd43b), dark = RGBA(0xd9480f).mix(base, 0.4)
        p.fill(x + 5, y, 10, 1, base); p.fill(x + 2, y + 1, 16, 2, base)
        p.fill(x + 1, y + 3, 18, 3, base); p.fill(x, y + 6, 20, 4, base)
        p.fill(x + 1, y + 10, 18, 1, dark); p.fill(x + 3, y + 11, 14, 1, dark)
        p.fill(x, y + 9, 1, 1, dark); p.fill(x + 19, y + 9, 1, 1, dark)
        p.fill(x + 5, y + 4, 10, 3, base.darker(0.12))
        p.fill(x + 4, y + 1, 4, 1, light); p.fill(x + 2, y + 3, 2, 2, light)
    }

    /// Always hand-drawn: Pixel Agents' COFFEE is a cup meant for a table, and resting agents brew coffee here.
    static func coffee(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat) {
        p.fill(x, y - 8, 14, 24, RGBA(0x495057)); p.fill(x + 2, y - 6, 10, 6, RGBA(0x212529))
        p.fill(x + 4, y + 4, 6, 6, RGBA(0x868e96)); p.fill(x + 5, y + 6, 4, 4, RGBA(0xffffff))
        p.fill(x + 10, y - 5, 2, 2, RGBA(0x51cf66))
    }

    // MARK: Things resting agents hold

    /// What a resting agent holds: at the hands of a 16x32 sheet, or beside a free-form sprite.
    static func held(_ pastime: OfficeSimulation.Pastime, _ p: PixelContext, _ r: CGRect, sheet: Bool, tick: Int) {
        switch pastime {
        case .coffee:
            if sheet { mug(p, r.minX + 12, r.minY + 22, tick: tick) } else { mug(p, r.maxX - 1, r.maxY - 6, tick: tick) }
        case .game:
            if sheet { handheld(p, r.minX + 5, r.minY + 21, tick: tick) } else { handheld(p, r.midX - 3, r.maxY - 5, tick: tick) }
        case .water:
            if sheet { wateringCan(p, r.minX + 8, r.minY + 21, tick: tick) } else { wateringCan(p, r.maxX - 2, r.maxY - 10, tick: tick) }
        default:
            break
        }
    }

    /// A mug held in the hand, with a wisp of steam drifting up.
    static func mug(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat, tick: Int) {
        p.fill(x - 1, y - 1, 5, 5, Palette.outline); p.fill(x + 3, y, 2, 3, Palette.outline)
        p.fill(x, y, 3, 3, RGBA(0xf8f9fa)); p.fill(x, y, 3, 1, RGBA(0x6b3e1f)); p.fill(x + 3, y + 1, 1, 1, RGBA(0xf8f9fa))
        let s = tick / 4 % 3
        p.fill(x + 1 + CGFloat(s % 2), y - 2 - CGFloat(s), 1, 1, RGBA(0xdee2e6))
    }

    /// A watering can tipped to the right, dripping from the spout.
    static func wateringCan(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat, tick: Int) {
        let body = RGBA(0x40c057), dark = RGBA(0x2b8a3e)
        p.fill(x, y, 5, 4, body); p.fill(x, y + 3, 5, 1, dark)
        p.fill(x + 1, y - 1, 3, 1, dark)
        p.fill(x + 5, y + 1, 1, 1, body); p.fill(x + 6, y, 1, 1, body); p.fill(x + 7, y - 1, 2, 1, dark)
        for k in 0..<2 { p.fill(x + 8, y + 1 + CGFloat((tick / 2 + k * 3) % 6), 1, 1, RGBA(0x74c0fc)) }
    }

    /// A handheld game console whose screen flickers.
    static func handheld(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat, tick: Int) {
        p.fill(x, y, 6, 4, RGBA(0x495057))
        p.fill(x + 1, y + 1, 4, 2, tick / 6 % 2 == 0 ? RGBA(0x8ce99a) : RGBA(0x74c0fc))
    }

    /// Always hand-drawn: Pixel Agents' BOOKSHELF is low and wide, and resting agents browse it from the side.
    static func bookshelf(_ p: PixelContext, _ x: CGFloat, _ y: CGFloat) {
        p.fill(x, y, 16, 32, woodFront); p.fill(x + 1, y + 1, 14, 30, woodDark)
        let colors = [RGBA(0xff6b6b), RGBA(0x4dabf7), RGBA(0xffd43b), RGBA(0x69db7c), RGBA(0xda77f2)]
        for shelf in 0..<3 {
            let sy = y + 2 + CGFloat(shelf * 10)
            for b in 0..<5 { p.fill(x + 2 + CGFloat(b * 3), sy + CGFloat(b % 2), 2, 8 - CGFloat(b % 2), colors[(b + shelf) % 5]) }
            p.fill(x + 1, sy + 8, 14, 1, woodFront)
        }
    }
}
