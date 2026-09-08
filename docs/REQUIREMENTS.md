# LitScenes Desktop Requirements

LitScenes Desktop is the public, canonical macOS application for turning personal media into story-aware planning, generation, editing, and export workflows.

## Product Contract

- The app is local-first. Projects, media indexes, credentials, prompts, traces, and generated artifacts remain on the operator's Mac except for provider requests the operator explicitly configures.
- An unconfigured Community install performs no background analytics or telemetry and remains usable with its bundled starter meaning and style resources.
- The primary workflow is MEDIA → STORY → CHARACTERS → SCENES. It should lead with usable content and direct next actions rather than internal pipeline terminology.
- Direct inference with the operator's own compatible key is a complete path. Optional hosted meaning retrieval may enrich it but must never be presented as required for the app to work.
- Provider/model/parameter controls must affect the next execution exactly as shown. Unavailable capabilities are visibly locked or omitted, never selectable theater.

## Creative Workflow

- Media intake preserves source identity and bytes, avoids accidental cropping in review surfaces, distinguishes missing files from managed/linked storage, and treats every source photo as an adoptable Frame without spend.
- STORY persists the creator's purpose, content type, constraints, cast, places, and source-media evidence. Saved state—not unsaved field text—determines readiness, and usable-but-imperfect story language may continue with warnings.
- CHARACTERS treats source images as inputs and rendered character sheets as continuity anchors. Rendering states, selected provider stack, source ordering, price, failure, staleness, and version choice remain visible and per-character.
- Character image creation and reference sheet generation are separate actions with independent persisted model choices. The image editor follows current sources until customized and displays the references actually used. A sheet requires a usable image reference, including an existing sheet; this is the approved workflow prerequisite, not a quality gate. New characters use manual sheet rendering while legacy effective preferences are preserved.
- Character refinement preserves established hair length, cut, silhouette, and texture across sheet panels and later updates unless the creator explicitly changes them; explicit changes apply consistently throughout the sheet. Conversation confirms saved instructions, never guarantees an uninspected image outcome. Source images and existing sheets provide identity evidence; the latest explicit creator instructions govern intended changes.
- Original-resolution character images and active or historical sheets open at actual pixel size in a large screen-relative inspector, with fit, actual-size, zoom and pan controls. Inspection does not change the selected continuity version; its version-strip badge reads Active.
- CHARACTERS supports deleting individual sheet versions from each thumbnail menu or right-click menu. Deleted versions stay out of browsing, pickers, and automatic character reference selection after reload or rescan; their files and provenance remain available to existing work. Deleting the active version selects the newest surviving version and restores its prompt hash; deleting the last clears the reference sheet. Surviving version numbers stay stable, and failed saves leave visible state unchanged.
- SCENES turns the saved story into concrete, diverse moments and Frames, preserves completed or attempted work across replanning, and makes planned intentions visibly different from queued or rendered artifacts.
- The SCENES thumbnail pool interleaves source photos and generated Frames newest first, including newly loading renders. Completion updates the same tile; adopted photos retain their source date and footage follows still images.
- Every Scene ends with one state-aware tail action: START SCENE when empty, ADD TO SCENE before playable video exists, and EXTEND SCENE afterward. AI, Frame, and Footage paths remain on this surface; animating an initial Frame is labeled distinctly from extending video. Opening or canceling AI continuation review must not mutate the Scene; confirmation shows the exact endpoint, executable method and model, duration/audio controls, and a complete price before any provider submission.
- AI Extend appends one continuation cell in the same Shot row without changing `shotId`, `activeRenderVersionId`, or numbered render history. Play, export, runtime, combination, and reel composition use the complete preserved source followed by the selected continuation clips. Only the confirmed link is generated.
- Each continuation owns immutable takes and their exact recipes. A successful tail retake selects automatically; a retake with downstream continuations waits for Use. Use immediately changes the working selection at $0. Dependent clips remain playable with stale warnings; separately priced Rechain repairs those dependencies and retains completed work if interrupted.
- Historical whole-Shot renders remain available as read-only previews. NEW VERSION makes an independent editable copy of a continuation-bearing Shot's selected sequence and edit state, sharing immutable media instead of dropping the continuation clips. Existing history remains on the source Shot.
- Continuation failures retain the safe phase and reason on the cell, take browser, Logs, and canonical traces. Completed provider output is persisted before local finishing. Repair uses retained media at $0; a new remote attempt requires price review. Unknown provider acceptance is distinguished from failure before submission.
- Continuation anchors may be ready Frames, ranged Footage, clean rendered Originals, or selected continuation takes. Native Extend is offered only with a valid video tail; active Looks and output edits that move the visible endpoint lock AI continuation with an explicit repair action while leaving other lawful workflow paths understandable.
- Shot-row thumbnails open their placement in the Shot modal paused; PLAY starts playback and must look enabled whenever saved media is playable. VIEW FRAME, ART DIRECT, TAKES, and INSPECT FOOTAGE remain explicit secondary row actions, with source inspection and take management available in the modal.
- The modal has explicit CURRENT, historical-version, and segment-preview states. The navigation highlight follows the viewed state; returning to CURRENT reloads the selected sequence even when its base media path matches a historical preview.
- Model provenance on the row and in the current modal describes selected sequence clips, including Footage, rather than the active whole-Shot render stamp. One model is named, two are both named, and larger mixtures show a model count. Ordered per-clip details remain inspectable separately from NEXT generation controls.
- A Frame appended after a completed continuation or readable rendered tail is a destination for an ending clip. RENDER ENDING opens a no-spend review of the exact start endpoint, ending Frame, prompt, executable paired-frame model, duration/audio settings, and full price. Confirmation generates only that connecting clip, preserving the existing Shot, earlier media, active render identity, and numbered history. The destination placement owns its takes; a completed ending can be extended again from its actual output endpoint.
- Ending takes persist immutable target Frame identity, image snapshot, and fingerprint with their recipe and source anchor. Native Extend and narration-only models are not selectable for paired-frame endings. Missing media is a repairable runtime prerequisite; merely having a historical render record does not make its source video available.
- Shot and cut editing is nondestructive and recoverable. Trims, skips, seams, loops, speed, picture insertions, narration, ambient audio, and version changes must preserve source media and support undo where the established workflow promises it.
- Export uses the assembled preview as authority, surfaces failures plainly, and never discards a completed provider or local artifact because a sibling operation failed.

