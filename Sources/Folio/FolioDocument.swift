import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Receives find results from the PDFDocument delegate.
protocol FindSink: AnyObject {
    func findDidMatch(_ selection: PDFSelection)
    func findDidEnd()
}

/// Read-only NSDocument wrapping a PDFDocument. NSDocument gives us Finder
/// integration, Open Recent, the title-bar proxy icon, and one-window-per-file
/// semantics for free.
///
/// Two kinds of file end up in the same PDFDocument slot. A `.pdf` is opened
/// directly. A `.markdown` file is converted to HTML and typeset into a real
/// paginated PDF by `MarkdownRenderer`, so everything downstream -- tabs, dark
/// mode, find, position memory, printing -- works without knowing the
/// difference. Because typesetting is asynchronous, the first Markdown render
/// is just "reload #0": the window opens empty and fills a fraction of a second
/// later through the same path a file-change reload uses.
@objc(FolioDocument)
final class FolioDocument: NSDocument, PDFDocumentDelegate {

    enum Kind {
        case pdf
        case markdown
    }

    /// macOS does not declare this in CoreTypes, so Folio imports it (see
    /// UTImportedTypeDeclarations in Info.plist).
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown",
                                     conformingTo: .plainText)

    private static let markdownExtensions: Set<String> =
        ["md", "markdown", "mdown", "mkdn", "mkd", "mdwn"]

    private(set) var kind: Kind = .pdf
    private(set) var pdf: PDFDocument?
    /// The bytes behind the current render, kept for Export as PDF.
    private(set) var renderedPDFData: Data?
    weak var findSink: FindSink?

    // Markdown state
    private var bodyHTML: String?
    private var lastLoadedHash: Int?
    private var typography = MarkdownTypography.current
    private var watcher: FileWatcher?
    /// Bumped for every render; a completion whose generation is stale is dropped.
    private var renderGeneration = 0
    private var observingPrefs = false
    /// Identifies this document to the renderer's job queue, so a second render
    /// of the same file supersedes one still waiting.
    private let renderKey = UUID().uuidString

    override class var autosavesInPlace: Bool { false }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }

    deinit {
        watcher?.stop()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Reading

    private static func kind(forType typeName: String, url: URL) -> Kind {
        if let type = UTType(typeName) {
            if type.conforms(to: .pdf) { return .pdf }
            if type == markdownType || type.conforms(to: markdownType) { return .markdown }
        }
        // LaunchServices sometimes hands over a plain-text type (or the raw
        // extension) for Markdown, so fall back to the file name.
        return markdownExtensions.contains(url.pathExtension.lowercased()) ? .markdown : .pdf
    }

    override func read(from url: URL, ofType typeName: String) throws {
        kind = Self.kind(forType: typeName, url: url)
        switch kind {
        case .pdf:
            guard let document = PDFDocument(url: url) else {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadCorruptFileError,
                    userInfo: [
                        NSURLErrorKey: url,
                        NSLocalizedDescriptionKey: "\(url.lastPathComponent) could not be opened as a PDF."
                    ]
                )
            }
            document.delegate = self
            pdf = document
        case .markdown:
            // Only text work here; `pdf` stays nil until the renderer finishes.
            let data = try Data(contentsOf: url)
            lastLoadedHash = data.hashValue
            bodyHTML = MarkdownHTML.body(
                fromMarkdown: try MarkdownHTML.decode(data, url: url),
                baseDirectory: url.deletingLastPathComponent())
        }
    }

    override func makeWindowControllers() {
        addWindowController(ReaderWindowController(document: self))
        guard kind == .markdown else { return }
        startRender(initial: true)
        startWatching()
        observePrefs()
    }

    // MARK: Markdown rendering

    private func startRender(initial: Bool) {
        guard kind == .markdown, let bodyHTML else { return }
        renderGeneration += 1
        let generation = renderGeneration
        let html = MarkdownHTML.page(body: bodyHTML,
                                     title: displayName ?? "",
                                     typography: typography)
        MarkdownRenderer.shared.render(html: html,
                                       baseURL: fileURL,
                                       key: renderKey) { [weak self] result in
            guard let self, generation == self.renderGeneration else { return }
            switch result {
            case .success(let rendered):
                self.install(rendered, initial: initial)
            case .failure(let error):
                // A reload that fails almost always means a half-written file;
                // keep showing the last good render and wait for the next save.
                guard initial else { return }
                self.presentError(error)
                self.close()
            }
        }
    }

    private func install(_ rendered: MarkdownRenderer.Result, initial: Bool) {
        // The delegate has to be in place before anything asks for a page:
        // PDFKit calls classForPage lazily, and a page vended before this is set
        // would be a plain PDFPage, which cannot draw dark-mode find highlights.
        rendered.document.delegate = self
        pdf = rendered.document
        renderedPDFData = rendered.data
        if let url = fileURL,
           let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) {
            fileModificationDate = values.contentModificationDate
        }
        NotificationCenter.default.post(name: .folioDocumentDidReplacePDF,
                                        object: self,
                                        userInfo: ["initial": initial])
    }

    // MARK: Reloading

    private func startWatching() {
        guard let url = fileURL, watcher == nil else { return }
        watcher = FileWatcher(url: url) { [weak self] in
            self?.reloadFromDisk()
        }
    }

    private func reloadFromDisk() {
        guard kind == .markdown, let url = fileURL else { return }
        let baseDirectory = url.deletingLastPathComponent()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let data = try? Data(contentsOf: url) else { return }
            let hash = data.hashValue
            guard let text = try? MarkdownHTML.decode(data, url: url) else { return }
            let body = MarkdownHTML.body(fromMarkdown: text, baseDirectory: baseDirectory)
            DispatchQueue.main.async {
                guard let self, self.lastLoadedHash != hash else { return }
                self.lastLoadedHash = hash
                self.bodyHTML = body
                self.startRender(initial: false)
            }
        }
    }

    // Route the coordinated-write callback into the watcher instead of letting
    // NSDocument run its own revert machinery; the watcher's debounce and
    // signature gate then keep the two paths from rendering twice.
    override func presentedItemDidChange() {
        watcher?.poke()
    }

    override func presentedItemDidMove(to newURL: URL) {
        super.presentedItemDidMove(to: newURL)
        watcher?.retarget(to: newURL)
    }

    override func close() {
        watcher?.stop()
        watcher = nil
        super.close()
        if kind == .markdown { MarkdownRenderer.shared.releaseIfIdle() }
    }

    // MARK: Typography

    private func observePrefs() {
        guard !observingPrefs else { return }
        observingPrefs = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(prefsChanged), name: .folioPrefsChanged, object: nil)
    }

    @objc private func prefsChanged() {
        let current = MarkdownTypography.current
        guard kind == .markdown, current != typography else { return }
        typography = current
        // The Markdown itself has not changed, only the stylesheet wrapped
        // around it, so the cached body is reused as is.
        startRender(initial: false)
    }

    // MARK: Export

    @objc func exportAsPDF(_ sender: Any?) {
        guard let window = windowControllers.first?.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        let base = fileURL?.deletingPathExtension().lastPathComponent
            ?? (displayName ?? "Document")
        panel.nameFieldStringValue = base + ".pdf"
        if let directory = fileURL?.deletingLastPathComponent() {
            panel.directoryURL = directory
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let destination = panel.url else { return }
            do {
                try self.pdfDataForExport().write(to: destination)
            } catch {
                self.presentError(error)
            }
        }
    }

    private func pdfDataForExport() throws -> Data {
        if kind == .markdown, let renderedPDFData { return renderedPDFData }
        // Copying the original bytes keeps a PDF export byte-identical;
        // dataRepresentation() re-serialises and is only the fallback.
        if kind == .pdf, let url = fileURL, let data = try? Data(contentsOf: url) { return data }
        guard let data = pdf?.dataRepresentation() else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileWriteUnknownError,
                userInfo: [NSLocalizedDescriptionKey: "There is nothing to export yet."])
        }
        return data
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(exportAsPDF(_:)) { return pdf != nil }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: PDFDocumentDelegate

    func classForPage() -> AnyClass {
        ReaderPage.self
    }

    func didMatchString(_ instance: PDFSelection) {
        if Thread.isMainThread {
            findSink?.findDidMatch(instance)
        } else {
            DispatchQueue.main.async { self.findSink?.findDidMatch(instance) }
        }
    }

    func documentDidEndDocumentFind(_ notification: Notification) {
        if Thread.isMainThread {
            findSink?.findDidEnd()
        } else {
            DispatchQueue.main.async { self.findSink?.findDidEnd() }
        }
    }
}
