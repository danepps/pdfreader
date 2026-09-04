// make-icon.swift — generates the Folio app icon artwork as a 1024x1024 PNG.
//
// Usage:
//   swift make-icon.swift <out.png> [--dark] [--full-bleed]
//
//   --dark        Dark appearance: black paper with white text.
//   --full-bleed  Use the full Icon Composer canvas. Without this flag the
//                 artwork uses the legacy 824-in-1024 macOS icon grid.
//
// Pure CoreGraphics + ImageIO so it runs as a plain script with no app bundle.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func pagePath(_ rect: CGRect, fold: CGFloat, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.minX + radius, y: rect.maxY),
                radius: radius)
    path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                tangent2End: CGPoint(x: rect.maxX - radius, y: rect.minY),
                radius: radius)
    path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                tangent2End: CGPoint(x: rect.minX, y: rect.minY + radius),
                radius: radius)
    path.closeSubpath()
    return path
}

func rgb(_ r: Int, _ g: Int, _ b: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255, alpha: alpha)
}

func fill(_ path: CGPath, color: CGColor, in context: CGContext) {
    context.addPath(path)
    context.setFillColor(color)
    context.fillPath()
}

func pill(_ rect: CGRect, color: CGColor, in context: CGContext) {
    fill(CGPath(roundedRect: rect, cornerWidth: rect.height / 2,
                cornerHeight: rect.height / 2, transform: nil),
         color: color, in: context)
}

struct Palette {
    let gradientTop: CGColor
    let gradientBottom: CGColor
    let page: CGColor
    let fold: CGColor
    let line: CGColor
    let pageRim: CGColor?
    let shadowAlpha: CGFloat
}

let lightPalette = Palette(
    gradientTop: rgb(82, 88, 96),       // #525860
    gradientBottom: rgb(34, 39, 45),    // #22272D
    page: rgb(255, 255, 255),
    fold: rgb(213, 220, 230),           // #D5DCE6
    line: rgb(38, 46, 58),              // #262E3A
    pageRim: nil,
    shadowAlpha: 0.42
)

let darkPalette = Palette(
    gradientTop: rgb(35, 41, 49),       // #232931
    gradientBottom: rgb(11, 14, 18),    // #0B0E12
    page: rgb(8, 11, 15),               // #080B0F
    fold: rgb(42, 48, 58),              // #2A303A
    line: rgb(245, 248, 252),           // #F5F8FC
    pageRim: rgb(125, 140, 160),        // #7D8CA0
    shadowAlpha: 0.65
)

var outputPath: String?
var dark = false
var fullBleed = false
for argument in CommandLine.arguments.dropFirst() {
    switch argument {
    case "--dark": dark = true
    case "--full-bleed": fullBleed = true
    default:
        if argument.hasPrefix("--") {
            FileHandle.standardError.write("unknown option \(argument)\n".data(using: .utf8)!)
            exit(2)
        }
        outputPath = argument
    }
}

guard let outputPath else {
    FileHandle.standardError.write(
        "usage: make-icon.swift <output.png> [--dark] [--full-bleed]\n".data(using: .utf8)!
    )
    exit(2)
}

let size: CGFloat = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(data: nil, width: Int(size), height: Int(size),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    FileHandle.standardError.write("failed to create bitmap context\n".data(using: .utf8)!)
    exit(1)
}
context.setAllowsAntialiasing(true)
context.interpolationQuality = .high

let bodyRect = fullBleed
    ? CGRect(x: 0, y: 0, width: size, height: size)
    : CGRect(x: 100, y: 100, width: 824, height: 824)
let scale = bodyRect.width / size
func x(_ value: CGFloat) -> CGFloat { bodyRect.minX + value * scale }
func y(_ value: CGFloat) -> CGFloat { bodyRect.minY + value * scale }
func d(_ value: CGFloat) -> CGFloat { value * scale }

let palette = dark ? darkPalette : lightPalette
let body = CGPath(roundedRect: bodyRect,
                  cornerWidth: d(188), cornerHeight: d(188), transform: nil)

// Graphite tile. Extending both ends is essential: without it the diagonal
// gradient leaves transparent wedges in the top-left and bottom-right corners.
context.saveGState()
context.addPath(body)
context.clip()
let gradient = CGGradient(colorsSpace: colorSpace,
                          colors: [palette.gradientTop, palette.gradientBottom] as CFArray,
                          locations: [0, 1])!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: x(220), y: y(1024)),
    end: CGPoint(x: x(800), y: y(0)),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
context.restoreGState()

if !fullBleed {
    context.addPath(body)
    context.setStrokeColor(rgb(255, 255, 255, 0.10))
    context.setLineWidth(d(5))
    context.strokePath()
}

// Margin tabs are drawn first so they emerge from behind the sheet.
let tabColors = [
    rgb(255, 91, 91),   // coral
    rgb(255, 190, 48),  // amber
    rgb(46, 210, 171),  // mint
    rgb(76, 160, 255)   // blue
]
for (index, color) in tabColors.enumerated() {
    let tab = CGRect(x: x(716), y: y(606 - CGFloat(index) * 104),
                     width: d(126), height: d(62))
    fill(CGPath(roundedRect: tab, cornerWidth: d(18), cornerHeight: d(18), transform: nil),
         color: color, in: context)
}

let pageRect = CGRect(x: x(214), y: y(168), width: d(546), height: d(686))
let fold = d(132)
let page = pagePath(pageRect, fold: fold, radius: d(20))

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: d(-18)), blur: d(34),
                  color: rgb(0, 0, 0, palette.shadowAlpha))
fill(page, color: palette.page, in: context)
context.restoreGState()

if let rim = palette.pageRim {
    context.addPath(page)
    context.setStrokeColor(rim)
    context.setLineWidth(d(4))
    context.strokePath()
}

let flap = CGMutablePath()
flap.move(to: CGPoint(x: pageRect.maxX - fold, y: pageRect.maxY))
flap.addLine(to: CGPoint(x: pageRect.maxX, y: pageRect.maxY - fold))
flap.addLine(to: CGPoint(x: pageRect.maxX - fold, y: pageRect.maxY - fold))
flap.closeSubpath()
fill(flap, color: palette.fold, in: context)

// Equal-width lines make the symbol read cleanly at Dock and Finder sizes.
for lineY in [CGFloat(680), 617, 512, 452, 368] {
    pill(CGRect(x: x(292), y: y(lineY), width: d(380), height: d(26)),
         color: palette.line, in: context)
}

let outputURL = URL(fileURLWithPath: outputPath)
guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL, UTType.png.identifier as CFString, 1, nil
      ) else {
    FileHandle.standardError.write("failed to create image destination\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write("failed to write \(outputURL.path)\n".data(using: .utf8)!)
    exit(1)
}

print("wrote \(outputURL.path)\(dark ? " [dark]" : " [light]")\(fullBleed ? " [full-bleed]" : "")")
