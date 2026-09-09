# Development Log

2026-09-06T18:36:23Z public-desktop-canonical-cutover: began the approved transition making this repository canonical for shared LitScenes Desktop development; added a curated product/development contract and preserved the history-clean initial public release as provenance. Pre-transition private history remains in the private product repository rather than being bulk-published here.
2026-09-06T18:36:23Z public-desktop-canonical-cutover: completed the uncommitted public working-tree transition on local `main` at `6af76e7` — preserved superseded README/REUSE/tour work in `stash@{0}`, added the curated Desktop contract and plans convention, moved the original export manifest to initial-only provenance without changing its SHA-256, and added generic source hygiene to CI. `scripts/check_source_hygiene.sh`, `swift build`, all 1,262 tests, and `git diff --check` pass; local REUSE execution is unavailable because the `reuse` command is not installed. Nothing committed or pushed.
2026-09-06T19:44:05Z scene-quick-extend: began the approved SCENES v2 quick-extension implementation in the canonical public checkout: replace the anonymous tail slot with START SCENE / EXTEND SCENE, render executable Native or Out-frame continuation takes from exact tail provenance, preserve selectable take history, and make dependent chains rebuildable without silent invalidation or spend.
2026-09-06T21:07:52Z scene-quick-extend: completed the uncommitted implementation in the public working tree. Added the named tail workflow, exact endpoint review, Native and Out-frame execution, immutable take records and thumbnails, shared take browsing, version-aware $0 branch reuse, derived downstream staleness, priced resumable Rechain and generated-chain rebuild, tolerant historical migration, and continuation trace lineage. `swift build`, all 12 focused continuation tests, all 1,274 tests, `scripts/check_source_hygiene.sh`, and `git diff --check` pass. No paid provider call was made; local REUSE execution remains unavailable because the `reuse` command is not installed. Commit reference is pending explicit authorization; nothing was committed or pushed.
2026-09-06T22:43:26Z scene-continuation-playback-chain: began the approved repair that keeps a rendered Scene's existing video before its appended continuation in the same Shot player, runtime, and export chain; existing isolated continuation versions must recover locally without another provider call.
2026-09-06T22:54:53Z scene-continuation-playback-chain: completed the uncommitted playback-chain repair. The live plan now derives every ordered clip from the rendered version captured by the continuation anchor, reuses those clips as immutable $0 source material, resolves the selected continuation take even when an older isolated continuation-only version is active, and stitches the full Scene before activation on future renders. The exact reported 15.042s + 5s regression, all 13 continuation tests, all 1,275 tests, `swift build`, source hygiene, and `git diff --check` pass; a fresh `LitScenes Development.app` was packaged under `dist/`. No provider call or project-database edit was made; REUSE remains unavailable locally. Nothing was committed or pushed.

2026-09-07T04:55:27Z shot-continuations-without-automatic-versions: began the approved correction in the public checkout; preserve selected clip playback independently of historical render versions.
2026-09-07T05:33:51Z shot-continuations-without-automatic-versions: completed the authorized public working-tree correction. Extend/retakes persist independent clips, historical renders preview without selection mutation, NEW VERSION retains selected media with explicit branch provenance, shared assembly retains the original sequence, and safe failure/local-repair lifecycle plus origin-project spend are durable. Final swift build, all 1,275 existing tests, source hygiene, and git diff --check pass. No new tests, paid provider calls, or interactive app/Traces verification were performed. REUSE could not run because reuse is not installed. No commits, pushes, branches/worktrees, private-pin updates, or remote schema changes.
2026-09-07T14:02:18Z shot-sequence-ux: began the approved row/modal navigation, current provenance, playback styling, and arrive-at-Frame ending implementation.
2026-09-07T14:26:50Z shot-sequence-ux: completed the approved implementation and packaged dist/LitScenes Development.app. Final Swift build, all 1,275 existing tests, source hygiene, git diff --check, and codesign verification pass. Prior bundle and iconset retained as dist/.deprecated_*_20260907T142501Z. Running app was not restarted. Interactive UI validation is unperformed because Accessibility is disabled; no paid provider call or live Traces UI verification was made. REUSE is not installed. No tests added, commits, pushes, branches/worktrees, private-pin updates, or remote schema changes.

