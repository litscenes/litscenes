# SCENES: newest thumbnails first

Approved implementation plan

- Combine source-photo and generated-frame thumbnails in the SCENES pool and sort by date descending; footage follows stills.
- Use generatedAt for finished Frames, falling back to updatedAt for pending or undated Frames. Adopted photos retain their original photo modifiedAt. Equal dates use thumbnail ID; empty dates sort last.
- Preserve existing deduplication and stable frame identity across completion. This is presentation-only; persisted plan and Scene order remain intact.
- Adjust existing ordering expectations and run Swift build/tests, source hygiene, available REUSE validation, and diff checks. Verify loading/completion, concurrency, ties, missing dates, filtering and reload without paid calls.
- Implement in the canonical public checkout. No commit, publishing or private pin update is authorized.
