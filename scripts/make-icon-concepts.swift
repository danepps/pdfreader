// make-icon-concepts.swift — exploratory Folio app-icon directions.
//
// Produces three light/dark concept pairs plus a review board. These are
// intentionally separate from the shipping icon pipeline until a direction is
// selected.

// Usage: swift scripts/make-icon-concepts.swift <output-directory>


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

func superellipse(in rect: CGRect, exponent n: CGFloat = 5.6) -> CGPath {
    let path = CGMutablePath()
    let p = 2 / n
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let point = CGPoint(
            x: rect.midX + rect.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), p),
            y: rect.midY + rect.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), p)
        )
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func pagePath(_ rect: CGRect, fold: CGFloat, radius: CGFloat = 20) -> CGPath {
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

func fill(_ path: CGPath, _ color: CGColor, in ctx: CGContext) {
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

func pill(_ rect: CGRect, color: CGColor, in ctx: CGContext) {
    fill(CGPath(roundedRect: rect, cornerWidth: rect.height / 2,
                cornerHeight: rect.height / 2, transform: nil), color, in: ctx)
}

func background(in ctx: CGContext, top: CGColor, bottom: CGColor,
                roundedSquare: Bool = false) {
    let bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    let shape = roundedSquare
        ? CGPath(roundedRect: bounds, cornerWidth: 188, cornerHeight: 188, transform: nil)
        : superellipse(in: bounds)
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: colorSpace,
                              colors: [top, bottom] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 220, y: canvas),
                           end: CGPoint(x: 800, y: 0),
                           options: roundedSquare
                               ? [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                               : [])
    ctx.restoreGState()

    ctx.addPath(shape)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.10))
    ctx.setLineWidth(5)
    ctx.strokePath()
}

func drawPageShadow(_ path: CGPath, fillColor: CGColor, in ctx: CGContext,
                    alpha: CGFloat = 0.38) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 34,
                  color: rgb(0, 0, 0, alpha))
    fill(path, fillColor, in: ctx)
    ctx.restoreGState()
}

func drawFold(rect: CGRect, size: CGFloat, color: CGColor, in ctx: CGContext) {
    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: rect.maxX - size, y: rect.maxY))
    flap.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - size))
    flap.addLine(to: CGPoint(x: rect.maxX - size, y: rect.maxY - size))
    flap.closeSubpath()
    fill(flap, color, in: ctx)
}

enum Concept: String, CaseIterable {
    case invert = "Invert"
    case folio = "Folio Stack"
    case focus = "Focus Band"
}

enum RoundTwoConcept: String, CaseIterable {
    case aperture = "Night Aperture"
    case pageTurn = "Page Turn"
    case openFolio = "Open Folio"
    case marginTabs = "Margin Tabs"
    case portal = "Reader Portal"
    case foldedF = "Folded F"
}