2026-09-07T14:37:54Z continuation-thumbnail-recovery — Fix AI marker persistence and recover continuation thumbnails without changing generated media.

2026-09-07T14:40:21Z continuation-thumbnail-recovery — Corrected acronym decoding and record-backed marker recovery. Build, 1,275 existing tests, hygiene and signature checks passed; Development app repackaged. No direct project database/media edits, paid calls, commits or pushes.

2026-09-07T15:17:51Z shot-state-preservation — Implement approved persistence-boundary correction, legacy chain recovery and take history; verify real store lifecycle and fresh actions without provider calls.

2026-09-07T15:34:53Z shot-state-preservation — Actual SQLite lifecycle diagnostics, injected write failure, native row/modal snapshots, three-clip composition/export and six-clip combination passed; all 1,275 existing tests and hygiene checks passed. No paid provider calls or direct edits to live project data. Packaging follows.

2026-09-07T15:36:05Z shot-state-preservation — Final swift build, Development packaging, codesign verification, source hygiene and git diff checks passed. Fixture-term scan found no motivating entities in added production source. Prior Development bundle retained under dist/.deprecated_; removable after the owner no longer needs it. No commits or pushes.

2026-09-07T16:58:34Z character-sheet-version-deletion — Implement approved individual version deletion, persistent browsing exclusion, and newest surviving active sheet selection.

2026-09-07T17:05:58Z character-sheet-version-deletion — Implemented in canonical public working tree; Swift build and all 1,275 existing tests pass; hygiene and whitespace checks clean. Files/provenance preserved, no commit or pin update. Interactive macOS validation remains unperformed.

2026-09-07T17:07:51Z scenes-newest-thumbnails-first — Implement approved shared newest-first ordering for source photos, loading renders, and completed Frames in the SCENES pool.

2026-09-07T17:11:16Z scenes-newest-thumbnails-first — Implemented newest-first interleaving of photos and Frames in the SCENES pool, using updatedAt for loading Frames and source modifiedAt for adopted photos. Preserved tile identity, deduplication, and footage placement. Swift build, all 1,275 existing tests, source hygiene and git diff --check pass. An isolated compiled inventory-function diagnostic passed loading/completion identity, concurrency, mixed photos, ties, missing dates, filtering order and serialized input reload. No interactive UI verification or paid calls. REUSE is unavailable locally. No new repository tests, commits, pushes or private submodule pin changes.

2026-09-07T17:15:40Z concurrent-project-jobs-and-global-logs: implement the approved project-runtime, queue, automatic recovery and global LOGS panel plan.

2026-09-07T18:21:25Z concurrent-project-jobs-and-global-logs: Implemented retained project workspaces, shared queues, durable global Logs, provider holds/recovery safeguards, and trace/spend integration; validation and audit recorded in the feature work log. No commit or publication.

2026-09-07T18:30:13Z concurrent-project-jobs-and-global-logs: Final build, 1,274 serialized tests, eight no-network lifecycle scenarios, both hygiene checks and diff check passed. Audit notes record the existing parallel temporary-directory timing race and live-provider/UI validation limits.

2026-09-07T18:38:05Z shot-editor-paths — Implement approved segment result visibility, contextual navigation, exact actions, recipe inheritance, and in-modal extension/branching; validate the open right editor with isolated media.

2026-09-07T19:25:21Z shot-editor-paths — Completed saved-segment video cards, exact segment focus/reviews, persistent next-take recipe inheritance, in-modal extension/branching and readable controls. Build, 1,274 existing tests, native interaction checks, isolated persistence/media checks, source hygiene, diff check and Development signing passed. No live-project repair, paid inference, new repository tests, commits or publication.

