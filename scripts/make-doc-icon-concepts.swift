// make-doc-icon-concepts.swift — Finder document-icon directions for .md files.
//
// A macOS document icon is a bare sheet on a transparent canvas: no tile, no
// background. Everything else borrows the shipping app icon's language —
// folded top-right corner, slate rules, four coloured margin tabs.
//
// Usage: swift scripts/make-doc-icon-concepts.swift <output-directory>

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255, alpha: a)
}

func context(width: Int, height: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    return ctx
}

func fill(_ path: CGPath, _ color: CGColor, in ctx: CGContext) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

func pill(_ rect: CGRect, _ color: CGColor, in ctx: CGContext) {
    fill(CGPath(roundedRect: rect, cornerWidth: rect.height / 2,
                cornerHeight: rect.height / 2, transform: nil), color, in: ctx)
}

func rounded(_ rect: CGRect, radius: CGFloat, _ color: CGColor, in ctx: CGContext) {
    fill(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                transform: nil), color, in: ctx)
}

func pagePath(_ rect: CGRect, fold: CGFloat, radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
    p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
    p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
             tangent2End: CGPoint(x: rect.minX + radius, y: rect.maxY), radius: radius)
    p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
    p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
             tangent2End: CGPoint(x: rect.maxX - radius, y: rect.minY), radius: radius)
    p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
    p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
             tangent2End: CGPoint(x: rect.minX, y: rect.minY + radius), radius: radius)
    p.closeSubpath()
    return p
}

// MARK: - Sheet geometry

// Finder document proportions: 0.78 : 1, centred, with the tabs allowed to
// break the right margin the way they do in the app icon.
let pageRect = CGRect(x: 152, y: 112, width: 624, height: 800)
let foldSize: CGFloat = 150
let pageRadius: CGFloat = 24
let pageCenterX = pageRect.midX

let lineX: CGFloat = 241
let lineW: CGFloat = 434
let lineH: CGFloat = 30
let fiveLineY: [CGFloat] = [697, 625, 505, 437, 341]

let tabX: CGFloat = 726
let tabW: CGFloat = 144
let tabH: CGFloat = 71
let tabRadius: CGFloat = 21
let tabY: [CGFloat] = [612, 493, 374, 255]
let tabColors = [rgb(255, 91, 91), rgb(255, 190, 48), rgb(46, 210, 171), rgb(76, 160, 255)]

struct Palette {
    let paper: CGColor
    let fold: CGColor
    let ink: CGColor
    let rim: CGColor?
    let shadowAlpha: CGFloat
    let badgeFill: CGColor
    let badgeText: CGColor
}

let lightPalette = Palette(
    paper: rgb(255, 255, 255),
    fold: rgb(212, 219, 229),
    ink: rgb(55, 65, 77),              // #37414D
    rim: nil,
    shadowAlpha: 0.22,
    badgeFill: rgb(55, 65, 77),
    badgeText: rgb(255, 255, 255)
)

let darkPalette = Palette(
    paper: rgb(31, 37, 47),            // slate sheet
    fold: rgb(62, 72, 86),
    ink: rgb(238, 243, 249),
    rim: rgb(96, 109, 126),
    shadowAlpha: 0.50,
    badgeFill: rgb(238, 243, 249),
    badgeText: rgb(28, 34, 43)
)

func palette(_ dark: Bool) -> Palette { dark ? darkPalette : lightPalette }

func drawTabs(_ indices: [Int], in ctx: CGContext) {
    for i in indices {
        rounded(CGRect(x: tabX, y: tabY[i], width: tabW, height: tabH),
                radius: tabRadius, tabColors[i], in: ctx)
    }
}

@discardableResult
func drawSheet(dark: Bool, in ctx: CGContext) -> CGPath {
    let p = palette(dark)
    let page = pagePath(pageRect, fold: foldSize, radius: pageRadius)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30,
                  color: rgb(0, 0, 0, p.shadowAlpha))
    fill(page, p.paper, in: ctx)
    ctx.restoreGState()

    if let rim = p.rim {
        ctx.addPath(page)
        ctx.setStrokeColor(rim)
        ctx.setLineWidth(4)
        ctx.strokePath()
    }

    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: pageRect.maxX - foldSize, y: pageRect.maxY))
    flap.addLine(to: CGPoint(x: pageRect.maxX, y: pageRect.maxY - foldSize))
    flap.addLine(to: CGPoint(x: pageRect.maxX - foldSize, y: pageRect.maxY - foldSize))
    flap.closeSubpath()
    fill(flap, p.fold, in: ctx)
    return page
}

