# Folio Code Review

## Executive summary

Folio is compact, readable, and currently builds into a valid signed macOS application. The reviewed debug and release builds both passed with warnings treated as errors; the ad hoc application bundle passed strict code-signing verification; and the new icon resources were present, structurally valid, and byte-identical to the copies embedded in the bundle.

I found no confirmed crash or data-loss defect in the ordinary reading path. The two issues I would address first are a credible stale-callback race when one PDF search replaces another, and release automation that can sweep pre-existing version/feed edits into a release and can leave a partially published release after a late failure. The next tier is test coverage, Swift 6 actor-isolation readiness, search-result rendering cost on large documents, and completing the standard Edit menu.

The review produced recommendations only; it did not change application behavior beyond the separately requested icon work.

## Scope and method

The review covered all Swift sources, package metadata, application resources, and the build, icon, and release scripts. I inspected the code paths for document opening, window construction, PDF navigation, search, result highlighting, appearance changes, position persistence, update integration, packaging, signing, and release publication.

Validation performed:

- Debug and release `swift build` runs with warnings promoted to errors: passed.
- Strict-concurrency diagnostic build: completed, with actor-isolation warnings that become errors in Swift 6 language mode.
- `build.sh --adhoc`: passed.
- `codesign --verify --deep --strict`: passed.
- Bundle executable architecture and dynamic-library linkage: valid; the executable is arm64 and Sparkle resolves through `@rpath`.
- Shell syntax checks for the build, release, and icon scripts: passed.
- Icon generator type-check, iconset unpacking, asset-catalog inspection, JSON/XML/plist validation, and source-to-bundle resource hash comparisons: passed.
- `swift test`: no tests ran because the package has no test target.

This was a static and build-level review. It did not include interactive accessibility testing, profiling with a very large PDF, notarization, or a live Sparkle update.

## Prioritized findings

### 1. Rapidly replacing a search can mix callbacks from two queries

**Priority:** High  
**Confidence:** High as a code-level race; runtime reproduction was not attempted.

`startFind` cancels an active `PDFDocument` search, immediately clears the result model, records the new query, and starts another search (`Sources/Folio/ReaderWindowController.swift:486`). The PDF delegate then forwards match and completion callbacks without attaching a query or search-generation identity (`Sources/Folio/FolioDocument.swift:46` and `:54`). Off-main callbacks are queued asynchronously onto the main queue.

That permits a callback already emitted by the cancelled search to arrive after the new search has begun. A stale match can be appended to the new result list, while a stale completion can set `findInProgress` to false and finalize the UI before the replacement search finishes. The short delayed highlight refresh has the same lack of session identity.

**Recommendation:** Give search replacement an explicit state machine. On a query change, cancel the current search, discard its remaining callbacks, wait for its terminal callback, and only then start the pending query. Alternatively, perform a generation-aware search whose callbacks carry an immutable generation identifier and ignore any generation other than the active one. Add a regression test that changes the query repeatedly while matches are still arriving.

### 2. Release publication is not sufficiently transactional

**Priority:** High  
**Confidence:** High; this follows directly from the script.

The cleanliness check deliberately excludes `Support/Info.plist` and `appcast.xml` (`release.sh:35`). Those are exactly the files later staged wholesale and committed (`release.sh:95`). A pre-existing manual edit in either file can therefore be silently included in a release commit.

The script also does not verify before mutation that local `main` equals `origin/main`, GitHub authentication is usable, the intended version is newer than the current one, or the eventual pushes are accepted. Publication then crosses several independently failing steps: push tag, create GitHub release, and push `main` (`release.sh:98`–`:105`). A failure after the tag push can leave an orphaned tag or a release with a stale appcast; the existing-tag guard then prevents a simple rerun.

**Recommendation:** Require a completely clean tree, fetch and verify `main == origin/main`, validate credentials and version monotonicity, and perform a dry-run push before changing files. Record release phases so a failed run can resume safely, and document exact recovery steps for each partially published state. Before committing, verify that the only generated diff is the expected version/build-number and appcast entry.

### 3. There is no automated test target or continuous-integration gate

**Priority:** Medium  
**Confidence:** Confirmed.

`swift test` exits because no tests exist, and the repository has no CI workflow. The most stateful logic—search cancellation and navigation, wraparound math, position serialization and eviction, window-frame parsing, position restoration, and release preflights—is therefore guarded only by manual testing.