func drawInvert(dark: Bool) -> CGImage {
    let ctx = context(width: 1024, height: 1024)
    background(in: ctx,
               top: dark ? rgb(22, 31, 49) : rgb(49, 87, 151),
               bottom: dark ? rgb(7, 11, 18) : rgb(18, 34, 64))

    let r = CGRect(x: 236, y: 182, width: 552, height: 660)
    let page = pagePath(r, fold: 138)
    drawPageShadow(page, fillColor: rgb(247, 249, 252), in: ctx, alpha: dark ? 0.60 : 0.36)

    ctx.saveGState()
    ctx.addPath(page)
    ctx.clip()
    ctx.setFillColor(dark ? rgb(30, 38, 52) : rgb(35, 45, 60))
    ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 326))
    ctx.saveGState()
    ctx.clip(to: CGRect(x: r.minX, y: 502, width: r.width, height: 12))
    let seam = CGGradient(colorsSpace: colorSpace,
                          colors: [rgb(77, 213, 255), rgb(93, 111, 255)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(seam,
                           start: CGPoint(x: r.minX, y: 508),
                           end: CGPoint(x: r.maxX, y: 508), options: [])
    ctx.restoreGState()
    ctx.restoreGState()

    drawFold(rect: r, size: 138,
             color: dark ? rgb(189, 203, 222) : rgb(199, 210, 225), in: ctx)

    let darkInk = dark ? rgb(64, 76, 94) : rgb(65, 78, 98)
    let lightInk = dark ? rgb(215, 224, 237) : rgb(223, 231, 241)
    pill(CGRect(x: 310, y: 672, width: 350, height: 29), color: darkInk, in: ctx)
    pill(CGRect(x: 310, y: 608, width: 404, height: 29), color: darkInk, in: ctx)
    pill(CGRect(x: 310, y: 420, width: 404, height: 29), color: lightInk, in: ctx)
    pill(CGRect(x: 310, y: 356, width: 276, height: 29), color: lightInk, in: ctx)
    return ctx.makeImage()!
}

func drawFolio(dark: Bool) -> CGImage {
    let ctx = context(width: 1024, height: 1024)
    background(in: ctx,
               top: dark ? rgb(20, 45, 45) : rgb(34, 110, 107),
               bottom: dark ? rgb(7, 18, 20) : rgb(9, 49, 56))

    let backRect = CGRect(x: 318, y: 236, width: 486, height: 590)
    let back = pagePath(backRect, fold: 118)
    drawPageShadow(back, fillColor: dark ? rgb(25, 163, 157) : rgb(59, 221, 204),
                   in: ctx, alpha: 0.42)
    drawFold(rect: backRect, size: 118,
             color: dark ? rgb(31, 113, 114) : rgb(30, 151, 150), in: ctx)

    let frontRect = CGRect(x: 218, y: 180, width: 500, height: 620)
    let front = pagePath(frontRect, fold: 126)
    drawPageShadow(front, fillColor: dark ? rgb(42, 51, 58) : rgb(249, 250, 247),
                   in: ctx, alpha: dark ? 0.58 : 0.38)
    if dark {
        ctx.addPath(front)
        ctx.setStrokeColor(rgb(116, 139, 144))
        ctx.setLineWidth(4)
        ctx.strokePath()
    }
    drawFold(rect: frontRect, size: 126,
             color: dark ? rgb(78, 97, 103) : rgb(202, 217, 215), in: ctx)

    let ink = dark ? rgb(201, 216, 218) : rgb(87, 105, 108)
    pill(CGRect(x: 286, y: 622, width: 318, height: 28), color: ink, in: ctx)
    pill(CGRect(x: 286, y: 555, width: 364, height: 28), color: ink, in: ctx)
    pill(CGRect(x: 286, y: 488, width: 292, height: 28), color: ink, in: ctx)
    pill(CGRect(x: 278, y: 397, width: 328, height: 62),
         color: dark ? rgb(25, 174, 161, 0.34) : rgb(55, 213, 191, 0.35), in: ctx)
    pill(CGRect(x: 302, y: 414, width: 246, height: 28),
         color: dark ? rgb(125, 244, 222) : rgb(13, 105, 99), in: ctx)
    return ctx.makeImage()!
}

func drawFocus(dark: Bool) -> CGImage {
    let ctx = context(width: 1024, height: 1024)
    background(in: ctx,
               top: dark ? rgb(44, 29, 47) : rgb(112, 63, 117),
               bottom: dark ? rgb(17, 12, 23) : rgb(48, 26, 63))

    let r = CGRect(x: 226, y: 180, width: 572, height: 664)
    let page = pagePath(r, fold: 138)
    let paper = dark ? rgb(53, 48, 61) : rgb(252, 248, 245)
    drawPageShadow(page, fillColor: paper, in: ctx, alpha: dark ? 0.60 : 0.40)
    if dark {
        ctx.addPath(page)
        ctx.setStrokeColor(rgb(125, 109, 136))
        ctx.setLineWidth(4)
        ctx.strokePath()
    }
    drawFold(rect: r, size: 138,
             color: dark ? rgb(93, 79, 103) : rgb(220, 207, 220), in: ctx)

    let faint = dark ? rgb(158, 147, 168) : rgb(167, 153, 164)
    pill(CGRect(x: 304, y: 665, width: 330, height: 25), color: faint, in: ctx)
    pill(CGRect(x: 304, y: 613, width: 410, height: 25), color: faint, in: ctx)

    let bandRect = CGRect(x: 258, y: 345, width: 508, height: 220)
    fill(CGPath(roundedRect: bandRect, cornerWidth: 36, cornerHeight: 36, transform: nil),
         dark ? rgb(22, 17, 29) : rgb(47, 31, 60), in: ctx)
    pill(CGRect(x: 312, y: 482, width: 366, height: 27), color: rgb(221, 210, 226), in: ctx)
    pill(CGRect(x: 312, y: 425, width: 292, height: 27), color: rgb(246, 184, 67), in: ctx)
    pill(CGRect(x: 304, y: 408, width: 326, height: 61), color: rgb(246, 184, 67, 0.16), in: ctx)
    return ctx.makeImage()!
}

func image(for concept: Concept, dark: Bool) -> CGImage {
    switch concept {
    case .invert: return drawInvert(dark: dark)
    case .folio: return drawFolio(dark: dark)
    case .focus: return drawFocus(dark: dark)
    }
}

func documentColors(dark: Bool) -> (paper: CGColor, ink: CGColor, fold: CGColor, rim: CGColor?) {
    dark
        ? (rgb(8, 11, 15), rgb(245, 248, 252), rgb(42, 48, 58), rgb(125, 140, 160))
        : (rgb(255, 255, 255), rgb(38, 46, 58), rgb(213, 220, 230), nil)
}

func drawDocument(_ rect: CGRect, fold: CGFloat, dark: Bool, in ctx: CGContext,
                  shadow: CGFloat = 0.42) -> CGPath {
    let colors = documentColors(dark: dark)
    let page = pagePath(rect, fold: fold)
    drawPageShadow(page, fillColor: colors.paper, in: ctx, alpha: dark ? 0.65 : shadow)
    if let rim = colors.rim {
        ctx.addPath(page)
        ctx.setStrokeColor(rim)
        ctx.setLineWidth(4)
        ctx.strokePath()
    }
    drawFold(rect: rect, size: fold, color: colors.fold, in: ctx)
    return page
}

func drawAperture(dark: Bool) -> CGImage {
    let ctx = context(width: 1024, height: 1024)
    background(in: ctx,
               top: dark ? rgb(11, 24, 47) : rgb(38, 105, 204),
               bottom: dark ? rgb(3, 7, 15) : rgb(11, 39, 91))
    let colors = documentColors(dark: dark)
    let r = CGRect(x: 224, y: 170, width: 576, height: 682)
    _ = drawDocument(r, fold: 134, dark: dark, in: ctx)

    pill(CGRect(x: 306, y: 685, width: 306, height: 25), color: colors.ink, in: ctx)
    pill(CGRect(x: 306, y: 630, width: 390, height: 25), color: colors.ink, in: ctx)

    let center = CGPoint(x: 520, y: 424)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 28, color: rgb(62, 205, 255, 0.50))
    ctx.setFillColor(dark ? rgb(5, 8, 14) : rgb(17, 28, 48))
    ctx.fillEllipse(in: CGRect(x: center.x - 174, y: center.y - 174, width: 348, height: 348))
    ctx.restoreGState()
    ctx.setStrokeColor(rgb(79, 213, 255))
    ctx.setLineWidth(18)
    ctx.strokeEllipse(in: CGRect(x: center.x - 174, y: center.y - 174, width: 348, height: 348))
    pill(CGRect(x: 400, y: 468, width: 242, height: 27), color: rgb(246, 250, 255), in: ctx)
    pill(CGRect(x: 400, y: 411, width: 206, height: 27), color: rgb(246, 250, 255), in: ctx)
    pill(CGRect(x: 400, y: 354, width: 150, height: 27), color: rgb(102, 226, 255), in: ctx)
    return ctx.makeImage()!
}