// MARK: - Drawn marks

// CommonMark's "M↓": a heavy M beside a solid down arrow. The M is a stroked
// polyline clipped to its own box, which keeps the stem terminals and the
// mitred apexes flat instead of spiking past the cap height.
func markdownMark(centerX: CGFloat, centerY: CGFloat, height h: CGFloat,
                  color: CGColor, in ctx: CGContext) {
    let t = h * 0.250
    let mW = h * 1.02
    let gap = h * 0.19
    let aW = h * 0.62
    let x0 = centerX - (mW + gap + aW) / 2
    let y0 = centerY - h / 2

    ctx.saveGState()
    ctx.clip(to: CGRect(x: x0 - t, y: y0, width: mW + 2 * t, height: h))
    let m = CGMutablePath()
    m.move(to: CGPoint(x: x0 + t / 2, y: y0 - t))
    m.addLine(to: CGPoint(x: x0 + t / 2, y: y0 + h))
    m.addLine(to: CGPoint(x: x0 + mW / 2, y: y0 + h * 0.40))
    m.addLine(to: CGPoint(x: x0 + mW - t / 2, y: y0 + h))
    m.addLine(to: CGPoint(x: x0 + mW - t / 2, y: y0 - t))
    ctx.addPath(m)
    ctx.setStrokeColor(color)
    ctx.setLineWidth(t)
    ctx.setLineJoin(.miter)
    ctx.setMiterLimit(24)
    ctx.setLineCap(.butt)
    ctx.strokePath()
    ctx.restoreGState()

    let ax = x0 + mW + gap
    let headH = h * 0.46
    let stemW = t
    fill(CGPath(rect: CGRect(x: ax + aW / 2 - stemW / 2, y: y0 + headH * 0.76,
                             width: stemW, height: h - headH * 0.76), transform: nil),
         color, in: ctx)
    let head = CGMutablePath()
    head.move(to: CGPoint(x: ax + aW / 2, y: y0))
    head.addLine(to: CGPoint(x: ax + aW, y: y0 + headH))
    head.addLine(to: CGPoint(x: ax, y: y0 + headH))
    head.closeSubpath()
    fill(head, color, in: ctx)
}

func hashMark(centerX: CGFloat, centerY: CGFloat, size: CGFloat,
              color: CGColor, in ctx: CGContext) {
    let t = size * 0.19
    let radius = t * 0.32
    for dx in [CGFloat(-0.215), 0.215] {
        let bar = CGRect(x: centerX + dx * size - t / 2, y: centerY - size / 2,
                         width: t, height: size)
        var slant = CGAffineTransform(translationX: bar.midX, y: bar.midY)
            .rotated(by: -0.15)
            .translatedBy(x: -bar.midX, y: -bar.midY)
        fill(CGPath(roundedRect: bar, cornerWidth: radius, cornerHeight: radius,
                    transform: &slant), color, in: ctx)
    }
    for dy in [CGFloat(-0.165), 0.165] {
        rounded(CGRect(x: centerX - size * 0.45, y: centerY + dy * size - t / 2,
                       width: size * 0.90, height: t),
                radius: radius, color, in: ctx)
    }
}

func systemFont(_ size: CGFloat, bold: Bool) -> CTFont {
    let base = CTFontCreateUIFontForLanguage(.system, size, nil)
        ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    guard bold else { return base }
    return CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitBold, .traitBold) ?? base
}

func drawCentered(_ text: String, font: CTFont, color: CGColor,
                  center: CGPoint, in ctx: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: center.x - bounds.midX, y: center.y - bounds.midY)
    CTLineDraw(line, ctx)
}

func label(_ text: String, at point: CGPoint, size: CGFloat, bold: Bool = false,
           color: CGColor, in ctx: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): systemFont(size, bold: bold),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attributes))
    ctx.textPosition = point
    CTLineDraw(line, ctx)
}

// MARK: - Concepts

func drawTabbedMark(dark: Bool) -> CGImage {
    let ctx = context(width: Int(canvas), height: Int(canvas))
    let p = palette(dark)
    drawTabs([0, 1, 2, 3], in: ctx)
    drawSheet(dark: dark, in: ctx)
    for y in [CGFloat(715), 650, 290, 225] {
        pill(CGRect(x: lineX, y: y, width: lineW, height: lineH), p.ink, in: ctx)
    }
    markdownMark(centerX: pageCenterX, centerY: 485, height: 224, color: p.ink, in: ctx)
    return ctx.makeImage()!
}

