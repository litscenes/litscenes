# Scene Quick Extend

## Outcome

Implemented the approved SCENES v2 continuation workflow in the canonical public Desktop source. Every Scene now ends with a named START SCENE / EXTEND SCENE cell. Nonempty Scenes can review and confirm one exact AI continuation without leaving SCENES; empty Scenes offer Create Frame with AI, Add Frame, and Add Footage from the same tail surface.

No commit or push was made. The implementation commit reference in `docs/REQUIREMENTS.md` remains pending explicit authorization.

## Decisions and behavior

- AI review is ephemeral until confirmation and shows the exact preserved endpoint, only executable Native Extend and Out-frame choices, the active provider/model/duration/audio recipe, editable direction, and the complete estimate on the submit button.
- Ready Frames, ranged Footage, clean rendered Originals, and selected ready continuation takes are valid anchors. Active Looks, OUT edits, reverse, loop, arranged picture copies, stale chains, missing sources or credentials, and an active video operation produce specific locks and repair paths.
- Each attempt is a durable continuation take. Success retains its segment clip, terminal still, source anchor and fingerprints, provider request/trace identity, recipe, prompt, and lifecycle state. Failure, cancellation, and relaunch interruption do not erase earlier ready takes.
- The marker cell and Scene Versions plate use the same take browser. Preview does not mutate. Use restores a compatible saved Scene version, assembles already saved clips locally for $0, or stages a branch whose downstream links need Rechain.
- Staleness is derived from selected predecessor lineage. Rechain generates only stale links in order; REBUILD GENERATED CHAIN replaces ambiguous full rerender for dependent chains. Each completed link is retained so a later failure resumes at unresolved work.
- A strict one-link render omits unrelated missing generated segments. It can retain the requested paid take and then ask the existing render plan to finish earlier missing work, without a hidden provider call.
- Continuation submission, Rechain, and chain rebuild require a complete estimate in both UI and engine preflight.
- Historical extension clips migrate deterministically into take records, keep adjacent realized markers, recover render recipes and upstream clip lineage where possible, and lazily extract missing endpoints. Generated media remains immutable and is not converted to Footage or pruned.

## Trace and spend

Continuation requests use the shared video-provider trace path with `shot_continuation` workflow identity, stable take artifact ids, one Scene continuation group, and parent trace linkage to a generated anchor Frame, rendered source segment, or predecessor take when available. Submission ids are persisted at provider acceptance; success, failure, cancellation, and interruption remain inspectable through the existing render/take records and provider trace lifecycle. No provider call was made for validation.

## Validation

- `swift build` — passed.
- `swift test --filter ShotContinuationTests` — 12 passed.
- `swift test` — 1,274 passed.
- `scripts/check_source_hygiene.sh` — passed.
- `git diff --check` — passed.
- Fixture-term scan — no motivating screenshot names or ids entered changed production source; the only repository-wide `robot` matches are pre-existing generic taxonomy/catalog resources.
- `reuse lint` — not run because the local `reuse` command is unavailable; it remains configured in CI.
