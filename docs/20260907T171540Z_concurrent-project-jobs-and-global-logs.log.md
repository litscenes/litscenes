# Concurrent project jobs and global Logs

2026-09-07T17:15:40Z Started implementation in the canonical public checkout. Existing continuation, character and media edits are preserved; baseline retained outside the repository for review.

## Scope audit and implemented changes

The former SCENES sidebar Logs was **session-scoped**, not a reliable global history: it displayed the latest 40 entries from the current engine's capped in-memory generation buffer, plus up to 12 saved body versions of the selected Scene Plan. Project loading changed that context. The canonical inference trace database already covered multiple projects, but the sidebar did not read it and release builds could disable capture.

| Blocking state or history gap | Implemented change |
| --- | --- |
| `selectProject` refused scanning, analysis and paid video operations; `load(project:)` canceled tasks and replaced creative state | A `ProjectWorkspaceCoordinator` retains a `LibraryEngine` and stable view identity for each visited project. Navigation changes visibility; registry refresh does not reload creative documents. |
| Frame Creator and ancillary frame/reframe controls reused project-wide rendering flags or refused a batch larger than free slots | Submission accepts durable jobs and queues overflow. Existing per-row claims still prevent conflicting work on the same frame. |
| Scalar Shot render/join/Look/narration/chip state blocked or misrepresented unrelated Shots | Active sets and per-Shot checks replace those shared guards. Independent Shots and narration can proceed concurrently. |
| Character study/sheet and Frame animation flags were shared across all characters/frames | Guards and busy indicators use the affected character or frame identity. |
| YouTube export refused while a different export or unrelated generation ran | Saved-output exports use shared local admission and scoped video prerequisites. AVAsset exports also share a two-encoder gate. |
| Regeneration appended from an old Scene Plan snapshot | New media merges with the latest frame collection; late individual outcomes use the existing owning-document reconciliation paths. |
| Session logs, Activity and inference records were disconnected | Jobs/events persist beside inference calls; Activity reads jobs; Logs displays global filtered history, trace detail, spend links and project Scene Plan versions. |
| Unwrapped inference clients and FAL/CivitAI media-transfer stages could bypass lifecycle history | The shared transport creates request-level jobs when no parent job exists; previously direct upload/download stages now use that transport. |
| Raw capture could retain unsafe response bodies and local control events appeared failed without HTTP responses | Capture redacts credentials/capabilities and binary media, including enrichment writes. Local preparation/control success is distinct from a provider outcome. Provider-bound prompts remain inspectable. |
| Retrying a submission timeout could duplicate a charge | Ambiguous paid submission acceptance is paused for review; rejected/transient safe stages get bounded retries, and funding/auth failures hold the vendor queue. |
| Project changes and quit had no durable shared job lifecycle | Running work remains owned by its project; quit checkpoints unfinished jobs. Relaunch retains reviewable requests rather than recreating paid submissions. |

## Runtime and UI behavior

- Shared FIFO admission defaults to 8 image / 3 video / 3 text / 2 audio / 2 local jobs. A second gate constrains actual requests when a workflow fans out.
- Seventy-one work-producing engine entry points are wrapped; nested calls inherit the current job. The transport supplies a lifecycle for remaining older inference clients. Duplicate identity is independent of a job's subsequently bound artifact id.
- LOGS is a compact right-aligned main-nav control. The panel follows the measured navigation bounds, preserves filters, refreshes expanded events/trace details, supports Close/Escape, and does not install a modal backdrop.
- Canceling an existing task propagates into its retained background job. Logs uses Stop after this step for running work rather than pretending every provider has remote cancellation.
- Funding/auth holds apply to the configured vendor across projects. Continue retries the retained request with the current credential in its original authentication scheme. Other vendors and local work remain available.
- Saved requests, provider identifiers, trace prompts/results and known spend estimates are visible. Search/filter queries run against durable storage rather than only the initially loaded page. History predating operational capture is not fabricated.
- Known Look recovery retains the existing request-id polling/download paths. A restart or ambiguous submission shows Review request; the saved recipe remains visible and Open item returns to the owning artifact. A new paid attempt still uses its established current-input/price review.
- The obsolete test requiring manual generation Pause to override all other lanes was removed because that product control was explicitly removed. Playback/recording Pause remains. No new repository tests were added.

## Validation

- Final `swift build` passed. Final `swift test --no-parallel` passed all 1,274 applicable tests.
- Public source hygiene and private integration hygiene passed.
- A temporary, uncommitted scenario runner linked against the actual Desktop module verified shared image capacity and overflow, stable project identity, independent vendors during a hold, Continue, parked-request cancellation, duplicate rejection, uncertain-acceptance persistence across restart, and readable canonical traces with safe prompts/redaction. No network or paid provider calls were made.
- Temporary validation used an isolated `LITSCENES_OPERATIONAL_DB` under the system temporary directory. Existing user operational history was not used as test input.

## Recommended follow-ups and practical limits

1. Add provider-specific recovery adapters where the current client cannot retrieve an already-submitted job. Keep those workflows at Review request until the adapter can prove retrieval does not resubmit. Generic automatic replay is deliberately unavailable after restart.
2. Add an explicit history retention/export policy and safe idle-workspace eviction if long sessions with many projects make local storage or retained view memory significant. Currently visited workspaces remain retained to preserve drafts.
3. Continue filling provider cost coverage. Logs displays recorded estimates and pricing notes, but does not infer a zero cost when the provider/ledger has no price.
4. Validate actual vendor funding/authentication responses, remote cancellation and paid recovery through normal authorized product use. Local scenarios verify the state machine, not vendor behavior. Interactive macOS layout and every provider path were not exercised with live paid renders in this session.

All implementation is in the canonical public checkout. Existing unrelated changes were preserved. No commit, branch, push, merge, publication or private submodule pin update was made.

## Final verification record

- Final standalone build, all 1,274 existing applicable tests, public hygiene, private integration hygiene, and `git diff --check` passed.
- One parallel full-suite run hit the existing ambient-bake cancellation check's five-second shared-directory deadline while a sibling successful bake was still alive. Its directory disappeared when the sibling finished. The cancellation check passed independently; the full suite passed when serialized. No cancellation test expectations were weakened.
- The final no-network runner passed all eight scenarios, including actual project-engine identity/selection retention and quit checkpoint persistence despite a late completion. SQLite inspection confirmed the local trace recorded success and migration version 1 was present.
- Media-transfer URLs are stored as safe host/hash references, including opaque capability paths. Creative text remains in safe request/trace projections.
- REUSE validation was not run because the `reuse` executable is unavailable in this environment; no licenses or licensing policy were changed by this task.
- No live provider calls or interactive macOS acceptance session was performed. No temporary scenario source or validation database was added to the repository.
