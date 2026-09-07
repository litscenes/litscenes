# Shot sequence UX and ending Frames

Approved behavior:
- START SCENE when empty, ADD TO SCENE before saved playback, EXTEND SCENE afterward.
- History navigation highlights the previewed version; CURRENT restores the working sequence without mutating its selected takes.
- Enabled PLAY is clearly visible. Thumbnails open their timeline position paused; PLAY starts playback. Small row and modal actions retain source inspection and take management.
- Provenance describes models in the selected sequence, with ordered per-clip details, independently of NEXT render controls.
- A Frame appended after video is an ending target with RENDER ENDING. Review shows exact current endpoint and target Frame, executable paired-frame model, prompt, duration/audio and complete price. Generate only that clip into the same Shot, with takes owned by the destination placement; subsequent extensions use its actual output endpoint.
- Reuse independent take persistence, failure, local repair, spend and tracing. Add tolerant v0.5 target snapshot fields, preserving legacy media/history. Update planner, suffix discovery, Rechain, branching and Combine for Frame-owned takes.
- Validate build, existing tests, hygiene and diff checks; inspect development UI with local media where available. No new test files, paid provider calls, commits, publication, branches/worktrees or private-pin/schema changes.