func transformed(_ path: CGPath, around center: CGPoint, angle: CGFloat) -> CGPath {
    var transform = CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: angle)
        .translatedBy(x: -center.x, y: -center.y)
    return path.copy(using: &transform)!
}

func drawPageTurn(dark: Bool) -> CGImage {
    let ctx = context(width: 1024, height: 1024)
    background(in: ctx,
               top: dark ? rgb(55, 20, 18) : rgb(226, 82, 43),
               bottom: dark ? rgb(18, 7, 8) : rgb(112, 23, 38))
    let colors = documentColors(dark: dark)

    let baseRect = CGRect(x: 270, y: 190, width: 484, height: 640)
    for (offset, angle, alpha) in [(CGSize(width: -58, height: 8), CGFloat(0.13), CGFloat(0.34)),
                                   (CGSize(width: 52, height: 4), CGFloat(-0.11), CGFloat(0.55))] {
        let r = baseRect.offsetBy(dx: offset.width, dy: offset.height)
        let path = transformed(pagePath(r, fold: 116), around: CGPoint(x: r.midX, y: r.midY), angle: angle)
        drawPageShadow(path,
                       fillColor: dark ? rgb(19, 22, 27, alpha + 0.35) : rgb(255, 203, 156, alpha + 0.25),
                       in: ctx, alpha: 0.28)
    }

    let front = pagePath(baseRect, fold: 122)
    drawPageShadow(front, fillColor: colors.paper, in: ctx, alpha: dark ? 0.66 : 0.44)
    if let rim = colors.rim {
        ctx.addPath(front); ctx.setStrokeColor(rim); ctx.setLineWidth(4); ctx.strokePath()
    }
    drawFold(rect: baseRect, size: 122, color: rgb(255, 113, 68), in: ctx)
    pill(CGRect(x: 338, y: 660, width: 260, height: 27), color: colors.ink, in: ctx)
    pill(CGRect(x: 338, y: 600, width: 348, height: 27), color: colors.ink, in: ctx)
    pill(CGRect(x: 338, y: 540, width: 306, height: 27), color: colors.ink, in: ctx)

    // A large turned corner doubles as a forward arrow.
    let turn = CGMutablePath()
    turn.move(to: CGPoint(x: 520, y: 190))
    turn.addCurve(to: CGPoint(x: 754, y: 414),
                  control1: CGPoint(x: 688, y: 206), control2: CGPoint(x: 746, y: 302))
    turn.addLine(to: CGPoint(x: 754, y: 190))
    turn.closeSubpath()
    fill(turn, dark ? rgb(255, 99, 63) : rgb(255, 124, 74), in: ctx)
    return ctx.makeImage()!
}

