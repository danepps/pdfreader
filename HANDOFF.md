# Folio — Handoff

_Last updated 2026-09-04. Repo: https://github.com/danepps/pdfreader (public
since v1.0.0, MIT; see "Signing,
notarization, updates")._

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

- `main` has the scaffold, the full UI, and (2026-09-04) window sizing,
  Developer ID signing/notarization, and Sparkle. Clean release build, zero
  warnings. Runtime-tested: open/tabs, dark inversion, black chrome, green
  highlights, hit counter, arrow paging, position memory, no crashes.
- Window sizing (2026-09-04): installing the split view controller as
  `contentViewController` shrinks the window to its fitting size (320×0), so
  the frame is set *after* that in `sizeWindowInitially`. A saved frame is
  vetted before restore (an early build autosaved the collapsed one) and
  `setFrameAutosaveName` is called last because it restores too. First launch
  centres on the widest landscape display. No `preferredContentSize`: the
  window snaps back to it and that broke macOS window tiling.
- Not yet exercised: an actual Sparkle update (needs two published releases).
- Not runtime-verified: dark mode at the very last page of a document (the
  bottom-band fix was checked mid-document); the light-mode icon variant
  (would have required toggling Dan's system appearance); Page Up/Down and
  Space paging (left to PDFView's defaults, code-checked only).

## Build, run, test

```sh
./build.sh --run           # release build + launch (run from repo root)
./build.sh --debug         # debug config
./build.sh --adhoc         # skip Developer ID signing (offline, no keychain)
./scripts/make-icon.sh     # regenerate icon assets
./release.sh 1.0.1         # cut a release (see "Signing, notarization, updates")
```

- Repo lives at `~/ClaudeCode/pdf` on one of Dan's machines and `~/ClaudeCode/pdfreader` on the other; use absolute paths from whichever root you're in.
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
| `AppDelegate.swift` | Installs the menu, applies saved appearance override, shows Open panel on launch/no windows, appearance & invert menu actions. Owns the Sparkle `SPUStandardUpdaterController` (started eagerly, so the scheduled background check runs). |
| `MainMenu.swift` | Entire menu bar in code. Nil-target actions ride the responder chain (`zoomIn:`, `goToNextPage:` etc. are PDFView's). "Open Recent" is just a submenu with a `clearRecentDocuments:` item; AppKit fills it. "Check for Updates…" is the one item with an explicit target — Sparkle's updater controller isn't in the responder chain, so it's passed in from the app delegate. |
| `FolioDocument.swift` | `NSDocument` (ObjC name `FolioDocument`, referenced from Info.plist) wrapping `PDFDocument`. `PDFDocumentDelegate`: returns `ReaderPage` for pages, forwards find callbacks to the window controller via `FindSink`. |
| `ReaderWindowController.swift` | Window, `NSSplitViewController` (sidebar + reader), unified toolbar, page indicator, search field + hit counter + previous/next match segmented control (⇧⌘G/⌘G equivalents), tabs, reading-position memory, black chrome in dark mode. |
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
- **Find highlights in dark mode are custom-drawn** in `ReaderPage.draw`: a
  translucent box (pre-filter green `(0, 0.77, 0)` at 0.35 alpha, which the
  filter turns into a dark-green box with pale-green glyphs), rect inset 1pt
  vertically so neighbouring ascenders/descenders aren't covered; the current
  match adds a 1.5pt solid outline *inside* its rect. An outline drawn
  *outside* the rect produced dark streaks across adjacent lines. An earlier
  version recoloured the glyphs with `.screen` blend plus an underline; Dan
  asked for boxes (2026-09-04). Light mode uses native
  `highlightedSelections` in systemGreen.
- **Native `NSWindow` tabbing** (`tabbingMode = .preferred`, identifier
  `FolioReader`, explicit `addTabbedWindow` in `showWindow`) rather than a
  custom tab bar. `newWindowForTab:` in the responder chain gives the "+"
  button and ⌘T.
- **Page indicator** is one attributed label ("4 of 30") that swaps to an
  editable field on click/⌥⌘G. Two-control versions were never centered.
- **Hit counter** is a separate toolbar item after the search field,
  centered, `visibilityPriority = .high`; search field 180pt so nothing
  overflows at the default width. The previous/next segmented control sits
  after it (also `.high`), disabled until a search has matches.

## Signing, notarization, updates

Folio ships signed, notarized, and self-updating via **Sparkle 2** (SwiftPM
dependency, currently 2.9.6).

- `./build.sh` signs with **Developer ID Application: Daniel Epps
  (82H77TF7AH)**, hardened runtime, secure timestamp, and ends with
  `codesign --verify --deep --strict`.
- `./build.sh --adhoc` signs ad-hoc instead: no certificate, no network. This
  is the flag for day-to-day work; everything below is only needed to ship.
- `./build.sh --notarize` additionally zips, submits with `xcrun notarytool
  --keychain-profile notary --wait`, staples, and runs `spctl`. Takes a few
  minutes. Without it `spctl` reports "Unnotarized Developer ID", which is
  expected on a plain build.

**Three secrets, all on this Mac's login keychain and nowhere else:** the
Developer ID Application certificate + private key, the `notary` notarytool
credential profile, and the Sparkle **EdDSA private key** (account `ed25519`,
created by Sparkle's `generate_keys`). The matching public key is checked into
`Support/Info.plist` as `SUPublicEDKey`
(`xkEJ4pttphM6v/lHQQ4mbSe9JHQZFe1eOefG26iqyWU=`) and must never be
regenerated — doing so orphans every already-installed copy of Folio.

**Feed URL:** `https://raw.githubusercontent.com/danepps/pdfreader/main/appcast.xml`
(`SUFeedURL`). `appcast.xml` lives at the repo root and is generated, not
hand-written — its entries carry EdDSA signatures that any manual edit breaks.
**The GitHub repo must be public**: the feed points at release *assets*
(`https://github.com/danepps/pdfreader/releases/download/v<version>/…`), and
GitHub release assets on a private repo need an auth token Sparkle won't send.

**`./release.sh <version> [notes]`** does the whole release: refuses to run off
`main` or with a dirty tree, sets `CFBundleShortVersionString` and bumps
`CFBundleVersion` (an integer, monotonic — it's what Sparkle actually compares),
runs `build.sh --notarize`, writes `build/releases/Folio-<version>.zip`, stages
that zip beside a copy of the live `appcast.xml` and runs Sparkle's
`generate_appcast` over the staging directory so new entries merge into the old
ones, copies the feed back, then commits, tags `v<version>`, pushes the tag,
runs `gh release create` (so the asset exists), and only then pushes `main`
(which is what makes the feed live). Don't hand-run the pieces; the appcast
signature and the download URL prefix have to agree with the tag.

### Setting up the MacBook

The other Mac (repo at `~/ClaudeCode/pdf`) can build and run Folio today;
these steps are only for cutting *signed, notarized* releases there.

1. `git pull`; Xcode 26 / Swift 6.3 installed; `gh auth status` shows you
   logged in. **`./build.sh --adhoc` needs none of steps 2–5** — that's the
   normal development path and it works out of the box.
2. **Developer ID certificate.** On *this* Mac: Keychain Access → My
   Certificates → "Developer ID Application: Daniel Epps (82H77TF7AH)" →
   right-click → Export as `.p12` with a password. AirDrop it; don't email it.
   On the MacBook double-click the `.p12` to import into the login keychain,
   then confirm: `security find-identity -v -p codesigning` must list exactly
   that identity as valid.
3. **If step 2 reports "0 valid identities"**, Apple's current intermediates
   are missing (this Mac was missing them too until Xcode installed them).
   Download and double-click
   <https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer> and
   <https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer>, then
   re-run the `find-identity` check.
4. **Notarization profile.** Create an app-specific password at
   account.apple.com → Sign-In and Security, then:
   `xcrun notarytool store-credentials notary --apple-id dsepps@gmail.com --team-id 82H77TF7AH --password <app-specific password>`.
   Pass `--password` inline: the interactive prompt does not work from the
   Claude Code `!` shell. Afterwards scrub it from history with
   `LC_ALL=C sed -i '' '/notarytool store-credentials/d' ~/.zsh_history`.
   Verify: `xcrun notarytool history --keychain-profile notary`.
5. **Sparkle EdDSA key.** The artifact path only exists after a first
   `./build.sh` has resolved the package. On this Mac:
   `~/ClaudeCode/pdfreader/.build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/folio_eddsa_key`.
   Transfer privately, then on the MacBook:
   `~/ClaudeCode/pdf/.build/artifacts/sparkle/Sparkle/bin/generate_keys -f ~/folio_eddsa_key`
   and delete the file on both machines. Do **not** run bare `generate_keys`
   there — it would mint a second key that no shipped app trusts.
6. **End to end:** `./build.sh --notarize` should finish with `accepted` and
   `source=Notarized Developer ID`.

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
- **`swift build` embeds nothing.** Xcode copies a SwiftPM binary target's
  framework into the bundle; `swift build` only links against it. So the
  target carries an explicit `-rpath @executable_path/../Frameworks` in
  `linkerSettings`, and `build.sh` `ditto`s `Sparkle.framework` out of
  `.build/artifacts/*/Sparkle/Sparkle.xcframework/macos-*/` into
  `Contents/Frameworks`. Without both halves the app dies at launch in dyld.
- **Sparkle.framework has to be signed inside out, before the app.** It is a
  bundle of bundles (`Autoupdate`, `Updater.app`, `XPCServices/*.xpc` under
  `Versions/B`); signing only the outer app leaves them with Sparkle's own
  signature and `codesign --verify --deep --strict` fails. Order and flags in
  `build.sh` follow <https://sparkle-project.org/documentation/sandboxing/>,
  including `--preserve-metadata=entitlements` on `Downloader.xpc`. Sparkle
  explicitly warns *against* `--deep` when signing the app itself.
- `swift build` produces an **arm64-only** binary, so `generate_appcast`
  stamps items with `<sparkle:hardwareRequirements>arm64</…>` and Intel Macs
  will never be offered the update. Fine today; would need a lipo'd universal
  binary in `build.sh` to change.
- XML comments cannot contain `--`. The hand-written `appcast.xml` skeleton
  tripped `generate_appcast`'s parser on exactly that.

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

- Sidebar is thumbnails only; an outline (table of contents) pane would be
  the obvious next sidebar mode (`PDFDocument.outlineRoot`).
- No annotation/highlighting tools; no text-copy cleanup (line-break
  stripping); no per-document invert override (global toggle only).
- Photos/figures render as luminance-inverted in dark mode; a per-image
  "don't invert" would need per-tile work and likely isn't worth it.
