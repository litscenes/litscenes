# Consistent Shot progress, clearer Logs, and correct Frame navigation

Approved implementation plan:

- Keep one stable video tile per rendered segment, interleaved with its input Frames. Confirmed work shows preparing/queued/rendering/finishing states and becomes saved video in place. Continuation and Footage placements are not duplicated. Retakes retain current playback and established selection semantics.
- Show only confirmed generation work; reused media never appears to regenerate. Preserve completed siblings after failure, identify unstarted or interrupted work, and keep paid retry review and existing local repair paths.
- Share structured workflow/segment progress across Shot rows, editor cards, Scene status and Logs. Remove stale READY progress, distinguish local assembly, and separate playable runtime from pending additions. Segment thumbnail navigation uses exact placement identity.
- Improve all Logs with concise artifact/outcome/provider/settings/time/cost summaries and expandable Inputs, Result/Failure, Activity and Technical details. Retain actual terminal errors despite delayed events; safely project older records without rewriting them. Preserve pagination, filters, privacy, supported recovery and owning-project navigation.
- Frame detail navigation follows the live originating thumbnail collection, including filtering, source photos and separate versions, with stable selected identity. Preserve Shot placement navigation, wraparound and text editing keyboard behavior.
- Add backward-compatible optional workflow JSON fields and ephemeral presentation/navigation types. Do not modify project documents to repair presentation or change media, render history, paid execution decisions or continuation ownership.
- Validate in isolated data with temporary diagnostics, run existing tests serially, build, hygiene, diff checks and REUSE if available; inspect narrow/wide native UI and package Development.
- No paid verification calls, live data repair, remote schemas, new repository tests, commits, branches, worktrees or pushes.
