# Folio

A small, fast, native macOS PDF reader that also opens Markdown. Swift + AppKit
+ PDFKit, no Electron, no storyboards; WebKit is used only offscreen, to typeset
Markdown into pages. Built because PDF Expert got slow.

- **Dark mode that inverts the page.** Follows the system appearance; in dark
  mode the PDF content itself renders light-on-dark, not just the window chrome.
  Toggle with View ▸ Invert Page Colors in Dark Mode, or force Light/Dark under
  View ▸ Appearance.
- **Opens Markdown too.** A `.md` file is typeset into real pages and shown
  through the same reader, so tabs, dark mode, find, paging, and position memory
  all work on it. It re-renders within about half a second whenever the file
  changes on disk, keeping your place. Pick the body typeface and size under
  View ▸ Markdown; export the rendered pages with ⇧⌘E.
- **One window, native tabs.** Every PDF opens as a tab (⌘T opens another,
  ⇧⌘[ / ⇧⌘] switch, drag tabs out to split).
- **Zippy.** Renders through PDFKit, the same engine as Preview. Launches cold in
  well under a second.
- **Remembers where you were** in each file.
- Arrow keys always page: ↑/← previous, ↓/→ next, ⌘↑/⌘↓ first/last.
- Thumbnail sidebar (⌃⌘S), find with a hit counter and green highlights (⌘F,
  ⌘G / ⇧⌘G), go to page (⌥⌘G), zoom (⌘= / ⌘- / ⌘0 fit / ⌘1 actual),
  back/forward (⌘[ / ⌘]), print, export as PDF (⇧⌘E).

## Build

Requires Xcode (or the command-line tools with a Swift 5.9+ toolchain) on
macOS 14 or later, Apple Silicon only (the build is arm64; a universal binary would need `lipo` in `build.sh`).

```sh
./build.sh          # builds build/Folio.app
./build.sh --run    # builds and launches
./build.sh --debug  # debug configuration
```

Drag `build/Folio.app` to `/Applications` if you want it in Launchpad, then
right-click a PDF ▸ Get Info ▸ Open With to make it the default. For Markdown
there is a menu item: Folio ▸ Use Folio to Open Markdown Files.

Dependencies are Sparkle and [swift-markdown][], which is pinned by commit
because its own manifest depends on swift-cmark by branch and SwiftPM will not
accept a version range on top of that.

[swift-markdown]: https://github.com/swiftlang/swift-markdown

## Layout

```
Package.swift                 Swift Package (single executable target)
Support/Info.plist            bundle metadata, PDF document type
Support/Folio.icon, .icns, Assets.car   app icon sources and compiled variants
build.sh                      assembles the .app bundle
Sources/Folio/
  main.swift                  NSApplication bootstrap
  AppDelegate.swift           launch behavior, appearance menu actions
  MainMenu.swift              menu bar, built in code
  FolioDocument.swift         NSDocument wrapper around PDFDocument (PDF or Markdown)
  MarkdownHTML.swift          Markdown -> HTML + the print stylesheet
  MarkdownRenderer.swift      offscreen WKWebView that typesets HTML into a PDF
  FileWatcher.swift           vnode watcher behind Markdown auto-refresh
  ReaderWindowController.swift  window, toolbar, tabs, find, page field
  ReaderViewController.swift  the PDFView and dark-mode handling
  SidebarViewController.swift thumbnail sidebar
  ReaderPage.swift            PDFPage subclass that draws dark-mode find highlights
  Prefs.swift                 UserDefaults-backed settings and reading positions
```

## How the dark-mode inversion works

The PDF view gets two Core Image filters on its layer: `CIColorInvert` followed
by a 180° `CIHueAdjust`. Together they flip luminance while preserving hue, so
white paper becomes black, black text becomes white, and blue links stay blue.
The GPU applies the filters at composite time, so there is no white flash while
tiles render, appearance changes are instant, and printing is untouched. The
thumbnail sidebar gets the same filters. Colors that must look right *after*
the filter (the page gutter, the green find highlights) are chosen pre-filter.

Find highlights in dark mode are drawn by `ReaderPage` (a `PDFPage` subclass)
with a `.screen` blend over each match, which recolors only the glyphs.

## How Markdown viewing works

A Markdown file is parsed with Apple's [swift-markdown][] and formatted to HTML,
then loaded into a `WKWebView` that lives in a window which is never shown. The
web view is printed to a temporary PDF with `NSPrintOperation`, and that
`PDFDocument` is handed to the normal reader. Nothing on screen is ever a web
view; WebKit is only the typesetter, and it is what gives us real page breaks,
selectable text, and clickable link annotations.

Two details matter. The print has to run through
`runModal(for:delegate:didRun:contextInfo:)` with `canSpawnSeparateThread` set:
WebKit computes its page range only on a secondary print thread, and
`NSPrintOperation.run()` never spawns one, which is the usual cause of blank
output. And margins come from `NSPrintInfo`, not from an `@page` rule, because
WebKit subtracts the print info's margins itself and setting both doubles them.

## Icon

`Support/Folio.icon` is an Icon Composer package with light and dark
appearances, compiled by `scripts/make-icon.sh` into `Support/Assets.car`
(macOS 26 uses it via `CFBundleIconName`). The same script renders
`Support/Folio.icns` as the fallback for macOS 14 and 15.

## License

MIT. See [LICENSE](LICENSE).
