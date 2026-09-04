import PDFKit

/// Global render switch consulted by every page at draw time. Set from the view
/// layer whenever the effective appearance or the invert preference changes.
enum PageRendering {
    /// Fill value used for the inversion. Black ink becomes this gray and white
    /// paper becomes (1 - this), so 0.92 gives ~#ebebeb text on ~#141414 paper.
    static let inkLevel: CGFloat = 0.92
    nonisolated(unsafe) static var invert = false
}

/// PDFPage subclass that can render itself light-on-dark. PDFKit instantiates
/// this class for every page because `FolioDocument.classForPage()` returns it,
/// so PDFView tiles and sidebar thumbnails both pick it up.
final class ReaderPage: PDFPage {
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        guard PageRendering.invert else {
            super.draw(with: box, to: context)
            return
        }

        let pageBounds = bounds(for: box)
        // Cover both the box rect and an origin-anchored rect of the same size so
        // pages with an offset media box still get a full paper fill.
        let paper = pageBounds.union(CGRect(origin: .zero, size: pageBounds.size))

        // 1. Guarantee opaque white paper under the content so the difference
        //    blend below has a known base (PDF pages have no intrinsic background).
        context.saveGState()
        context.setBlendMode(.normal)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(paper)
        context.restoreGState()

        // 2. Draw the page normally.
        super.draw(with: box, to: context)

        // 3. Invert luminance: result = |ink - existing|. White paper -> dark,
        //    black text -> light gray. Done in one GPU-friendly blend pass, so it
        //    costs essentially nothing per tile.
        context.saveGState()
        context.setBlendMode(.difference)
        context.setFillColor(CGColor(gray: PageRendering.inkLevel, alpha: 1))
        context.fill(paper)
        context.restoreGState()
    }
}
