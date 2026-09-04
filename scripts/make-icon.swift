// make-icon.swift — generates the Folio app icon artwork as a 1024x1024 PNG.
//
// Usage:
//   swift make-icon.swift <out.png> [--dark] [--full-bleed]
//
//   --dark        Dark-appearance palette (near-black tile, dark page,
//                 light gray text lines) for the macOS 26 dark icon variant.
//   --full-bleed  Draw the squircle at the full 1024 canvas instead of the
//                 legacy 824-in-1024 grid. Icon Composer (.icon) layers are
//                 full-canvas and get masked by the system; the legacy .icns
//                 wants the inset grid.
//
// Pure CoreGraphics + ImageIO so it runs as a plain script with no app bundle.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry helpers

/// Apple-style continuous-corner rounded square, approximated with a
/// superellipse |x/a|^n + |y/b|^n = 1. n = 5.6 lands very close to the
/// macOS icon shape (~22% effective corner radius).
func squirclePath(in rect: CGRect, exponent n: CGFloat = 5.6, segments: Int = 1440) -> CGPath {
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    let p = 2.0 / n
    let path = CGMutablePath()
    for i in 0...segments {
        let t = (CGFloat(i) / CGFloat(segments)) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), p)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), p)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// A page rectangle whose top-right corner is cut away by a 45 degree fold.
/// The other three corners get a small radius.
func pagePath(_ r: CGRect, fold: CGFloat, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
    path.move(to: CGPoint(x: minX, y: minY + radius))
    path.addLine(to: CGPoint(x: minX, y: maxY - radius))
    path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX + radius, y: maxY), radius: radius)
    path.addLine(to: CGPoint(x: maxX - fold, y: maxY))
    path.addLine(to: CGPoint(x: maxX, y: maxY - fold))   // the diagonal
    path.addLine(to: CGPoint(x: maxX, y: minY + radius))
    path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX - radius, y: minY), radius: radius)
    path.addLine(to: CGPoint(x: minX + radius, y: minY))
    path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX, y: minY + radius), radius: radius)
    path.closeSubpath()
    return path
}

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

// MARK: - Palettes

struct Palette {
    let gradientTop: CGColor
    let gradientBottom: CGColor
    let page: CGColor
    let fold: CGColor
    let line: CGColor
    /// Hairline around the page. Dark mode needs it so a dark-gray page still
    /// separates from a near-black tile; light mode leaves it nil.
    let pageRim: CGColor?
    let shadowAlpha: CGFloat
}

let lightPalette = Palette(
    gradientTop:    rgb(60, 74, 90),      // #3C4A5A
    gradientBottom: rgb(24, 31, 40),      // #181F28
    page:           rgb(255, 255, 255),
    fold:           rgb(186, 197, 209),   // #BAC5D1
    line:           rgb(150, 162, 176),   // #96A2B0
    pageRim:        nil,
    shadowAlpha:    0.32
)

let darkPalette = Palette(
    gradientTop:    rgb(28, 34, 43),      // #1C222B
    gradientBottom: rgb(14, 18, 22),      // #0E1216
    page:           rgb(49, 58, 70),      // #313A46 - #2A313A lifted slightly so the
                                          // page silhouette still separates at 16-32px
    fold:           rgb(78, 89, 103),     // #4E5967 - a touch lighter than the page
    line:           rgb(184, 192, 202),   // #B8C0CA
    pageRim:        rgb(107, 122, 140, 0.95),
    shadowAlpha:    0.55
)

// MARK: - Arguments

var outPath: String?
var dark = false
var fullBleed = false
for arg in CommandLine.arguments.dropFirst() {
    switch arg {
    case "--dark":       dark = true
    case "--full-bleed": fullBleed = true
    default:
        if arg.hasPrefix("--") {
            FileHandle.standardError.write("unknown option \(arg)\n".data(using: .utf8)!)
            exit(2)
        }
        outPath = arg
    }
}
guard let outPath else {
    FileHandle.standardError.write("usage: make-icon.swift <output.png> [--dark] [--full-bleed]\n".data(using: .utf8)!)
    exit(2)
}
let outURL = URL(fileURLWithPath: outPath)
let pal = dark ? darkPalette : lightPalette

