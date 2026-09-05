import AppKit
import PDFKit
import WebKit

/// Errors the Markdown render pipeline can report.
enum MarkdownRenderError: LocalizedError {
    /// A newer render of the same document replaced this one before it started.
    case superseded
    case timedOut
    case printFailed
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .superseded: return "The render was replaced by a newer one."
        case .timedOut: return "Typesetting the Markdown timed out."
        case .printFailed: return "Typesetting the Markdown failed."
        case .emptyDocument: return "Typesetting the Markdown produced no pages."
        }
    }
}

/// Typesets HTML into a paginated PDF with an offscreen WKWebView.
///
/// Nothing on screen is ever a web view: the view lives in a borderless window
/// that is never ordered in, and its only job is to run WebKit's print path,
/// which is what gives us real page breaks, selectable text, and link
/// annotations. Jobs run one at a time; a newer job for the same document
/// supersedes one still waiting in the queue.
@MainActor
final class MarkdownRenderer: NSObject {

    static let shared = MarkdownRenderer()

    /// US Letter at 72 dpi.
    static let paperSize = NSSize(width: 612, height: 792)
    /// One inch. Margins come from NSPrintInfo, never from an `@page` rule:
    /// WebKit subtracts the print info's margins itself and would double them.
    private static let margin: CGFloat = 72
    /// WebKit lays a printed page out 25% wider than the paper and scales the
    /// result down to fit (WebCore's minimum shrink factor), so a measurement
    /// only matches the print if the web view is that much wider too -- and the
    /// height it reports has to be scaled back down by the same amount.
    private static let printShrinkFactor: CGFloat = 1.25
    private static let timeout: TimeInterval = 10
    private static let idleTeardownDelay: TimeInterval = 30

    struct Result {
        let data: Data
        let document: PDFDocument
    }

    private struct Job {
        let key: String
        let html: String
        let baseURL: URL?
        let layout: MarkdownLayout
        let completion: (Swift.Result<Result, Error>) -> Void
    }

    private var webView: WKWebView?
    private var hostWindow: NSWindow?

    private var queue: [Job] = []
    private var current: Job?
    private var watchdog: DispatchWorkItem?
    private var idleTeardown: DispatchWorkItem?
    private var outputURL: URL?
    /// The operation whose completion we are waiting for. A callback from any
    /// other (say, one the watchdog already gave up on) is ignored rather than
    /// being credited to whatever job is current by then.
    private var activeOperation: NSPrintOperation?
    /// The load we are waiting for, for the same reason: cancelling a navigation
    /// to start the next job makes the old one report failure, and that failure
    /// must not be charged to the job that displaced it.
    private var activeNavigation: WKNavigation?
    private var didRetryPrint = false
    private var didRestartWebProcess = false
    /// The measured height of a continuous job's content, in points; nil for a
    /// paginated job, and also when the measurement failed and the job has to
    /// fall back to Letter pages.
    private var continuousHeight: CGFloat?

    private override init() { super.init() }

    // MARK: API

    /// Render `html` into a PDF. `key` identifies the document: queuing a second
    /// job with the same key drops the first (its completion gets `.superseded`).
    /// A `.continuous` job is measured after it loads and printed onto a single
    /// page as tall as its content.
    func render(html: String,
                baseURL: URL?,
                key: String,
                layout: MarkdownLayout,
                completion: @escaping (Swift.Result<Result, Error>) -> Void) {
        idleTeardown?.cancel()
        idleTeardown = nil

        if let index = queue.firstIndex(where: { $0.key == key }) {
            let dropped = queue.remove(at: index)
            dropped.completion(.failure(MarkdownRenderError.superseded))
        }
        queue.append(Job(key: key, html: html, baseURL: baseURL,
                         layout: layout, completion: completion))
        pump()
    }

