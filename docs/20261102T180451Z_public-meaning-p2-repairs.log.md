# Public meaning P2 repairs

2026-11-02T18:04:51Z Implementation started on existing feature/local-meaning branch; approved plan recorded.

2026-11-02T20:46:52Z Completed all three planned fixes.

- Canonical avoidance resolution handles aliases and conflicting roles; filters positive nodes, incident edges/evidence, Story meaning/tension and Frame Form fallbacks. Explicit constraints are preserved in prompts and traces. Local context v2 repairs old cached contexts without paid followups.
- Empty initial/expanded Form selection records a local result, preserves saved forms, shows persistent warnings and Review Goal, and makes no provider request. Expansion provenance uses the current Goal.
- Replacement preview validates the new graph independently, discloses unavailable old comparison, and retains existing atomic activation/history guards.
- Shared integer validation rejects unsafe rank fields in base packs, overlay fields and compilation. Context/graph readers and manifest verification use checked conversions.

Validation: build passed; 1,369 tests passed on the first full run. Subsequent parallel runs exposed the unchanged audio cancellation test's shared-scratch deadline race. That test passed alone; the remaining 1,368 passed together. Counter-fixtures cover different projects, renamed entities, alias/order conflicts, edge evidence and zero-spend initial/expanded forms. Offline probes verified missing base/overlay recovery, ordinary comparison, invalid replacement rejection, retained history, atomic compilation, numeric boundaries/legacy decoding, unresolved exclusions and stale same-pack context refresh. Trace detail pages rendered inputs, exclusions, graph provenance and local outcomes. Bundled graph verification, source hygiene and diff whitespace passed. No fixture terms were added to production source. REUSE is not installed.

No paid provider calls, remote schema changes, commits, pushes or merges. No changes to the other review findings.
