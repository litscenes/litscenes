# Keep AI Extend inside the current Shot

Approved implementation contract:
- Extend appends one cell without changing Shot identity, active render identity, or render history.
- Retakes stay behind their cell; Use changes playback immediately with stale-link warnings.
- History previews are read-only; NEW VERSION creates an independent editable copy reusing selected media and edit state.
- Generate and persist continuation clips independently of whole-Shot artifacts; preserve exact recipe, safe lifecycle traces, errors, and completed media.
- Player, export, endpoints, runtime, and reel use selected clips and the complete preserved prefix. Never substitute provider tail context for the original.
- Legacy migration preserves valid selections and all historical media. Rechain/rebuild retain completed work.
- Validate with existing tests and local media without paid provider calls. No commits, pushes, branches, remote schema changes, or private-pin updates.

This replaces the version-coupled behavior in the two earlier continuation plans.
