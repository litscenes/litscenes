# Continuation thumbnail recovery

2026-09-07T14:37:54Z

Reproduced using the actual ShotFrameEntry source and the app's snake-case JSON strategies: an AI marker encoded as true decoded as false. This sends its row thumbnail to the missing library Frame placeholder, even when its continuation take owns playable media.

Correct the coding key, accept legacy literal camel-case keys, and recover previously cleared markers only where a durable continuation record exists and the entry has neither a Frame nor a Footage reference. No direct project database edits, media changes, or provider calls. Destination Frame identity is preserved.

Validation: the actual entry source now preserves true through the app JSON round trip and accepts the legacy camel-case key. Swift build and all 1,275 existing tests passed. Source hygiene, diff whitespace, Development packaging, and bundle signature verification passed. Interactive UI verification remains unavailable; no live provider call was made. The prior app bundle is retained by the packaging script under dist/.deprecated_ and may be deleted by the owner once no longer needed. No commit authorized.
