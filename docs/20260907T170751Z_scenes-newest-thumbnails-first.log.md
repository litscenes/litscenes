# SCENES newest thumbnails first

2026-09-07T17:11:16Z

The approved choice is one date-descending list of source photos and generated Frames, followed by footage. Implementation is in the canonical public Desktop checkout.

Implemented newest-first interleaving of photos and Frames in the SCENES pool, using updatedAt for loading Frames and source modifiedAt for adopted photos. Preserved tile identity, deduplication, and footage placement. Swift build, all 1,275 existing tests, source hygiene and git diff --check pass. An isolated compiled inventory-function diagnostic passed loading/completion identity, concurrency, mixed photos, ties, missing dates, filtering order and serialized input reload. No interactive UI verification or paid calls. REUSE is unavailable locally. No new repository tests, commits, pushes or private submodule pin changes.

Implementation commit: pending explicit commit authorization. The pinned private checkout has not advanced.
