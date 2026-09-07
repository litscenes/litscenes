# SCENES v2 Quick Extend with Versioned Continuation Chains

> Superseded for continuation ownership and version behavior by [Keep AI Extend inside the current Shot](20260907T045527Z-shot-continuations-without-automatic-versions.md). This historical plan does not authorize automatic version creation.

## Summary

Replace the anonymous Scene tail slot with one START SCENE / EXTEND SCENE affordance. Continue stable tails through an executable Native or Out-frame path, make the rendered marker a real thumbnail, preserve every continuation take, and keep AI-on-AI chains honest through explicit branch impact, rechain, and guided rebuild behavior. The continuation registry is canonical; immutable Scene render versions reference take ids.

## Operator Workflow

- Empty Scenes offer Create Frame with AI, Add Frame, and Add Footage. Nonempty Scenes add Continue with AI as the primary action. Opening or canceling the popover does not mutate the Scene.
- Continue with AI previews the exact anchor, seeds an editable prompt, exposes only executable mode/model/duration controls, and prices the confirmed provider operation. Native is preferred when a valid tail clip of at least three seconds exists; Out-frame uses the exact terminal still.
- Ready Frames, ranged Footage, clean rendered Originals, and selected ready continuation takes can anchor without an intermediate whole-Scene render. Active Looks, shortened OUT points, reversed endings, trailing loops or arranged copies, and equivalent output transformations lock only AI continuation with a specific repair action.
- A confirmed render creates the marker. Its cell shows extending, ready, failed/interrupted, or derived rechain state; success replaces the dashed placeholder with the actual terminal frame and leaves the operator in SCENES with Play available.
- The cell and Scene Versions plate share a take browser. Preview is read-only. Use reviews downstream impact, restores a compatible saved branch or local assembly for $0 when possible, and otherwise stages the selected take while the last playable version remains active until separately confirmed rechain.
- Scenes with dependent continuation chains use REBUILD GENERATED CHAIN instead of an ambiguous re-render-all action. All prices are confirmed before submission, completed takes survive partial failure, and resume begins at the first unresolved dependency.

## Persistence and Rendering

- Add tolerant continuation anchor, take, record, and availability models. Store records on ProjectShot and link immutable ShotRenderSegmentClip snapshots to take ids and anchor fingerprints.
- Derive dependency compatibility from predecessor output and child anchor fingerprints. Do not persist a separate stale flag.
- Generalize Native input from placed Footage to an exact tail-video source representing Footage, a rendered segment, or a continuation take. Compile adjacent continuations sequentially and never fall back silently when lineage is missing.
- Keep all take records and successful media until a future explicitly confirmed storage-cleanup workflow. Do not convert generated continuations into ordinary Footage and do not automatically prune them.
- Migrate historical extension clips in place with deterministic take ids and lazy local endpoint extraction. Preserve adjacent markers with distinct lineage; collapse only legacy inert duplicates.
- Trace submission, polling, retrieval, success, failure, interruption, and cancellation with stable workflow/group/parent/artifact identity and safe media fingerprints.

## Validation and Delivery

- Cover pure availability, anchoring, migration, lifecycle, branch selection, staleness, rechain/rebuild, pricing, and non-spending Preview/Use behavior in the public test suite using provider fakes only.
- Run source hygiene, Swift build, the full Swift test suite, diff checks, and REUSE when available. Make no paid validation call.
- Leave the general render-plan layout and global disclosure preference unchanged. Publish the complete behavior as one release; update the private consumer pin only after a separately authorized public commit and push.
