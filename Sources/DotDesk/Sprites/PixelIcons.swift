import CoreGraphics

/// 7x7 activity icons shown in a speech bubble above characters.
enum PixelIcon: CaseIterable {
    case dots, book, magnifier, pencil, terminal, globe, people, checklist, wrench, exclaim, question, check, zzz

    private var art: ([String], [Character: RGBA]) {
        switch self {
        case .dots:
            return ([".......", ".......", ".......", ".#.#.#.", ".......", ".......", "......."],
                    ["#": RGBA(0x495057)])
        case .book:
            return ([".####..", ".#ooo#.", ".#---#.", ".#ooo#.", ".#---#.", ".#ooo#.", ".#####."],
                    ["#": RGBA(0x8b5a2b), "o": RGBA(0xfff3d6), "-": RGBA(0xc8a27a)])
        case .magnifier:
            return ([".###...", "#xxx#..", "#xxx#..", "#xxx#..", ".###...", "....##.", ".....##"],
                    ["#": RGBA(0x444466), "x": RGBA(0xbfe3ff)])
        case .pencil:
            return ([".....##", "....#x#", "...#o#.", "..#o#..", ".#o#...", "#w#....", "##....."],
                    ["#": RGBA(0x444466), "x": RGBA(0xff8fab), "o": RGBA(0xffc93c), "w": RGBA(0xf5d5a0)])
        case .terminal:
            return (["#######", "#ooooo#", "#xoooo#", "#oxooo#", "#xoxxo#", "#ooooo#", "#######"],
                    ["#": RGBA(0x6b7280), "o": RGBA(0x1e2233), "x": RGBA(0x51e07a)])
        case .globe:
            return (["..###..", ".#xox#.", "#xxoxx#", "#ooooo#", "#xxoxx#", ".#xox#.", "..###.."],
                    ["#": RGBA(0x1c7ed6), "x": RGBA(0x74c0fc), "o": RGBA(0x51cf66)])
        case .people:
            return ([".#...#.", "###.###", ".#...#.", ".......", "xxx.ooo", "xxx.ooo", "......."],
                    ["#": RGBA(0xe0a370), "x": RGBA(0xff6b6b), "o": RGBA(0x4dabf7)])
        case .checklist:
            return (["#######", "#xwooo#", "#wwwww#", "#xwooo#", "#wwwww#", "#xwooo#", "#######"],
                    ["#": RGBA(0x868e96), "x": RGBA(0x2f9e44), "o": RGBA(0xadb5bd), "w": RGBA(0xffffff)])
        case .wrench:
            return ([".#.#.#.", "#######", ".##o##.", "##ooo##", ".##o##.", "#######", ".#.#.#."],
                    ["#": RGBA(0x868e96), "o": RGBA(0xffffff)])
        case .exclaim:
            return (["...#...", "..###..", "..###..", "..###..", "...#...", ".......", "...#..."],
                    ["#": RGBA(0xf03e3e)])
        case .question:
            return (["..###..", ".#...#.", ".....#.", "...##..", "...#...", ".......", "...#..."],
                    ["#": RGBA(0x7048e8)])
        case .check:
            return ([".......", "......#", ".....##", "#...##.", "##.##..", ".###...", "..#...."],
                    ["#": RGBA(0x2f9e44)])
        case .zzz:
            return (["####...", "..#....", ".#.....", "####...", "....###", ".....#.", "....###"],
                    ["#": RGBA(0x5c7cfa)])
        }
    }

    private static var cache: [PixelIcon: CGImage] = [:]

    /// 15x14 speech bubble with the icon inside; the tail points down at x=7.
    var bubble: CGImage {
        if let img = Self.cache[self] { return img }
        var c = PixelCanvas(15, 14)
        let white = RGBA(0xffffff)
        c.rect(1, 1, 13, 10, white)
        for (x, y) in [(1, 1), (13, 1), (1, 10), (13, 10)] { c[x, y] = .clear }
        c.rect(6, 11, 3, 1, white)
        c[7, 12] = white
        let (rows, colors) = art
        c.stamp(rows, at: 4, 2, colors)
        c.outline()
        let img = c.makeImage()
        Self.cache[self] = img
        return img
    }
}
