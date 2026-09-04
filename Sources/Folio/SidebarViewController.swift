import AppKit
import CoreImage
import PDFKit

/// Page thumbnails. PDFThumbnailView does the selection sync with the PDFView
/// on its own, so there is nothing else to wire up.
final class SidebarViewController: NSViewController {

    private let thumbnailView = PDFThumbnailView()
    private let pdfView: PDFView
    private var pendingFilters: [CIFilter] = []

    init(pdfView: PDFView) {
        self.pdfView = pdfView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        view = thumbnailView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = NSSize(width: 120, height: 160)
        thumbnailView.maximumNumberOfColumns = 1
        // Clear so the sidebar's vibrant material shows through.
        thumbnailView.backgroundColor = .clear
        thumbnailView.wantsLayer = true
        thumbnailView.contentFilters = pendingFilters
    }

    /// Same inversion filters as the reader, so thumbnails match the pages.
    func setContentFilters(_ filters: [CIFilter]) {
        pendingFilters = filters
        if isViewLoaded { thumbnailView.contentFilters = filters }
    }
}
