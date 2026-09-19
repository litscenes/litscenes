# Fix segment reuse and take-browser readability

Approved implementation: Copy Video → another Shot row → Paste Video Segment at End; Show in Finder on saved segment cards; readable Continuation Takes in both appearances.

## Implementation
- Preserve full same-project clipboard payload and distinguish saved clips from structural frame-pair copies.
- Register/reuse immutable footage and append a hard-cut placement plus provenance-bearing seed clip in one picture undo transaction. Whole files are reused; genuine ranges use local extraction. No paid calls.
- Expose paste on row and thumbnail menus; refresh and revalidate clipboard, project, media and target lock state. Report failures honestly.
- Reveal the exact selected in-film clip from the segment card using Finder, checking file availability.
- Keep the cream take-browser layout with explicit light appearance, dark ink, darker secondary text, 10pt minimum metadata, 11pt prompts and readable disabled buttons. Scope style changes to the browser and its confirmation dialog.

## Verification
- Existing Swift build/test suite, public/private source hygiene, whitespace checks and REUSE if installed.
- Check same-project saved-video and legacy frame-pair paste; empty/rendered destinations; ranges; source independence; reopen; undo/redo; missing media and failed persistence.
- Check Finder and take-browser sheet/popover appearance in light/dark states when interactive access is available. Package Development app and verify its signature.

## Boundaries
Canonical public checkout only. No new tests, provider calls, commits, pushes, branches, worktrees, remote schema changes or private pin updates.