2026-09-07T21:05:09Z shot-prompt-assistance — Implement approved readable take review and one prompt field with Improve, Suggest, Revert and Undo, retaining existing timing and generation artifacts.

2026-09-07T21:43:26Z shot-prompt-assistance: Implemented one prompt field with Improve/Suggest/Revert/Undo, atomic text/timing saves, traced text inference, and readable continuation review. Existing Swift suite, native checks, hygiene and Development packaging validated; no paid provider calls or live-project repairs.

2026-09-07T23:22:27Z character-workspace-ux: Implement approved source-aware character creation, explicit sheet actions, independent models, full-resolution inspection, and continuity prompt refinements.

2026-09-08T00:00:12Z character-workspace-ux — Implemented separate image/sheet actions and saved models, source-following editor, full-resolution inspection, manual new-character defaults, continuity prompts, and safe character chat traces. Final build and all 1,275 tests pass; native component and local mock trace checks pass. Source hygiene and whitespace checks are clean; REUSE CLI unavailable. No paid provider calls, commit, publication, or submodule changes.

2026-09-08T00:45:26Z character-sheet-inspection — Enlarge character sheet inspection to most of the available screen, open at actual-size zoom, and use Active for the selected sheet in the UI. Preserve inspection-only behavior and existing artifacts.

2026-09-08T00:51:44Z character-sheet-inspection — Completed larger screen-relative inspector with actual-size opening zoom and Active sheet selection copy. Build, 1,275 tests, actual native sheet size/pixel-scale/shortcut checks, hygiene and whitespace checks pass. No inference calls, commits, publication or pin update.

2026-09-08T01:34:34Z analyze-modal-hide — Replace the disabled Analyze close control with Hide; minimize to a live status pill that reopens the existing log while analysis continues.

2026-09-08T01:37:39Z analyze-modal-hide — Implemented Hide and live status-pill expansion in the canonical Desktop working tree. Swift build and all 1,275 existing tests pass. Public source hygiene, private hygiene checks for both the canonical and pinned checkouts, and whitespace checks pass. No interactive UI verification or paid inference calls. REUSE CLI is unavailable. No new tests, commits, pushes, or submodule pin changes.

2026-09-08T02:08:27Z frame-references-camera-turn — Implement approved shared reference resolution and truthful suggestion UI; repair Reframe layout/contrast and add stationary Turn Camera angles, notes, prompt isolation, compatibility and trace validation.

2026-09-08T02:42:12Z frame-references-camera-turn: implementation and validation complete; see `docs/20260908T020827Z_frame-references-camera-turn.log.md`. Shared source remains uncommitted in the public checkout.

2026-09-08T03:25:27Z exact-video-endpoints — Implement approved correction for endpoint extraction, verified continuation inputs and retake review; preserve historical takes.

2026-09-08T03:55:54Z exact-video-endpoints — Implemented exact/ranged video extraction, verified review cache, preserved retake inputs, missing-source guards and linked local trace events. Offline native append/reopen, retake/rechain/rebuild, footage, cancellation and provider-input checks pass; final package verification in progress.

2026-09-08T03:57:48Z exact-video-endpoints — Complete: final offline native diagnostics pass, 1,281 existing tests pass serially, build/hygiene/whitespace/signature checks pass. Development app packaged; historical media preserved and no live project repair or paid calls performed.

2026-09-09T00:55:43+00:00 shot-progress-logs-frame-navigation: implement approved consistent segment tiles, structured progress and outcomes, readable Logs, and origin-ordered Frame browsing.

2026-09-09T01:57:00Z shot-progress-logs-frame-navigation: implemented shared segment lifecycle and stable video tiles, richer durable Logs and failure provenance, and live thumbnail-order Frame browsing. Native/offline diagnostics passed; final existing-suite and Development packaging verification recorded in the feature log.
