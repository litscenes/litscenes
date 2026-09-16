# Civitai browser UI correction

2026-09-16T02:55:45Z

The supplied screenshots requested the Shot render-strip menu interaction in the current-shot/segment editor, a bottom-most Civitai browser entry, and readable modal colors.

Implemented shared model/duration menu content across those surfaces, preserving account and segment-shape availability rules, independent default/override writes, resolution, native audio, and reset behavior. Removed the standalone Browse/Length controls from that panel. Browser presentation stays outside native menu content and owns an explicit light background, foreground and control appearance. No provider calls or persistence changes are part of this correction.

Validation: swift build and all 1,292 existing tests passed with --disable-index-store -Xswiftc -gnone. Both source-hygiene scripts and git diff --check passed. REUSE CLI is not installed. No new tests, provider calls, commits, pushes or private submodule changes. Interactive appearance was not captured from a running app.
