import AppKit
import PDFKit

/// Receives find results from the PDFDocument delegate.
protocol FindSink: AnyObject {
    func findDidMatch(_ selection: PDFSelection)
    func findDidEnd()
}

/// Read-only NSDocument wrapping a PDFDocument. NSDocument gives us Finder
/// integration, Open Recent, the title-bar proxy icon, and one-window-per-file
/// semantics for free.
@objc(FolioDocument)
final class FolioDocument: NSDocument, PDFDocumentDelegate {
    private(set) var pdf: PDFDocument?
    weak var findSink: FindSink?

    override class var autosavesInPlace: Bool { false }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { true }

    override func read(from url: URL, ofType typeName: String) throws {
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
    }

    override func makeWindowControllers() {
        addWindowController(ReaderWindowController(document: self))
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
