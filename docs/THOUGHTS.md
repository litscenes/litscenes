# Development Thoughts

2026-09-06T18:36:23Z A public repository becomes a trustworthy source of truth when its product contract, development discipline, validation boundary, and provenance live with the code; raw private work logs are an archive, not a substitute for that contract.
2026-09-06T18:36:23Z A per-file export manifest is truthful provenance for the immutable initial tag, but becomes misleading when left at the repository root after ordinary public development begins, so its scope must be named rather than silently regenerated.
2026-09-06T19:44:05Z A continuation take registry should own working take selection while immutable Scene render artifacts reference take ids; duplicating mutable take state in both places would let the strip and Versions plate disagree.
2026-09-06T19:44:05Z Continuation staleness is a consequence of anchor and predecessor fingerprints and should be derived rather than persisted as a second state that can drift.
2026-09-06T21:07:52Z A one-link continuation confirmation must omit unrelated missing generated segments rather than treating a partial-render filter as permission to spend on them; the completed take can remain durable while the Scene asks to resume its earlier missing work.
2026-09-06T21:07:52Z A paid continuation action with an unavailable or partial rate is not an honest confirmation, so both the UI and engine refuse submission until the complete estimate is available.
2026-09-06T21:07:52Z Historical extension migration should point at the actual upstream clip when one exists so lazy endpoint extraction, Native Extend, and parent trace lineage remain recoverable without converting the media.
2026-09-06T22:43:26Z A continuation anchored to an already rendered open-ended Scene must preserve that rendered source as the first playback segment; replacing its plan slot with the new link makes the extension look like a separate Shot even when ownership is correct.
2026-09-06T22:54:53Z The continuation anchor's render-version lineage must recover the complete ordered prior Scene, not merely the tail clip used as provider context; player, runtime, export, and local reassembly should all consume that one derived clip sequence.

2026-09-07T04:55:27Z Continuation selection is working state; whole-Shot render history must neither own that selection nor be created merely to persist a clip.
2026-09-07T05:30:42Z A continuation is a durable clip/take operation, while a render version is a historical whole-Shot artifact; routing per-segment continuation rerenders through the take owner prevents those identities from becoming coupled again.
2026-09-07T05:30:42Z Completed provider media and spend belong to the originating project even after the operator switches projects; local endpoint extraction and repair must not discard or resubmit that media.
2026-09-07T05:30:42Z Coarse video thumbnails are review placeholders, so Original and Footage continuation review must extract the actual terminal frame before confirmation.
2026-09-07T14:24:51Z The modal preview identity must differ from persisted render selection and from a file path, because CURRENT can contain added clips while sharing the same base path as a historical render.
2026-09-07T14:24:51Z A destination Frame owns a generated ending take without becoming an anonymous AI marker; planner and lifecycle behavior must follow its take record instead of the marker flag.
2026-09-07T14:24:51Z Existing suffix tests exposed that a historical render stamp alone is not a usable endpoint; ending conversion now requires readable rendered media and retains legacy missing-media planning.

2026-09-07T14:37:54Z The JSON snake-case decoder converts is_ai_extension to isAiExtension, so the original acronym key silently lost AI marker identity on reload; continuation records can recover empty-reference markers without touching media or destination Frames.

2026-09-07T15:34:53Z The underlying failure crossed decoding, destructive normalization, and publication of a pre-normalized in-memory document; lifecycle validation must compare the returned saved document with the real SQLite reload, not only constructed model values.
2026-09-07T15:34:53Z A combined source boundary prevents its first Frame from being inferred as an ending destination for the preceding source; the six-clip composition diagnostic verifies this constraint.

2026-09-07T16:58:34Z Existing rejected media can still appear in pickers; deleted sheet IDs need a separate project-level marker, saved with the active-sheet transition while historical files remain intact.

2026-09-07T17:05:58Z Scene planning can retain a roster snapshot across an await; character saves now preserve committed deletion markers and their replacement anchor so older work cannot resurrect a deleted sheet.

2026-09-07T17:07:51Z Loading Frames have empty generatedAt and a current updatedAt; sorting the combined still inventory by generatedAt with updatedAt fallback brings new renders forward while photo adoption retains its source date.

2026-09-07T17:15:40Z Project switching currently tears down mutable engine state, so navigation must switch retained runtimes before broad render locks can be removed safely.

2026-09-07T18:21:25Z Project selection was destructive because it loaded every project into one engine; retaining independent engines preserves both job ownership and existing view drafts without duplicating the creative persistence model.
2026-09-07T18:21:25Z A workflow can fan out into several provider requests, so workflow admission alone cannot enforce real capacity; shared request and encoder gates also bound resource use.
2026-09-07T18:21:25Z Unknown submission acceptance cannot be made retry-safe by a generic retry loop; these jobs remain under review while supported request-id retrieval and local repair keep completed work reusable.
2026-09-07T18:21:25Z Logs originally mixed session-only generation messages with selected Scene Plan versions; durable global jobs now supply activity while project-filtered versions remain a separate history section.
2026-09-07T18:21:25Z Creative reset is a justified hard gate for unfinished jobs in the same project because retained tasks could otherwise write into the newly reset document.

2026-09-07T18:38:05Z The editor conflates generation inputs with saved results; continuation recipe fallback also contradicts Shot-default override removal, so both display resolution and next-run intent must be corrected together.

