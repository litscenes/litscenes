# Shot continuations without automatic versions

Implemented in the canonical public working tree; no commit or publication was requested.

- Split one-clip provider execution from whole-Shot rendering. Extend and retakes persist to continuation records, preserving the Shot and active render identity.
- Persist safe preflight/provider/finishing outcomes, exact recipes, submitted IDs, raw completed media, selected clip provenance, and canonical lifecycle traces. Local repair and resumable chain work retain completed clips. Spend follows the originating project.
- Select working takes independently of historical render artifacts. Historical player actions preview only. The dedicated take browser exposes Use, price-reviewed retries, stale-link Rechain, and saved-media Repair.
- Preserve the full source prefix and selected takes in the shared plan used by playback, runtime, export, and reel composition. Footage is materialized locally when its first continuation creates playable output without a render version. Export rejects a missing preserved source instead of silently exporting only a suffix.
- Copy continuation-bearing Shots with independent placements/edit state and shared selected media; carry selected continuation provenance through Combine. Migrate old projects tolerantly without overwriting valid take selections.
- Preserve unrelated unstaged governance, provenance, licensing, and CI work. Earlier version-coupled continuation plans are explicitly superseded.

Validation: final swift build, the full existing 1,275-test suite, source hygiene, and git diff --check passed. No new tests were written. No paid provider request or interactive end-to-end app/Traces verification was performed. REUSE was unavailable because the reuse executable is not installed.

No commits, pushes, branch/worktree creation, private-pin updates, or remote database schema changes.