// MARK: - Canvas

let S: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write("failed to create bitmap context\n".data(using: .utf8)!)
    exit(1)
}
ctx.interpolationQuality = .high
ctx.setAllowsAntialiasing(true)

// Legacy .icns art uses the 824-in-1024 macOS icon grid. Icon Composer layers
// are drawn edge to edge and masked to the icon shape by the system.
let bodyRect = fullBleed ? CGRect(x: 0, y: 0, width: S, height: S)
                         : CGRect(x: 100, y: 100, width: 824, height: 824)
/// Everything below is expressed against the 824pt grid and scaled to fit.
let k = bodyRect.width / 824
let body = squirclePath(in: bodyRect)

// MARK: - Tile

ctx.saveGState()
ctx.addPath(body)
ctx.clip()
let gradient = CGGradient(colorsSpace: space,
                          colors: [pal.gradientTop, pal.gradientBottom] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: bodyRect.maxY),
                       end: CGPoint(x: 0, y: bodyRect.minY),
                       options: [])
ctx.restoreGState()

// Hairline top highlight, legacy art only. On a full-bleed layer this would sit
// exactly on the system mask edge and could fringe, so it is skipped there.
if !fullBleed {
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.addPath(body)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.10))
    ctx.setLineWidth(6 * k)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Page

let pageW = 408 * k
let pageH = 500 * k
let pageRect = CGRect(x: bodyRect.midX - pageW / 2,
                      y: bodyRect.midY - pageH / 2 - 4 * k,
                      width: pageW, height: pageH)
let fold = 104 * k
let page = pagePath(pageRect, fold: fold, radius: 16 * k)

// Faint shadow, page only.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 26 * k, color: rgb(0, 0, 0, pal.shadowAlpha))
ctx.addPath(page)
ctx.setFillColor(pal.page)
ctx.fillPath()
ctx.restoreGState()

// Dark mode: hairline rim so the page edge survives against the near-black tile.
if let rim = pal.pageRim {
    ctx.saveGState()
    ctx.addPath(page)
    ctx.setStrokeColor(rim)
    ctx.setLineWidth(4 * k)
    ctx.strokePath()
    ctx.restoreGState()
}

// Folded corner: the flap lying against the page face.
ctx.saveGState()
let flap = CGMutablePath()
flap.move(to: CGPoint(x: pageRect.maxX - fold, y: pageRect.maxY))
flap.addLine(to: CGPoint(x: pageRect.maxX, y: pageRect.maxY - fold))
flap.addLine(to: CGPoint(x: pageRect.maxX - fold, y: pageRect.maxY - fold))
flap.closeSubpath()
ctx.addPath(flap)
ctx.setFillColor(pal.fold)
ctx.fillPath()
ctx.restoreGState()

// MARK: - Text lines

let inset = 52 * k
let lineH = 24 * k
let gap = 44 * k
let lineX = pageRect.minX + inset
let fullW = pageRect.width - inset * 2
let widths: [CGFloat] = [fullW, fullW, fullW, fullW * 0.58]

// Block of lines sits just below the folded corner, optically centered.
var lineY = pageRect.maxY - 148 * k
ctx.setFillColor(pal.line)
for w in widths {
    let r = CGRect(x: lineX, y: lineY - lineH, width: w, height: lineH)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: lineH / 2, cornerHeight: lineH / 2, transform: nil))
    ctx.fillPath()
    lineY -= (lineH + gap)
}

// MARK: - Write PNG

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write("failed to create image destination\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write("failed to write \(outURL.path)\n".data(using: .utf8)!)
    exit(1)
}
print("wrote \(outURL.path)\(dark ? " [dark]" : " [light]")\(fullBleed ? " [full-bleed]" : "")")
