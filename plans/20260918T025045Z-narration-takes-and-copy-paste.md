# Narration takes, copy/paste, and independent video models

## Approved workspace boundary

All implementation, documentation, plans, and checks stay in this public checkout. Preserve unrelated changes. Do not modify the private integration checkout or its submodule pin. No commits or publication are authorized.

## Shot workflow

Keep the model picker visible in ordinary and LTX render panels. Show narration takes inline, newest first, with voice, duration, transcript, status, Active, Play, Use, and Copy. Preview does not select. Show takes after generation/paste and while reviewing a render. A successful generation becomes active; failed/interrupted attempts retain the prior usable take. Ordinary video models keep narration as mixed voice-over rather than provider input. Show accurate LTX duration errors and Open Narration; those checks never block ordinary models.

## Copy/paste

Copy one complete take with audio, script, voice, current speed, and provenance, excluding source-shot trim/placement/mix. Paste Narration is available on empty, collapsed, and populated shot rows and in the narration area. Support keyboard copy/paste without intercepting text editing. Paste an independent active take at zero, retaining destination history and mix. Copy audio into the destination project with independent paths and original lineage, without provider calls. Missing source files leave destination state intact. Paste is undoable; full audio survives absent/short video.

## Persistence and implementation

Add durable take IDs/history/selection and keep narrationArtifact as the selected compatibility mirror. Persist all attempt outcomes, including repeated scripts. Link actual speech and script traces separately. Tolerantly migrate the singleton without inventing historical audio. Use a typed system-pasteboard payload. Share activation logic across regions, playback, export, and LTX. Use retains destination placement/gain/mute and resets to full take; Paste starts at zero. Preserve output scopes, duplication rules, immutable source audio, distinct speed derivatives, and drafts across model changes. Update human-facing requirements and logs.

## Validation

Exercise preview/use/restart, failure/interruption, legacy migration, empty/populated/cross-project paste, repeat paste, undo/redo, missing media, independent speed edits, scoped snapshots, and model/duration boundaries. Run existing Swift tests/build/source hygiene/diff checks, plus REUSE if installed. Use local media without paid calls. Retain manual duration adjustment and visible voice-over overflow warnings.
