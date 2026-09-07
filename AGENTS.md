# LitScenes Desktop Development

- Never merge to or push `main` without the project owner's explicit consent.
- This repository is the canonical source for shared LitScenes Desktop code. Do not develop shared Desktop behavior in a private mirror or pinned consumer checkout.

LitScenes is a local-first storytelling engine that turns personal media archives into story-aware video compositions. Its working thesis is:

finite meaning primitives + finite story primitives + a personal media archive + contextual interpretation = infinite story compositions.

The product's north-star questions are: what is a frame literally showing; what archetypal situation, symbols, value tension, thought, theme, transformation, and story beat does it support?

## Working Loop

1. Read `docs/VISION.md` and `docs/REQUIREMENTS.md` before material product work.
2. Before implementation, append the feature name, UTC timestamp, and intent to `docs/LOG.md`.
3. Record important decisions or resolved tensions in `docs/THOUGHTS.md` using shortened ISO-8601 timestamps.
4. Save an approved material plan under `plans/{short_datetime}-{title}.md`.
5. After implementation, update the human-facing requirements and work log accurately.
6. Do not create commits, branches, worktrees, merges, or pushes unless the owner explicitly authorizes them.

## Product and UX Discipline

- Inspect the existing screen, workflow, models, persistence, and provider wiring before proposing or changing a visible workflow.
- Extend established surfaces unless the owner explicitly approves replacing them.
- Distinguish displayed provenance, controls affecting the next run, executable provider capability, and locked future capability. Never present an option as selectable if it cannot run.
- For creative controls, specify where the control lives, its scope, its effect on existing artifacts, and how it persists.
- Quality, sparsity, confidence, and stylistic concerns are warnings with repair or continue actions. Hard blocks are reserved for invalid persisted state, unavailable prerequisites, destructive/security/privacy risk, or impossible execution.
- If the UX direction is unclear or the owner signals a mismatch, stop and repair the plan before editing.

## Engineering Laws

- Keep shared logic simple and functional where practical. Keep UI views thin and move reusable behavior into focused models/helpers.
- Keep imports at file scope. Preserve tolerant decoding for existing project documents and add explicit migrations for persisted format changes.
- Never log secrets, tokens, signed media URLs, raw PII, or full provider bodies that may contain them.
- Every repeated inference workflow must use the canonical inference trace store. Persist safe provider-bound prompts, workflow/run identity, provider/model/parameters, status, latency, errors, usage/cost when available, parsed outputs, and artifact provenance for success, failure, interruption, and cancellation.
- Provider controls and spend claims must be executable and honest. Preserve completed sibling artifacts when another provider or stage fails.
- Examples, screenshots, saved traces, and bug-report entities are fixtures, not production rules. Do not place their names, brands, places, props, emotions, or expected phrases into production prompts, regexes, fallbacks, or classifiers.
- Do not modify remote database schemas or make paid provider calls without explicit consent.

## Public-Source Boundary

- `Sources/` and `Tests/` must contain no private services, Graph Review source, official-commercial assets, credentials, development-era dated comments, personal operational identifiers, or retired QA-control interfaces.
- Proprietary catalogs and generators may contribute reviewed generated resources, but their implementation and raw sources remain outside this repository.
- Community, Development, and Official Commercial release identities remain distinct. Shared behavior lands here first; private consumers pin a public commit afterward.
- Run `scripts/check_source_hygiene.sh`, `swift build`, `swift test`, and `git diff --check` before ending material Desktop work. Also run REUSE validation when the `reuse` command is available.

