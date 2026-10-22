# Embed the complete meaning engine in Desktop

Approved implementation plan: move meaning lookup, traversal, evidence, aesthetic matching, and story/form orchestration into the canonical public Desktop repository. YAML is the editable source, SQLite the query store, and Swift the runtime.

## Data and runtime

- Graduate all existing active provisional and reviewed-provisional meaning nodes and edges in one audited transaction. Preserve IDs, archive decisions, and before/after status records. No additional item-level approval is required.
- Export the complete active graph after graduation, with articulated nodes, relationships, source citations/rationales, and primary active aesthetic metadata and facet assignments. Exclude archived endpoints, raw corpora, review history, private images, credentials, and operational records.
- Build a public Swift graph core using Yams and SQLite3, a shared YAML compiler, bundled SQLite, indexed graph traversal, and FTS5 retrieval. Port deterministic resolution, evidence limits, aesthetic scoring, abstraction/pole selection, and divergent branching.
- Replace starter-only meaning readers with bounded candidate packets from the selected graph. Keep creative quality and sparse coverage non-blocking.

## Packs and project controls

- Support independently distributed base packs and ordered YAML overlays with stable identities, hashes, schema versions, and attribution.
- Overlays add namespaced records, override explicit fields, and reversibly disable records. Later overrides win; arrays replace; IDs and existing slugs stay stable. Disabled nodes suppress incident edges/evidence.
- Put project graph controls in STORY and installed packs/defaults in existing Settings. Persist exact base/overlay sources and selection per project. Import/compile off the UI thread and activate atomically.
- Preview updates and conflicts before applying. Preserve graph snapshots for running work and historical artifacts; failed changes leave the active graph intact.

## Inference and cutover

- Resolve graph context without provider credentials. Use local Swift prompts/schemas and the existing personal or managed generic text transports for generation, preserving payer snapshots and recovery.
- Add backward-compatible graph provenance to existing context/result documents. Persist graph identity, selected context, prompts, attempts, outcomes, and artifact links in the canonical trace store.
- Cut over Desktop and the gateway, reconcile legacy jobs, verify remaining callers, and retire only the meaning Lambda. SMS/mobile/billing/rendering and private ingestion/curation remain.
- Update both repositories' guidance, requirements, licensing descriptions, and work logs. Public publication, commits, pushes, and submodule advancement are separate explicit-consent steps.

## Validation

- Verify export identities/counts, edge/evidence integrity, deterministic ranking, aesthetic scores, and form selection.
- Exercise offline resolution, overlays, update conflicts, rollback, project reopening, and artifact preservation with no paid provider calls.
- Run existing Swift checks, source hygiene, REUSE, and diff checks; do not introduce an unrelated new test suite.
