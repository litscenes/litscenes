# Independent Desktop graph edition

Approved plan: ../plans/20261026T151848Z-independent-desktop-graph.md.

Implementation starts from 01b4b0a; publication remains separate.

## Completed edition

2026-10-26T17:57:49Z Implementation is complete in `feature/local-meaning`, based on `01b4b0a`, and remains uncommitted. The concurrent workflow fix is preserved.

- Pack `fa52672dbc8acd66`: 1,915 concepts, 1,775 relationships, 3,046 evidence records, 708 aesthetics, 5,958 terms and 10,360 assignments.
- All 206 pending concepts are resolved: 181 canonical additions and 25 aliases. Of 517 pending relationships, 304 are retained and 213 explicitly excluded (185 lack an accepted active endpoint; 28 fail semantic review). Archived or rejected material is not revived merely to enlarge the graph.
- The resolved baseline is 1,710 concepts. The 205 original concepts add 11.9883%; aliases, repairs and edges are not counted as original growth. The additions broaden care, work, play, ordinary beauty, privacy, shared memory and film grammar, including 24 scene roles, 24 beat functions and 22 transformations.
- Repaired 46 concept records, including all 43 placeholder families, and made 21 further field clarifications. Original canonical IDs/slugs remain unchanged. There are no isolated concepts or hierarchy cycles; the 239 semantic components are not forcibly joined.
- Added 258 editorial relationships and recovered source attribution, including 402 citations from older candidate records. Evidence includes 1,272 edge citations. Literary interpretations, original editorial ideas and refinements have distinct provenance; original additions do not invent extraction scores or literary authority.
- Removed scraped navigation/maintenance categories using captured source memberships: 36,776 category assignments became 4,795. All 708 eligible aesthetics and their original rank values remain.

## Desktop behavior

Graph execution, pack import, preview, activation and project history remain local. The prior bundled YAML is retained byte-for-byte; projects keep their chosen source by content hash, including across app upgrades. New projects use the new pack. Existing artifacts keep their original provenance.

Scene Story receives at most six selected concepts and eight direct relationships, distributed across selections with deterministic ranking. Definitions, expressions, boundaries and abstract editorial notes offer optional creative guidance. Evidence, source-specific relationship rationales and private review history stay outside this projection; user intent takes precedence. Existing structured trace transport captures the provider-bound result.

Executable Go/account/purchase paths, startup service configuration/announcements, hosted meaning credentials and live catalog fetching are removed. New generation uses personal provider accounts or the existing compatible endpoint configuration. Historical managed funding and job data remain readable; old jobs cannot silently switch payer or poll the retired service. Previously downloaded outputs remain available through verified local cache reads.

The 26 starter images are generated previews, with the same IDs and byte hashes as the previous browse catalog. Their portable references resolve to verified bundled PNGs. Purchased reference composites are excluded. Explicit legacy image references retain their hashes; missing cached references request a replacement instead of fetching or substituting an image.

Portable-app validation found and repaired two build-directory dependencies: Desktop resources and the vendored Phosphor icon bundle. Fonts, notices, graph/catalog data and images resolve inside `Contents/Resources`; the packager includes both required resource bundles. The vendored subset documents its resource-accessor adjustment.

README, requirements, graph format/behavior docs, catalog notices, dependency inventory, changelog and GitHub installer guidance now describe the independent Desktop experience.

## Verification

- Swift build passed. All 1,368 existing tests passed with network access denied after the final code changes. Existing tests were extended for old graph retention, image integrity and two distinct Story counter-fixtures; no separate test framework or new test files were added.
- Compiler verification compares the YAML, release manifest and every compiled SQLite record. Source SHA-256: `932c8fbb36eeef1b837cf5688be6171897d5776465c1c118610e29957047d068`. Effective engine hash: `6bb9e74e7863628818016f3044bbd7410306a654c1e9f815a50cc47939893a4b`.
- Source hygiene, shell syntax, installer help, whitespace checks and strict ad-hoc app signature verification passed. REUSE CLI is unavailable in this environment; its check was not claimed. Existing SPDX declarations cover the new source/resources; asset/dependency notices were updated.
- A copied development app ran against an isolated library with network access, personal credential files and the entire public source/build checkout denied. Fresh setup, reopened projects, graph preview and the 26-image style browser worked. The catalog notice URL resolved inside the copied app; fonts and icons rendered correctly.
- Native Logs/Traces displayed a copied test-only trace database with exact safe request data, workflow/artifact links, provider request identifiers and outcome events. No paid provider call was made. Existing offline tests exercise local editing/export and mocked provider lifecycle behavior; a live paid end-to-end generation was not attempted.
- The two renamed Story fixtures appear only in tests, with no production-source matches. Production projection routes structural fields and enforces general bounds; it does not classify fixture-specific entities.

## Release boundary

No commit, push, merge, release upload, production deployment, remote schema change or cloud shutdown was performed. Official graph download remains unavailable until the manifest's release asset is published. Development packaging was validated; a signed/notarized distribution was not produced. The private integration submodule pin is unchanged. Prior local app/iconset builds were renamed with `.deprecated_` prefixes and may be deleted when no longer needed.

## Local commit authorization

2026-10-26T20:21:05Z The owner authorized committing all remaining public Desktop changes. The edition, original starter assets, packaging and provider migration are being recorded together after source hygiene, build, tests and graph verification. This supersedes the earlier no-commit boundary; publishing, pushing, merging, cloud shutdown and the private submodule update remain separate. Scenes V1 source is already recorded in `62a91aa`.

Commit preparation rechecked the complete working tree: build, all 1,368 offline tests, graph YAML/manifest/SQLite verification, source hygiene and shell syntax passed. Staging exposed an extra trailing blank line in the new provider setup view; it was removed before the final whitespace check.