**Recommendation:** Start with small deterministic units rather than UI automation: extract a search-session model, page/match navigation, position storage, and release preflight rules into testable components. Add a macOS CI job that runs the unit tests, warnings-as-errors debug and release builds, shell syntax checks, and an ad hoc bundle/signature check. Add focused UI tests later for document opening, page restoration, find replacement, menus, appearance changes, and multiple windows.

### 4. Swift 6 actor-isolation errors are accumulating behind Swift 5 mode

**Priority:** Medium  
**Confidence:** Confirmed by the strict-concurrency build.

The current package builds cleanly in its configured language mode, but strict concurrency reports UI isolation and `Sendable` problems in `AppDelegate`, `MainMenu`, `Prefs`, `FolioDocument`, `ReaderPage`, and `ReaderWindowController`. Representative cases include accessing `NSApp` through a nonisolated preference setter, constructing UI-owned updater state outside an explicitly main-actor context, crossing actor boundaries through `PDFDocumentDelegate` and `FindSink`, and using a global raw-pointer key in the page-rendering path.

These diagnostics are warnings today but are errors under Swift 6 language mode.

**Recommendation:** Mark UI construction and state owners `@MainActor`. Treat PDFKit delegate delivery as an explicit boundary: use `nonisolated` callbacks only where required, capture safe immutable values, and marshal them to the main actor deliberately. Audit the `ReaderPage` associated-object mechanism separately because it sits on PDFKit's rendering boundary. Avoid blanket `@unchecked Sendable` annotations unless an invariant is documented and tested.

### 5. Incremental search updates repeatedly rebuild all highlight geometry

**Priority:** Medium  
**Confidence:** High for the algorithmic cost; user-visible impact needs profiling.

Search matches are batched roughly every 150 ms (`Sources/Folio/ReaderWindowController.swift:503`). Each batch replaces the complete match array, rebuilds line rectangles for every match, refreshes every previously or currently affected page, and forces `layoutDocumentView()` (`Sources/Folio/ReaderViewController.swift:37`–`:98`). As a result, a common search term in a long PDF can repeatedly rescan a growing result set and invalidate many pages, approaching quadratic aggregate work.

**Recommendation:** Append geometry only for newly received matches, track newly dirty pages, and separate “current match changed” invalidation from “new result arrived” invalidation. Coalesce display work without relaying out the entire document view on every batch. Profile with a large, text-heavy PDF and a deliberately common query before and after the change.

### 6. The Edit menu omits standard editing commands

**Priority:** Medium  
**Confidence:** Confirmed.

The Edit menu provides Copy, Select All, and Find commands, but no Undo, Redo, Cut, or Paste (`Sources/Folio/MainMenu.swift:95`). Folio contains editable search and page-number fields, so the omission reduces discoverability, menu-based operation, and accessibility even where AppKit text bindings may still handle familiar keyboard shortcuts.

**Recommendation:** Add the conventional AppKit Edit menu items with nil targets so the responder chain supplies the appropriate implementation, including Undo, Redo, Cut, Copy, Paste, Delete, and Select All. Verify enablement and VoiceOver announcements while focus is in each editable control and in the PDF view.

### 7. Reading-position identity and eviction are fragile

**Priority:** Low to medium  
**Confidence:** Confirmed.

Positions are keyed by the raw file path, so moving a PDF or reaching it through a different symlink creates a new history entry (`Sources/Folio/Prefs.swift:56`). Once the table exceeds 500 entries, arbitrary dictionary keys are removed rather than the least recently used entries (`Sources/Folio/Prefs.swift:65`). Property-list dictionary ordering is not a recency guarantee, so a recently used position can be discarded.

There is also a small restoration edge case: a saved position on page zero is ignored when `y == 0`, even if `x` is nonzero (`Sources/Folio/ReaderWindowController.swift:721`).

**Recommendation:** Store a canonical file identity—preferably a resource identifier or security-scoped bookmark as appropriate—plus `lastAccessed`, and evict deterministically by oldest access. Make the restore-validity condition consider all coordinates or store an explicit “has saved position” record.

### 8. The default monitor choice is personalized rather than application-neutral

**Priority:** Low  
**Confidence:** Confirmed.

On first launch, Folio chooses the widest landscape display, with an inline comment tied to one specific workstation (`Sources/Folio/ReaderWindowController.swift:160`). On another multi-display setup this can open a document on a secondary screen rather than the screen containing the active app or pointer.

**Recommendation:** Prefer the screen of the key/main window, then `NSScreen.main`, and use a widest-landscape policy only as an explicit preference. Remove personal-machine assumptions from production comments.

### 9. Shared mutable Core Image filter objects should be instance-scoped