    /// Tear the web view down once nothing has needed it for a while: the
    /// WebContent process costs 60-120 MB and a Markdown-free session should
    /// not pay for it.
    func releaseIfIdle() {
        idleTeardown?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.current == nil, self.queue.isEmpty else { return }
            self.teardownWebView()
            self.idleTeardown = nil
        }
        idleTeardown = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleTeardownDelay, execute: work)
    }

    // MARK: Queue

    private func pump() {
        guard current == nil, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        current = job
        didRetryPrint = false
        didRestartWebProcess = false
        continuousHeight = nil
        startWatchdog()
        let view = makeWebView()
        // Lay a continuous job out at the width WebKit will print it at, so its
        // measured height is the printed height; a paginated job is never
        // measured and its frame does not matter.
        view.frame.size.width = job.layout == .continuous
            ? Self.paperSize.width * Self.printShrinkFactor
            : Self.paperSize.width
        activeNavigation = view.loadHTMLString(job.html, baseURL: job.baseURL)
    }

    private func startWatchdog() {
        watchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Abandon the stuck load rather than let the next job inherit it.
            self.teardownWebView()
            self.finish(.failure(MarkdownRenderError.timedOut))
        }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout, execute: work)
    }

    private func finish(_ result: Swift.Result<Result, Error>) {
        watchdog?.cancel()
        watchdog = nil
        if let url = outputURL {
            try? FileManager.default.removeItem(at: url)
            outputURL = nil
        }
        activeOperation = nil
        activeNavigation = nil
        guard let job = current else { return }
        current = nil
        job.completion(result)
        pump()
    }

    // MARK: Web view

    private func makeWebView() -> WKWebView {
        if let webView { return webView }

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.preferences.shouldPrintBackgrounds = true
        configuration.suppressesIncrementalRendering = true

        let frame = NSRect(origin: .zero, size: Self.paperSize)
        let view = WKWebView(frame: frame, configuration: configuration)
        view.navigationDelegate = self

        // WebKit lays out and prints reliably only from a window. This one is
        // borderless, never ordered in, and never released.
        let window = NSWindow(contentRect: frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view

        webView = view
        hostWindow = window
        return view
    }

    private func teardownWebView() {
        webView?.navigationDelegate = nil
        hostWindow?.contentView = nil
        webView = nil
        hostWindow = nil
    }

    // MARK: Printing

    /// A continuous job needs its content measured before it can be printed;
    /// everything else goes straight to the press.
    private func printWhenMeasured() {
        guard let job = current else { return }
        guard job.layout == .continuous else {
            printLoadedPage()
            return
        }
        measureContentHeight { [weak self] height in
            guard let self, self.current != nil else { return }
            self.continuousHeight = height
            self.printLoadedPage()
        }
    }

    /// The document's laid-out height. Page scripts are disabled and the CSP
    /// blocks them anyway, but an evaluation in the client content world still
    /// runs; if it ever stops, `nil` falls back to ordinary Letter pages.
    private func measureContentHeight(_ completion: @escaping (CGFloat?) -> Void) {
        guard let webView else {
            completion(nil)
            return
        }
        webView.evaluateJavaScript("document.documentElement.scrollHeight",
                                   in: nil,
                                   in: .defaultClient) { result in
            switch result {
            case .success(let value):
                completion((value as? NSNumber).map {
                    CGFloat($0.doubleValue) / Self.printShrinkFactor
                })
            case .failure:
                completion(nil)
            }
        }
    }

    private func printLoadedPage() {
        guard current != nil, let webView, let hostWindow else { return }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-md-\(UUID().uuidString).pdf")
        outputURL = output

        // One tall page instead of many: the paper is exactly as tall as the
        // content (plus a hair, so a rounding error cannot spill onto a second
        // page) and the margins are zero, because in this mode the stylesheet
        // pads the body instead.
        let continuous = continuousHeight.map {
            NSSize(width: Self.paperSize.width, height: ceil($0) + 2)
        }
        let paper = continuous ?? Self.paperSize
        let margin = continuous == nil ? Self.margin : 0

        // A fresh NSPrintInfo, never NSPrintInfo.shared: that one belongs to the
        // user's Print… panel and mutating it would leak these settings into it.
        let info = NSPrintInfo(dictionary: [:])
        if continuous == nil { info.paperName = NSPrinter.PaperName("na-letter") }
        info.paperSize = paper
        info.orientation = .portrait
        info.scalingFactor = 1
        info.leftMargin = margin
        info.rightMargin = margin
        info.topMargin = margin
        info.bottomMargin = margin
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = false

        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // WKPrintingView computes its page range only on a secondary print
        // thread; on the main thread it returns an open-ended range and never
        // finishes. run() never spawns that thread, runModal(for:...) does --
        // this is the whole reason for the sheet-shaped API below.
        operation.canSpawnSeparateThread = true
        operation.view?.frame = NSRect(origin: .zero, size: paper)
        activeOperation = operation

        operation.runModal(for: hostWindow,
                           delegate: self,
                           didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                           contextInfo: nil)
    }

    /// AppKit runs the operation on a secondary print thread -- that is the
    /// whole point of `canSpawnSeparateThread` -- and calls this back *on that
    /// thread*. Everything downstream (installing a PDFDocument into a PDFView,
    /// posting notifications) is main-thread work, so hop first.
    @objc private nonisolated func printOperationDidRun(_ operation: NSPrintOperation,
                                                        success: Bool,
                                                        contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.printDidRun(operation, success: success) }
        }
    }

    private func printDidRun(_ operation: NSPrintOperation, success: Bool) {
        guard current != nil, operation === activeOperation else { return }
        guard success, let url = outputURL else {
            finish(.failure(MarkdownRenderError.printFailed))
            return
        }

        guard let data = try? Data(contentsOf: url),
              let document = PDFDocument(data: data),
              document.pageCount > 0
        else {
            // WebKit occasionally lands here on the very first print of a
            // freshly created web view; one retry a beat later fixes it.
            if !didRetryPrint {
                didRetryPrint = true
                try? FileManager.default.removeItem(at: url)
                outputURL = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.printLoadedPage()
                }
                return
            }
            finish(.failure(MarkdownRenderError.emptyDocument))
            return
        }

        finish(.success(Result(data: data, document: document)))
    }
}

// MARK: - WKNavigationDelegate

extension MarkdownRenderer: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation else { return }
        // Give WebKit one run-loop turn to settle its layout before printing.
        DispatchQueue.main.async { [weak self] in self?.printWhenMeasured() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === activeNavigation else { return }
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        guard navigation === activeNavigation else { return }
        finish(.failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        teardownWebView()
        guard let job = current, !didRestartWebProcess else {
            finish(.failure(MarkdownRenderError.printFailed))
            return
        }
        didRestartWebProcess = true
        activeNavigation = makeWebView().loadHTMLString(job.html, baseURL: job.baseURL)
    }
}
