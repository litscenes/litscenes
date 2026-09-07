# Shot editor across entry paths

Approved plan: show what is in the Shot, which segment is being edited, and what the next action changes in the existing player/timeline/right editor.

- First-render inputs remain editable; completed originals, continuations, endings, imported footage, branch/combined seeds, and flattened saved outputs remain visible and previewable.
- PLAY opens CURRENT; a row thumbnail focuses its placement paused and highlights/scrolls its editor card. Card selection stays in full-Shot context; explicit Preview Clip isolates saved media, with return to the prior position.
- Selected saved video, immutable provenance, inputs, next-take drafts, and in-flight/failed alternatives remain distinct. Missing inputs cannot hide retained media. Skips remain restorable; source duration and edited output duration are distinct.
- History is read-only with Edit Current Shot. Looks retain Edit Original. Narration generation controls explain whole-Shot scope without hiding saved outputs.
- Continuation overrides use the saved recipe as baseline; explicit settings survive save/reopen even when equal to the Shot default. Reset returns to the saved recipe. Ordinary draft segments use Shot defaults.
- Placement-specific Takes/New Take/Render Ending route to the exact owner. Flush drafts into the existing paid review. Cancel creates no artifact; tail retakes select, earlier retakes await Use with stale/rechain consequences.
- Extend Scene reuses the row's AI/Frame/Footage picker in the modal; Frame creation returns here. New Version opens a successfully saved independent editable copy with selected media retained.
- Chain regeneration is secondary and explicitly priced. The primary segment action affects only its link. Remove first-pending-ending interception in row and modal paths.
- Shared read-only saved-segment resolution supplies output, Preview, Copy, and provenance. Explicit entry intent governs focus/autoplay/review. Use existing generation, persistence, and trace operations; no database reconstruction/schema migration.
- Fix cramped control layout. Verify actual right panel with all entry paths, exact drafts/review targets, missing media/inputs, retry/repair, saved setting equality, Copy/paste, and save/reopen using isolated fixtures and existing media. Run existing build/tests/hygiene, capture native screenshots, package Development. No new test files, paid provider calls, commits, or pushes.
