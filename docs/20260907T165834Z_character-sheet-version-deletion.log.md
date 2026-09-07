# Character sheet version deletion

- Approved plan: delete individual versions from browsing, retain historical files, select newest surviving sheet.
- Implementation in canonical public Desktop checkout; unrelated work preserved.
- Validation pending.

## Implementation

- Added per-version Delete Version menus and confirmation on the existing character sheet plate.
- Persisted project-level deletion markers and active replacement in one existing character-document save; old documents decode an empty marker list without a SQL schema change.
- Kept archived inventory, image bytes, per-version hashes, and historical traces. Version ordinals use the full archived order while browsing uses surviving versions.
- Applied a shared browsing projection to media/scene inventories and reference pickers; guarded active-version selection, source association, and future automatic reference inputs. Current character sources and pending Studio/chat attachments exclude deleted IDs without clearing unsent text.
- Protected deletion markers and replacement anchors against later planner saves based on pre-deletion snapshots. No provider prompts, models, inference schemas, or trace transport changed; no motivating fixture entities were introduced.

## Validation

- Final `swift build`: passed. An existing trailing-closure warning remains in unrelated shot-continuation code.
- Final `swift test`: all 1,275 existing tests passed. No new tests were written.
- Public `scripts/check_source_hygiene.sh`: clean.
- Private `scripts/check_public_desktop_hygiene.sh` against the pinned checkout: clean.
- `git diff --check`: clean in both repositories.
- REUSE executable is not installed, so REUSE validation was unavailable.
- Reviewed inactive/active/final-version transitions, legacy decoding, reload/rescan data flow, stale-save protection, pending-input cleanup, and retained historical media paths in source. Interactive macOS click-through and injected persistence-failure scenarios were not exercised.
- No paid provider calls, commits, branches, publication, remote schema changes, or private submodule pin updates.
