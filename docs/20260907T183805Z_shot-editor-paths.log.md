# Shot editor paths

2026-09-07T18:38:05Z Started approved implementation. Existing staged and unrelated unstaged work retained; source backups isolated under /tmp/shot-editor-before. No paid inference or project-data repair is authorized for validation.

2026-09-07T19:25:21Z Completed implementation.

The editor now resolves selected continuation media, current render segments and reusable seeds without mutating them. Result cards show saved video/provenance/take selection above input Frame inspection and next-run controls. Missing inputs retain a saved-media card and Takes access. Raw Footage uses its placed range. Current, solo preview, historical render and Look states retain their established navigation boundaries.

Continuation override equality now uses the selected recipe as its baseline; explicit settings equal to the Shot default survive normalization and reopening. Segment actions flush drafts before resolving their exact review owner. The review retains the chosen continuation method instead of switching merely because Native Extend is configured. Failed prompt/Beats persistence blocks stale paid execution, which is a required persisted-data failure rather than a creative-quality gate.

The modal and row share the tail picker. Nested Frame Creator opens after picker dismissal; New Version waits for a successful copy save and resets player identity. Rebuild remains secondary and fully estimated. Whole-control wrapping fixes both the right editor and the existing timeline/footer tools.

Validation:

- `swift build` passed; final packaging rebuilt the LitScenes product successfully.
- `swift test`: all 1,274 existing tests passed. No new test source was added.
- `scripts/check_source_hygiene.sh` and `git diff --check` passed. `reuse` is not installed, so REUSE lint was unavailable.
- An isolated project copy under `/tmp/shot-editor-validation` exercised the actual ProjectContextStore save/load path. The three selected videos resolve to the same paths as the playback assembly; AVFoundation assembled 24.7917 seconds. Default-equal settings survive real SQLite reopening; Reset restores the saved recipe without altering media. Pending-ending routing, failed alternatives, take selection, stale descendants, branch reuse, missing-file selection, and clipboard payload roundtrip checks passed.
- The actual LibraryEngine draft setters and review builder carried a different project-neutral direction, the selected next model/duration, and the intended owner. Repeated review construction changed no attempt records. This validation submitted no provider request.
- Raw Footage was previewed as the real 2–4 second source range through a local AVFoundation composition. It required no generated render.
- Native screenshots covered the open current editor, focused middle segment, pending ending, historical render, imported Footage, narration as the next model, an independent version, whole-video fallback and first render. The middle saved output is visible alongside its correct selected take and recipe. Offscreen AppKit bitmap capture does not include AVPlayer's video layer; source thumbnails and compositions were checked independently.
- Native mouse events confined to the diagnostic window verified middle focus → Preview Clip → Full Shot, returning to the same displayed 00:15:01 position. New Take dispatched the middle placement key. Extend Scene and New Version dispatched their distinct actions.
- A second native check used the production ShotPlayerSheetHost and LibraryEngine: New Version persisted and opened a distinct three-clip Shot; Extend opened the shared picker; Create Frame opened after picker dismissal; Cancel returned to the same Shot with selected takes intact.
- Production additions contain none of the motivating fixture's subject, action, place or personal identifiers. Provider names remain executable model/provenance labels. No inference prompt or fixture-specific production rule was introduced.
- `scripts/build_litscenes_app.sh --channel development` produced `dist/LitScenes Development.app`; `codesign --verify --deep --strict` passed. The existing packaging script retained the previous local bundle and iconset as `.deprecated_LitScenes_Development.app_20260907T192015Z` and `.deprecated_LitScenes_Development.iconset_20260907T192016Z` under `dist`; these old build artifacts can be deleted after checking the new build.

Diagnostic code, screenshots and detailed command logs remain under `/tmp`, outside shipped source. Existing unrelated working-tree changes were retained. No live-project database repair, schema migration, paid provider call, branch, commit, push, publication or private submodule update occurred. Paid submission/completion with a live provider was intentionally not exercised.
