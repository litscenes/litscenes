# Character smart prompt

Approved: chat and manual editing share one visible subject prompt on the left, with durable version history. Image and reference sheet are separate generation actions using that prompt.

- Keep the existing character workspace and right-hand chat. Promote a single SMART PROMPT editor above sources and generated output, with saved status and a history browser. Move output-specific controls below it; remove the detached image text editor from this flow.
- Persist prompt checkpoints in the character document. Seed existing descriptions, preserve legacy sheet overrides for inspection, and retain immutable revisions for manual edits, chat, redrafts, and restores. Save on explicit save, blur, chat, generation, and leaving the workspace; avoid revisions per keystroke.
- Chat takes the current saved prompt as its full starting point and returns a complete revised prompt, not a change-summary fragment. Later manual edits or restores must survive an outstanding chat; save its result as a reviewable revision when its base changed.
- Keep generation settings and references independent of prompt history. Capture the submitted prompt version for each image/sheet and its trace, so later edits do not retarget a queued request. Restoring prompts never renders or alters existing images.
- Both output paths follow the shared prompt. Archive previous custom sheet overrides before adopting the new shared workflow; expose their text in history rather than silently deleting it. The sheet adds only its output layout; image framing and identity attachments must not assume humanoid anatomy.
- Use the current local document persistence and shared inference trace transport; no remote schema change or new provider workflow. Validate decoding/migration, revision restoration, concurrent chat updates, render snapshot provenance, and unrelated counter-fixtures without paid calls.
- Work in the canonical public repository, preserving existing staged Shot work. No commit, branch, push, install, or submodule pin change is authorized.
