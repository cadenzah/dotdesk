import CoreGraphics

/// Procedurally painted 16x32 chibi office workers. Original art, safe to ship with the app.
///
/// Sheets follow the Pixel Agents layout (rows: down, up, right; 16x32 frames) so every
/// character source renders through the same code, with three extra columns: sleep, cheer and doze
/// (sitting with eyes closed).
enum BuiltinCharacters {
    enum HairStyle { case short, long, bun, spiky, cap }

    struct Look {
        let name: String
        let skin: RGBA
        let hair: RGBA
        let style: HairStyle
        let pants: RGBA
        let shoes: RGBA
    }

    enum Frame: Int, CaseIterable {
        case walk1 = 0, stand, walk2, type1, type2, read1, read2, sleep, cheer, doze
    }

    static let looks: [Look] = [
        Look(name: "밤톨머리", skin: RGBA(0xffd9b8), hair: RGBA(0x6b4423), style: .short, pants: RGBA(0x2f3b52), shoes: RGBA(0x3b2f2f)),
        Look(name: "긴 생머리", skin: RGBA(0xf1c27d), hair: RGBA(0x2b2b35), style: .long, pants: RGBA(0x3d405b), shoes: RGBA(0x2a2a2a)),
        Look(name: "삐죽 금발", skin: RGBA(0xe0ac69), hair: RGBA(0xe8c15a), style: .spiky, pants: RGBA(0x264653), shoes: RGBA(0x4a3426)),
        Look(name: "핑크 똥머리", skin: RGBA(0xffe0c4), hair: RGBA(0xf28cb5), style: .bun, pants: RGBA(0x5a4a78), shoes: RGBA(0x3b2f2f)),
        Look(name: "모자 쓴 친구", skin: RGBA(0xc68642), hair: RGBA(0x1e1e28), style: .cap, pants: RGBA(0x343a40), shoes: RGBA(0xf1f3f5)),
        Look(name: "주황 머리", skin: RGBA(0xffd9b8), hair: RGBA(0xd9622b), style: .short, pants: RGBA(0x495057), shoes: RGBA(0x2a2a2a)),
        Look(name: "은발 장발", skin: RGBA(0x8d5524), hair: RGBA(0xdedede), style: .long, pants: RGBA(0x22303c), shoes: RGBA(0x5c3d2e)),
        Look(name: "파란 삐죽", skin: RGBA(0xf1c27d), hair: RGBA(0x4a6fd1), style: .spiky, pants: RGBA(0x3b3b3b), shoes: RGBA(0xc92a2a)),
    ]

    static func sheet(look index: Int, shirt: RGBA) -> CGImage {
        let look = looks[((index % looks.count) + looks.count) % looks.count]
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
        let sh = shirt, shS = shirt.darker(0.3)
        let pants = L.pants, shoes = L.shoes
        let eye = RGBA(0x2b2440), blush = RGBA(0xf59ca0), mouth = RGBA(0xb5524a)
        let paper = RGBA(0xfdfdf6), ink = RGBA(0xb8bcc8)
        let side = dir == .right || dir == .left
        let seated = !side && [.type1, .type2, .read1, .read2, .doze].contains(f)

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

        // Torso
        if side {
            c.rect(5, 19, 6, 6, sh); c.rect(5, 24, 6, 1, shS)
        } else {
            c.rect(4, 19, 8, 6, sh); c.rect(4, 24, 8, 1, shS)
            if dir == .down { c[7, 19] = skin; c[8, 19] = skin }
        }

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
        let closed = f == .sleep || f == .doze
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

        c.outline()
        if dir == .left {
            var m = PixelCanvas(16, 32)
            for y in 0..<32 { for x in 0..<16 { m[15 - x, y] = c[x, y] } }
            return m
        }
        return c
    }
}
