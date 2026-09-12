# Story scene type-checking

The owner supplied a build log from another Apple Silicon Mac. The blocking error is the compiler timeout at the Story card's scene-title Text expression. The cited deprecated APIs and ambiguous trailing closure are warnings, and this repair is scoped to the fatal expression.

Split the scene-title row and individual chip into typed helper functions. Materialize at most four titles, iterate their indices, and form an explicit String before Text(verbatim:). Retain all existing fonts, colors, spacing, truncation, ordering, and duplicate-title behavior.

The local toolchain is Apple Swift 6.1.2 targeting arm64 macOS 15. The remote machine's compiler/SDK version is not provided; successful local checks will not be described as an M5 reproduction. No new tests, commits, branches, pushes, provider calls, or consumer-pin changes are requested.

## Validation

2026-09-12T18:42:24Z story-scene-typecheck: completed uncommitted. Extracted scene-title row and chip helpers with explicit String labels and index iteration. Local Apple Swift 6.1.2 arm64 build succeeds; all 1,287 existing tests pass. Public source hygiene, private hygiene on canonical/pinned source, and whitespace checks pass. The remote M5 toolchain was not available for direct reproduction. No new tests, commit, branch, push, provider call, installation, or submodule update.

The required local checks passed. REUSE validation could not run because the CLI is unavailable. The nonfatal diagnostics shown in the report were not altered. Implementation commit hash remains pending explicit commit authorization.
