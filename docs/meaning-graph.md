# Meaning graph packs

The complete creative meaning engine runs in Desktop: concept and alias lookup, FTS5 candidate retrieval, incoming/outgoing relationships, evidence, aesthetic matching, frame poles and branching, and story/form prompt assembly and validation. Provider requests still need a personal key or an available Go account. Resolving graph context needs neither.

YAML is the editable source; SQLite is a compiled, disposable query cache. `MeaningGraphCore` is shared by the app and `MeaningGraphCompiler`. The bundled pack contains 1,529 concepts, 1,229 relationships, 1,545 evidence records, 708 aesthetics, 5,958 terms and 10,360 assignments. It includes citations/rationales and aesthetic source attribution; raw source texts, private curation history and reference images are excluded.

## Project controls

In STORY's Goal workspace, open **Meaning graph**. Select a base pack, import YAML, add installed overlays, enable/disable or reorder them, and choose **Preview changes**. Preview reports additions, changes and removals; invalid references, identities or schemas leave the current graph intact. **Apply to project** saves the configuration and refreshes free local context. It does not start new paid generation. Existing stories and frame generations retain graph provenance. **Revert edits** discards the draft; **Use bundled graph** previews restoration of the app's original pack.

Settings → Story Inference → **Meaning graph library** imports packs, downloads an official update on explicit request, and sets the default for newly initialized projects. Installing a pack does not activate it in existing projects. The update source is this repository's release manifest, with a pinned GitHub release asset URL, SHA-256 and size check. Updates need no app release. If a manifest or asset is unavailable, the installed graph remains usable.

Each project stores the identity of its graph sources (content hash, pack id, version, title, kind) and overlay ordering in its existing SQLite document store. The YAML itself is kept once per Mac, by content hash, under Application Support `meaning-graphs/sources/`; the bundled pack is read from the app by hash. Applying a graph atomically writes the current selection and graph history. Hashes include the engine version, base source and enabled overlays in order. Running jobs capture their own configuration, and the compiled cache can be rebuilt from the stored sources. A project whose source is not installed on this Mac says so and keeps its current graph until that YAML is imported or another graph is chosen. Documents written with inline YAML migrate to the shared store the next time the project opens. Inactive overlays do not change runtime identity.

The Goal interview receives a bounded choice packet from the project's graph: the brief's own concepts, concepts matched to the conversation, at least three of every concept kind, and aesthetic terms limited to the facets the Goal brief can hold (colour 24, motif 160, value 120, decade 40 at most), ranked by relevance to the conversation and then by how many aesthetics use the term.

## Base YAML format

Required header fields: `schema_version: litscenes.meaning_graph.v1`, `pack_id`, `version`, `title`, `generated_on` (date only), and `license`. Required tables are arrays, including empty ones: `nodes`, `edges`, `evidence`, `aesthetics`, `terms`, `assignments`.

| Table | Identity and references | Common content |
| --- | --- | --- |
| nodes | unique `id`, unique case-insensitive `slug`, nonempty `name` and `kind` | definition, aliases, tags, abstraction_level, positive_expression, negative_expression, boundary, examples, anti_examples, confidence_score, reuse_score |
| edges | unique `id`; source_node_id, target_node_id; nonempty relation_type; unique endpoint/relation tuple | strength, confidence_score, rationale |
| evidence | unique `id`; target_type (`node` or `edge`), target_id | context_type/id, role, rationale, weight, confidence_score, work_title/author, passage_id/index, section_title, source_url, rights_status |
| aesthetics | unique `id` | slug, title, description, aliases, categories, primary_rank, source_url, source_license |
| terms | unique `id` | slug, display_name, normalized_value, facet_type, color_family, color_hex |
| assignments | unique `id`; aesthetic_id, term_id | facet_type, rank, weight |

References must exist, including before disabled-record suppression. Optional fields stay optional; low confidence, sparse relationships and absent pole expressions produce warnings/fallbacks. Scores and weights are finite numbers from zero to one; ranks/indexes are nonnegative integers. Known text and text-array fields enforce their representation. Limits are 64 MB per YAML file and 32 nesting levels. Aliases, merge keys, duplicate mapping keys and complex mapping keys are rejected. Packs contain data only.

## Overlays

Overlays target a base `pack_id`. Each has its own stable namespace and version. Example:

```yaml
schema_version: litscenes.meaning_graph_overlay.v1
pack_id: studio.craft
version: "1"
title: Craft concepts
base_pack_id: litscenes.meaning
operations:
  - table: nodes
    action: add
    id: studio.craft:patient-practice
    fields:
      slug: studio.patient-practice
      name: Patient practice
      kind: theme
      definition: Repeated care develops capability over time.
      abstraction_level: thematic
      positive_expression: Repetition turns attention into skill.
      negative_expression: Repetition becomes an excuse to avoid change.
      tags: [practice, patience]
```

Operations are `add`, `override`, and `disable`. `add` IDs begin with the overlay's `pack_id` plus `:`. `override` supplies only replacement fields; arrays replace as a whole. IDs, original pack attribution and existing slugs cannot be overwritten. Use aliases or change the display name instead. A later explicit override re-enables a previously disabled record. Disabling a node also suppresses incident relationships and evidence; disabling an aesthetic/term suppresses its assignments. Re-enabling/removing an overlay recompiles from original data, so suppression is reversible.

Only one operation per table/ID is allowed within an overlay. Multiple enabled versions of the same overlay namespace are a conflict. Overlays may reference records added by earlier layers, and a later layer may disable an earlier layer's addition. An added relationship, evidence record or assignment whose target this configuration disables is a conflict, not a silent omission. Missing targets after changing a base version are surfaced in preview and never silently discarded.

## Build and verification

```sh
swift build --product MeaningGraphCompiler
.build/debug/MeaningGraphCompiler Sources/LitScenes/Resources/MeaningGraph/graph.yaml Sources/LitScenes/Resources/MeaningGraph/graph.sqlite
.build/debug/MeaningGraphCompiler --verify Sources/LitScenes/Resources/MeaningGraph/graph.yaml Sources/LitScenes/Resources/MeaningGraph/graph.sqlite
.build/debug/MeaningGraphCompiler --inspect Sources/LitScenes/Resources/MeaningGraph/graph.sqlite transformation
```

Pass overlay paths after the output SQLite path to compile a layered graph. Compilation validates before atomic replacement; a failure preserves the previous database. `--verify` rebuilds into a temporary file and compares provenance and every record with the bundled database, and checks the release manifest. App packaging and CI run it automatically.

Lookup resolves exact IDs/slugs before unambiguous aliases. Search weights name, alias, tags and definition with bounded FTS5 queries. Traversal is bidirectional and stable; divergent branching prioritizes contrasting and transforming relationships. Initial form selection uses actual abstraction levels, confidence/reuse and tension/degree scores. Aesthetic matching preserves source/facet/role weights and per-assignment rank normalization. Ties use stable identities where the previous service relied on implicit database ordering.

Context, frame selection, provider calls and validation outcomes use the canonical trace store, with project/run/group/parent IDs and graph provenance. Story and frame artifacts preserve the exact graph identity. Old documents remain readable without inventing historical graph versions. Source and provider-bound prompts, structured outputs and failures remain inspectable in Traces.

The implementation is uncommitted pending explicit publication authorization. Graph release assets must be published before **Download official update** can install this version. Bundled use is fully offline. Cloud service retirement is an operational cutover after Desktop release; it does not happen merely by editing this repository.
