# Repeated speed edits

2026-09-10T04:17:09Z Started approved repair. Shared-file edits target only Shot behavior; unrelated character work remains in the checkout.

# Reliable repeated speed edits

Implement the approved shared source resolver, stable scope references, material-ordered speed replacements, atomic composition validation and explicit failure/recovery. Recognize Original, selected continuation/ending, seed, Footage, whole-video fallback and Earlier cut sources.

Keep existing Speed controls, rates, audio and overlap rules. Preserve media, takes, independent razors, ordinary paste ordering, Undo and scope ownership. Legacy pairs recover only from matching saved provenance. No filename heuristics, database schema changes, paid calls, live-project repairs, commits or pushes.

Verify repeated, separate and adjacent edits in both directions across source kinds; cache refresh, missing media, changed takes, Undo/reload, scopes/branch/combination and preview/export. Use temporary diagnostics and existing tests; package Development. Preserve unrelated concurrent character work.

## Implementation and verification

2026-09-10T04:49:46Z Completed the approved repair.

- Added one active/retained source catalog for picture editing, including selected continuation/ending takes, seeds, saved full-video artifacts, and scope caches. Artifact retention remains tied to its own render version; review provenance permits evidence-based legacy cache resolution.
- Added optional scope references to cuts, copies and clipboard spans, with tolerant legacy decoding. Equivalent cache relocation resolves at playback without rewriting persisted edits or paid inputs. Branch/combination remap scope references and linked cut IDs. Combination now carries the picture replacements alongside its copied cuts.
- Ordered speed carriers by source segment and local range, including all-base-replaced cases. Ordinary paste run ordering remains unchanged.
- Validated candidate ordered picture coverage and fresh replacement output before persistence and audio ripple. Save failures and speed refusals reach the existing player status. Undo/Redo retains the compound edit.
- Runtime recovery removes only unavailable replacements' linked cuts from derived playback, exposing available base picture at 1× with a repair notice; independent razors and stored documents remain intact. Re-copy updates both pinned identities and validates the repaired sequence.
- Preview rebuilding creates its destination directory if absent.

Validation completed:

- `swift build` passed. Existing unrelated compiler warnings remain.
- `swift test --no-parallel`: 1,287 existing tests passed after the final source change. No repository tests were added or modified by this feature.
- 89 temporary native model checks passed: repeated separate/adjacent edits in both directions, all six orders of three adjoining sections, cross-segment selection, continuation, saved full-video, Footage, nested scopes, branch/combine, retention, Undo/reload, equivalent cache paths, changed scope identity, legacy JSON, unavailable replacement and independent razor preservation.
- 18 temporary native engine checks passed: Original/continuation/ending selection, successive saves, correct duration and one audio ripple per action, Undo/Redo, overlap refusal without mutation, reopen then edit again, real AVFoundation export matching playback, source-media retention, editing within an Earlier cut, absent-directory cache rebuild, unavailable-speed fallback and explicit Re-copy repair.
- The temporary export harness was compiled with the app's Swift 6 mode and macOS deployment target. Initial harness-only issues from incompatible compiler mode and invalid fixture setup were corrected before accepting the native result. The absent cache directory revealed a real recovery prerequisite, fixed and reverified above.
- `scripts/check_source_hygiene.sh` and `git diff --check` passed. REUSE executable was unavailable.
- Development app packaged successfully. Strict/deep code-signature validation passed; packaged Mach-O text matches the validated executable (SHA-256 `312a78ed023cac0eaa09a8fcedd07a4110491f4f5e6f746ea32d8573c241a774`).

Limits and workspace scope:

Validation used isolated temporary projects and media; no live project was inspected or repaired, no paid generation ran, and the running app was not restarted. Existing complete pairs can recover from retained source identity; deleted replacement records or ambiguous provenance are not reconstructed. Unrelated character work and earlier staged ending work were preserved. No commit, branch, worktree, push, remote schema change, or private submodule update was performed. Commit reference remains pending explicit authorization.
