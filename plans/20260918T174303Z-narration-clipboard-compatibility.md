# Repair narration Copy/Paste and feedback

Approved scope: implement only in LitScenes-Public; preserve concurrent work; no commits, publication, or provider calls.

Timeline Copy must publish the existing audio-region representation and its identifiable full narration take. Shot-row Paste Narration copies the whole take at zero with independent media; timeline Paste retains region edits. Resolve legacy narration-region clipboards through their source Shot and exact audio reference; unresolved origins get a visible repair instruction. Copy buttons, menus and keyboard commands confirm only verified clipboard writes. All rows refresh when clipboard ownership changes, and Paste uses one validation path for availability and execution with explicit refusal reasons. Preserve unrelated audio and text copy/paste.

Validate both copy surfaces and keyboard commands through an isolated native pasteboard, empty/populated destinations, legacy and cross-project payloads, missing files, repeat paste and undo/redo. Run existing tests/build/hygiene; verify the resulting public app bundle. The currently running app is from another checkout, so do not replace it or modify that checkout.