func drawOpenFolio(dark: Bool) -> CGImage {
    let ctx = context(width: 1024, height: 1024)
    background(in: ctx,
               top: dark ? rgb(10, 40, 30) : rgb(38, 145, 93),
               bottom: dark ? rgb(3, 14, 11) : rgb(9, 66, 49))
    let colors = documentColors(dark: dark)

    let left = CGMutablePath()
    left.move(to: CGPoint(x: 176, y: 716))
    left.addCurve(to: CGPoint(x: 500, y: 660), control1: CGPoint(x: 300, y: 752), control2: CGPoint(x: 432, y: 722))
    left.addLine(to: CGPoint(x: 500, y: 244))
    left.addCurve(to: CGPoint(x: 176, y: 302), control1: CGPoint(x: 420, y: 306), control2: CGPoint(x: 306, y: 272))
    left.closeSubpath()
    let right = CGMutablePath()
    right.move(to: CGPoint(x: 848, y: 716))
    right.addCurve(to: CGPoint(x: 524, y: 660), control1: CGPoint(x: 724, y: 752), control2: CGPoint(x: 592, y: 722))
    right.addLine(to: CGPoint(x: 524, y: 244))
    right.addCurve(to: CGPoint(x: 848, y: 302), control1: CGPoint(x: 604, y: 306), control2: CGPoint(x: 718, y: 272))
    right.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 34, color: rgb(0, 0, 0, dark ? 0.68 : 0.42))
    fill(left, colors.paper, in: ctx); fill(right, colors.paper, in: ctx)
    ctx.restoreGState()
    if let rim = colors.rim {
        for page in [left, right] { ctx.addPath(page); ctx.setStrokeColor(rim); ctx.setLineWidth(4); ctx.strokePath() }
    }
    ctx.setStrokeColor(dark ? rgb(91, 106, 101) : rgb(196, 208, 202))
    ctx.setLineWidth(10)
    ctx.move(to: CGPoint(x: 512, y: 250)); ctx.addLine(to: CGPoint(x: 512, y: 662)); ctx.strokePath()
    for y in [580, 510, 440] {
        pill(CGRect(x: 238, y: CGFloat(y), width: 196, height: 24), color: colors.ink, in: ctx)
        pill(CGRect(x: 588, y: CGFloat(y), width: y == 440 ? 146 : 198, height: 24), color: colors.ink, in: ctx)
    }
    // Bookmark at the spine gives the open-book silhouette a memorable accent.
    let ribbon = CGMutablePath()
    ribbon.move(to: CGPoint(x: 487, y: 666)); ribbon.addLine(to: CGPoint(x: 537, y: 666))
    ribbon.addLine(to: CGPoint(x: 537, y: 758)); ribbon.addLine(to: CGPoint(x: 512, y: 731))
    ribbon.addLine(to: CGPoint(x: 487, y: 758)); ribbon.closeSubpath()
    fill(ribbon, rgb(255, 199, 56), in: ctx)
    return ctx.makeImage()!
}

func drawMarginTabs(dark: Bool,
                    lightTop: CGColor? = nil, lightBottom: CGColor? = nil,
                    darkTop: CGColor? = nil, darkBottom: CGColor? = nil,
                    showHighlight: Bool = true,
                    roundedBackground: Bool = false,
                    uniformLineWidths: Bool = false) -> CGImage {
    let ctx = context(width: 1024, height: 1024)
    background(in: ctx,
               top: dark ? (darkTop ?? rgb(39, 31, 16)) : (lightTop ?? rgb(185, 126, 29)),
               bottom: dark ? (darkBottom ?? rgb(14, 10, 5)) : (lightBottom ?? rgb(87, 48, 8)),
               roundedSquare: roundedBackground)
    let colors = documentColors(dark: dark)
    let r = CGRect(x: 214, y: 168, width: 546, height: 686)
    let tabColors = [rgb(255, 91, 91), rgb(255, 190, 48), rgb(46, 210, 171), rgb(76, 160, 255)]
    for (i, color) in tabColors.enumerated() {
        let y = 606 - CGFloat(i) * 104
        let tab = CGPath(roundedRect: CGRect(x: 716, y: y, width: 126, height: 62),
                         cornerWidth: 18, cornerHeight: 18, transform: nil)
        fill(tab, color, in: ctx)
    }
    _ = drawDocument(r, fold: 132, dark: dark, in: ctx)
    let topWidths: [CGFloat] = uniformLineWidths ? [380, 380, 380] : [282, 380, 344]
    for (y, width) in zip([CGFloat(680), 617, 512], topWidths) {
        pill(CGRect(x: 292, y: y, width: width, height: 26), color: colors.ink, in: ctx)
    }
    if showHighlight {
        // Match Folio's in-app find treatment. Dark appearance is deliberately
        // shifted a little cooler than the raw filtered sample: beside the yellow
        // margin tab, the mathematically pure green reads perceptually olive.
        pill(CGRect(x: 278, y: 434, width: 410, height: 64),
             color: dark ? rgb(7, 78, 38) : rgb(40, 205, 65, 0.35), in: ctx)
        pill(CGRect(x: 304, y: 452, width: 302, height: 27),
             color: dark ? rgb(143, 232, 177) : colors.ink, in: ctx)
    } else {
        pill(CGRect(x: 292, y: 452, width: uniformLineWidths ? 380 : 310, height: 26),
             color: colors.ink, in: ctx)
    }
    pill(CGRect(x: 292, y: 368, width: uniformLineWidths ? 380 : 310, height: 26),
         color: colors.ink, in: ctx)
    return ctx.makeImage()!
}

func drawPortal(dark: Bool) -> CGImage {
    let ctx = context(width: 1024, height: 1024)
    background(in: ctx,
               top: dark ? rgb(32, 16, 43) : rgb(117, 48, 170),
               bottom: dark ? rgb(8, 5, 14) : rgb(42, 18, 83))
    let colors = documentColors(dark: dark)

    let ringRect = CGRect(x: 172, y: 172, width: 680, height: 680)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 34, color: rgb(217, 108, 255, 0.60))
    ctx.setStrokeColor(rgb(215, 111, 255))
    ctx.setLineWidth(64)
    ctx.strokeEllipse(in: ringRect)
    ctx.restoreGState()

    let r = CGRect(x: 286, y: 188, width: 452, height: 646)
    _ = drawDocument(r, fold: 114, dark: dark, in: ctx)
    pill(CGRect(x: 344, y: 650, width: 252, height: 26), color: colors.ink, in: ctx)
    pill(CGRect(x: 344, y: 588, width: 328, height: 26), color: colors.ink, in: ctx)
    pill(CGRect(x: 344, y: 526, width: 286, height: 26), color: colors.ink, in: ctx)

    // Redraw the near arc so the sheet appears to pass through the portal.
    let nearArc = CGMutablePath()
    nearArc.addArc(center: CGPoint(x: 512, y: 512), radius: 340,
                   startAngle: .pi * 1.08, endAngle: .pi * 1.92, clockwise: false)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 26, color: rgb(217, 108, 255, 0.55))
    ctx.addPath(nearArc); ctx.setStrokeColor(rgb(238, 141, 255)); ctx.setLineWidth(64); ctx.strokePath()
    ctx.restoreGState()
    return ctx.makeImage()!
}

