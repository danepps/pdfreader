import AppKit
import PDFKit

extension NSToolbarItem.Identifier {
    static let pageIndicator = NSToolbarItem.Identifier("folio.pageIndicator")
    static let search = NSToolbarItem.Identifier("folio.search")
    static let searchCount = NSToolbarItem.Identifier("folio.searchCount")
    static let searchNav = NSToolbarItem.Identifier("folio.searchNav")
}

/// Toolbar view for the page indicator: just a container that shows a
/// pointing-hand cursor, so the number reads as clickable.
private final class PageIndicatorContainer: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// One window (or tab) per document: sidebar + PDFView, a unified toolbar with
/// a page indicator and a search field, incremental find, and reading-position
/// memory.
final class ReaderWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
                                    NSSearchFieldDelegate, NSTextFieldDelegate, FindSink {

    private let folioDocument: FolioDocument
    private let readerVC: ReaderViewController
    private let sidebarVC: SidebarViewController
    private let splitVC = NSSplitViewController()
    private var sidebarItem: NSSplitViewItem?
    private var didSettleSidebar = false

    private let pageLabel = NSTextField(labelWithString: "")
    private let pageField = NSTextField()
    private weak var searchItem: NSSearchToolbarItem?
    private let searchCountLabel = NSTextField(labelWithString: "")

    private var matches: [PDFSelection] = []
    private var matchIndex = 0
    private var searchNavControl: NSSegmentedControl?
    private var findInProgress = false
    private var lastQuery = ""
    /// Read once, at init: PDFView posts page-change notifications while it
    /// lays out, and those would otherwise overwrite the stored position with
    /// page 1 before we ever get a chance to restore it.
    private let savedPosition: Prefs.Position?
    private var restoreStarted = false
    private var restoreFinished = false

    private var pdfView: ReaderPDFView { readerVC.pdfView }
    private var pageCount: Int { folioDocument.pdf?.pageCount ?? 0 }

    // MARK: Init

    init(document: FolioDocument) {
        folioDocument = document
        savedPosition = document.fileURL.flatMap { Prefs.lastPosition(for: $0) }
        let reader = ReaderViewController(document: document)
        readerVC = reader
        sidebarVC = SidebarViewController(pdfView: reader.pdfView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 1040),
            // Deliberately no .fullSizeContentView: macOS 26's glass toolbar
            // tints itself from the content beneath it, and it samples the PDF
            // view *before* the inversion filter, which made the whole title
            // and tab bar read light in dark mode.
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "FolioReader"
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .automatic
        window.contentMinSize = Self.minimumContentSize

        super.init(window: window)

        window.delegate = self
        shouldCascadeWindows = false

        document.findSink = self
        reader.onInversionChanged = { [weak self] inverted in
            self?.applyInversion(inverted)
        }

        buildContent()
        // Installing the content view controller resizes the window to the
        // split view's fitting size (320pt wide, no height), so the frame is
        // chosen only after it: the autosaved one if there is one, else the
        // default clamped to the screen.
        sizeWindowInitially(window)
        buildToolbar()
        configurePageControls()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Keep the sidebar and the find highlights in step with the page inversion.
    private func applyInversion(_ inverted: Bool) {
        sidebarVC.setContentFilters(inverted ? ReaderViewController.invertFilters : [])
        applyHighlights()
        applyWindowChrome()
    }

    /// In dark mode the title bar and tab bar sit on plain black, matching the
    /// inverted page paper; the toolbar controls keep their own glass capsules.
    private func applyWindowChrome() {
        guard let window else { return }
        let dark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        window.titlebarAppearsTransparent = dark
        window.backgroundColor = dark ? .black : .windowBackgroundColor
        window.titlebarSeparatorStyle = dark ? .none : .automatic
    }

    /// Dark mode recolours the matched glyphs green in ReaderPage; light mode
    /// uses PDFKit's own translucent highlight.
    private func applyHighlights() {
        let inverted = readerVC.isInverted
        pdfView.isInverted = inverted
        if inverted {
            // The reverse-video boxes are the highlight; suppress PDFKit's own
            // translucent selection wash so it does not double up on them.
            for selection in matches { selection.color = .clear }
            pdfView.highlightedSelections = nil
            pdfView.setFindMatches(matches, current: matchIndex)
        } else {
            pdfView.setFindMatches([], current: 0)
            for selection in matches {
                selection.color = NSColor.systemGreen.withAlphaComponent(0.35)
            }
            pdfView.highlightedSelections = matches.isEmpty ? nil : matches
        }
    }

    private static let defaultContentSize = NSSize(width: 960, height: 1040)
    private static let minimumContentSize = NSSize(width: 480, height: 360)

    /// The autosave string is "x y w h sx sy sw sh" in points.
    private static func hasUsableSavedFrame(named name: String) -> Bool {
        guard let raw = UserDefaults.standard.string(forKey: "NSWindow Frame \(name)") else {
            return false
        }
        let parts = raw.split(separator: " ").compactMap { Double($0) }
        guard parts.count >= 4 else { return false }
        return parts[2] >= minimumContentSize.width && parts[3] >= minimumContentSize.height
    }

    /// First-launch screen: the widest landscape display (Dan reads on the
    /// landscape Studio Display, not the portrait one), else whatever there is.
    private static var preferredScreen: NSScreen? {
        let landscape = NSScreen.screens.filter { $0.frame.width > $0.frame.height }
        return landscape.max { $0.frame.width < $1.frame.width } ?? NSScreen.main
    }

    /// The default frame: defaultContentSize clamped to fit, centred on the
    /// preferred screen.
    private static func defaultFrame(for window: NSWindow) -> NSRect {
        var size = defaultContentSize
        let chrome = window.frame.height - window.contentLayoutRect.height
        guard let screen = preferredScreen else {
            return NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height + chrome))
        }
        let visible = screen.visibleFrame
        size.width = min(size.width, visible.width)
        size.height = min(size.height, visible.height - chrome)
        let frameSize = NSSize(width: size.width, height: size.height + chrome)
        return NSRect(
            x: visible.midX - frameSize.width / 2,
            y: visible.midY - frameSize.height / 2,
            width: frameSize.width,
            height: frameSize.height
        )
    }

    private func sizeWindowInitially(_ window: NSWindow) {
        if !Self.hasUsableSavedFrame(named: "ReaderWindow") {
            // A build that predates this sizing logic autosaved the collapsed
            // 320x32 frame, and setFrameAutosaveName below would restore it
            // (clamped up to contentMinSize), so drop it first.
            UserDefaults.standard.removeObject(forKey: "NSWindow Frame ReaderWindow")
            window.setFrame(Self.defaultFrame(for: window), display: false)
        }
        // Restores the saved frame when there is one, and saves from here on.
        window.setFrameAutosaveName("ReaderWindow")
    }

    private func buildContent() {
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 150
        sidebarItem.maximumThickness = 280
        sidebarItem.canCollapse = true
        sidebarItem.isCollapsed = true
        sidebarItem.allowsFullHeightLayout = true

        let contentItem = NSSplitViewItem(viewController: readerVC)
        contentItem.minimumThickness = 320

        splitVC.addSplitViewItem(sidebarItem)
        splitVC.addSplitViewItem(contentItem)
        self.sidebarItem = sidebarItem

        // Installing this shrinks the window to the split view's fitting
        // size (320pt wide, no height); sizeWindowInitially runs afterwards.
        // Deliberately no preferredContentSize: the window keeps snapping
        // back to it, which broke user resizing and window tiling.
        contentViewController = splitVC
    }

    private func buildToolbar() {
        let toolbar = NSToolbar(identifier: "FolioReaderToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
    }

    // MARK: Page indicator

    private var indicatorFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    private func configurePageControls() {
        let font = indicatorFont

        // Idle state: one label holding the whole "13 of 30" string, so it is
        // centred in the capsule by construction whatever the digit count.
        pageLabel.alignment = .center
        pageLabel.font = font
        pageLabel.toolTip = "Go to page (\u{2325}\u{2318}G)"
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        // Editing state: an unbezelled field in the same place. The toolbar
        // item's capsule is the only chrome; the accent tint is the caret hint.
        pageField.isEditable = true
        pageField.isSelectable = true
        pageField.isBezeled = false
        pageField.isBordered = false
        pageField.drawsBackground = false
        pageField.focusRingType = .none
        pageField.alignment = .center
        pageField.font = font
        pageField.textColor = .labelColor
        pageField.delegate = self
        pageField.target = self
        pageField.action = #selector(commitPageField)
        pageField.wantsLayer = true
        pageField.layer?.cornerRadius = 4
        pageField.layer?.masksToBounds = true
        pageField.isHidden = true
        pageField.translatesAutoresizingMaskIntoConstraints = false

        updatePageField()
    }

    private func makePageIndicatorItem() -> NSToolbarItem {
        let container = PageIndicatorContainer()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pageLabel)
        container.addSubview(pageField)

        // Fixed width, sized for the widest string this document can show, so
        // the capsule never resizes while paging; the label centres inside it.
        let widest = "\(max(pageCount, 1)) of \(max(pageCount, 1))"
            .size(withAttributes: [.font: indicatorFont]).width

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 22),
            container.widthAnchor.constraint(equalToConstant: ceil(widest) + 20),

            pageLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            pageLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            pageField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            pageField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            pageField.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(beginPageEdit))
        container.addGestureRecognizer(click)

        let item = NSToolbarItem(itemIdentifier: .pageIndicator)
        item.label = "Page"
        item.paletteLabel = "Page"
        item.toolTip = "Go to page (\u{2325}\u{2318}G)"
        item.view = container
        item.isBordered = true
        item.visibilityPriority = .high
        return item
    }

    private var currentPageNumber: Int? {
        guard let pdf = pdfView.document, let page = pdfView.currentPage else { return nil }
        let index = pdf.index(for: page)
        return index == NSNotFound ? nil : index + 1
    }

    private func updatePageField() {
        guard let number = currentPageNumber, pageCount > 0 else {
            pageLabel.stringValue = ""
            return
        }
        let font = indicatorFont
        let text = NSMutableAttributedString(
            string: "\(number)",
            attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        text.append(NSAttributedString(
            string: " of \(pageCount)",
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        pageLabel.attributedStringValue = text
        if pageField.isHidden { pageField.stringValue = "\(number)" }
    }

    /// Swap the label for the editable field, with the number preselected.
    @objc func beginPageEdit() {
        guard pageCount > 0, pageField.isHidden else { return }
        pageField.stringValue = currentPageNumber.map(String.init) ?? ""
        pageLabel.isHidden = true
        pageField.isHidden = false
        window?.makeFirstResponder(pageField)
        pageField.currentEditor()?.selectAll(nil)
    }

    /// Back to the idle label. Never navigates on its own.
    private func endPageEdit() {
        guard !pageField.isHidden else { return }
        pageField.isHidden = true
        pageField.drawsBackground = false
        pageLabel.isHidden = false
        updatePageField()
    }

    @objc private func commitPageField() {
        defer {
            endPageEdit()
            window?.makeFirstResponder(pdfView)
        }
        guard let pdf = pdfView.document, pdf.pageCount > 0,
              let requested = Int(pageField.stringValue.trimmingCharacters(in: .whitespaces))
        else { return }
        let target = min(max(requested, 1), pdf.pageCount) - 1
        let current = pdfView.currentPage.map { pdf.index(for: $0) } ?? NSNotFound
        if target != current, let page = pdf.page(at: target) {
            pdfView.go(to: page)
        }
    }

    @objc private func pageChanged() {
        updatePageField()
        savePosition()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === pageField else { return }
        pageField.drawsBackground = true
        pageField.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
        pageField.currentEditor()?.selectAll(nil)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === pageField else { return }
        endPageEdit()
    }

    // MARK: Toolbar delegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .pageIndicator,
         .flexibleSpace, .search, .searchCount, .searchNav]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .pageIndicator:
            return makePageIndicatorItem()
        case .search:
            let item = NSSearchToolbarItem(itemIdentifier: .search)
            item.preferredWidthForSearchField = 180
            item.resignsFirstResponderWithCancel = true
            let field = item.searchField
            field.delegate = self
            field.sendsWholeSearchString = false
            field.sendsSearchStringImmediately = false
            field.target = self
            field.action = #selector(searchChanged(_:))
            searchItem = item
            return item
        case .searchCount:
            return makeSearchCountItem()
        case .searchNav:
            return makeSearchNavItem()
        default:
            return nil
        }
    }

    // MARK: Find

    private var searchField: NSSearchField? { searchItem?.searchField }

    private func makeSearchCountItem() -> NSToolbarItem {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize,
                                                    weight: .regular)
        searchCountLabel.font = font
        searchCountLabel.textColor = .secondaryLabelColor
        searchCountLabel.alignment = .center
        searchCountLabel.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(searchCountLabel)
        // Hug the text with symmetric insets, but never shrink below 56pt, so
        // the capsule keeps a steady shape as the readout changes.
        let hug = container.widthAnchor.constraint(equalTo: searchCountLabel.widthAnchor,
                                                   constant: 20)
        hug.priority = .defaultLow

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 22),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            container.widthAnchor.constraint(greaterThanOrEqualTo: searchCountLabel.widthAnchor,
                                             constant: 20),
            hug,
            searchCountLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            searchCountLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        let item = NSToolbarItem(itemIdentifier: .searchCount)
        item.label = "Matches"
        item.paletteLabel = "Matches"
        item.view = container
        // Must outrank the search field so it is never pushed into the
        // toolbar's overflow menu.
        item.visibilityPriority = .high
        return item
    }

    /// Previous / next match, mirroring ⇧⌘G / ⌘G. Greyed out until a search
    /// has produced matches.
    private func makeSearchNavItem() -> NSToolbarItem {
        let control = NSSegmentedControl(
            images: [
                NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous match")!,
                NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next match")!
            ],
            trackingMode: .momentary,
            target: self,
            action: #selector(searchNavClicked(_:))
        )
        control.segmentStyle = .separated
        control.setToolTip("Previous match (\u{21E7}\u{2318}G)", forSegment: 0)
        control.setToolTip("Next match (\u{2318}G)", forSegment: 1)
        control.isEnabled = false
        searchNavControl = control

        let item = NSToolbarItem(itemIdentifier: .searchNav)
        item.label = "Previous/Next"
        item.paletteLabel = "Previous/Next Match"
        item.view = control
        item.visibilityPriority = .high
        return item
    }

    @objc private func searchNavClicked(_ sender: NSSegmentedControl) {
        sender.selectedSegment == 0 ? findPrevious(sender) : findNext(sender)
    }

    private func startFind(_ query: String) {
        if let pdf = folioDocument.pdf, pdf.isFinding { pdf.cancelFindString() }
        matches.removeAll()
        matchIndex = 0
        searchNavControl?.isEnabled = false
        pdfView.highlightedSelections = nil
        pdfView.setFindMatches([], current: 0)

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        lastQuery = trimmed
        findInProgress = !trimmed.isEmpty
        searchCountLabel.stringValue = ""

        guard !trimmed.isEmpty, let pdf = folioDocument.pdf else { return }
        pdf.beginFindString(trimmed, withOptions: [.caseInsensitive])
    }

    func findDidMatch(_ selection: PDFSelection) {
        matches.append(selection)
        // Show the first hit immediately; the rest arrive asynchronously.
        // Reassigning the highlight array per match is quadratic on large
        // documents, so later hits are batched onto a short timer instead:
        // they appear within ~150ms of being found rather than only when the
        // whole search ends.
        if matches.count == 1 {
            showMatch(0)
            applyHighlights()
        } else {
            scheduleHighlightRefresh()
        }
        searchCountLabel.stringValue = "\(matches.count) found…"
    }

    func findDidEnd() {
        findInProgress = false
        applyHighlights()
        updateSearchCount()
    }

    private var highlightRefreshPending = false

    private func scheduleHighlightRefresh() {
        guard !highlightRefreshPending else { return }
        highlightRefreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.highlightRefreshPending = false
            // findDidEnd has already applied the final set if the search is over.
            if self.findInProgress { self.applyHighlights() }
        }
    }

    /// "K of N" once a search has finished, "No matches" when it found nothing,
    /// blank when there is no query. Left alone while a search is still running
    /// -- findDidMatch shows the running total there.
    private func updateSearchCount() {
        searchNavControl?.isEnabled = !matches.isEmpty
        guard !lastQuery.isEmpty else {
            searchCountLabel.stringValue = ""
            return
        }
        if findInProgress {
            searchCountLabel.stringValue = "\(matches.count) found…"
        } else if matches.isEmpty {
            searchCountLabel.stringValue = "No matches"
        } else {
            searchCountLabel.stringValue = "\(matchIndex + 1) of \(matches.count)"
        }
    }

    private func showMatch(_ index: Int) {
        guard !matches.isEmpty else { return }
        let count = matches.count
        matchIndex = ((index % count) + count) % count
        let selection = matches[matchIndex]
        if readerVC.isInverted {
            // PDFKit would paint its own selection wash over our reverse-video
            // box, and inverted it comes out olive. Scroll to the match, then
            // drop the selection and let the drawn box mark it.
            pdfView.go(to: selection)
            pdfView.setCurrentSelection(nil, animate: false)
            pdfView.setCurrentMatchIndex(matchIndex)
        } else {
            pdfView.setCurrentSelection(selection, animate: true)
            pdfView.go(to: selection)
        }
        if !findInProgress { updateSearchCount() }
    }

    @objc func searchChanged(_ sender: NSSearchField) {
        startFind(sender.stringValue)
    }

    @objc func findNext(_ sender: Any?) {
        step(by: 1)
    }

    @objc func findPrevious(_ sender: Any?) {
        step(by: -1)
    }

    private func step(by delta: Int) {
        guard matches.isEmpty else {
            showMatch(matchIndex + delta)
            return
        }
        let query = (searchField?.stringValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !findInProgress, !query.isEmpty, query == lastQuery {
            // Already searched for exactly this and came up empty.
            NSSound.beep()
        } else {
            startFind(query)
        }
    }

    @objc func focusSearch(_ sender: Any?) {
        searchItem?.beginSearchInteraction()
    }

    @objc func useSelectionForFind(_ sender: Any?) {
        guard let text = pdfView.currentSelection?.string, !text.isEmpty else { return }
        searchField?.stringValue = text
        startFind(text)
    }

    @objc func focusPageField(_ sender: Any?) {
        beginPageEdit()
    }

    // MARK: Field editing

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        if control is NSSearchField {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                if matches.isEmpty {
                    startFind(control.stringValue)
                } else if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    findPrevious(nil)
                } else {
                    findNext(nil)
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                control.stringValue = ""
                startFind("")
                searchItem?.endSearchInteraction()
                window?.makeFirstResponder(pdfView)
                return true
            default:
                return false
            }
        }

        if control === pageField {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                commitPageField()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                endPageEdit()
                window?.makeFirstResponder(pdfView)
                return true
            default:
                return false
            }
        }

        return false
    }

    // MARK: Window / tabs

    override func showWindow(_ sender: Any?) {
        if let window, !window.isVisible {
            // Front-to-back: adopt the frontmost existing reader window as tab host.
            let host = NSApp.orderedWindows.first {
                $0 !== window && $0.isVisible && !$0.isMiniaturized
                    && $0.tabbingIdentifier == window.tabbingIdentifier
            }
            host?.addTabbedWindow(window, ordered: .above)
            // Joining a tab group re-lays the split view out and loses the
            // collapsed state set at init, so assert it again here.
            sidebarItem?.isCollapsed = true
        }

        super.showWindow(sender)
        window?.makeFirstResponder(pdfView)
        restorePositionIfNeeded()
    }

    /// Opening a new tab means opening another document, which also makes
    /// AppKit show the "+" button in the tab bar.
    override func newWindowForTab(_ sender: Any?) {
        NSDocumentController.shared.openDocument(sender)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard !didSettleSidebar else { return }
        didSettleSidebar = true
        sidebarItem?.isCollapsed = true
    }

    func windowWillClose(_ notification: Notification) {
        if let pdf = folioDocument.pdf, pdf.isFinding { pdf.cancelFindString() }
        savePosition()
    }

    // MARK: Reading position

    private func savePosition() {
        // Nothing is worth saving until the restore has run: the layout-time
        // page changes all report page 1.
        guard restoreFinished else { return }
        guard let url = folioDocument.fileURL,
              let pdf = pdfView.document,
              let destination = pdfView.currentDestination,
              let page = destination.page
        else { return }
        let index = pdf.index(for: page)
        guard index != NSNotFound else { return }
        Prefs.setLastPosition(
            Prefs.Position(pageIndex: index,
                           x: destination.point.x,
                           y: destination.point.y),
            for: url
        )
    }

    private func restorePositionIfNeeded() {
        guard !restoreStarted else { return }
        restoreStarted = true

        guard let saved = savedPosition,
              let pdf = pdfView.document,
              saved.pageIndex > 0 || saved.y != 0,
              saved.pageIndex < pdf.pageCount,
              let page = pdf.page(at: saved.pageIndex)
        else {
            restoreFinished = true
            updatePageField()
            return
        }

        let destination = PDFDestination(page: page, at: NSPoint(x: saved.x, y: saved.y))

        // PDFView silently ignores go(to:) before it has laid the document out,
        // so force layout and jump on the next runloop pass; then confirm we
        // actually landed on the saved page and retry once if not.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pdfView.layoutDocumentView()
            self.pdfView.go(to: destination)

            DispatchQueue.main.async {
                let landed = self.pdfView.currentPage.map { pdf.index(for: $0) } ?? NSNotFound
                if landed != saved.pageIndex {
                    self.pdfView.go(to: destination)
                }
                self.restoreFinished = true
                self.updatePageField()
            }
        }
    }
}
