# Character sheet inspection

2026-09-08T00:45:26Z User requested a much larger character sheet modal, actual-size zoom on open, and Active terminology for the selected sheet. Implement in canonical public source; no inference, data migration, commits, publishing, or pin update.

2026-09-08T00:51:44Z Completed in the canonical public working tree.

- Character image/sheet inspection uses 94% of the active screen's visible width and 90% of its visible height. The original image opens at 100% pixel scale; that mode follows the opening layout and display scale until the user chooses Fit or changes zoom. Fit and Actual size remain explicit controls with shortcuts. Inspection still does not activate a historical sheet or alter artifacts.
- The selected character sheet is labeled ACTIVE in the version strip. Sheet reference tooltips and deletion/replacement wording use active consistently. The phrase current source images describes the live source collection and is separate from the active sheet version.
- Native validation presented the actual SwiftUI sheet via NSHostingController: 1577×972pt content on a 1677×1079pt visible screen, opening pixel scale exactly 1.0. Manual zoom survived layout; Command-0 Fit and Command-1 Actual size both executed and produced the expected scale. A temporary screenshot was saved at /private/tmp/litscenes-character-sheet-inspection.png.
- swift build and all 1,275 existing tests pass. Public source hygiene, private hygiene for both pinned and changed public checkouts, and whitespace checks pass. REUSE CLI remains unavailable. No new repository tests or inference calls were added.

No commits, publishing, installed-app replacement, remote database changes, or private submodule updates. Implementation commit reference is pending explicit authorization.