func drawFoldedF(dark: Bool) -> CGImage {
    let ctx = context(width: 1024, height: 1024)
    background(in: ctx,
               top: dark ? rgb(18, 25, 40) : rgb(42, 88, 193),
               bottom: dark ? rgb(4, 7, 12) : rgb(14, 31, 90))

    let mark = CGMutablePath()
    mark.move(to: CGPoint(x: 300, y: 210))
    mark.addLine(to: CGPoint(x: 300, y: 790))
    mark.addArc(tangent1End: CGPoint(x: 300, y: 820), tangent2End: CGPoint(x: 330, y: 820), radius: 30)
    mark.addLine(to: CGPoint(x: 748, y: 820))
    mark.addLine(to: CGPoint(x: 650, y: 690))
    mark.addLine(to: CGPoint(x: 452, y: 690))
    mark.addLine(to: CGPoint(x: 452, y: 570))
    mark.addLine(to: CGPoint(x: 674, y: 570))
    mark.addLine(to: CGPoint(x: 674, y: 438))
    mark.addLine(to: CGPoint(x: 452, y: 438))
    mark.addLine(to: CGPoint(x: 452, y: 210))
    mark.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 34, color: rgb(0, 0, 0, 0.46))
    fill(mark, dark ? rgb(250, 252, 255) : rgb(255, 255, 255), in: ctx)
    ctx.restoreGState()

    // The clipped top-right corner turns the monogram into a folded sheet.
    let fold = CGMutablePath()
    fold.move(to: CGPoint(x: 650, y: 690))
    fold.addLine(to: CGPoint(x: 748, y: 820))
    fold.addLine(to: CGPoint(x: 650, y: 820))
    fold.closeSubpath()
    fill(fold, dark ? rgb(88, 205, 255) : rgb(94, 214, 255), in: ctx)
    let notch = CGMutablePath()
    notch.move(to: CGPoint(x: 452, y: 438)); notch.addLine(to: CGPoint(x: 674, y: 438))
    notch.addLine(to: CGPoint(x: 624, y: 488)); notch.addLine(to: CGPoint(x: 452, y: 488)); notch.closeSubpath()
    fill(notch, dark ? rgb(205, 236, 255) : rgb(208, 238, 255), in: ctx)
    return ctx.makeImage()!
}

func image(for concept: RoundTwoConcept, dark: Bool) -> CGImage {
    switch concept {
    case .aperture: return drawAperture(dark: dark)
    case .pageTurn: return drawPageTurn(dark: dark)
    case .openFolio: return drawOpenFolio(dark: dark)
    case .marginTabs: return drawMarginTabs(dark: dark)
    case .portal: return drawPortal(dark: dark)
    case .foldedF: return drawFoldedF(dark: dark)
    }
}

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}

