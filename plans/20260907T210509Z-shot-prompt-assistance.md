# One prompt field, two useful AI actions

Approved: keep the existing Shot editor, with one prompt field and a Render new take… action followed by small Improve · Suggest · Revert links. Remove Beats/Raw and Draft All Beats from Shot segment editors only. Improve preserves written intent; Suggest proposes a fresh direction from available segment context. Both replace the textarea with Undo; Revert restores the selected saved prompt (or initial direction when unrendered).

Show assistance progress and inline errors, allow continued typing, prevent duplicate segment requests, and require Apply/Dismiss when inputs or text change during the request. Closing the editor prevents late application. Assistance never changes saved media or an in-flight render. Use the existing text provider, queue and canonical trace transport with safe source/provider prompt, result/error and stable project/segment identity.

Preserve untouched legacy timing, display its compiled text, and make explicitly edited text authoritative for the next run with one atomic draft/mode save. Explain native multi-shot transition and restore previous state with Undo. Apply the shared prompt UI to modal and inline segment editors; no data reconstruction or schema migration.

Make the review presentation consistently cream with dark ink, including native editor/menu/Cancel controls, without changing the surrounding app. Verify actual nested row/modal review in light/dark appearance, assistance/revert/undo/failure/stale completion/close, concurrent video, save/reopen and exact paid review payload. Run existing tests/build/hygiene and package Development. No new repository tests, paid validation calls, commits or publication.
