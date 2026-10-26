import CoreGraphics
import Foundation
import SwiftUI

struct RGBA: Equatable, Hashable {
    var r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255

    static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    init(_ hex: UInt32) {
        r = UInt8((hex >> 16) & 0xff); g = UInt8((hex >> 8) & 0xff); b = UInt8(hex & 0xff); a = 255
    }

    init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(v)
    }

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    func mix(_ o: RGBA, _ t: Double) -> RGBA {
        func m(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(max(0, min(255, Double(x) + (Double(y) - Double(x)) * t))) }
        return RGBA(r: m(r, o.r), g: m(g, o.g), b: m(b, o.b), a: a)
    }

    func darker(_ t: Double = 0.25) -> RGBA { mix(RGBA(0x1b1530), t) }
    func lighter(_ t: Double = 0.3) -> RGBA { mix(RGBA(0xffffff), t) }

    var cg: CGColor { CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255) }
    var color: Color { Color(cgColor: cg) }

    init(_ c: Color) {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? .gray
        self.init(r: UInt8(ns.redComponent * 255), g: UInt8(ns.greenComponent * 255), b: UInt8(ns.blueComponent * 255))
    }
}

enum Palette {
    static let outline = RGBA(0x221c35)
    static let project: [RGBA] = [
        RGBA(0xff6b6b), RGBA(0x4dabf7), RGBA(0x69db7c), RGBA(0xffa94d),
        RGBA(0xda77f2), RGBA(0x38d9a9), RGBA(0xf783ac), RGBA(0x748ffc), RGBA(0xffd43b),
    ]
    static let account: [RGBA] = [
        RGBA(0xe8590c), RGBA(0x1c7ed6), RGBA(0x2f9e44), RGBA(0xae3ec9), RGBA(0xf08c00), RGBA(0x0ca678),
    ]
}

/// A small RGBA bitmap addressed top-left origin, y down — the natural space for hand-made pixel art.
struct PixelCanvas {
    let width: Int, height: Int
    var px: [RGBA]

    init(_ w: Int, _ h: Int) {
        width = w; height = h
        px = Array(repeating: .clear, count: w * h)
    }

    subscript(x: Int, y: Int) -> RGBA {
        get { (x >= 0 && y >= 0 && x < width && y < height) ? px[y * width + x] : .clear }
        set { if x >= 0 && y >= 0 && x < width && y < height { px[y * width + x] = newValue } }
    }

    mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGBA) {
        for yy in y..<(y + h) { for xx in x..<(x + w) { self[xx, yy] = c } }
    }

    /// Draws ASCII art: each character maps to a color via `colors`; unknown characters are transparent.
    mutating func stamp(_ rows: [String], at x: Int, _ y: Int, _ colors: [Character: RGBA], flipX: Bool = false) {
        for (j, row) in rows.enumerated() {
            let chars = Array(row)
            for (i, ch) in chars.enumerated() {
                guard let c = colors[ch] else { continue }
                self[x + (flipX ? chars.count - 1 - i : i), y + j] = c
            }
        }
    }

    /// Adds a 1px outline around every opaque shape.
    mutating func outline(_ c: RGBA = Palette.outline) {
        let src = px
        for y in 0..<height {
            for x in 0..<width where src[y * width + x].a == 0 {
                func solid(_ nx: Int, _ ny: Int) -> Bool {
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { return false }
                    let p = src[ny * width + nx]
                    return p.a > 0 && p != c
                }
                if solid(x - 1, y) || solid(x + 1, y) || solid(x, y - 1) || solid(x, y + 1) {
                    px[y * width + x] = c
                }
            }
        }
    }

    func makeImage() -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for (i, p) in px.enumerated() {
            // Premultiplied alpha.
            let a = UInt16(p.a)
            bytes[i * 4] = UInt8(UInt16(p.r) * a / 255)
            bytes[i * 4 + 1] = UInt8(UInt16(p.g) * a / 255)
            bytes[i * 4 + 2] = UInt8(UInt16(p.b) * a / 255)
            bytes[i * 4 + 3] = p.a
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

/// Drawing surface in pixel units with y pointing down, backed by a CGContext.
final class PixelContext {
    let ctx: CGContext
    let width: Int, height: Int

    init(_ w: Int, _ h: Int) {
        width = w; height = h
        ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
    }

    func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: RGBA) {
        ctx.setFillColor(c.cg)
        ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    func image(_ img: CGImage, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat? = nil, _ h: CGFloat? = nil,
               flipX: Bool = false, smooth: Bool = false, alpha: CGFloat = 1) {
        let w = w ?? CGFloat(img.width), h = h ?? CGFloat(img.height)
        ctx.saveGState()
        ctx.interpolationQuality = smooth ? .high : .none
        ctx.setAlpha(alpha)
        // Undo the y-flip locally so the image isn't drawn upside down.
        ctx.translateBy(x: flipX ? x + w : x, y: y + h)
        ctx.scaleBy(x: flipX ? -1 : 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()
    }

    func makeImage() -> CGImage? { ctx.makeImage() }
}

extension CGImage {
    func crop(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CGImage? {
        cropping(to: CGRect(x: x, y: y, width: w, height: h))
    }

    /// The image turned a quarter turn counter-clockwise, so its top ends up on the left.
    func rotatedLeft() -> CGImage? {
        let w = width, h = height
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let src = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: info),
              let dst = CGContext(data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: h * 4, space: space, bitmapInfo: info),
              let sp = src.data, let dp = dst.data else { return nil }
        src.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        let s = sp.bindMemory(to: UInt32.self, capacity: w * h), d = dp.bindMemory(to: UInt32.self, capacity: w * h)
        for y in 0..<h { for x in 0..<w { d[(w - 1 - x) * h + y] = s[y * w + x] } }
        return dst.makeImage()
    }

    /// Bounding box of non-transparent pixels.
    func opaqueBounds() -> CGRect {
        let w = width, h = height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return CGRect(x: 0, y: 0, width: w, height: h) }
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where p[(y * w + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        if maxX < 0 { return CGRect(x: 0, y: 0, width: w, height: h) }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