## Shot Editor

- The existing right-hand editor shows saved video for every current segment separately from its input Frames and next-render draft. Selected continuations, endings, preserved Originals, imported Footage, reused branch/combined clips and whole-video fallbacks remain inspectable; unavailable generation inputs never hide retained selected media.
- Selecting a segment card seeks its placement in the full Shot and pauses. Preview Clip plays its saved video separately; Full Shot returns to the prior position. Row thumbnails focus, highlight and scroll to the corresponding editor card. Imported Footage previews its placed source range before any generated render.
- Saved model, duration and selected take describe the current media. Per-segment model, duration, audio and one editable direction field describe the next run. Continuations inherit their selected take's saved recipe; explicit overrides survive reopening even when equal to the Shot default. Reset restores that saved recipe. Ordinary draft segments inherit Shot defaults.
- Improve and Suggest are small text-AI links beside Render new take in the existing segment editor. Improve clarifies the written action and camera direction while preserving intent; Suggest proposes a fresh direction from available Frame descriptions, relationships, narration and model/duration, ignoring existing text. Neither generates video. Revert restores the selected saved prompt or initial unrendered direction; Undo restores the previous text and timing authority.
- Assistance is traceable through the shared text workflow and inference store. Operators can keep typing while it runs. Changed text or segment inputs require Apply/Dismiss for the result; closing the editor prevents late application. Duplicate requests for one segment are prevented; failure keeps the draft and offers Retry.
- Untouched legacy timed direction remains executable and visible as compiled text. An explicit text edit or AI replacement saves text and raw authority atomically, retaining the old plan and immutable media. Native multi-shot timing changes are explained before rendering. Story Beats elsewhere are unaffected. Paid review uses readable dark ink on cream, including native controls, independently of the surrounding appearance.
- Render new take, Takes and Render Ending address their own placement. Opening a review flushes the current prompt and timing authority together, carries the exact owner and executable recipe, and adds no attempt until confirmation. A failed draft save prevents paid review/submission using stale text and offers retry from the segment card. Failed or in-flight alternatives do not replace selected media.
- Extend Scene reuses the row's AI/Frame/Footage picker inside the modal. Frame Creator returns to that Shot. New Version opens a successfully persisted independent copy; changing Shot identity resets player selection and focus. Whole-chain regeneration is a secondary action with a complete estimate, distinct from generating one take.
- Historical renders remain read-only with Edit Current Shot. Active Looks retain Edit Original. Choosing a narration model for the next run leaves current saved segments visible and explains the established whole-Shot narration workflow. Copy Video carries the selected immutable clip; Copy Frame Pair retains the existing structural clipboard behavior.
- Controls wrap as whole controls within the editor and timeline toolbars; action labels must not collapse into vertical fragments.

