# Edited Shot endings

2026-09-09T20:31:52Z Started approved implementation.

# Ending a Shot from its current edited output

Approved experience: dropping or choosing a Frame stages it. Render Ending opens the same review from the row and player, immediately shows the destination, prepares the exact current cut without generation charges, and exposes direction, executable paired-frame model, duration/audio, and price. Failures remain in that review with the exact reason and recovery. Extend Scene surfaces the pending ending first. Multiple destinations render in order.

Preserve the preceding edited output in an additive edit scope when a successful ending is selected; append outside that scope. Scope state includes picture order/cuts/Reverse/loops/OUT, audio and Look. Legacy documents retain existing behavior. Keep segment identities, editor cards, immutable media/takes and current Shot version. Earlier-cut controls stay on the established timeline, with undo/redo preserving scopes without deleting paid takes.

Use one scoped composition for playback, exports, runtime, audio, Looks, combination and exact continuation preparation. Prepare a disposable cached cut and verify its endpoint; confirm snapshots composition and target provenance. Revalidate before submission and completion. Changes during rendering leave the ready take available without replacing changed playback. Update staleness, rechain and branching for scope dependencies.

Validate recognizable local media through edits, repeated append, both entry points, ordering, changed/missing inputs, cancellation/failure, retake/rechain, undo/redo, branch and reload. Inspect native sheets in light/dark. Run existing build/tests/hygiene/diff checks and package Development. No paid calls, live data repairs, commits or pushes.

## Implementation and decisions

2026-09-09T21:34:08Z Implemented and validated the shared ending review and editable preceding-cut scopes.

- Both row and player open one review session with explicit append/ending/retake intent. The selected destination remains visible during local preparation, failure and refresh; typed direction survives retry. Extend Scene promotes the first staged ending; later destinations identify the preceding ending to render.
- Reviews use the exact visible edited output, including arranged copies, trim/OUT, Reverse, speed, loops, audio and active Look. Supported paired-frame models and complete price remain prerequisites for remote submission. Fixed ink/paper colors make the review and picker readable under light and dark appearance.
- Selecting the ending installs the reviewed preceding output as an editable scope, clears only outer edits, and appends once. Existing segment cards, source entries, media, render identity and takes remain. Earlier cut controls use the existing timeline and prompt panel; scope edits persist with Undo/Redo. No automatic Shot version is created.
- Composition caches are derived, uniquely named local media. Missing caches show preparation/retry and cannot cause playback to show only the later clips. Export prepares missing/changed scopes from saved inputs. Scoped edits, branch and combination preserve original resources and remap local identity without changing provider evidence.
- Immutable review evidence records composition fingerprint, source clip/take identities and endpoint evidence. Preparation/submission/completion revalidate dependencies. If the cut changes while a provider runs, the completed take stays ready and unselected; explicit Use preserves the current cut and retains a stale warning, and Rechain uses its current scoped dependency.
- Undo deselects a newly created ending without deleting its completed take. Older manually created undo snapshots retain legacy selection behavior. Historical retakes retain the endpoint-correction notice and immutable original input.
- Persistence is an additive document extension: missing `outputScopes` decodes explicitly to the legacy empty-scope representation; absent anchor review and record scope binding remain nil. Optional cache offsets can be regenerated. Existing documents are not rewritten by opening/canceling review, and no database schema or historical media repair was performed.

## Validation

- `swift build` passed. The final existing suite passed all **1,281 tests** (`swift test --no-parallel`). No repository test files were added or changed.
- The suite exposed a worker-stack overflow in combined-cut planning while the full review evidence was a nested value. Replaced it with immutable shared evidence, reproduced the affected check, and reran the full suite successfully. Later Undo/cache recovery changes also passed the full suite.
- Native offline diagnostics used fresh temporary projects and generic landscape Frames with recognizable timecoded moving video, independently of the motivating screenshots and historical project data. Every provider request was intercepted by a local URLProtocol stub; unexpected hosts fail the diagnostic.
- Verified multi-clip initial render; exact edited endpoint; review without project mutation/provider submission; same render identity; both original clips plus ending; repeated/nested endings; staged destination ordering; provider failure and retry; changed cut during generation; explicit Use and Rechain; missing cache recovery; scoped audio editing; Undo/Redo retaining takes; JSON reload; branch and combination playback/lineage; arranged picture copies; active Look preservation.
- Inspected native ready and failure reviews and the pending-ending picker under dark appearance, plus light appearance. Start/end labels, model, direction, price, Cancel and recovery links remain readable.
- The motivating screenshot names and diagnostic fixture labels have no matches in added production code or prompts. The independent fixture exercises the same generic behavior without entity-specific routing.
- Public source hygiene and `git diff --check` passed. REUSE is not installed in this environment. Packaged the Development app, verified its signature, and verified the executable code matches the validated build. Packaging retains older local bundles under `.deprecated_` names; these can be deleted after the new build is accepted.
- The existing Traces app rendered successful and failed offline ending records with prompt, workflow, outcome/error, reviewed-output fingerprint, scope and source provenance. The provider submission also retained the exact executable prompt and paired-frame parameters. Validation used an isolated app copy and fixture database, with the installed Node runtime matching its existing SQLite module.
- No paid calls, live project edits, private-source changes, commits or pushes were used for this implementation. Commit hash remains pending explicit authorization.
