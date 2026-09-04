import ObjectiveC
import PDFKit

/// Stable, unique address used as the associated-object key.
private let highlightKey = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

/// Immutable box so the render thread only ever sees a fully formed value.
private final class HighlightBox: NSObject {
    let items: [ReaderPage.Highlight]
    init(_ items: [ReaderPage.Highlight]) { self.items = items }
}

/// PDFPage subclass used for every page (see `FolioDocument.classForPage()`).
/// It draws the dark-mode find highlights: PDFKit renders pages through the
/// page object, so this is the hook that actually runs, and the reverse-video
/// boxes end up inside the view's inversion filter along with the text.
///
/// Deliberately no Swift stored properties: PDFKit allocates pages through a
/// private initialiser that never runs Swift's ivar setup, so a stored `Array`
/// here is read as a null buffer on the tile-rendering thread and crashes.
/// State lives in an associated object, which the ObjC runtime keeps
/// thread-safe, and the boxed array is immutable once published.
final class ReaderPage: PDFPage {

    struct Highlight {
        let rect: CGRect
        let isCurrent: Bool
    }

    /// Set by ReaderPDFView. Empty in light mode, where PDFKit's own yellow
    /// `highlightedSelections` are used instead.
    var findHighlights: [Highlight] {
        get { (objc_getAssociatedObject(self, highlightKey) as? HighlightBox)?.items ?? [] }
        set {
            objc_setAssociatedObject(self, highlightKey, HighlightBox(newValue),
                                     .OBJC_ASSOCIATION_RETAIN)
        }
    }

    /// Pre-filter ink for the matches. The view's inversion filter (invert +
    /// 180 degree hue rotation) turns this into terminal green, ~#5CF25C, on
    /// the dark page.
    private static let matchInk = CGColor(red: 0, green: 0.77, blue: 0, alpha: 1)

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)

        let boxes = findHighlights
        guard !boxes.isEmpty else { return }

        context.saveGState()

        // Screen leaves the white paper white and lifts the black glyphs to the
        // fill colour, so only the matched text is recoloured -- no box. The
        // 1pt vertical inset keeps the rect off the neighbouring lines, whose
        // ascenders and descenders reach into a line's selection bounds.
        context.setBlendMode(.screen)
        context.setFillColor(Self.matchInk)
        for highlight in boxes {
            context.fill(highlight.rect.insetBy(dx: 0, dy: 1))
        }

        // The current match gets a 2pt underline along the inside of its bottom
        // edge. (An outline drawn *outside* the rect painted opaque green over
        // the neighbouring lines' glyphs, which the inversion filter turned
        // into a dark strike through them.)
        context.setBlendMode(.normal)
        for highlight in boxes where highlight.isCurrent {
            let rect = highlight.rect.insetBy(dx: 0, dy: 1)
            context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2))
        }

        context.restoreGState()
    }
}
