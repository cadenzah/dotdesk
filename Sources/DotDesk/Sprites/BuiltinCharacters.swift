import CoreGraphics

/// Procedurally painted 16x32 chibi office workers. Original art, safe to ship with the app.
///
/// Sheets follow the Pixel Agents layout (rows: down, up, right; 16x32 frames) so every
/// character source renders through the same code, with four extra columns: sleep, cheer, doze
/// (sitting with eyes closed) and nap (head down on the desk).
enum BuiltinCharacters {
    enum HairStyle { case short, long, bun, spiky, cap }
    /// The top always carries the project color (`shirt`), so outfits vary in cut, not in color.
    enum Outfit { case tee, hoodie, shirtTie, jacket, stripes, overalls }
    enum Bottom { case pants, shorts, skirt }

    struct Look {
        let name: String
        let skin: RGBA
        let hair: RGBA
        let style: HairStyle
        let pants: RGBA
        let shoes: RGBA
        var outfit: Outfit = .tee
        var bottom: Bottom = .pants
        /// Tie, inner shirt under a jacket, or the tee under overalls.
        var accent = RGBA(0xf8f9fa)
    }

    enum Frame: Int, CaseIterable {
        case walk1 = 0, stand, walk2, type1, type2, read1, read2, sleep, cheer, doze, nap
    }

    /// Computed so the names follow the UI language.
    static var looks: [Look] { [
        Look(name: L("밤톨머리", "Buzz cut"), skin: RGBA(0xffd9b8), hair: RGBA(0x6b4423), style: .short, pants: RGBA(0x2f3b52), shoes: RGBA(0x3b2f2f)),
        Look(name: L("긴 생머리", "Long straight hair"), skin: RGBA(0xf1c27d), hair: RGBA(0x2b2b35), style: .long, pants: RGBA(0x6d6875), shoes: RGBA(0x2a2a2a),
             outfit: .stripes, bottom: .skirt),
        Look(name: L("삐죽 금발", "Spiky blond"), skin: RGBA(0xe0ac69), hair: RGBA(0xe8c15a), style: .spiky, pants: RGBA(0x264653), shoes: RGBA(0x4a3426),
             outfit: .hoodie),
        Look(name: L("핑크 똥머리", "Pink bun"), skin: RGBA(0xffe0c4), hair: RGBA(0xf28cb5), style: .bun, pants: RGBA(0x5a4a78), shoes: RGBA(0x3b2f2f),
             outfit: .overalls, accent: RGBA(0xfff4e6)),
        Look(name: L("모자 쓴 친구", "Cap wearer"), skin: RGBA(0xc68642), hair: RGBA(0x1e1e28), style: .cap, pants: RGBA(0x343a40), shoes: RGBA(0xf1f3f5),
             bottom: .shorts),
        Look(name: L("주황 머리", "Ginger"), skin: RGBA(0xffd9b8), hair: RGBA(0xd9622b), style: .short, pants: RGBA(0x495057), shoes: RGBA(0x2a2a2a),
             outfit: .jacket),
        Look(name: L("은발 장발", "Long silver hair"), skin: RGBA(0x8d5524), hair: RGBA(0xdedede), style: .long, pants: RGBA(0x6c757d), shoes: RGBA(0x5c3d2e),
             outfit: .jacket, bottom: .skirt, accent: RGBA(0xffec99)),
        Look(name: L("파란 삐죽", "Blue spikes"), skin: RGBA(0xf1c27d), hair: RGBA(0x4a6fd1), style: .spiky, pants: RGBA(0x3b3b3b), shoes: RGBA(0xc92a2a),
             outfit: .shirtTie, accent: RGBA(0x2b2d42)),
    ] }

    static func sheet(look index: Int, shirt: RGBA) -> CGImage {
        sheet(looks[((index % looks.count) + looks.count) % looks.count], shirt: shirt)
    }

    // MARK: Random looks

    /// "mix:<hex seed>" — a look assembled from random parts. The same seed always gives the same look.
    static func mixRef(_ seed: UInt64) -> String { "mix:" + String(seed, radix: 16) }

    static func mixSeed(_ ref: String) -> UInt64? {
        guard ref.hasPrefix("mix:") else { return nil }
        return UInt64(ref.dropFirst(4), radix: 16)
    }

