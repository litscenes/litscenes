# Use the actual video ending for every continuation

Approved implementation: extract the last visual frame with zero timing tolerances and no assumed frame rate. Respect selected footage ranges. Cache verified endpoints by extraction revision, source content fingerprint and range; retain actual extraction timestamps. Video sources must never silently fall back to an old poster or anchor.

Apply the shared preparation to appended ending Frames, AI Extend, new takes, Rechain and chain regeneration. Retakes retain their recorded predecessor, with a corrected endpoint shown in the existing review. Show a short notice if its image differs from the historical input. Submission must preserve the reviewed image and reject missing or changed sources before spending.

Preserve historical clips, prompts, input snapshots, selected takes and versions. No bulk data repair or database migration. True still starts are unchanged. Existing downstream stale/Rechain semantics remain.

Validate using existing tests and temporary native diagnostics: repeated appends and reopening; prior cached opening images; different frame rates, variable timing, nonzero starts and ranged footage; missing/changed media and cancellation; normalized provider inputs and readable canonical traces. No paid validation calls. Build, run source hygiene, package Development and record results without committing or disturbing unrelated work.
