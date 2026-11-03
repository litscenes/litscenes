# Frame deletion in the source pool

2026-11-03T17:57:53Z User confirmed the preview closes successfully, but an imported-photo Frame remains in the source/Frame thumbnail pool. The callback works; the source-photo fallback resurrects its tile. Fix the inventory projection using existing persisted disabled adoption rows. Preserve original media and deliberate re-adoption. No button interaction change.

2026-11-03T18:01:34Z Completed the confirmed display/persistence fix. No delete-button gesture change.

- Both live pool callers now supply raw project Frame rows, retaining disabled adoption markers.
- Inventory suppresses a source photo when its adoption is deleted. Original Media remains intact; deliberate re-adoption restores the same row. An enabled legacy adoption still produces one tile.
- Raw inventory still excludes disabled Frames and unfulfilled plans from display. Existing Scene artifacts and source bytes are retained.
- Updated the existing pool expectation that previously required the deleted photo to return.

Validation: swift build --build-tests passed; 1,368 existing tests passed together and the known shared-temp audio cancellation test passed separately (1,369 total). Source hygiene and git diff --check passed. A disposable-project probe verified immediate disappearance, persistence after reload, unchanged original bytes, retained copied pixels, identity-preserving restoration, legacy live-adoption deduplication and planned-frame filtering. The old delete callback was also exercised in a disposable native preview, confirming the user's clarification that deletion itself succeeds.

Prior public-meaning fixes remain intact. No paid provider calls, schema migrations, commits, pushes or merges.
