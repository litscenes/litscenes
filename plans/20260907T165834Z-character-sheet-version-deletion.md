# Delete individual character sheet versions

Approved implementation: add Delete Version to the existing thumbnail menus and right-click menus with a confirmation explaining the active-sheet consequence. Deleting the active version selects the newest remaining version; deleting the last clears its anchor and prompt hash. Preserve version numbering.

Persist project-level deletedSheetMediaIds in the existing character document, atomically with the replacement selection. Older documents decode an empty list. Keep inventory records, files, traces, and historical artifacts; filter deleted versions from browsing, pickers, and automatic reference selection. Clear pending attachments after a successful save, preserve unsent prompts, and leave state unchanged on save failure. Existing generation may finish using captured inputs without resurrecting deleted IDs.

Validate legacy decoding, selection transitions, numbering, reload/rescan persistence, browsing exclusion, pending-input cleanup, and existing artifact access. Run existing Swift tests, build, hygiene, and whitespace checks; REUSE if installed. No new tests or paid calls. Preserve unrelated work. No commits, pushes, branches, or submodule pin changes.