    private static let skins: [UInt32] = [0xffd9b8, 0xf1c27d, 0xe0ac69, 0xffe0c4, 0xc68642, 0x8d5524]
    private static let hairs: [UInt32] = [0x6b4423, 0x2b2b35, 0xe8c15a, 0xf28cb5, 0x1e1e28, 0xd9622b, 0xdedede, 0x4a6fd1, 0x8a5a44, 0x7b5ea7]
    private static let pantsColors: [UInt32] = [0x2f3b52, 0x264653, 0x5a4a78, 0x343a40, 0x495057, 0x22303c, 0x3b3b3b]
    // Skirts sit right above the outline, so they need lighter colors to read.
    private static let skirtColors: [UInt32] = [0x6d6875, 0x6c757d, 0x5a4a78, 0x7a6a5a]
    private static let shoeColors: [UInt32] = [0x3b2f2f, 0x2a2a2a, 0x4a3426, 0xf1f3f5, 0x5c3d2e, 0xc92a2a]
    private static let accents: [Outfit: [UInt32]] = [
        .shirtTie: [0x2b2d42, 0x5c2a3e, 0x1d3557],
        .jacket: [0xf8f9fa, 0xffec99, 0xd0ebff],
        .overalls: [0xfff4e6, 0xf8f9fa, 0xd0ebff],
    ]
    private static var styleNames: [HairStyle: String] {
        [.short: L("짧은 머리", "Short hair"), .long: L("긴 머리", "Long hair"), .bun: L("똥머리", "Bun"),
         .spiky: L("삐죽머리", "Spiky hair"), .cap: L("모자", "Cap")]
    }
    private static var outfitNames: [Outfit: String] { [
        .tee: L("반팔 티", "Tee"), .hoodie: L("후드티", "Hoodie"), .shirtTie: L("넥타이", "Tie"), .jacket: L("재킷", "Jacket"),
        .stripes: L("줄무늬", "Stripes"), .overalls: L("멜빵바지", "Overalls"),
    ] }

