# Folio — Handoff

_Last updated 2026-09-03. Repo: https://github.com/danepps/pdfreader (private)._

## What this is

Folio is Dan Epps's from-scratch native macOS PDF reader, built because PDF
Expert got slow. Swift + AppKit + PDFKit. No Electron, no storyboards, no
Xcode project: a Swift Package plus `build.sh`, which assembles
`build/Folio.app`. Deployment target macOS 14; developed and tested on
macOS 26 (Tahoe) with Swift 6.3 / Xcode 26.

Dan's stated requirements, all met as of this handoff:

- Simple, really clean Mac interface, zippy.
- One window, tabs.
- Dark mode tied to system settings, and the **PDF content itself**
  white-on-black in dark mode (not just the chrome). Chrome should be pure
  black, not gray.
- Arrow keys always move by page (↑/← prev, ↓/→ next; ⌘↑/⌘↓ first/last).
- Search shows a hit count; matches are bright green (#5CF25C-ish), current
  match underlined.
- Dark-mode variant of the app icon.

## State

- `main` has two commits (scaffold; full UI). Clean release build, zero
  warnings. Runtime-tested: open/tabs, dark inversion, black chrome, green
  highlights, hit counter, arrow paging, position memory, no crashes.
- Not runtime-verified: dark mode at the very last page of a document (the
  bottom-band fix was checked mid-document); the light-mode icon variant
  (would have required toggling Dan's system appearance); Page Up/Down and
  Space paging (left to PDFView's defaults, code-checked only).

## Build, run, test

```sh
/Users/dan/ClaudeCode/pdf/build.sh --run     # release build + launch
/Users/dan/ClaudeCode/pdf/build.sh --debug   # debug config
/Users/dan/ClaudeCode/pdf/scripts/make-icon.sh   # regenerate icon assets
```

- Always run the `.app`, never the bare binary: NSDocument needs Info.plist.
- Force dark/light without touching system settings:
  `defaults write com.epps.Folio appearance -int 2` (0 system, 1 light,
  2 dark), relaunch, then set back to 0.
- `screencapture -x /abs/path.png` works on this machine for visual checks;
  crop with `sips -c`. GUI keystroke automation via System Events is flaky
  (keystrokes can land in other apps); guard on Folio being frontmost.
- Test PDFs the agents used live in the session scratchpad and are gone;
  Dan has plenty in ~/Downloads (SCOTUS slip opinions are good: color,
  small caps, lots of matches).

## Architecture (Sources/Folio)

| File | Role |
|---|---|
| `main.swift` | NSApplication bootstrap, sets `AppDelegate`. |
| `AppDelegate.swift` | Installs the menu, applies saved appearance override, shows Open panel on launch/no windows, appearance & invert menu actions. |
| `MainMenu.swift` | Entire menu bar in code. Nil-target actions ride the responder chain (`zoomIn:`, `goToNextPage:` etc. are PDFView's). "Open Recent" is just a submenu with a `clearRecentDocuments:` item; AppKit fills it. |
| `FolioDocument.swift` | `NSDocument` (ObjC name `FolioDocument`, referenced from Info.plist) wrapping `PDFDocument`. `PDFDocumentDelegate`: returns `ReaderPage` for pages, forwards find callbacks to the window controller via `FindSink`. |
| `ReaderWindowController.swift` | Window, `NSSplitViewController` (sidebar + reader), unified toolbar, page indicator, search field + hit counter, tabs, reading-position memory, black chrome in dark mode. |
| `ReaderViewController.swift` | `ReaderPDFView` (PDFView subclass: arrow-key paging, per-page highlight bookkeeping), appearance routine that installs the inversion filters. |
| `SidebarViewController.swift` | `PDFThumbnailView`, mirrors the inversion filters. |
| `ReaderPage.swift` | `PDFPage` subclass; draws dark-mode find highlights. |
| `Prefs.swift` | UserDefaults: invert toggle, appearance override, per-file last position. |

Support/: `Info.plist`, `Folio.icon` (Icon Composer package, light+dark),
`Assets.car` (compiled from it), `Folio.icns` (fallback). scripts/:
`make-icon.swift` renders both variants, `make-icon.sh` builds icns +
`.icon` + runs `actool`.

## Design decisions and why

- **Inversion is a layer filter, not page drawing.** `pdfView.contentFilters
  = [CIColorInvert, CIHueAdjust(π)]` (same on the thumbnail view). Invert +
  180° hue = luminance flip with hue preserved, so links stay blue. The GPU
  applies it at composite time: no white flash while tiles render (PDFKit
  paints a white placeholder that page-level inversion can't touch), instant
  appearance switches, printing unaffected. The first attempt (a
  `.difference` fill inside `PDFPage.draw`) had the flash; it's in the
  scaffold commit if ever needed.
- **Consequence: pre-filter colors.** Anything inside the filtered view must
  be chosen for how it looks *after* the filter. Gutter is white 0.997
  pre-filter (CIColorInvert works in linear light, so 0.89 came out
  mid-gray). Green highlight ink is `(0, 0.77, 0)` pre-filter, calibrated by
  pixel-sampling screenshots to ~#69E170 on screen; the analytic value
  clips. Formula: same chroma, luminance 1−Y.
- **No `.fullSizeContentView`.** macOS 26 Liquid Glass toolbar/tab bar tint
  from the content beneath them and they sample the PDF view's *pre-filter*
  colors, so with content under the toolbar the chrome went light gray and a
  cloudy gradient (scroll edge effect) appeared. Content now stops below the
  toolbar. In dark mode the window also gets `titlebarAppearsTransparent`,
  `backgroundColor = .black`, `titlebarSeparatorStyle = .none` to make the
  chrome solid black.
- **`pageShadowsEnabled = false` when inverted.** Inverted drop shadows
  showed as bright halos and a light band at the bottom of the view.
- **Find highlights in dark mode are custom-drawn** in `ReaderPage.draw`
  with `.screen` blend (recolors glyphs only, paper untouched), rect inset
  1pt vertically so neighbouring ascenders/descenders aren't tinted; current
  match gets a 2pt underline inside its rect. An outline drawn *outside* the
  rect produced dark streaks across adjacent lines. Light mode uses native
  `highlightedSelections` in systemGreen.
- **Native `NSWindow` tabbing** (`tabbingMode = .preferred`, identifier
  `FolioReader`, explicit `addTabbedWindow` in `showWindow`) rather than a
  custom tab bar. `newWindowForTab:` in the responder chain gives the "+"
  button and ⌘T.
- **Page indicator** is one attributed label ("4 of 30") that swaps to an
  editable field on click/⌥⌘G. Two-control versions were never centered.
- **Hit counter** is a separate toolbar item after the search field,
  centered, `visibilityPriority = .high`; search field 180pt so nothing
  overflows at the default width.

## Gotchas learned the hard way

- **Never add Swift stored properties to a `PDFPage` subclass.** PDFKit
  allocates pages through a private initializer that skips Swift ivar
  setup; the property reads as garbage on the tile thread and crashes
  (`EXC_BAD_ACCESS` in `draw`). `ReaderPage` keeps state in an ObjC
  associated object holding an immutable box.
- `annotationsChanged(on:)` alone does not drop an already-rendered tile;
  follow it with `layoutDocumentView()` + `needsDisplay`.
- `.PDFViewPageChanged` fires during initial layout reporting page 1, which
  clobbered the saved reading position. Position is read once in init and
  saving is gated until the restore has run.
- `sidebarItem.isCollapsed = true` doesn't survive `addTabbedWindow`;
  re-assert after tabbing and once in `windowDidBecomeKey`.
- `actool` compiling a `.icon` package is undocumented by Apple (works via
  `man actool` + experiment). `actool` writes `Assets.car` even on error, so
  `make-icon.sh` greps its output for `error:` before installing. Valid
  `appearance` values in `icon.json` are only `light`, `dark`, `tinted`.
- No public scroll-edge-effect API on `NSScrollView` in the 26.0 SDK.

## Working conventions for this repo

- Dan wants Fable to **plan and review, and delegate implementation to Opus
  subagents** to conserve his usage. Spawn `general-purpose` agents with
  `model: "opus"` and a file-by-file spec; queue follow-ups with SendMessage.
- **Never `cd` in Bash**; absolute paths only (his permission rules depend on
  it). Scratch files go in the session scratchpad, not the repo.
- Repo git email is set locally to dsepps@gmail.com (global is a
  placeholder). Commit/push only when he asks; he has asked for pushes here.
- App name "Folio" and bundle id `com.epps.Folio` were my picks; rename is
  a find-and-replace plus `Support/Info.plist` and the icon script.

## Known quirks / candidates for next work

- Current-match underline sits at the line-box bottom and crosses
  descenders; could key off the baseline or drop 2pt.
- Sidebar is thumbnails only; an outline (table of contents) pane would be
  the obvious next sidebar mode (`PDFDocument.outlineRoot`).
- No annotation/highlighting tools; no text-copy cleanup (line-break
  stripping); no per-document invert override (global toggle only).
- Photos/figures render as luminance-inverted in dark mode; a per-image
  "don't invert" would need per-tile work and likely isn't worth it.
