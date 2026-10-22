# Embedded meaning graph

Implementation follows the approved plan. Graph resolution runs locally; YAML packs and ordered overlays are pinned per project. Existing artifacts retain their snapshots. Validation is pending. No commit or push has been authorized.

2026-10-06T23:04:43Z Implementation and offline validation complete.

## Implementation and validation

- Added the shared Swift graph core/compiler, complete YAML and SQLite resources, indexed alias/FTS/traversal/evidence queries, aesthetic scoring, abstraction/pole selection, and divergent form branching.
- Replaced starter-only readers and the unused hosted meaning client. Personal and Go-funded story/form generation use native prompts/schemas through the existing generic provider transport; local context needs no provider key.
- Added project graph controls in Goal and pack installation/defaults in Settings. Ordered overlays support additions, overrides and reversible suppression; previews reject structural conflicts before activation. Project SQLite retains exact current and historical sources, and graph changes refresh local context without paid automation.
- Added graph identity to context/story/frame provenance and linked local selection, provider and validation traces. Exact provider-bound prompts and retry usage remain inspectable; historical artifacts are preserved.
- Swift build and all 1,348 existing tests passed with network access denied. Updated obsolete starter-only assertions; no new permanent test suite was added.
- Recompiling YAML exactly matches the bundled SQLite records and manifest. Temporary offline probes passed alias lookup, traversal, ordered overrides, additions, disabling, conflict rollback, stable IDs, malformed YAML rejection, base restoration and a renamed counter-fixture.
- A temporary program linked against the actual Desktop objects verified project reopening, exact source retention, graph history, artifact preservation, restoration, aesthetic contribution totals and permissive sparse graph progression.
- Both public source hygiene and private Desktop hygiene checks passed (including the unchanged pinned checkout); diff checks passed. REUSE is not installed locally, so its CI check remains pending. License inventory and REUSE resource annotations were updated.
- The new local resolve trace was read through the existing Traces app with HTTP 200; rendered content includes graph identity, workflow/artifact IDs and structured output. Validation used temporary databases; no paid provider call occurred. Provider acceptance/billing in a live account and manual Desktop UI interaction were not exercised.

## Release status

The implementation is uncommitted. No branch, commit, push, release asset, app publication or submodule pin update occurred. The public graph update URL becomes usable only after its declared release asset is published. The live meaning Lambda has not been shut down; cutover follows public app release and the final remaining-client audit.

## Readiness fixes (2026-10-22T17:53:19Z)

- Goal interview choice packet: concepts matched to the conversation with every kind topped up to three; aesthetic terms limited to the Goal facet types with per-facet caps, ranked by relevance then breadth of use. Brand and other non-Goal facets no longer appear.
- Graph sources: project documents and history keep identity only (hash, pack, version, title, kind, order). YAML is stored once per Mac under `meaning-graphs/sources/<hash>.yaml`; the bundled pack is read from the app by hash. Documents and library entries written with inline YAML migrate on open. A source missing from this Mac is reported and leaves the current graph intact.
- Compiler: an overlay addition that loses its target only to suppression in the same configuration is rejected; a later layer may still disable an earlier layer's addition.
- Tests: `MeaningGraphCoreTests` (compile, lookup, search, traversal, evidence, overlays, every rejected overlay shape, rollback, YAML hardening, aesthetic gating, term choices) and `MeaningGraphRuntimeTests` (legacy migration, bundled reuse, store-backed overlay compile and preview, Goal choice caps and kind coverage). A pre-existing trace-probe test now sets a busy timeout on its read-only connection; it had reported SQLITE_BUSY under the larger parallel suite.
- Build, 1,364 offline tests, bundled graph verify, source hygiene and diff checks passed. REUSE remains unverified locally. Still uncommitted; no release asset, publication or cutover.