## Data, Inference, and Spend

- Project-local SQLite is the canonical structured state store. Persisted-format changes use explicit, tolerant migrations and stable project/artifact identities.
- Repeated text, image, video, audio, enrichment, evaluation, and agent workflows are incomplete until their full safe lifecycle is written to the shared inference trace store and inspectable through the established trace tooling.
- Traces preserve the exact provider-bound prompt, source/operator prompt when different, stable run and parent/group identity, workflow step, artifact identity, provider/model/parameters, request/response identifiers, status, latency, errors, usage/cost when available, parsed output, and safe media references or hashes.
- Secrets, access tokens, signed URLs, raw PII, and unnecessary binary media never enter logs or traces.
- Paid actions state their provider and expected price before submission, create durable spend/provenance records, and distinguish unpriced work from free work. Retrying a remote stage must not silently spend again.
- Continuation generation, Rechain, and generated-chain rebuild refuse provider submission when any requested link lacks a complete estimate. Every completed continuation clip remains reusable after later failure; retry resumes from unresolved work rather than regenerating successful links.

## Concurrent Work and Operational History

- Selecting another project changes the visible workspace without canceling or retargeting work. Each visited project retains its engine, selections, and unfinished view drafts. Refreshing the project registry must not tear down creative state.
- Independent Frames, Shots, character studies/sheets, narration and saved-output exports can proceed together. Busy indicators and mutation conflicts belong to the affected artifact. Shared queues admit up to eight image, three video, three text, two audio and two local jobs; request and encoder limits also constrain workflows that fan out.
- Confirmed requests are persisted before provider submission. Frame Creator closes after its submitted batch has been durably accepted. Repeated clicks on the same in-flight request must not spend again. Completion reconciles with the owning project's current documents and retains completed sibling artifacts.
- LOGS lives in a compact utility navigation at the far right of the main navigation bar. Its nonmodal panel opens beneath that bar, occupies approximately 60% of window width and 90% of available height, and leaves uncovered workspace interactive. Close and Escape dismiss it.
- Logs defaults to all projects and preserves filters across project switches and closing/reopening. Project, status, provider, workflow and text searches query durable history. Active work appears first; older history loads in pages. Details expose steps, safe requests/prompts, model and provider identifiers, and linked spend estimates when recorded. Unknown cost remains unknown. Saved Scene Plan versions remain accessible under a project filter.
- Operational jobs/events share the canonical inference SQLite database in every build. Higher-level jobs group repeated steps; older inference clients receive a request-level job through the shared transport. Recording finalization, imports/scans, local exports, and inference workflows produce structured events rather than depending on scraped console output. Activity reads the same job lifecycle.
- Manual generation Pause is removed; playback and recording Pause remain. Quit/crash and vendor failures create explicit automatic pauses. Safe retrieval/rejected-request retries are bounded; funding and authentication failures pause the affected vendor queue immediately while unrelated vendors and local work continue.
- Continue is executable for a retained rejected request and refreshes its existing authentication scheme from current credentials. Queued work can be canceled; running jobs offer Stop after this step where remote cancellation is unavailable. Existing artifact-specific cancel/resume controls retain their provider semantics.
- Relaunch does not automatically recreate a paid submission. Known resumable Look jobs use existing provider request identifiers; ambiguous acceptance requires checking the saved request and provider before retry. Other interrupted jobs retain their saved request and open the original artifact for review of current inputs, capabilities and pricing. Completed media can use the existing local repair paths.
- Resetting a project's creative database is blocked while that project has unfinished operational jobs, because background completion could repopulate or corrupt reset state. This destructive-state prerequisite does not block unrelated projects.

