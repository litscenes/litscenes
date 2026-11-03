# Public meaning P2 repairs

Approved implementation scope: explicit avoidance across Story, Frame Context and initial/expanded Frame Forms; recovery when previous graph sources are unavailable; safe integer validation and decoding.

## Avoidance
Resolve IDs/slugs/aliases; avoidance wins conflicts before truncation. Filter selections, edges, evidence, form neighbors/top-ups/fallbacks and story meaning/tension. Add backward-compatible excludedMeaningNodeRefs and provider meaning_exclusions. Upgrade local context contract to v2 and affected prompt versions; refresh stale contract/Goal/hash locally without paid automation. Preserve saved forms, omit excluded parents as positive seeds. Empty eligible forms return warnings and local traces without provider calls; show persisted warnings with Review Goal beside Form controls.

## Recovery
Validate/read replacement first. Explicit comparison states: complete, unavailable(reason), no previous selection. Old-source failures permit Apply with honest warning and replacement counts/provenance; invalid replacements still fail. Preserve atomic saves, history, draft/project guards and free-only context refresh.

## Numeric safety
Validate rank, primary_rank, passage_index as finite non-negative Int-representable integers at pack/overlay loading and final compilation. Checked conversions in context, graph projection and manifest verification. Preserve historical tolerant integer/string/fractional decoding with default/nil on overflow. Failed imports/compiles preserve prior DB/selection; graph identities and cache format remain stable.

## Validation
Existing suite plus offline repros: avoidance order/alias conflicts, excluded neighbors/fallbacks, unresolved exclusions, stale same-pack context, empty catalog; required unrelated counter-fixture with entity renaming; missing old base/overlay, valid replacement, invalid replacement, normal comparison/history/concurrency; numeric extremes, malformed manifests and old cached responses. Verify safe local traces, build/test, bundled graph verify, hygiene, diff whitespace. No paid calls, remote migrations, commits, pushes or merges. Update requirements/work logs.
