# Make video actions follow what is being viewed

Approved implementation plan:
- One player action bar: Copy Take / Copy Full Shot / Copy Saved Render and Show in Finder target the displayed material. Remove duplicate card actions and Compare entry points; retain All Takes.
- Selected take thumbnails, metadata, saved prompt, input provenance and Next Take agree. In-film membership is separate; Use in Film is explicit and undoable.
- Full Shot returns cards to their in-film takes and actions to the exact edited film, including its audio. Prepare/cache a durable local file using the existing flattening path and output fingerprint; preserve provenance, reject stale completions, and preserve the clipboard on failure.
- Next Take inherits the inspected take's saved recipe, prompt and timing. Persist independent drafts per immutable take and placement, restore on switching/reopening, and initialize legacy in-film drafts from existing overrides. Render review/submission carry the explicit base and draft, including the original continuation input anchor. Do not silently substitute unsupported recipes.
- All Takes shares the selected take, including return to the main player. Preserve readable light/dark controls and increase tiny labels.
- Paste Video at End uses existing same-project row paste, plays immediately, preserves audio/provenance and supports Undo.
- Verify alternate-take copy/Finder/paste, exact full-shot export, draft switching/reopen and review, missing files and native interactions. Run existing tests, build and hygiene checks; rebuild Development. No paid calls, commits, pushes or submodule changes.
