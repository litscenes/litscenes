# Civitai model browser

Implemented in the canonical Desktop working tree. No commit or publication is authorized.

## Delivered

- One native grid/detail browser shared by the existing image and video generation surfaces; account-key gating, search/filter/favorites/pagination, version metadata and previews, independent mature-content choices.
- Explicit SD1/SDXL, Flux.2 Klein, WAN image, WAN 2.2 Comfy LoRA video, WAN 2.5 and WAN 2.7 payloads. Unsupported resource and ending-frame combinations remain unavailable.
- Exact-request Buzz quote confirmation, separate Buzz ledger totals, frozen recipe/version/seed provenance, last-confirmed defaults and legacy-compatible decoding.
- Safe lifecycle traces, stable submission identity, saved provider IDs, local cancellation semantics and Media Start Video recovery.

## Validation

- Civitai's current public orchestration OpenAPI and official developer documentation reviewed for payload, version, resource, service, pricing, maturity and idempotency semantics.
- Existing focused suite: 21 checks passed, including Civitai payloads, trace persistence, legacy stacks, spend and the affected Shot case.
- Complete existing suite after all production changes: 1,292 checks passed. The app compiled and signed successfully with indexing/debug symbols disabled to fit available disk space.
- The Traces app's actual getTraceDetail reader successfully read offline successful, failed and canceled Civitai records, showing prompt, workflow, artifact and outcome. No user trace data was used.
- Source hygiene and whitespace checks passed. REUSE CLI is not installed; the existing REUSE.toml covers new Sources/docs/plans files.

## Limits

No live authenticated catalog, quote, or paid render was exercised. Provider availability and account-specific restrictions still require runtime validation with the user's key. Unknown acceptance cannot be repaired by guessing; the UI directs the operator to Traces. There are no new test files, provider credentials in source, remote database changes, commits, pushes, or private submodule changes.

2026-09-16T00:38:10Z Final verification: complete suite passed all 1,292 tests in 6.877 seconds; both public-source hygiene checks and git diff --check passed. No live provider calls were made.
