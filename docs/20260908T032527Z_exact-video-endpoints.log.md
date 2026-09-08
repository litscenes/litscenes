# Exact video endpoints

Approved plan: `plans/20260908T032527Z-exact-video-endpoints.md`.

Confirmed through native read-only extraction: default timing tolerances can return the opening frame; zero tolerance plus the final timestamp inside the visual range returns its last displayed frame. Preserve recorded predecessor identity and existing take inputs.

## Implemented

- Shared AVFoundation endpoint extraction now uses zero tolerances and the final timestamp inside the visual interval. It records the returned sample time and respects selected footage ranges without a frame-rate assumption.
- A focused helper verifies a revisioned, source-content/range cache, checks cached image hashes, rejects changed sources and honors cancellation. Video-backed review always resolves from video; old take input images and endpoint caches are never trusted as authoritative sources for new work.
- New take provenance adds optional, tolerantly decoded endpoint evidence. No database schema migration or project-wide repair. Existing take inputs, generated clips, versions and selections are preserved.
- The existing review shows the corrected endpoint and a short notice when it differs from the historical video input. Confirmation verifies the displayed image, preserves its durable copy and checks again before provider submission.
- All continuation entry points, direct segment retake dispatch, ranged Footage preview and full-render Footage handoffs use the correction. Known missing generated videos no longer fall through to a still Frame.
- Local continuation events now attach their canonical trace IDs to the owning Logs workflow. Details expose source/image fingerprints and requested/actual times; preflight failures remain visible without a provider request.

## Validation

Temporary diagnostics stayed outside the repository and used a scratch copy of project data. A URLProtocol intercepted every HTTP request, used dummy credentials, returned synthetic video outputs and blocked all other requests. No live project database writes or paid provider calls.

- Final samples and trimmed out points matched independent decoded timestamps for 24, 30 and 60 fps, variable frame timing, and offset source timestamps.
- Actual saved clips produced corrected final images for both historical retakes and the newest append. Review/cancel left the timeline unchanged.
- Two successive Frame drops, ending renders and engine reopenings preserved previous clips and numbered versions; each new request started at its immediate predecessor's actual ending. Provider-bound normalized image hashes matched the images derived from review.
- Correcting a middle retake kept its recorded predecessor and original selection. Use marked descendants stale; Rechain and full chain rebuild followed selected predecessors in order. AI Extend also preserved its reviewed image.
- True still starts, trimmed variable-timing Footage, the Footage Inspector, and initial full-Shot Footage-to-generation handoffs passed offline generation checks.
- Corrupted caches regenerated; canceled preparation left no new cache; missing or replaced source videos and unverified historical anchors refused provider submission. Failures retained their reason and completed siblings.
- The shared native review rendered readable text under a dark parent and its Cancel action left project state unchanged. The canonical detail API used by Logs exposed endpoint evidence, prompts, provider input hashes, success and local preflight failure after trace IDs were attached.
- Independent synthetic moving patterns exercised the same production paths as saved media. Fixture entity/phrase scan found no additions to changed production logic or prompts.
- Source hygiene and whitespace checks pass. REUSE is not installed in the current environment.

The full existing suite passed 1,281 tests before the final local-trace attachment. Parallel runs also exposed the existing ambient cancellation test's shared-scratch race: its five-second cleanup check can observe a sibling bake still in progress. It passes in isolation. Final serial suite and Development packaging results follow below.

## Final result

- Final `swift build` passes. `swift test --no-parallel` passes all 1,281 existing tests after the trace attachment, avoiding the documented ambient shared-scratch timing race. All temporary offline endpoint diagnostics pass against the final binary.
- `scripts/check_source_hygiene.sh` and `git diff --check` pass. No new repository tests were added.
- Development packaged at `dist/LitScenes Development.app`. Strict/deep code-signature verification passes. The packaged executable and tested build have the same Mach-O UUID; their whole-file hashes differ because packaging signs the executable.
- Six historical input/endpoint/clip comparisons against the read-only original project remain byte-identical. Live project data was not rewritten; no paid calls, commits, pushes, branches or worktrees were created. Unrelated unstaged frame-reference/camera work was preserved.
- The packaging script retained the previous app and iconset under `dist/.deprecated_LitScenes_Development.*_20260908T035620Z`; these obsolete build artifacts can be deleted when no longer needed.
