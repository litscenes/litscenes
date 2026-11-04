# readme-meaning-graph

2026-11-04T01:26:53Z

## Decisions

- Figures are rendered from `graph.sqlite` by `scripts/render_meaning_graph_figures.py` (standard library only) into `docs/media/`; the README links the script so readers can regenerate them.
- Overview: concepts on a ring grouped by kind, every relationship a chord; four families (Expresses, Orders, Accompanies, Turns) with three validated hues plus dashed ink for Turns. Light and dark variants, switched with `<picture>`.
- Neighbourhood: `theme.shared-stewardship`, an editorial-original theme whose eleven relationships span eight kinds; pulses animate along each edge with SMIL, which GitHub renders inside `<img>`.
- Support section removed. Contributing keeps only Issues, the CLA state and Security.
- CI badge removed: main's workflow is red (hygiene job: ripgrep missing on ubuntu; build-and-test failing). Fixing CI is separate work.

## Verification

- `scripts/check_source_hygiene.sh` clean; `git diff --check` clean.
- Figures rasterised with headless Chrome; README rendered through the GitHub markdown API and inspected.
- Uncommitted; publication requires owner consent.
