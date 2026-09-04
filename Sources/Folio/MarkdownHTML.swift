import Foundation
import Markdown
import UniformTypeIdentifiers

/// Body typeface and size for rendered Markdown. Held separately from `Prefs`
/// so the HTML can be built off the main thread.
struct MarkdownTypography: Equatable {
    var typeface: MarkdownTypeface
    var size: Int

    static var current: MarkdownTypography {
        MarkdownTypography(typeface: Prefs.markdownTypeface, size: Prefs.markdownFontSize)
    }
}

/// Markdown -> HTML. Pure Swift, no AppKit, safe to call off the main thread.
///
/// The HTML is a complete page with an inline stylesheet; page geometry is
/// deliberately *not* in it (no `@page` rule) because the print info supplies
/// the margins and WebKit would otherwise apply both.
enum MarkdownHTML {

    /// Decode file bytes as text. UTF-8 is the rule; a UTF-16 byte-order mark is
    /// honoured, and anything else is reported the way an unreadable PDF is.
    static func decode(_ data: Data, url: URL) throws -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16) { return text }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadInapplicableStringEncodingError,
            userInfo: [
                NSURLErrorKey: url,
                NSLocalizedDescriptionKey:
                    "\(url.lastPathComponent) is not valid UTF-8 text."
            ]
        )
    }

    /// Convert Markdown to the `<body>` half of the page. `baseDirectory` is the
    /// Markdown file's folder: relative image references are resolved against it
    /// and inlined as data URIs, since the page is loaded from a string and the
    /// CSP blocks every other image source.
    ///
    /// Kept separate from `page(body:title:typography:)` so a typeface or size
    /// change can re-wrap the same body without reparsing the Markdown.
    static func body(fromMarkdown markdown: String, baseDirectory: URL?) -> String {
        var document = Document(parsing: stripFrontMatter(markdown),
                                options: [.disableSourcePosOpts])
        if let baseDirectory {
            var inliner = ImageInliner(baseDirectory: baseDirectory.standardizedFileURL)
            if let rewritten = inliner.visit(document) as? Document {
                document = rewritten
            }
        }
        return HTMLFormatter.format(document)
    }

    /// Wrap a formatted body in the full page: charset, CSP, and the stylesheet
    /// for the current typography.
    static func page(body: String, title: String, typography: MarkdownTypography) -> String {
        """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" \
        content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <title>\(escape(title))</title>
        <style>\(stylesheet(typography))</style>
        </head><body>
        \(body)
        </body></html>
        """
    }

    // MARK: Front matter

    /// Drop a leading YAML front-matter block (`---` … `---` or `…`), which is
    /// metadata for other tools and reads as a horizontal rule otherwise.
    static func stripFrontMatter(_ text: String) -> String {
        var body = text
        if body.hasPrefix("\u{FEFF}") { body.removeFirst() }
        guard body.hasPrefix("---") else { return body }

        let lines = body.components(separatedBy: "\n")
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == "---" else { return body }
        for index in 1..<lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line == "---" || line == "..." {
                return lines[(index + 1)...].joined(separator: "\n")
            }
        }
        return body
    }

    // MARK: Images

    /// Rewrites relative image sources that point inside the document's own
    /// folder into `data:` URIs. Remote sources are left alone and the CSP then
    /// keeps them from loading, so a render never touches the network.
    private struct ImageInliner: MarkupRewriter {
        let baseDirectory: URL
        /// Refuse to inline anything huge: it would bloat the HTML and stall
        /// the render for no reading benefit.
        static let sizeCap = 8 * 1024 * 1024

        mutating func visitImage(_ image: Image) -> Markup? {
            guard let source = image.source, !source.isEmpty else { return image }
            if let url = URL(string: source), url.scheme != nil { return image }

            let relative = source.removingPercentEncoding ?? source
            let resolved = URL(fileURLWithPath: relative,
                               relativeTo: baseDirectory).standardizedFileURL
            // Stay inside the document's folder; "../../secret.png" is not ours
            // to inline.
            guard resolved.path.hasPrefix(baseDirectory.path + "/") else { return image }

            guard let values = try? resolved.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize, size <= Self.sizeCap,
                  let data = try? Data(contentsOf: resolved),
                  let type = UTType(filenameExtension: resolved.pathExtension),
                  let mime = type.preferredMIMEType
            else { return image }

            var copy = image
            copy.source = "data:\(mime);base64,\(data.base64EncodedString())"
            return copy
        }
    }

    // MARK: Template

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Colours are chosen for how they look *after* the reader's dark-mode
    /// filter (invert + 180° hue = a luminance flip). Near-whites invert to
    /// near-blacks; mid grays invert to mid grays, so the light values here are
    /// deliberately close to white. The blue keeps its hue through the filter.
    private static func stylesheet(_ typography: MarkdownTypography) -> String {
        """
        :root {
          --body-font: \(typography.typeface.cssFontFamily);
          --body-size: \(typography.size)pt;
        }
        html { -webkit-print-color-adjust: exact; }
        body {
          font-family: var(--body-font);
          font-size: var(--body-size);
          line-height: 1.5;
          color: #000;
          margin: 0;
          word-wrap: break-word;
        }
        h1, h2, h3, h4, h5, h6 {
          font-weight: 600;
          line-height: 1.25;
          margin: 14pt 0 6pt;
          break-after: avoid;
          page-break-after: avoid;
          break-inside: avoid;
        }
        /* WebKit ignores break-after: avoid when the next block is itself
           unbreakable, which leaves headings stranded at the foot of a page.
           Giving the heading an invisible tail that is taller than a line, then
           pulling it back with a negative margin, makes the heading box too
           tall to fit there and carries it over with its content. */
        h1::after, h2::after, h3::after, h4::after, h5::after, h6::after {
          content: "";
          display: block;
          height: 72pt;
          margin-bottom: -72pt;
        }
        h1 { font-size: calc(var(--body-size) * 1.8); margin-top: 0; }
        h2 { font-size: calc(var(--body-size) * 1.35); }
        h3 { font-size: calc(var(--body-size) * 1.15); }
        h4, h5, h6 { font-size: var(--body-size); }
        p { margin: 0 0 8pt; orphans: 2; widows: 2; }
        a { color: #0B57D0; text-decoration: none; }
        ul, ol { margin: 0 0 8pt; padding-left: 20pt; }
        li { margin: 0 0 2pt; }
        li > ul, li > ol { margin-top: 2pt; }
        li > ul:last-child, li > ol:last-child { margin-bottom: 0; }
        /* swift-markdown's HTMLFormatter wraps every list item's text in a <p>,
           even in a tight list, so item spacing has to come off the paragraph
           and a task item's text has to be pulled back inline beside its box. */
        li > p { margin: 0 0 2pt; }
        li > p:last-child { margin-bottom: 0; }
        input[type="checkbox"] + p { display: inline; }
        code {
          font-family: ui-monospace, "SF Mono", Menlo, monospace;
          font-size: calc(var(--body-size) * 0.87);
          background: #FAFAFA;
          border: 1px solid #E0E0E0;
          border-radius: 3px;
          padding: 0 2px;
        }
        pre {
          font-family: ui-monospace, "SF Mono", Menlo, monospace;
          font-size: calc(var(--body-size) * 0.82);
          line-height: 1.35;
          background: #FAFAFA;
          border: 1px solid #E0E0E0;
          border-radius: 4px;
          padding: 6pt 8pt;
          margin: 0 0 8pt;
          white-space: pre-wrap;
          overflow-wrap: anywhere;
          break-inside: avoid;
          page-break-inside: avoid;
        }
        pre code { background: none; border: 0; padding: 0; font-size: inherit; }
        blockquote {
          margin: 0 0 8pt;
          padding-left: 10pt;
          border-left: 3px solid #D0D0D0;
          color: #444;
        }
        table {
          border-collapse: collapse;
          font-size: calc(var(--body-size) * 0.91);
          margin: 0 0 8pt;
          width: 100%;
        }
        th, td { border: 1px solid #D0D0D0; padding: 3pt 5pt; text-align: left; vertical-align: top; }
        th { background: #F5F5F5; font-weight: 600; }
        tr { break-inside: avoid; page-break-inside: avoid; }
        img { max-width: 100%; }
        /* Remote images are blocked by the CSP; hide the empty box too. */
        img[src^="http"] { display: none; }
        hr { border: 0; border-top: 1px solid #D0D0D0; margin: 12pt 0; }
        del { text-decoration: line-through; }
        input[type="checkbox"] {
          -webkit-appearance: none;
          appearance: none;
          width: 9pt;
          height: 9pt;
          border: 1px solid #999;
          border-radius: 2px;
          vertical-align: -1px;
          margin: 0 4px 0 0;
        }
        input[type="checkbox"]:checked {
          background: #444;
          border-color: #444;
        }
        li:has(> input[type="checkbox"]) { list-style: none; margin-left: -14pt; }
        """
    }
}
