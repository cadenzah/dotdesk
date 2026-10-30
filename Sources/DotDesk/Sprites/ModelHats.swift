import CoreGraphics

/// A hat for the Claude model an agent runs on, so Opus, Sonnet, Haiku and Fable sessions look apart at a glance.
/// It sits on the top of whatever the sprite has there, so it works for every character source.
enum ModelHat: CaseIterable {
    case crown, beret, sprout, wizard

    init?(model: String?) {
        guard let m = model?.lowercased() else { return nil }
        if m.contains("opus") { self = .crown }
        else if m.contains("sonnet") { self = .beret }
        else if m.contains("haiku") { self = .sprout }
        else if m.contains("fable") { self = .wizard }
        else { return nil }
    }

    private var rows: [String] {
        switch self {
        case .crown: return ["Y..Y..Y", "YYRYRYY", "DDDDDDD"]
        case .beret: return ["..B....", ".BBBBB.", "BBBBBBD"]
        case .sprout: return ["GG.GG", ".GDG.", "..D..", "..D.."]
        case .wizard: return ["....P..", "...PP..", "..PPP..", "..PSP..", ".PPPPP.", "DDDDDDD"]
        }
    }

    private var colors: [Character: RGBA] {
        switch self {
        case .crown: return ["Y": RGBA(0xffd43b), "R": RGBA(0xe03131), "D": RGBA(0xf08c00)]
        case .beret: return ["B": RGBA(0x364fc7), "D": RGBA(0x253585)]
        case .sprout: return ["G": RGBA(0x51cf66), "D": RGBA(0x2b8a3e)]
        case .wizard: return ["P": RGBA(0x7048e8), "S": RGBA(0xffd43b), "D": RGBA(0x4c2fa6)]
        }
    }

    /// Draws the hat on the head of `img` as drawn in `rect` (mirrored when `flip`). `px` is the size of one hat pixel.
    func draw(_ p: PixelContext, on img: CGImage, in rect: CGRect, flip: Bool, px: CGFloat = 1) {
        guard let head = Self.headTop(img) else { return }
        let k = rect.width / CGFloat(img.width)
        let cx = rect.minX + (flip ? CGFloat(img.width) - head.x : head.x) * k
        let top = rect.minY + head.y * k
        let rows = rows, colors = colors
        let w = rows[0].count, h = rows.count
        // The bottom row overlaps the top of the head by one pixel so the hat sits on it.
        let x0 = (cx - CGFloat(w) * px / 2).rounded(), y0 = (top - CGFloat(h - 1) * px).rounded()
        func filled(_ c: Int, _ r: Int) -> Bool {
            r >= 0 && r < h && c >= 0 && c < w && colors[Array(rows[r])[c]] != nil
        }
        // Outline on the sides and top only, like the characters' own outline.
        for r in -1..<h {
            for c in -1...w where !filled(c, r) && (filled(c - 1, r) || filled(c + 1, r) || filled(c, r + 1) || (r >= 0 && filled(c, r - 1))) {
                let dc = flip ? w - 1 - c : c
                p.fill(x0 + CGFloat(dc) * px, y0 + CGFloat(r) * px, px, px, Palette.outline)
            }
        }
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() {
                guard let color = colors[ch] else { continue }
                let dc = flip ? w - 1 - c : c
                p.fill(x0 + CGFloat(dc) * px, y0 + CGFloat(r) * px, px, px, color)
            }
        }
    }

    /// Frames are cached by their skins, so each one is scanned once.
    private static var heads: [ObjectIdentifier: (CGImage, CGPoint?)] = [:]

    /// Top centre of the head in image pixels: the first row nearly as wide as a head,
    /// centred on what is opaque in it and the two rows below.
    private static func headTop(_ img: CGImage) -> CGPoint? {
        let id = ObjectIdentifier(img)
        if let (cached, point) = heads[id], cached === img { return point }
        if heads.count > 2000 { heads.removeAll() }
        let point = scan(img)
        heads[id] = (img, point)
        return point
    }

    private static func scan(_ img: CGImage) -> CGPoint? {
        let w = img.width, h = img.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let a = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        func opaque(_ x: Int, _ y: Int) -> Bool { a[(y * w + x) * 4 + 3] > 8 }
        // A hair tuft or antenna is a few pixels wide; the head is close to the widest part of the sprite.
        let counts = (0..<h).map { y in (0..<w).filter { opaque($0, y) }.count }
        let need = max(2, (counts.max() ?? 0) * 45 / 100)
        guard let top = counts.firstIndex(where: { $0 >= need }) else { return nil }
        let xs = (top..<min(h, top + 3)).flatMap { y in (0..<w).filter { opaque($0, y) } }
        guard let lo = xs.min(), let hi = xs.max() else { return nil }
        return CGPoint(x: CGFloat(lo + hi + 1) / 2, y: CGFloat(top))
    }
}