    static func randomLook(seed: UInt64) -> Look {
        var rng = SplitMix64(seed)
        func pick<T>(_ a: [T]) -> T { a[Int(rng.next() % UInt64(a.count))] }
        let skin = RGBA(pick(skins))
        var hair = RGBA(pick(hairs))
        // Re-roll hair that would blend into the face.
        func distance(_ a: RGBA, _ b: RGBA) -> Int { abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b)) }
        while distance(hair, skin) < 120 { hair = RGBA(pick(hairs)) }
        let style = pick([HairStyle.short, .long, .bun, .spiky, .cap])
        let outfit = pick([Outfit.tee, .hoodie, .shirtTie, .jacket, .stripes, .overalls])
        let bottom = pick([Bottom.pants, .pants, .shorts, .skirt])
        let pants = RGBA(bottom == .skirt ? pick(skirtColors) : pick(pantsColors))
        let shoes = RGBA(pick(shoeColors))
        let accent = accents[outfit].map { RGBA(pick($0)) } ?? RGBA(0xf8f9fa)
        return Look(name: "\(styleNames[style]!) · \(outfitNames[outfit]!)", skin: skin, hair: hair, style: style,
                    pants: pants, shoes: shoes, outfit: outfit, bottom: bottom, accent: accent)
    }

    static func sheet(_ look: Look, shirt: RGBA) -> CGImage {
        let cols = Frame.allCases.count
        var sheet = PixelCanvas(16 * cols, 32 * 3)
        for (row, dir) in [Facing.down, .up, .right].enumerated() {
            for f in Frame.allCases {
                let c = paint(look, shirt: shirt, dir: dir, f: f)
                for y in 0..<32 { for x in 0..<16 { sheet[f.rawValue * 16 + x, row * 32 + y] = c[x, y] } }
            }
        }
        return sheet.makeImage()
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func paint(_ L: Look, shirt: RGBA, dir: Facing, f: Frame) -> PixelCanvas {
        var c = PixelCanvas(16, 32)
        let skin = L.skin
        let hair = L.hair, hairHi = L.hair.lighter(0.25)
        let overalls = L.outfit == .overalls
        // Overalls carry the project color on the bib and legs; the tee underneath takes the accent.
        let sh = overalls ? L.accent : shirt, shS = sh.darker(0.3)
        let pants = overalls ? shirt : L.pants, shoes = L.shoes
        let white = RGBA(0xf8f9fa)
        let eye = RGBA(0x2b2440), blush = RGBA(0xf59ca0), mouth = RGBA(0xb5524a)
        let paper = RGBA(0xfdfdf6), ink = RGBA(0xb8bcc8)
        let side = dir == .right || dir == .left
        let seated = !side && [.type1, .type2, .read1, .read2, .doze, .nap].contains(f)

        // Legs
        if side {
            c.rect(6, 25, 4, 1, pants)
            switch f {
            case .walk1:
                c.rect(8, 26, 2, 3, pants); c.rect(8, 29, 4, 2, shoes)
                c.rect(5, 26, 2, 2, pants); c.rect(4, 28, 3, 2, shoes)
            case .walk2:
                c.rect(5, 26, 2, 3, pants); c.rect(5, 29, 4, 2, shoes)
                c.rect(8, 26, 2, 2, pants); c.rect(9, 28, 3, 2, shoes)
            default:
                c.rect(6, 26, 4, 3, pants); c.rect(6, 29, 5, 2, shoes)
            }
        } else if seated {
            c.rect(4, 25, 8, 3, pants)
            c.rect(4, 28, 3, 2, shoes); c.rect(9, 28, 3, 2, shoes)
        } else {
            c.rect(5, 25, 6, 1, pants)
            let lUp = f == .walk1 ? 1 : 0, rUp = f == .walk2 ? 1 : 0
            c.rect(5, 26, 2, 3 - lUp, pants); c.rect(4, 29 - lUp, 3, 2, shoes)
            c.rect(9, 26, 2, 3 - rUp, pants); c.rect(9, 29 - rUp, 3, 2, shoes)
        }
        if L.bottom != .pants {
            // Bare knees below the hem.
            for y in 27..<32 { for x in 0..<16 where c[x, y] == pants { c[x, y] = skin } }
        }
        if L.bottom == .skirt && !seated {
            if side { c.rect(5, 25, 6, 1, pants); c.rect(4, 26, 8, 1, pants) } else { c.rect(4, 25, 8, 1, pants); c.rect(3, 26, 10, 1, pants) }
        }

        // Torso
        if side {
            c.rect(5, 19, 6, 6, sh); c.rect(5, 24, 6, 1, shS)
        } else {
            c.rect(4, 19, 8, 6, sh); c.rect(4, 24, 8, 1, shS)
            if dir == .down { c[7, 19] = skin; c[8, 19] = skin }
        }
        dress(&c, L, shirt: shirt, dir: dir, white: white)

        // Arms
        if side {
            switch f {
            case .walk1: c.rect(8, 19, 2, 4, shS); c.rect(9, 23, 2, 1, skin)
            case .walk2: c.rect(6, 19, 2, 4, shS); c.rect(5, 23, 2, 1, skin)
            case .type1, .type2, .read1, .read2: c.rect(8, 20, 4, 2, shS); c.rect(12, 20, 1, 2, skin)
            case .cheer: c.rect(7, 14, 2, 6, shS); c.rect(7, 13, 2, 1, skin)
            default: c.rect(7, 19, 2, 5, shS); c.rect(7, 24, 2, 1, skin)
            }
        } else {
            switch f {
            case .type1 where dir == .down, .type2 where dir == .down:
                c.rect(3, 19, 1, 4, shS); c.rect(12, 19, 1, 4, shS)
                let lh = f == .type1 ? 23 : 24, rh = f == .type1 ? 24 : 23
                c.rect(3, lh - 1, 2, 1, shS); c.rect(4, lh, 2, 1, skin)
                c.rect(11, rh - 1, 2, 1, shS); c.rect(10, rh, 2, 1, skin)
            case .read1 where dir == .down, .read2 where dir == .down:
                let py = f == .read1 ? 21 : 20
                c.rect(3, 19, 1, 4, shS); c.rect(12, 19, 1, 4, shS)
                c.rect(5, py, 6, 5, paper)
                c.rect(6, py + 1, 4, 1, ink); c.rect(6, py + 3, 3, 1, ink)
                c[4, py + 2] = skin; c[11, py + 2] = skin
            case .cheer:
                c.rect(2, 14, 1, 6, shS); c.rect(13, 14, 1, 6, shS)
                c[2, 13] = skin; c[13, 13] = skin
            case .walk1:
                c.rect(3, 19, 1, 4, shS); c[3, 23] = skin
                c.rect(12, 19, 1, 5, shS); c[12, 24] = skin
            case .walk2:
                c.rect(3, 19, 1, 5, shS); c[3, 24] = skin
                c.rect(12, 19, 1, 4, shS); c[12, 23] = skin
            default:
                c.rect(3, 19, 1, 5, shS); c[3, 24] = skin
                c.rect(12, 19, 1, 5, shS); c[12, 24] = skin
            }
        }

        // Head
        let closed = f == .sleep || f == .doze || f == .nap
        switch dir {
        case .down:
            c.rect(3, 8, 10, 11, skin)
            for (x, y) in [(3, 8), (12, 8), (3, 18), (12, 18)] { c[x, y] = .clear }
            if L.style == .cap {
                c.rect(3, 7, 10, 4, shirt.darker(0.15)); c.rect(3, 11, 10, 1, shirt.darker(0.4))
                c[3, 7] = .clear; c[12, 7] = .clear
                c.rect(3, 12, 1, 3, hair); c.rect(12, 12, 1, 3, hair)
            } else {
                c.rect(3, 8, 10, 4, hair); c[3, 8] = .clear; c[12, 8] = .clear
                c.rect(5, 9, 3, 1, hairHi)
                c.rect(3, 12, 1, 4, hair); c.rect(12, 12, 1, 4, hair)
                for x in [4, 5, 7, 8, 10, 11] { c[x, 12] = hair }
            }
            if closed {
                c.rect(4, 15, 2, 1, eye); c.rect(10, 15, 2, 1, eye)
            } else {
                c.rect(5, 14, 1, 2, eye); c.rect(10, 14, 1, 2, eye)
            }
            c[4, 16] = blush; c[11, 16] = blush
            c[7, 17] = mouth; c[8, 17] = mouth
            if f == .cheer { c[7, 18] = mouth; c[8, 18] = mouth }
        case .up:
            c.rect(3, 8, 10, 11, hair)
            for (x, y) in [(3, 8), (12, 8), (3, 18), (12, 18)] { c[x, y] = .clear }
            c.rect(5, 9, 3, 1, hairHi)
            if L.style == .cap { c.rect(3, 7, 10, 4, shirt.darker(0.15)); c[3, 7] = .clear; c[12, 7] = .clear }
        case .right, .left:
            c.rect(4, 8, 9, 11, skin)
            for (x, y) in [(4, 8), (12, 8), (4, 18), (12, 18)] { c[x, y] = .clear }
            if L.style == .cap {
                c.rect(4, 7, 9, 4, shirt.darker(0.15)); c.rect(9, 11, 5, 1, shirt.darker(0.4))
                c[4, 7] = .clear
                c.rect(4, 11, 3, 4, hair)
            } else {
                c.rect(4, 8, 9, 4, hair); c[4, 8] = .clear; c[12, 8] = .clear
                c.rect(6, 9, 3, 1, hairHi)
                c.rect(4, 12, 4, 5, hair)
                c[9, 12] = hair; c[11, 12] = hair
            }
            if closed { c.rect(10, 15, 2, 1, eye) } else { c.rect(11, 14, 1, 2, eye) }
            c[10, 16] = blush
            c[12, 17] = mouth
        }

        // Hair that sits outside the head box
        switch (L.style, dir) {
        case (.long, .down):
            c.rect(2, 12, 2, 9, hair); c.rect(12, 12, 2, 9, hair)
        case (.long, .up):
            c.rect(3, 12, 10, 9, hair)
        case (.long, .right), (.long, .left):
            c.rect(3, 12, 4, 9, hair)
        case (.bun, .right), (.bun, .left):
            c.rect(4, 5, 4, 3, hair)
        case (.bun, _):
            c.rect(6, 5, 4, 3, hair); c[7, 5] = hairHi
        case (.spiky, .right), (.spiky, .left):
            for x in [5, 7, 9, 11] { c[x, 7] = hair }
            c[4, 9] = hair; c[3, 10] = hair
        case (.spiky, _):
            for x in [4, 6, 8, 10] { c[x, 7] = hair }
            c[5, 6] = hair; c[9, 6] = hair
        default:
            break
        }

        if L.outfit == .hoodie && dir == .down { c[3, 18] = shS; c[12, 18] = shS }
        if f == .nap && dir == .down { bow(&c, L, sleeve: shS) }

        c.outline()
        if dir == .left {
            var m = PixelCanvas(16, 32)
            for y in 0..<32 { for x in 0..<16 { m[15 - x, y] = c[x, y] } }
            return m
        }
        return c
    }

    /// Drops the head forward onto arms folded in front, so mostly hair shows above the closed eyes.
    private static func bow(_ c: inout PixelCanvas, _ L: Look, sleeve: RGBA) {
        let src = c
        for y in 0..<21 { for x in 0..<16 { c[x, y] = y >= 2 ? src[x, y - 2] : .clear } }
        c[7, 19] = L.skin; c[8, 19] = L.skin
        if L.style != .cap { c.rect(4, 14, 8, 2, L.hair) }
        c.rect(2, 21, 12, 3, sleeve)
        c.rect(3, 21, 2, 1, L.skin); c.rect(11, 21, 2, 1, L.skin)
    }

    /// Paints the outfit details over the plain torso.
    private static func dress(_ c: inout PixelCanvas, _ L: Look, shirt: RGBA, dir: Facing, white: RGBA) {
        let shS = shirt.darker(0.3), pocket = shirt.darker(0.12)
        let side = dir == .right || dir == .left
        switch (L.outfit, dir) {
        case (.tee, _):
            break
        case (.hoodie, .down):
            c.rect(4, 19, 3, 1, shS); c.rect(9, 19, 3, 1, shS)
            c.rect(6, 20, 1, 2, white); c.rect(9, 20, 1, 2, white)
            c.rect(5, 22, 6, 2, pocket)
        case (.hoodie, .up):
            c.rect(5, 19, 6, 2, shS)
        case (.hoodie, _):
            c.rect(4, 19, 3, 2, shS)
            c.rect(10, 20, 1, 2, white)
            c.rect(7, 22, 3, 2, pocket)
        case (.shirtTie, .down):
            c[5, 19] = white; c[6, 19] = white; c[9, 19] = white; c[10, 19] = white
            c[7, 19] = L.accent.darker(0.3); c[8, 19] = L.accent.darker(0.3)
            c.rect(7, 20, 2, 3, L.accent); c[7, 23] = L.accent
        case (.shirtTie, .up):
            c.rect(5, 19, 6, 1, white)
        case (.shirtTie, _):
            c.rect(8, 19, 3, 1, white)
            c.rect(10, 20, 1, 3, L.accent)
        case (.jacket, .down):
            c.rect(6, 19, 4, 2, L.accent); c.rect(7, 21, 2, 3, L.accent)
            c[7, 19] = L.skin; c[8, 19] = L.skin
            c[6, 22] = shS
        case (.jacket, .up):
            c.rect(5, 19, 6, 1, shS)
            c.rect(7, 22, 2, 3, pocket)
        case (.jacket, _):
            c.rect(10, 19, 1, 5, L.accent)
            c[9, 19] = shS; c[9, 20] = shS
        case (.stripes, _):
            let stripe = shirt.lighter(0.5)
            let x = side ? 5 : 4, w = side ? 6 : 8
            c.rect(x, 20, w, 1, stripe); c.rect(x, 22, w, 1, stripe)
        case (.overalls, .down):
            c.rect(5, 21, 6, 4, shirt); c.rect(4, 24, 8, 1, shirt)
            c.rect(5, 19, 1, 2, shirt); c.rect(10, 19, 1, 2, shirt)
            c[5, 21] = shirt.lighter(0.4); c[10, 21] = shirt.lighter(0.4)
            c.rect(6, 22, 4, 1, shS)
        case (.overalls, .up):
            c.rect(5, 19, 1, 4, shirt); c.rect(10, 19, 1, 4, shirt)
            c.rect(4, 23, 8, 2, shirt)
        case (.overalls, _):
            c.rect(5, 23, 6, 2, shirt)
            c.rect(8, 21, 3, 2, shirt); c.rect(8, 19, 1, 2, shirt)
        }
    }
}

/// Tiny deterministic generator, so a seed maps to the same look on every launch and Swift version.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