## Validation and Compatibility

- Hard failures are limited to invalid required persisted state, unavailable credentials/services, security or privacy risk, destructive operations, and impossible runtime prerequisites. Creative quality concerns remain soft warnings with repair, regenerate, review, or continue actions.
- Fixture-specific entities never become production inference rules. Generic behavior must survive renamed entities and materially different projects.
- Existing project documents decode tolerantly. New schemas are closed and versioned where strict provider output is required; all model-generated structured outputs validate before persistence.
- Saving a Shot publishes the exact canonical document successfully persisted. Append, ending and take selection preserve earlier selected media, placement order and numbered render history through save/reopen; normalization never silently drops a continuation-owned or referenced entry.
- Continuation and ending attempts must be saved before provider submission. A persistence failure cannot report generation success; completed local media retains a recovery recipe for repair without another provider call.
- Legacy missing continuation ancestors recover once from retained take ancestry. Related extension-only historical outputs appear as alternate Takes, retaining original artifacts and provider provenance; ordinary editing never reconstructs deliberately removed entries.
- Combined source boundaries begin independent sequences. Their first Frames cannot become ending targets for the previous source's continuation.
- AI continuation identity survives save/reload. Previously cleared markers recover from their continuation records without changing media or converting destination Frames into open-ended extensions.
- Historical AI-extension clips migrate deterministically into continuation take records without copying or converting media. Legacy adjacent rendered links retain lineage and tail-clip provenance; in-flight attempts reconcile as interrupted after relaunch.
- The supported development baseline is macOS 15+, Xcode 16.3+, and Swift 6.1+. The repository must pass its Swift build, full existing test suite, source-hygiene checks, and REUSE licensing validation.

## Release and Ownership Boundary

- This repository owns all shared Desktop source. Private consumers may pin a public commit but may not originate shared changes in their pinned checkout.
- Community is `AGPL-3.0-only`; trademark and official-build identity are governed separately. AGPL-compliant commercial use and redistribution remain permitted.
- Development, Community, and Official Commercial builds retain distinct names, bundle identifiers, preferences, credentials, storage roots, legal material, signing, and update configuration.
- Private services, Graph Review, full proprietary catalogs, official artwork/EULA/signing material, website infrastructure, and private operational logs do not enter this repository.

## Implementation References

- Scene Quick Extend — implemented and validated in the current working tree; commit hash pending explicit commit authorization.
- Scene Continuation Playback Chain — superseded by the independent continuation ownership correction below; historical media and migration support remain.
- Shot Continuations Without Automatic Versions — implemented in the current working tree; commit hash pending explicit commit authorization. See `plans/20260907T045527Z-shot-continuations-without-automatic-versions.md`.

- Shot Sequence UX and Ending Frames — implemented in the current working tree; commit hash pending explicit commit authorization. Timeline v0.5 decodes older takes without target snapshots.

- Shot State Preservation — implemented and validated in the current working tree; commit hash pending explicit authorization. Timeline v0.6 separates legacy recovery from new actions; see `plans/20260907-shot-state-preservation.md`.

- SCENES Newest Thumbnails First — implemented and validated in the current working tree; commit hash pending explicit commit authorization. See `plans/20260907T170751Z-scenes-newest-thumbnails-first.md`.

- Concurrent Project Jobs and Global Logs — implemented in the current working tree; commit hash pending explicit authorization. See `plans/20260907T171540Z-concurrent-project-jobs-and-global-logs.md` and the corresponding audit/work log.

- Shot Editor Paths — implemented and validated in the current working tree; commit hash pending explicit authorization. See `plans/20260907T183805Z-shot-editor-paths.md` and `docs/20260907T183805Z_shot-editor-paths.log.md`.

- Shot Prompt Assistance — implemented and validated in the current working tree; commit hash pending explicit authorization. See `plans/20260907T210509Z-shot-prompt-assistance.md` and `docs/20260907T210509Z_shot-prompt-assistance.log.md`.
