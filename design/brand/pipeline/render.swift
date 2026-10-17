// Renders a specimen or sheet with CoreText, the text engine the Mac app uses.
// Usage: swift render.swift <spec.json> <out.png>
// The spec lists font files to register (process scope, exactly as PixelFonts.ensureRegistered does in the app),
// a canvas, filled rectangles, PNG images and text runs. Every text run names a PostScript font; the renderer
// fails if CoreText resolves it to any other font, so a specimen can only be produced by the real font file.
import AppKit
import CoreText
import Foundation

struct Spec: Decodable {
    struct Rect: Decodable { let x, y, w, h: Double; let color: String; let radius: Double? }
    struct Image: Decodable { let path: String; let x, y, w, h: Double; let smooth: Bool? }
    struct Text: Decodable {
        let font: String; let size: Double; let color: String; let x, y: Double
        let text: String; let tracking: Double?; let maxWidth: Double?; let lineHeight: Double?
    }
    let fonts: [String]
    let width, height: Double
    let scale: Double
    let background: String
    let rects: [Rect]?
    let images: [Image]?
    let texts: [Text]
}

func color(_ hex: String) -> CGColor {
    var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    var alpha: CGFloat = 1
    if s.count == 8 { alpha = CGFloat(UInt8(s.suffix(2), radix: 16)!) / 255; s = String(s.prefix(6)) }
    let v = UInt32(s, radix: 16)!
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
}

let args = CommandLine.arguments
let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
for path in spec.fonts {
    var error: Unmanaged<CFError>?
    if !CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, &error) {
        fputs("register failed: \(path) \(String(describing: error?.takeRetainedValue()))\n", stderr)
    }
}
let w = Int(spec.width * spec.scale), h = Int(spec.height * spec.scale)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: spec.scale, y: spec.scale)
// Top-left origin for layout; text is drawn with a local flip.
ctx.translateBy(x: 0, y: spec.height)
ctx.scaleBy(x: 1, y: -1)
ctx.setFillColor(color(spec.background))
ctx.fill(CGRect(x: 0, y: 0, width: spec.width, height: spec.height))
for r in spec.rects ?? [] {
    ctx.setFillColor(color(r.color))
    let rect = CGRect(x: r.x, y: r.y, width: r.w, height: r.h)
    if let rad = r.radius, rad > 0 {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rad, cornerHeight: rad, transform: nil)); ctx.fillPath()
    } else { ctx.fill(rect) }
}
for im in spec.images ?? [] {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: im.path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fputs("missing image \(im.path)\n", stderr); exit(1) }
    ctx.saveGState()
    ctx.interpolationQuality = (im.smooth ?? true) ? .high : .none
    ctx.translateBy(x: im.x, y: im.y + im.h); ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: im.w, height: im.h))
    ctx.restoreGState()
}
var resolved = Set<String>()
for t in spec.texts {
    // "system-mono" / "system-mono-medium": the app's current sentence face (SF Mono), for comparison only.
    let font: CTFont
    if t.font.hasPrefix("system-mono") {
        font = NSFont.monospacedSystemFont(ofSize: CGFloat(t.size), weight: t.font.hasSuffix("medium") ? .medium : .regular) as CTFont
    } else {
        font = CTFontCreateWithName(t.font as CFString, CGFloat(t.size), nil)
        let actual = CTFontCopyPostScriptName(font) as String
        guard actual == t.font else { fputs("font \(t.font) resolved to \(actual)\n", stderr); exit(2) }
        resolved.insert(actual)
    }
    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(t.color)]
    if let k = t.tracking { attrs[.kern] = k }
    let para = NSMutableParagraphStyle()
    if let lh = t.lineHeight { para.minimumLineHeight = CGFloat(lh); para.maximumLineHeight = CGFloat(lh) }
    attrs[.paragraphStyle] = para
    let str = NSAttributedString(string: t.text, attributes: attrs)
    let setter = CTFramesetterCreateWithAttributedString(str)
    let maxW = t.maxWidth ?? 10000
    let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                                                            CGSize(width: maxW, height: 10000), nil)
    // y is the top of the text box in top-left coordinates.
    ctx.saveGState()
    ctx.translateBy(x: t.x, y: t.y + size.height); ctx.scaleBy(x: 1, y: -1)
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                                         CGPath(rect: CGRect(x: 0, y: 0, width: maxW, height: size.height + 1), transform: nil), nil)
    CTFrameDraw(frame, ctx)
    ctx.restoreGState()
}
let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("rendered \(args[2]) with \(resolved.sorted().joined(separator: ", "))")
