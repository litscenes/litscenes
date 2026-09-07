# Keep Scene Extensions in One Shot Playback Chain

> Superseded for continuation ownership and version behavior by [Keep AI Extend inside the current Shot](20260907T045527Z-shot-continuations-without-automatic-versions.md). This historical plan does not authorize automatic version creation.

## Summary

- Keep continuation ownership, thumbnails, and selection on the existing Shot.
- Preserve an already rendered open-ended source as a zero-cost playback segment before its generated continuation links.
- Generate only the requested continuation, then assemble and activate the complete ordered Shot.

## Implementation

- Derive an internal preserved-source segment from the continuation anchor's exact render version and segment lineage when the live plan no longer represents that source.
- Resolve selected continuation takes and preserved sources consistently for render reuse, player composition, export, and runtime.
- Recover existing isolated continuation versions from their saved lineage without paid work or direct project-database edits.
- Keep the prior complete render playable during generation and after failure; activate only a complete assembled version.

## Validation

- Cover a rendered single-frame source followed by one or more continuations, including recovery from an already isolated active version.
- Preserve multi-frame, Footage, retake, failure, and missing-source behavior without hidden generation.
- Run source hygiene, Swift build, focused and full Swift tests, and diff checks without a paid provider call.

## Assumptions

- Play means the whole Shot from its beginning; alternate takes remain behind their continuation thumbnail.
- Preserve the established duplicate-handoff trim.
- No commit, push, private-pin update, or live project-database mutation is authorized.