func drawHash(dark: Bool) -> CGImage {
    let ctx = context(width: Int(canvas), height: Int(canvas))
    let p = palette(dark)
    drawTabs([3], in: ctx)
    drawSheet(dark: dark, in: ctx)
    hashMark(centerX: pageCenterX, centerY: 595, size: 330, color: p.ink, in: ctx)
    pill(CGRect(x: pageCenterX - 160, y: 305, width: 320, height: lineH), p.ink, in: ctx)
    pill(CGRect(x: pageCenterX - 115, y: 230, width: 230, height: lineH), p.ink, in: ctx)
    return ctx.makeImage()!
}

func drawSource(dark: Bool) -> CGImage {
    let ctx = context(width: Int(canvas), height: Int(canvas))
    let p = palette(dark)
    drawTabs([0, 1, 2, 3], in: ctx)
    drawSheet(dark: dark, in: ctx)

    hashMark(centerX: 272, centerY: 719, size: 62, color: p.ink, in: ctx)
    rounded(CGRect(x: 325, y: 698, width: 350, height: 42), radius: 12, p.ink, in: ctx)

    for y in [CGFloat(615), 535, 455] {
        rounded(CGRect(x: 241, y: y + 6, width: 38, height: 15), radius: 7, p.ink, in: ctx)
        pill(CGRect(x: 303, y: y, width: 322, height: 26), p.ink, in: ctx)
    }

    // `**bold**`: a rule with weighted ends standing in for the asterisk pairs.
    pill(CGRect(x: 307, y: 350, width: 290, height: 24), p.ink, in: ctx)
    rounded(CGRect(x: 289, y: 338, width: 54, height: 48), radius: 16, p.ink, in: ctx)
    rounded(CGRect(x: 561, y: 338, width: 54, height: 48), radius: 16, p.ink, in: ctx)
    return ctx.makeImage()!
}

func drawBadge(dark: Bool) -> CGImage {
    let ctx = context(width: Int(canvas), height: Int(canvas))
    let p = palette(dark)
    drawTabs([0, 1, 2, 3], in: ctx)
    drawSheet(dark: dark, in: ctx)
    for y in fiveLineY {
        pill(CGRect(x: lineX, y: y, width: lineW, height: lineH), p.ink, in: ctx)
    }
    let badge = CGRect(x: 598, y: 118, width: 252, height: 132)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: rgb(0, 0, 0, 0.34))
    rounded(badge, radius: 36, p.badgeFill, in: ctx)
    ctx.restoreGState()
    drawCentered("MD", font: systemFont(88, bold: true), color: p.badgeText,
                 center: CGPoint(x: badge.midX, y: badge.midY), in: ctx)
    return ctx.makeImage()!
}

func drawRibbon(dark: Bool) -> CGImage {
    let ctx = context(width: Int(canvas), height: Int(canvas))
    let p = palette(dark)
    let page = drawSheet(dark: dark, in: ctx)

    ctx.saveGState()
    ctx.addPath(page)
    ctx.clip()
    let ribbon = CGMutablePath()
    ribbon.move(to: CGPoint(x: 371, y: pageRect.maxY))
    ribbon.addLine(to: CGPoint(x: 557, y: pageRect.maxY))
    ribbon.addLine(to: CGPoint(x: 557, y: 545))
    ribbon.addLine(to: CGPoint(x: 464, y: 606))
    ribbon.addLine(to: CGPoint(x: 371, y: 545))
    ribbon.closeSubpath()
    fill(ribbon, rgb(255, 91, 91), in: ctx)
    ctx.restoreGState()

    markdownMark(centerX: 464, centerY: 790, height: 78,
                 color: rgb(255, 255, 255), in: ctx)
    for y in [CGFloat(455), 383, 311, 239] {
        pill(CGRect(x: lineX, y: y, width: lineW, height: lineH), p.ink, in: ctx)
    }
    return ctx.makeImage()!
}

func drawMinimal(dark: Bool) -> CGImage {
    let ctx = context(width: Int(canvas), height: Int(canvas))
    let p = palette(dark)
    drawSheet(dark: dark, in: ctx)
    markdownMark(centerX: pageCenterX, centerY: 470, height: 292, color: p.ink, in: ctx)
    return ctx.makeImage()!
}

struct Concept {
    let name: String
    let slug: String
    let draw: (Bool) -> CGImage
}