2026-09-07T19:25:21Z Saved clip selection and generation inputs are separate authorities; one read-only media resolver now supplies editor Preview, Copy and provenance without rewriting the Shot.
2026-09-07T19:25:21Z A pending ending elsewhere in the Shot cannot own an earlier segment action; review routing now uses the requested placement after drafts have saved successfully.
2026-09-07T19:25:21Z Whole controls need to wrap within the modal columns; squeezing every control into one horizontal row made labels unreadable even when the underlying actions worked.
2026-09-07T19:25:21Z Native validation must enter copied legacy documents through the same canonical store-loading path as the app; direct raw JSON decoding does not represent the user-visible loaded Shot.

2026-09-07T21:05:09Z The fixed cream take-review background conflicts with inherited dark appearance; prompt assistance must also distinguish refining operator intent from proposing a fresh direction, and explicit text edits must atomically retire hidden timing authority.

2026-09-07T21:43:26Z Prompt assistance changes the next draft, while selected media and retained timing stay independent; the existing narration-wide confirmation still owns its separate prompt save, and Logs navigation uses the owning Shot while traces retain segment identity.

2026-09-07T23:22:27Z The source-row Generate action only opened an already-open editor; saved selections ignored later sources and a shared model picker hid its scope. The approved workflow names each output and preserves separate model choices.

2026-09-08T00:00:12Z Character chat previously stored a multimodal raw request whose safe prompt and artifact were not readable in Traces; explicit text/media summaries now retain exact creative provenance without binary payloads.

2026-09-08T00:00:12Z Prompt consistency is an instruction contract rather than verified image quality; explicit appearance changes outrank reference continuity, and independent panel generation remains deferred.

2026-09-08T00:45:26Z The character inspector opens at Fit in a modest sheet; the requested inspection experience instead starts at actual pixel size with a larger screen-relative viewport, while Fit remains an explicit option.

2026-09-08T01:34:34Z Analyze work already belongs to the library engine; its overlay prevents dismissal while running and only supports a completed pill, so minimizing can stay presentation-only by extending that existing pill to every run state.

2026-09-08T02:08:27Z Suggestion avatars currently resolve roster identities independently of provider attachments; camera directions currently mix image-plane compass headings with camera motion, while mode changes can save the wrong prompt draft. Shared structured intent must own both display and execution.

2026-09-08T02:42:12Z Structured character links, not avatar availability or prose punctuation, now determine suggestion image attachments; both surfaces show the same selection.
2026-09-08T02:42:12Z Native validation showed that adaptive paper colors still resolve differently in dark appearance; reframe editors therefore use explicit fixed ink, paper and caret colors.
2026-09-08T02:42:12Z Failed and canceled image requests need prompt and reference metadata before submission, so safe trace capture now precedes image-edit and Responses transport.

2026-09-08T03:25:27Z Continuation lineage is correct, but unrestricted AVFoundation image timing returned the opening frame for an ending request; cached stills then propagated that error. New takes must verify video endpoints without rewriting historical inputs.

2026-09-08T03:55:54Z Offline repeated append/render/reopen checks confirm correct predecessor identity and corrected final-frame inputs. Missing-video availability also needed to retain its video prerequisite, and local continuation traces needed links into Logs; neither repair rewrites historical media.

2026-09-09T00:55:43+00:00 Continuation progress currently reads a previous ready render artifact while ordinary renders lack a result tile; display state must distinguish selected saved media from the current attempt.

2026-09-09T01:57:00Z Shot progress must describe a confirmed operation independently of selected immutable media; a failed retake may coexist with a playable selected clip, while queued siblings have not started.
2026-09-09T01:57:00Z Native inspection caught an empty whole-video fallback during a first render; fallback tiles now require a recorded video path, and the isolated render diagnostic checks exact tile count while rendering.
2026-09-09T01:57:00Z FAL trace summaries lost plain-string error leaves; retaining safe string values fixes both plain and nested error evidence without creative-text rules. Live Logs search now matches the durable payload so newly saved outcomes remain findable.

2026-09-09T20:31:52Z Removing the arranged-output guard alone would allow existing Reverse, loops and OUT trims to transform or hide appended media; these edits need an explicit owning scope.

2026-09-09T21:34:08Z An ending must append outside existing output edits; editable preceding-cut scopes preserve OUT, Reverse, arranged copies, audio and Looks without hiding the original segment cards.
2026-09-09T21:34:08Z Review evidence must be immutable and cheap to pass through planning; sharing the evidence object avoids a worker-stack overflow without permitting provider provenance to change.
2026-09-09T21:34:08Z A missing derived earlier-cut cache cannot justify playing only later clips; playback waits visibly while local composition rebuilds from retained media and edits.

2026-09-10T02:45:20Z The detached image prompt protected manual edits by ignoring later identity updates; version history allows chat and manual edits to share one document without losing prior work.

2026-09-10T03:09:21Z Queued generation must capture both prompt text and revision before its task starts; merging later output links must preserve newer active revisions and their original order. Local regression checks and canonical trace-reader inspection verified those boundaries.

2026-09-10T04:49:46Z Speed used a razor plus a replacement copy, but freshness and retention omitted selected continuations and Earlier cut caches; one shared source catalog now governs both halves of the edit.
2026-09-10T04:49:46Z Adjacent speed replacements must resolve by source order even after all base keeps disappear; all six edit orders of three adjoining sections preserve ordered coverage.
2026-09-10T04:49:46Z Derived cache relocation is not a new creative edit; explicit scope references retain speed identity while a changed scope exposes available base picture and requires Re-copy.
2026-09-10T04:49:46Z Native validation confirmed that a missing cache directory must be recreated before exporting an Earlier cut; this now succeeds without modifying source media.
