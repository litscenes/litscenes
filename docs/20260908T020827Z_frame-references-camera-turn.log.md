# Frame references and Turn Camera

2026-09-08T02:08:27Z Approved plan: `plans/20260908T020827Z-frame-references-camera-turn.md`.

2026-09-08T02:42:12Z Implementation complete.

Implemented the approved plan in the canonical public Desktop source:

- Replaced unbounded preview controls with a scrolling sidebar and pinned Generate guidance/action. Fixed native prompt text and caret colors in dark and light appearances.
- Added Turn Camera yaw/pitch controls and presets, a point marker without crop resize/roll handles, authoritative composed geometry plus editable notes, separate camera templates, independent Zoom drafts, and an optional persisted camera intent. Map, prompt and attachment descriptions use the same coordinates and signed angles; edge crop clipping does not move the camera. Legacy compass records retain their meaning.
- Unified actual character reference selection across featured/list suggestions, default rendering and Art-direct initialization. Preserved sheet/composite/source fallback and provider limits, removed duplicate attachments, and kept explicit chip/picker removals from being reattached by mentions. Added missing-reference guidance and clarified the featured card's relationship to Suggested Frames.
- Moved safe image-edit/Responses prompt and media-hash capture before transport so HTTP failure and cancellation retain creative provenance. No additional provider call was added.

Validation:

- Clean Swift build and 1,281 tests passed; the final color and trace refinements also passed the full suite. Six added regression/counter-fixture cases cover structured identity without mentions, roster renaming and saved cast links, fallback/missing files, deduplication, legacy serialization/templates, angle normalization/round-trip, map signs/edge coordinates, and prompt priority with unrelated scenes and long notes. Existing provider capacity and fulfillment tests also pass.
- Native AppKit previews at 850-point and 430-point heights, in dark and light appearances, verified a visible pinned Generate action and fixed editor/caret contrast, including the no-pivot guidance. Model controls remain on existing executable provider paths.
- Real OpenAI image-edit and Responses clients called a localhost mock only. The shared Traces app readers verified all six success/HTTP-failure/cancellation records, exact prompt equality against captured local requests, workflow/run/artifact identity, safe source/output hashes, and absence of credentials or binary image bodies.
- Public hygiene, private hygiene against both the pinned and canonical checkouts, and whitespace checks passed. REUSE CLI is unavailable. Sixteen changed production files contain no motivating-fixture phrase matches; the counter-fixtures keep behavior independent of names.
- Initial incremental builds contained stale Swift ABI objects after the optional model field changed; a clean build resolved the compiler/link/runtime failures. Native validation caught adaptive palette colors and prompted the fixed-color correction.

No paid provider calls were made, so generated camera geometry has not been visually assessed against a new provider output. Existing user artifacts were not rerendered. Changes are uncommitted against public base `2151b3a`; no implementation commit hash exists because committing was not authorized. No branch, worktree, push or private submodule pin change was made.

