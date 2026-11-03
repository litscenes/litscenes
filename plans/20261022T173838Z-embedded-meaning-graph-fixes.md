# Embedded meaning graph: readiness fixes

Approved follow-up to `20261006T222617Z-embedded-meaning-graph.md` after review of the uncommitted implementation.

## Goal choice context

- Offer aesthetic terms only for the facet types the Goal brief can hold, each facet capped (colour 24, motif 160, value 120, decade 40). Rank by token overlap with the conversation and current brief, then by how many aesthetics use the term, then by stable identity.
- Keep bounded FTS concept retrieval, and top up every concept kind to at least three choices so no kind disappears from the interview.
- The ranking lives in `MeaningGraphCore`; the facet list and caps live in Desktop beside the Goal model.

## Graph sources by reference

- Project documents and graph history keep source identity only: hash, pack id, version, title, kind, and overlay order. YAML is stored once per Mac at `meaning-graphs/sources/<hash>.yaml`; the bundled pack is read from the app by hash.
- Documents written with inline YAML migrate on load: the YAML moves to the store and the document is rewritten lean. History documents stay readable.
- A source missing from this Mac blocks activation with a plain message; the current graph stays intact.

## Tests

- Permanent `MeaningGraphCore` tests on a synthetic pack: compile counts and degrees, id/slug/alias lookup, FTS search, plain and divergent traversal, evidence, overlay add/override/disable, every rejected overlay shape, failed-compile rollback, YAML alias and duplicate-key rejection, aesthetic gating and ordering.
- Desktop tests: Goal choice caps and kind coverage against the bundled graph; legacy source decode and migration.

## Story generation hang (added after the manual pass)

- The first-Stories task was spawned from the Scene Plan save inside the Scene Plan job and inherited its task-local workflow context; one second later that job finished, and the story's first provider call waited forever for admission to it. No request reached the provider.
- Coordinator: an inherited context whose job is no longer live counts as none. `run` starts a fresh job, `WorkflowHTTP.owned` opens one, and the provider gate fails fast with a plain message.
- Desktop: every automatic follow-up task starts through one helper that clears the workflow context and billing snapshot task-locals.
- Tests cover the three coordinator paths with a five-second bound so a regression fails instead of hanging.
- The trace store's writer connection gets a busy timeout; a transient reader lock no longer fails a provenance save and the provider request behind it.

## Out of scope

- Category navigation residue, constant `primary_rank`, and citation markers in the aesthetic records belong to the private export generator and are not hand-edited in the public pack.
- The unreachable aesthetic-direction boost predates this work and is left for a product decision.