**Priority:** Low  
**Confidence:** Moderate; no visible failure was reproduced.

`ReaderViewController.invertFilters` stores shared `CIFilter` instances in a static array (`Sources/Folio/ReaderViewController.swift:135`). The same mutable objects can then be installed on multiple views and windows. Core Image filters are mutable and not `Sendable`; sharing them across independent view/layer rendering lifecycles is unnecessary risk.

**Recommendation:** Replace the static instances with a factory that creates a fresh invert/hue pair for each consuming view or window. Keep filter configuration immutable after installation.

### 10. Build-script flag parsing accepts mistakes silently

**Priority:** Low  
**Confidence:** Confirmed.

The argument `case` in `build.sh` has no unknown-option branch (`build.sh:9`). A typo such as `--adhooc` is ignored and can cause a different, potentially credential-using build path than intended. Conflicting modes such as `--debug --notarize` are also accepted without an explicit policy.

**Recommendation:** Reject every unknown argument, validate incompatible combinations, initialize every option before parsing, and print the resolved build mode before doing work.

### 11. Search controls stay disabled while useful results are already visible

**Priority:** Low  
**Confidence:** Confirmed.

The toolbar's next/previous control is disabled at search start and is re-enabled only after the document search ends (`Sources/Folio/ReaderWindowController.swift:490` and `:542`). The first match is displayed immediately, but the visible toolbar arrows remain unavailable throughout a long-running search.

**Recommendation:** Enable navigation when the first match arrives and define sensible wrap behavior over the results discovered so far. Keep the running-count state visually distinct from the completed result count.

### 12. Distribution and containment choices should be made explicit

**Priority:** Product decision  
**Confidence:** Confirmed configuration.

The built executable is arm64-only. That is appropriate if Folio intentionally supports only Apple Silicon; otherwise it excludes Intel Macs. The application is also unsandboxed, which simplifies arbitrary PDF access and Sparkle updating but gives PDFKit processing of untrusted documents the application's full user-level authority.

**Recommendation:** Document Apple Silicon as an explicit system requirement or build a universal binary. Separately evaluate App Sandbox adoption as a security-hardening project, including security-scoped file access and the chosen Sparkle integration; this is an architectural tradeoff rather than a quick flag change.

## Maintainability observations

`ReaderWindowController` is now responsible for window construction, toolbar composition, search state, appearance coordination, page navigation, tab behavior, and position persistence. At roughly 750 lines it remains understandable, but the search/session logic and position store have enough state to justify their own types. Extract those pieces after tests are in place; splitting first would make the existing search race harder to validate.

The strongest parts of the implementation are its small dependency surface, clear ownership of the read-only document model, disciplined responder-chain menu targets, careful restoration after PDF layout, explicit handling of appearance changes, and direct source-driven icon generation. The build script also assembles and verifies a conventional app bundle without hiding the steps behind a large project file.

The generated icon pipeline is now deterministic at the design-source level: light and dark 1024-pixel masters feed the modern asset catalog and legacy `.icns`. Asset-catalog compilation may embed toolchain metadata, so byte-for-byte reproducibility of `Assets.car` across Xcode versions should not be assumed; source masters and the generator should remain the reviewable canonical inputs.

## Suggested implementation order

1. Fix search replacement semantics and cover them with unit tests.
2. Harden and make the release workflow resumable before the next public release.
3. Add the initial test target and CI gate, including the current clean build/package checks.
4. Resolve strict-concurrency diagnostics in bounded slices, beginning with main-actor UI ownership and the PDF delegate boundary.
5. Profile and incrementally update search highlights.
6. Complete the standard Edit menu and perform keyboard/VoiceOver checks.
7. Improve position identity/eviction and default-screen selection.
8. Make explicit product decisions on Intel support and sandboxing.

## Verification limits

The review did not run a notarized distribution build because that would require release credentials and an external Apple submission. It did not publish or consume a Sparkle update, exercise every command through the live macOS UI, run VoiceOver, or benchmark search on a pathological document. Findings described as risks rather than confirmed failures should be reproduced or measured before assigning release severity.

Topic: Folio code review
Date: 2026-09-04
By: Codex-GPT-5
Production details: tokens unavailable (runtime did not expose exact usage); elapsed time: 11 minutes 24 seconds; subagents: none; validation included source review, warnings-as-errors debug and release builds, strict-concurrency diagnostics, ad hoc application packaging, code-signature verification, resource/hash inspection, and icon-format validation; limits: no interactive UI, notarization, live Sparkle update, VoiceOver session, or large-document performance benchmark.
