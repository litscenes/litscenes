# Take draft consumption + honest canceled reel bakes

2026-10-03T11:07:53Z Started in the canonical public Desktop checkout.

## Findings (from the open project's document and job ledger, read-only)

- Take strip labels were correct: each take's clip stores the prompt that rendered it. The "Next take · based on Take N" editor showed the persisted draft authored while Take N was the base — the edit that had already produced Take N+1. Drafts were never consumed: the take render applied the draft only to a local shot copy, and the panel's close flush re-saved its in-memory copy.
- PLAY ALL: both picks were rendered. The second pick's bake was canceled twice within 7–10 s of starting (reel closed while baking). The running debug binary predates the concurrent reel-play-all fix that gates autoplay on the full bake batch; after a cancel the cut's state became nil, which the board hides, so the reel played the one ready cut without naming the missing one.

## Decisions

- THE CONSUMED DRAFT LAW: a draft is an unsent edit. When its render is dispatched, its recipe becomes the placement's override lanes (what the in-film take seeds from) and that one draft leaves the bank. Unsent drafts on sibling takes survive. Consumption lives in the engine at the dispatch persist (regular segment renders and continuation retakes), plus the panel drops its in-memory copy after handing the draft over.
- A bake canceled from Activity while the reel is open is a named, retryable board state; closing the reel still clears pending claims silently (the next open re-queues). The waiting notice counts ready cuts; the header turns rust when a reel plays fewer cuts than were picked.

## Result and verification

2026-10-03T11:12:18Z Implemented and verified.

- Production source: ShotTakeDraft.swift (applyingRecipe split into a shared projection; new consumed(from:) removes only the consumed draft), LibraryEngine.swift (consumeShotTakeDraft at the generating-version persist in renderShot; continuation retake removes the reviewed draft by end entry + base take; cancelReelBakes(reason:) and the Activity cancel passes one), FinalsReelModels.swift (ReelBakeState.canceled), FinalsReelLaneViews.swift (canceled board row, Retry Unfinished Bakes), FinalsReelPlayerView.swift (ready-count in the waiting notice, rust header when a reel plays fewer cuts than picked), ShotRenderPromptPanelView.swift (in-memory draft dropped after hand-over).
- swift build passed; swift test --no-parallel passed all 1,348 existing tests (20.5s); scripts/check_source_hygiene.sh clean; git diff --check clean. No new repository tests.
- The two drafts already persisted on the open project's segment remain in its bank until Revert is pressed on each take (the consumption law applies to renders dispatched from now on). The running debug binary must be relaunched to pick this up, together with the earlier reel-play-all gate.
- No commit, branch, publication, private submodule change, project-media edit, or paid call.
