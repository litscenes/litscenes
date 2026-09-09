# Shot progress, Logs and Frame navigation

Implementation started. Approved plan: `plans/20260909T005543Z-shot-progress-logs-frame-navigation.md`.

Keep generated media and creative selections authoritative; operational progress belongs to workflow records and read-only presentation.

## Delivered behavior

- Added optional workflow/segment JSON fields and shared presentation helpers; project timeline format and media ownership are unchanged. Render, continuation, ending, retake, rechain/rebuild, narration, and local repair publish existing execution milestones.
- Interleaved persistent video tiles with input Frames; reused AI/Footage placements, exact segment focus, separate clip preview, current playback during retakes, honest pending duration, explicit interrupted/not-started states, and existing review/Logs recovery.
- Kept completed clips after failure and precise preflight/provider/local errors in the canonical workflow history. Fixed delayed-error and delayed-completion timing, safe plain-string FAL error trace capture, and live-versus-durable Logs search. Expanded details include source inputs when recorded and immutable output evidence.
- Frame browsing receives the displayed collection rather than rebuilding lens order. It retains semantic selection across filtering, separate versions, source-photo adoption, and identity groups; Shot browsing remains placement-based.

## Validation

- Native offline diagnostic used a synthetic landscape project with an intercepting provider simulator; six simulated submissions and zero real provider calls. Verified partial failure, exact loading-tile count/order, all segment stages, retained playable siblings, missing-only resume, continuation without a new Shot version, ending from the prior tail, middle-retake selection preservation, save/reopen equality, preflight error retention, structured provider errors, canonical prompt/error trace readability, interruption, cancellation, and late-event timing.
- Native Frame modal key events verified displayed order (including separately visible versions), live-filter wraparound, both arrow directions, source-photo adoption and its following position, and the text-editing guard.
- Native wide/narrow row screenshots and Logs inspection used isolated data. Checks and screenshots remain under temporary validation storage rather than entering public source or user projects.
- Existing suite passed with 1,281 tests. No repository tests were added. Build and source hygiene passed; REUSE executable is unavailable. Final diff check and Development packaging passed.
- Production additions contain no screenshot/diagnostic entities or creative heuristics. A structurally different duration-validation error exercises generic error projection alongside the plain-text provider rejection. No production prompt or generation recipe changed; provider/model names are existing product wiring.
- No commits, branches, worktrees, pushes, remote schema edits, paid verification calls, or live project repairs. Commit reference remains pending explicit authorization.

2026-09-09T01:59:28Z Final verification: 1,281 existing tests passed (18.356 seconds); source hygiene and diff checks passed. Native and durable Logs search both retrieve the recorded failure. Development app packaged at `dist/LitScenes Development.app`; the prior bundle/iconset remains under `dist/.deprecated_*` and can be removed when no longer needed.
