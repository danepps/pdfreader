# Folio

A small, fast, native macOS PDF reader. Swift + AppKit + PDFKit, no Electron, no
web view, no storyboards. Built because PDF Expert got slow.

- **Dark mode that inverts the page.** Follows the system appearance; in dark
  mode the PDF content itself renders light-on-dark, not just the window chrome.
  Toggle with View ▸ Invert Page Colors in Dark Mode, or force Light/Dark under
  View ▸ Appearance.
- **One window, native tabs.** Every PDF opens as a tab (⌘T opens another,
  ⇧⌘[ / ⇧⌘] switch, drag tabs out to split).
- **Zippy.** Renders through PDFKit, the same engine as Preview. Launches cold in
  well under a second.
- **Remembers where you were** in each file.
- Thumbnail sidebar (⌃⌘S), find with highlights (⌘F, ⌘G / ⇧⌘G), go to page
  (⌥⌘G), zoom (⌘= / ⌘- / ⌘0 fit / ⌘1 actual), back/forward (⌘[ / ⌘]), print.

## Build

Requires Xcode (or the command-line tools with a Swift 5.9+ toolchain) on
macOS 14 or later.

```sh
./build.sh          # builds build/Folio.app
./build.sh --run    # builds and launches
./build.sh --debug  # debug configuration
```

Drag `build/Folio.app` to `/Applications` if you want it in Launchpad, then
right-click a PDF ▸ Get Info ▸ Open With to make it the default.

## Layout

```
Package.swift                 Swift Package (single executable target)
Support/Info.plist            bundle metadata, PDF document type
Support/Folio.icns            app icon (regenerate with scripts/make-icon.sh)
build.sh                      assembles the .app bundle
Sources/Folio/
  main.swift                  NSApplication bootstrap
  AppDelegate.swift           launch behavior, appearance menu actions
  MainMenu.swift              menu bar, built in code
  FolioDocument.swift         NSDocument wrapper around PDFDocument
  ReaderWindowController.swift  window, toolbar, tabs, find, page field
  ReaderViewController.swift  the PDFView and dark-mode handling
  SidebarViewController.swift thumbnail sidebar
  ReaderPage.swift            PDFPage subclass that inverts page colors
  Prefs.swift                 UserDefaults-backed settings and reading positions
```

## How the dark-mode inversion works

`ReaderPage` overrides `draw(with:to:)`: it paints opaque white paper, draws the
page normally, then fills the page with a light gray using the `.difference`
blend mode. White paper becomes near-black and black ink becomes light gray, in
a single blend pass per tile, so it costs nothing noticeable. Colored content is
complemented (blue links turn orange-ish; photos look like negatives), which is
why the toggle exists.
