# Scene Continuation Playback Chain

## Outcome

Repaired Scene continuation playback in the canonical public Desktop source. Extending a rendered Scene still appends one continuation cell to the same Shot row, but the selected continuation no longer replaces the Scene in the main editor: Play and export now retain the complete prior rendered Scene first and then play the selected continuation.

The already-created continuation-only version in the reported project requires no provider retry or direct database repair. Its saved continuation anchor identifies the prior ready render and selected take, so the corrected app derives the complete chain locally when the project opens.

No commit or push was made. The implementation reference remains pending explicit authorization.

## Decisions and behavior

- A rendered-original continuation anchor is authoritative lineage for the Scene that was reviewed. Its source render's ordered clip ledger becomes immutable, zero-cost plan material.
- If the historical source lacks a complete per-clip ledger, the prior whole render is retained as one fallback segment instead of retaining only its provider-context tail.
- Matching live generated or Footage slots are replaced by the saved source clips. Only the new continuation remains in the generation plan.
- Player, timeline bands, runtime, combined-cut copy, source-audio identity, export, and render assembly resolve the same preserved-source segment type.
- The selected continuation take is resolved from the take registry before the active whole-Scene version. This recovers a project whose active version contains only the new continuation clip.
- A future continuation render reuses the prior clips, generates the requested link, applies the established three-frame handoff trim, stitches the complete Scene, and activates only that complete version.
- Missing preserved source media is a hard preflight failure before artifact creation or provider submission; the app asks the operator to restore the source.
- No persisted schema change was required.

## Validation

- Reported-shape regression: a saved 15.042-second original followed by a 5-second continuation produces two ordered playback inputs and 19.917 seconds after the established 3/24-second handoff trim.
- `swift test --filter continuation` — 13 passed.
- `swift test` — 1,275 passed.
- `swift build` — passed.
- `scripts/check_source_hygiene.sh` — passed.
- `git diff --check` — passed.
- `scripts/build_litscenes_app.sh --channel development` — packaged `dist/LitScenes Development.app`.
- `reuse lint` — not run because the local `reuse` command is unavailable; it remains configured in CI.
- No paid provider call and no direct project-database write were performed.