let concepts = [
    Concept(name: "Tabbed page + M\u{2193}", slug: "tabbed", draw: drawTabbedMark),
    Concept(name: "Hash", slug: "hash", draw: drawHash),
    Concept(name: "Markdown source", slug: "source", draw: drawSource),
    Concept(name: "Badge", slug: "badge", draw: drawBadge),
    Concept(name: "Ribbon", slug: "ribbon", draw: drawRibbon),
    Concept(name: "Minimal", slug: "minimal", draw: drawMinimal)
]

// MARK: - Output

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}

func resized(_ image: CGImage, to side: Int) -> CGImage {
    let ctx = context(width: side, height: side)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return ctx.makeImage()!
}

// A single 1024 → 32 draw aliases badly. Halving repeatedly first is the
// cheap equivalent of a mipmap chain and keeps the 32 px tabs from breaking up.
func downsample(_ image: CGImage, to side: Int) -> CGImage {
    var current = image
    while current.width / 2 >= side * 2 {
        current = resized(current, to: current.width / 2)
    }
    return current.width == side ? current : resized(current, to: side)
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift scripts/make-doc-icon-concepts.swift <output-directory>\n", stderr)
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

var rendered: [(light: CGImage, dark: CGImage)] = []
for (index, concept) in concepts.enumerated() {
    let light = concept.draw(false)
    let dark = concept.draw(true)
    rendered.append((light, dark))
    write(light, to: output.appendingPathComponent("docicon-\(index + 1)-\(concept.slug)-light-1024.png"))
    write(dark, to: output.appendingPathComponent("docicon-\(index + 1)-\(concept.slug)-dark-1024.png"))
}

let boardW = 2560, boardH = 3600
let board = context(width: boardW, height: boardH)
board.setFillColor(rgb(238, 241, 245))
board.fill(CGRect(x: 0, y: 0, width: CGFloat(boardW), height: CGFloat(boardH)))

label("Glassine — Markdown document icon concepts", at: CGPoint(x: 100, y: 3470),
      size: 62, bold: true, color: rgb(26, 33, 43), in: board)
label("Transparent document sheets · six directions · light and dark at 512, 128, 64 and 32 px",
      at: CGPoint(x: 102, y: 3400), size: 30, color: rgb(94, 104, 118), in: board)

let lightPanelX: CGFloat = 490, darkPanelX: CGFloat = 1480, panelW: CGFloat = 970
let cellOffsets: [(CGFloat, Int)] = [(30, 512), (610, 128), (780, 64), (890, 32)]

label("LIGHT", at: CGPoint(x: lightPanelX + 30, y: 3336), size: 24, bold: true,
      color: rgb(94, 104, 118), in: board)
label("DARK", at: CGPoint(x: darkPanelX + 30, y: 3336), size: 24, bold: true,
      color: rgb(94, 104, 118), in: board)

for (index, concept) in concepts.enumerated() {
    let imageY = CGFloat(2776 - index * 528)
    let centerY = imageY + 256

    rounded(CGRect(x: lightPanelX, y: imageY - 24, width: panelW, height: 560),
            radius: 28, rgb(225, 229, 236), in: board)
    rounded(CGRect(x: darkPanelX, y: imageY - 24, width: panelW, height: 560),
            radius: 28, rgb(24, 28, 34), in: board)

    label("\(index + 1)", at: CGPoint(x: 100, y: centerY + 8), size: 36, bold: true,
          color: rgb(150, 159, 172), in: board)
    label(concept.name, at: CGPoint(x: 148, y: centerY + 8), size: 36, bold: true,
          color: rgb(30, 38, 49), in: board)

    for (panelX, source) in [(lightPanelX, rendered[index].light),
                             (darkPanelX, rendered[index].dark)] {
        for (dx, side) in cellOffsets {
            let scaled = downsample(source, to: side)
            let s = CGFloat(side)
            board.draw(scaled, in: CGRect(x: panelX + dx,
                                          y: centerY - s / 2, width: s, height: s))
        }
    }
}

for panelX in [lightPanelX, darkPanelX] {
    for (dx, side) in cellOffsets {
        let center = panelX + dx + CGFloat(side) / 2
        label("\(side) px", at: CGPoint(x: center - 32, y: 118), size: 26,
              color: rgb(110, 120, 134), in: board)
    }
}

write(board.makeImage()!, to: output.appendingPathComponent("docicon-board.png"))
print("wrote document icon concepts to \(output.path)")