func label(_ text: String, at point: CGPoint, size: CGFloat,
           color: CGColor, in ctx: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String):
            CTFontCreateWithName("SF Pro Display" as CFString, size, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    ctx.textPosition = point
    CTLineDraw(line, ctx)
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift scripts/make-icon-concepts.swift <output-directory>\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

var images: [String: CGImage] = [:]
for concept in Concept.allCases {
    for dark in [false, true] {
        let rendered = image(for: concept, dark: dark)
        let suffix = dark ? "dark" : "light"
        let key = "\(concept.rawValue)-\(suffix)"
        images[key] = rendered
        write(rendered, to: output.appendingPathComponent("folio-concept-\(concept.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))-\(suffix).png"))
    }
}

// A single sheet for evaluating visual character and 32/64 px legibility.
let board = context(width: 2400, height: 1680)
board.setFillColor(rgb(236, 239, 243))
board.fill(CGRect(x: 0, y: 0, width: 2400, height: 1680))
label("Folio — app icon directions", at: CGPoint(x: 120, y: 1570),
      size: 54, color: rgb(28, 35, 45), in: board)
label("Light and dark appearance studies · with 64 px and 32 px checks", at: CGPoint(x: 122, y: 1512),
      size: 28, color: rgb(91, 101, 114), in: board)

let columns: [CGFloat] = [120, 900, 1680]
for (index, concept) in Concept.allCases.enumerated() {
    let x = columns[index]
    label("\(index + 1)  \(concept.rawValue)", at: CGPoint(x: x, y: 1425),
          size: 36, color: rgb(32, 40, 51), in: board)
    let light = images["\(concept.rawValue)-light"]!
    let dark = images["\(concept.rawValue)-dark"]!
    board.draw(light, in: CGRect(x: x, y: 770, width: 560, height: 560))
    board.draw(dark, in: CGRect(x: x, y: 170, width: 560, height: 560))
    label("LIGHT", at: CGPoint(x: x + 590, y: 1256), size: 19,
          color: rgb(91, 101, 114), in: board)
    label("DARK", at: CGPoint(x: x + 590, y: 656), size: 19,
          color: rgb(91, 101, 114), in: board)
    board.draw(light, in: CGRect(x: x + 590, y: 1150, width: 64, height: 64))
    board.draw(light, in: CGRect(x: x + 606, y: 1092, width: 32, height: 32))
    board.draw(dark, in: CGRect(x: x + 590, y: 550, width: 64, height: 64))
    board.draw(dark, in: CGRect(x: x + 606, y: 492, width: 32, height: 32))
}

write(board.makeImage()!, to: output.appendingPathComponent("folio-icon-concepts-board.png"))

var roundTwoImages: [String: CGImage] = [:]
for concept in RoundTwoConcept.allCases {
    for dark in [false, true] {
        let rendered = image(for: concept, dark: dark)
        let suffix = dark ? "dark" : "light"
        let key = "\(concept.rawValue)-\(suffix)"
        roundTwoImages[key] = rendered
        let stem = concept.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
        write(rendered, to: output.appendingPathComponent("folio-concept-v2-\(stem)-\(suffix).png"))
    }
}

let boardTwo = context(width: 3000, height: 2280)
boardTwo.setFillColor(rgb(236, 239, 243))
boardTwo.fill(CGRect(x: 0, y: 0, width: 3000, height: 2280))
label("Folio — expanded icon directions", at: CGPoint(x: 120, y: 2170),
      size: 58, color: rgb(28, 35, 45), in: boardTwo)
label("White paper in light appearance · black paper with white type in dark appearance", at: CGPoint(x: 122, y: 2106),
      size: 29, color: rgb(91, 101, 114), in: boardTwo)

for (index, concept) in RoundTwoConcept.allCases.enumerated() {
    let column = index % 3
    let row = index / 3
    let x = CGFloat(column) * 960 + 100
    let y = row == 0 ? CGFloat(1120) : CGFloat(120)
    let titleY = y + 820
    label("\(index + 1)  \(concept.rawValue)", at: CGPoint(x: x, y: titleY),
          size: 38, color: rgb(32, 40, 51), in: boardTwo)
    label("LIGHT", at: CGPoint(x: x, y: y + 760), size: 18,
          color: rgb(91, 101, 114), in: boardTwo)
    label("DARK", at: CGPoint(x: x + 430, y: y + 760), size: 18,
          color: rgb(91, 101, 114), in: boardTwo)
    let light = roundTwoImages["\(concept.rawValue)-light"]!
    let dark = roundTwoImages["\(concept.rawValue)-dark"]!
    boardTwo.draw(light, in: CGRect(x: x, y: y + 280, width: 410, height: 410))
    boardTwo.draw(dark, in: CGRect(x: x + 430, y: y + 280, width: 410, height: 410))
    label("64", at: CGPoint(x: x + 4, y: y + 210), size: 16,
          color: rgb(116, 125, 137), in: boardTwo)
    label("32", at: CGPoint(x: x + 98, y: y + 210), size: 16,
          color: rgb(116, 125, 137), in: boardTwo)
    boardTwo.draw(light, in: CGRect(x: x, y: y + 120, width: 64, height: 64))
    boardTwo.draw(light, in: CGRect(x: x + 96, y: y + 136, width: 32, height: 32))
    boardTwo.draw(dark, in: CGRect(x: x + 430, y: y + 120, width: 64, height: 64))
    boardTwo.draw(dark, in: CGRect(x: x + 526, y: y + 136, width: 32, height: 32))
}

write(boardTwo.makeImage()!, to: output.appendingPathComponent("folio-icon-concepts-v2-board.png"))

struct BackgroundOption {
    let name: String
    let slug: String
    let top: CGColor
    let bottom: CGColor
    let hex: String
}

let marginBackgrounds: [BackgroundOption] = [
    BackgroundOption(name: "Ink Blue", slug: "ink-blue",
                     top: rgb(64, 100, 135), bottom: rgb(22, 49, 73),
                     hex: "#406487 → #163149"),
    BackgroundOption(name: "Blue Slate", slug: "blue-slate",
                     top: rgb(92, 108, 124), bottom: rgb(40, 51, 64),
                     hex: "#5C6C7C → #283340"),
    BackgroundOption(name: "Graphite", slug: "graphite",
                     top: rgb(82, 88, 96), bottom: rgb(34, 39, 45),
                     hex: "#525860 → #22272D"),
    BackgroundOption(name: "Quiet Indigo", slug: "quiet-indigo",
                     top: rgb(79, 91, 157), bottom: rgb(37, 43, 91),
                     hex: "#4F5B9D → #252B5B"),
    BackgroundOption(name: "Aubergine", slug: "aubergine",
                     top: rgb(111, 75, 108), bottom: rgb(57, 34, 57),
                     hex: "#6F4B6C → #392239"),
    BackgroundOption(name: "Brick", slug: "brick",
                     top: rgb(163, 77, 62), bottom: rgb(91, 37, 34),
                     hex: "#A34D3E → #5B2522"),
    BackgroundOption(name: "Forest", slug: "forest",
                     top: rgb(70, 112, 87), bottom: rgb(32, 61, 45),
                     hex: "#467057 → #203D2D"),
    BackgroundOption(name: "Soft Stone", slug: "soft-stone",
                     top: rgb(119, 111, 99), bottom: rgb(68, 61, 53),
                     hex: "#776F63 → #443D35")
]

var marginPaletteImages: [CGImage] = []
for option in marginBackgrounds {
    let rendered = drawMarginTabs(dark: false, lightTop: option.top, lightBottom: option.bottom)
    marginPaletteImages.append(rendered)
    write(rendered, to: output.appendingPathComponent("folio-margin-tabs-bg-\(option.slug).png"))
}

let paletteBoard = context(width: 3000, height: 1800)
paletteBoard.setFillColor(rgb(236, 239, 243))
paletteBoard.fill(CGRect(x: 0, y: 0, width: 3000, height: 1800))
label("Margin Tabs — light background studies", at: CGPoint(x: 110, y: 1695),
      size: 56, color: rgb(28, 35, 45), in: paletteBoard)
label("Document, typography, tabs, lighting, and geometry held constant", at: CGPoint(x: 112, y: 1635),
      size: 28, color: rgb(91, 101, 114), in: paletteBoard)

for index in marginBackgrounds.indices {
    let column = index % 4
    let row = index / 4
    let x = CGFloat(column) * 735 + 90
    let y = row == 0 ? CGFloat(830) : CGFloat(70)
    let option = marginBackgrounds[index]
    let rendered = marginPaletteImages[index]
    label("\(index + 1)  \(option.name)", at: CGPoint(x: x, y: y + 650),
          size: 34, color: rgb(32, 40, 51), in: paletteBoard)
    label(option.hex, at: CGPoint(x: x, y: y + 608),
          size: 20, color: rgb(105, 114, 126), in: paletteBoard)
    paletteBoard.draw(rendered, in: CGRect(x: x, y: y + 70, width: 500, height: 500))
    paletteBoard.draw(rendered, in: CGRect(x: x + 525, y: y + 405, width: 64, height: 64))
    paletteBoard.draw(rendered, in: CGRect(x: x + 541, y: y + 340, width: 32, height: 32))
}

write(paletteBoard.makeImage()!, to: output.appendingPathComponent("folio-margin-tabs-light-backgrounds.png"))

let selectedLight = drawMarginTabs(
    dark: false,
    lightTop: rgb(82, 88, 96), lightBottom: rgb(34, 39, 45)
)
let selectedDark = drawMarginTabs(
    dark: true,
    darkTop: rgb(35, 41, 49), darkBottom: rgb(11, 14, 18)
)
write(selectedLight, to: output.appendingPathComponent("folio-margin-tabs-selected-light.png"))
write(selectedDark, to: output.appendingPathComponent("folio-margin-tabs-selected-dark.png"))

let selectedBoard = context(width: 1900, height: 1160)
selectedBoard.setFillColor(rgb(236, 239, 243))
selectedBoard.fill(CGRect(x: 0, y: 0, width: 1900, height: 1160))
label("Margin Tabs — selected graphite pair", at: CGPoint(x: 110, y: 1050),
      size: 54, color: rgb(28, 35, 45), in: selectedBoard)
label("Candidate artwork · shipping assets unchanged", at: CGPoint(x: 112, y: 992),
      size: 27, color: rgb(91, 101, 114), in: selectedBoard)
label("LIGHT · GRAPHITE", at: CGPoint(x: 110, y: 900), size: 22,
      color: rgb(91, 101, 114), in: selectedBoard)
label("DARK · NEUTRAL BLACK", at: CGPoint(x: 960, y: 900), size: 22,
      color: rgb(91, 101, 114), in: selectedBoard)
selectedBoard.draw(selectedLight, in: CGRect(x: 110, y: 190, width: 680, height: 680))
selectedBoard.draw(selectedDark, in: CGRect(x: 960, y: 190, width: 680, height: 680))
selectedBoard.draw(selectedLight, in: CGRect(x: 810, y: 520, width: 64, height: 64))
selectedBoard.draw(selectedLight, in: CGRect(x: 826, y: 452, width: 32, height: 32))
selectedBoard.draw(selectedDark, in: CGRect(x: 1660, y: 520, width: 64, height: 64))
selectedBoard.draw(selectedDark, in: CGRect(x: 1676, y: 452, width: 32, height: 32))
write(selectedBoard.makeImage()!, to: output.appendingPathComponent("folio-margin-tabs-selected-pair.png"))

struct ShapeVariant {
    let name: String
    let slug: String
    let showHighlight: Bool
    let roundedBackground: Bool
}

let shapeVariants = [
    ShapeVariant(name: "Clean Page", slug: "clean-page",
                 showHighlight: false, roundedBackground: false),
    ShapeVariant(name: "Four Corners", slug: "four-corners",
                 showHighlight: true, roundedBackground: true),
    ShapeVariant(name: "Clean + Rounded", slug: "clean-rounded",
                 showHighlight: false, roundedBackground: true)
]

var variantPairs: [(light: CGImage, dark: CGImage)] = []
for variant in shapeVariants {
    let light = drawMarginTabs(
        dark: false,
        lightTop: rgb(82, 88, 96), lightBottom: rgb(34, 39, 45),
        showHighlight: variant.showHighlight,
        roundedBackground: variant.roundedBackground
    )
    let dark = drawMarginTabs(
        dark: true,
        darkTop: rgb(35, 41, 49), darkBottom: rgb(11, 14, 18),
        showHighlight: variant.showHighlight,
        roundedBackground: variant.roundedBackground
    )
    variantPairs.append((light, dark))
    write(light, to: output.appendingPathComponent("folio-margin-tabs-\(variant.slug)-light.png"))
    write(dark, to: output.appendingPathComponent("folio-margin-tabs-\(variant.slug)-dark.png"))
}

let shapeBoard = context(width: 3000, height: 1260)
shapeBoard.setFillColor(rgb(236, 239, 243))
shapeBoard.fill(CGRect(x: 0, y: 0, width: 3000, height: 1260))
label("Margin Tabs — highlight and frame studies", at: CGPoint(x: 110, y: 1150),
      size: 56, color: rgb(28, 35, 45), in: shapeBoard)
label("Light and dark pairs · graphite palette and document geometry held constant", at: CGPoint(x: 112, y: 1090),
      size: 28, color: rgb(91, 101, 114), in: shapeBoard)

for index in shapeVariants.indices {
    let x = CGFloat(index) * 960 + 90
    let variant = shapeVariants[index]
    let pair = variantPairs[index]
    label("\(index + 1)  \(variant.name)", at: CGPoint(x: x, y: 995),
          size: 38, color: rgb(32, 40, 51), in: shapeBoard)
    label("LIGHT", at: CGPoint(x: x, y: 938), size: 18,
          color: rgb(91, 101, 114), in: shapeBoard)
    label("DARK", at: CGPoint(x: x + 430, y: 938), size: 18,
          color: rgb(91, 101, 114), in: shapeBoard)
    shapeBoard.draw(pair.light, in: CGRect(x: x, y: 400, width: 410, height: 410))
    shapeBoard.draw(pair.dark, in: CGRect(x: x + 430, y: 400, width: 410, height: 410))
    shapeBoard.draw(pair.light, in: CGRect(x: x, y: 270, width: 64, height: 64))
    shapeBoard.draw(pair.light, in: CGRect(x: x + 92, y: 286, width: 32, height: 32))
    shapeBoard.draw(pair.dark, in: CGRect(x: x + 430, y: 270, width: 64, height: 64))
    shapeBoard.draw(pair.dark, in: CGRect(x: x + 522, y: 286, width: 32, height: 32))
}

write(shapeBoard.makeImage()!, to: output.appendingPathComponent("folio-margin-tabs-shape-variants.png"))

let equalLinesLight = drawMarginTabs(
    dark: false,
    lightTop: rgb(82, 88, 96), lightBottom: rgb(34, 39, 45),
    showHighlight: false, roundedBackground: true, uniformLineWidths: true
)
let equalLinesDark = drawMarginTabs(
    dark: true,
    darkTop: rgb(35, 41, 49), darkBottom: rgb(11, 14, 18),
    showHighlight: false, roundedBackground: true, uniformLineWidths: true
)
write(equalLinesLight, to: output.appendingPathComponent("folio-margin-tabs-clean-rounded-equal-lines-light.png"))
write(equalLinesDark, to: output.appendingPathComponent("folio-margin-tabs-clean-rounded-equal-lines-dark.png"))

let equalLinesBoard = context(width: 1900, height: 1160)
equalLinesBoard.setFillColor(rgb(236, 239, 243))
equalLinesBoard.fill(CGRect(x: 0, y: 0, width: 1900, height: 1160))
label("Margin Tabs — clean, rounded, equal lines", at: CGPoint(x: 110, y: 1050),
      size: 54, color: rgb(28, 35, 45), in: equalLinesBoard)
label("Option 3 refinement · line spacing and all other geometry unchanged", at: CGPoint(x: 112, y: 992),
      size: 27, color: rgb(91, 101, 114), in: equalLinesBoard)
label("LIGHT", at: CGPoint(x: 110, y: 900), size: 22,
      color: rgb(91, 101, 114), in: equalLinesBoard)
label("DARK", at: CGPoint(x: 960, y: 900), size: 22,
      color: rgb(91, 101, 114), in: equalLinesBoard)
equalLinesBoard.draw(equalLinesLight, in: CGRect(x: 110, y: 190, width: 680, height: 680))
equalLinesBoard.draw(equalLinesDark, in: CGRect(x: 960, y: 190, width: 680, height: 680))
equalLinesBoard.draw(equalLinesLight, in: CGRect(x: 810, y: 520, width: 64, height: 64))
equalLinesBoard.draw(equalLinesLight, in: CGRect(x: 826, y: 452, width: 32, height: 32))
equalLinesBoard.draw(equalLinesDark, in: CGRect(x: 1660, y: 520, width: 64, height: 64))
equalLinesBoard.draw(equalLinesDark, in: CGRect(x: 1676, y: 452, width: 32, height: 32))
write(equalLinesBoard.makeImage()!, to: output.appendingPathComponent("folio-margin-tabs-clean-rounded-equal-lines-pair.png"))
print("wrote concepts to \(output.path)")
