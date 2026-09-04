import AppKit
import CoreImage
import PDFKit

/// PDFView with two additions: it reports effective-appearance changes
/// (NSViewController has no hook for that -- only NSView does), and the arrow
/// keys always move a whole page instead of scrolling by a line.
final class ReaderPDFView: PDFView {
    var onEffectiveAppearanceChange: (() -> Void)?

    /// Set by the window controller. When true, find matches are drawn here as
    /// reverse video instead of PDFKit's translucent yellow, because a yellow
    /// wash reads poorly through the dark-mode inversion filter.
    var isInverted = false {
        didSet { if isInverted != oldValue { refresh(allMatchPages) } }
    }

    private(set) var findMatches: [PDFSelection] = []
    private(set) var currentMatchIndex = 0

    private struct LineRect {
        let rect: CGRect
        let match: Int
    }

    private var lineRects: [ObjectIdentifier: [LineRect]] = [:]
    private var pagesByMatch: [Int: [PDFPage]] = [:]
    private var allMatchPages: [PDFPage] = []

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }

    // MARK: Reverse-video find highlights

    func setFindMatches(_ selections: [PDFSelection], current: Int) {
        let previous = allMatchPages
        findMatches = selections
        currentMatchIndex = current
        rebuildLineRects()
        refresh(previous + allMatchPages)
    }

    func setCurrentMatchIndex(_ index: Int) {
        guard index != currentMatchIndex else { return }
        let affected = (pagesByMatch[currentMatchIndex] ?? []) + (pagesByMatch[index] ?? [])
        currentMatchIndex = index
        refresh(affected)
    }

    /// Flatten every match into per-line rectangles keyed by page, so drawing a
    /// page is a dictionary lookup rather than a scan of the whole match list.
    private func rebuildLineRects() {
        lineRects = [:]
        pagesByMatch = [:]
        allMatchPages = []
        var seen = Set<ObjectIdentifier>()

        for (index, selection) in findMatches.enumerated() {
            var pages: [PDFPage] = []
            for line in selection.selectionsByLine() {
                for page in line.pages {
                    let rect = line.bounds(for: page).insetBy(dx: 0, dy: -1)
                    lineRects[ObjectIdentifier(page), default: []]
                        .append(LineRect(rect: rect, match: index))
                    if !pages.contains(where: { $0 === page }) { pages.append(page) }
                }
            }
            pagesByMatch[index] = pages
            for page in pages where seen.insert(ObjectIdentifier(page)).inserted {
                allMatchPages.append(page)
            }
        }
    }

    /// Push the current rects into the page objects (PDFKit draws through
    /// them) and invalidate the cached tiles for every page that changed.
    private func refresh(_ pages: [PDFPage]) {
        var seen = Set<ObjectIdentifier>()
        for page in pages where seen.insert(ObjectIdentifier(page)).inserted {
            if let readerPage = page as? ReaderPage {
                let rects = isInverted ? (lineRects[ObjectIdentifier(page)] ?? []) : []
                readerPage.findHighlights = rects.map {
                    ReaderPage.Highlight(rect: $0.rect,
                                         isCurrent: $0.match == currentMatchIndex)
                }
            }
            annotationsChanged(on: page)
        }
        // annotationsChanged alone does not always drop an already-rendered
        // tile, so nudge the layout as well: without this, matches that arrive
        // after a page is on screen stay unhighlighted until it is scrolled
        // out and back.
        if !pages.isEmpty {
            layoutDocumentView()
            needsDisplay = true
        }
    }

    /// Page-at-a-time arrows. This lives on the view, so arrow keys still edit
    /// text normally while the search field or page field has focus. Page
    /// Up/Down and Space/Shift-Space fall through to PDFView untouched.
    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        switch event.specialKey {
        case .upArrow, .leftArrow:
            if command && event.specialKey == .upArrow { goToFirstPage(nil) }
            else { goToPreviousPage(nil) }
        case .downArrow, .rightArrow:
            if command && event.specialKey == .downArrow { goToLastPage(nil) }
            else { goToNextPage(nil) }
        default:
            super.keyDown(with: event)
        }
    }
}


/// Hosts the PDFView and owns the light/dark rendering decision for its window.
final class ReaderViewController: NSViewController {

    let pdfView = ReaderPDFView()
    private let folioDocument: FolioDocument

    /// True when pages are being shown light-on-dark.
    private(set) var isInverted = false

    /// Called after every appearance pass with the current inversion state, so
    /// the window can keep the sidebar and the find highlights in step.
    var onInversionChanged: ((Bool) -> Void)?

    /// Luminance inversion that keeps hues: invert, then rotate hue 180 degrees,
    /// so blue links stay blue instead of turning orange.
    static let invertFilters: [CIFilter] = {
        guard let invert = CIFilter(name: "CIColorInvert"),
              let hue = CIFilter(name: "CIHueAdjust") else { return [] }
        hue.setValue(Float.pi, forKey: "inputAngle")
        return [invert, hue]
    }()

    init(document: FolioDocument) {
        self.folioDocument = document
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func loadView() {
        view = pdfView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.autoScales = true
        pdfView.displaysPageBreaks = true
        pdfView.pageShadowsEnabled = true
        pdfView.enableDataDetectors = false
        // Inversion is a layer filter on the whole view, so PDFKit's own white
        // placeholder tiles are inverted too and pages never flash white.
        pdfView.wantsLayer = true
        pdfView.document = folioDocument.pdf
        pdfView.onEffectiveAppearanceChange = { [weak self] in self?.applyAppearance() }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(prefsChanged),
            name: .folioPrefsChanged,
            object: nil
        )
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        applyAppearance()
    }

    @objc private func prefsChanged() {
        applyAppearance()
    }

    // MARK: Appearance

    private func applyAppearance() {
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let invert = dark && Prefs.invertInDarkMode

        // The filter inverts everything inside the view, gutter included, so the
        // pre-filter gutter colour is the complement of what we want to see.
        // CIColorInvert works in linear light, so the pre-filter gutter has to
        // sit very close to white to come out near-black: 0.997 composites to
        // roughly 0.07, dark enough to read as black but still just visible
        // against the pure-black page paper at a page break.
        pdfView.backgroundColor = invert
            ? NSColor(white: 0.997, alpha: 1)
            : NSColor(white: dark ? 0.11 : 0.94, alpha: 1)

        pdfView.contentFilters = invert ? Self.invertFilters : []
        // Inverted, PDFKit's drop shadows become bright halos around every page
        // and a light band at the end of the document.
        pdfView.pageShadowsEnabled = !invert

        if isInverted != invert {
            isInverted = invert
        }
        onInversionChanged?(invert)
    }

    // MARK: Actions

    @objc func zoomToFit(_ sender: Any?) {
        pdfView.autoScales = true
    }

    @objc func actualSize(_ sender: Any?) {
        pdfView.autoScales = false
        pdfView.scaleFactor = 1
    }

    @objc func printDocument(_ sender: Any?) {
        pdfView.print(with: NSPrintInfo.shared, autoRotate: true)
    }
}
