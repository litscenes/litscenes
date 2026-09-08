# Clear character images and reference sheets

Approved implementation plan: preserve the existing character rail, central workspace, and conversation. Distinguish single character images from continuity reference sheets.

## Workspace

- Without usable references, hide sheet controls and lead with adding, uploading, or creating an image. Existing readable sheets qualify as references. Continue to Scenes remains available.
- Rename the source action Create character image…; always open and scroll to its inline editor. Generate image adds one image to Source Images.
- Follow current source images and ordering until the user customizes selection; offer Use current sources. Show actual attachments and capacity. The existing sheet is optional for single images.
- Consolidate sheet controls into a persistent Reference sheet bar with Generate reference sheet or Regenerate reference sheet. Preserve history and activate successful new versions for subsequent work.
- New characters render manually by default. Preserve legacy effective auto-render settings; label the opt-in Automatically regenerate reference sheet. Chat confirms saved instructions and offers the next action.
- Name running operations and failures accurately; prevent duplicate submissions for the affected character only.

## Models and inspection

- Save independent image and sheet model choices per character; Nano Banana 2 defaults when configured. Expose GPT Image 2 · OpenAI and other executable choices with accurate locks, prices, and reference capacities.
- Inspect original-resolution current and historical sheets with Fit, Actual size, zoom buttons, pinch zoom, and panning. Inspection does not activate historical versions. Reuse native image-viewing machinery.

## Implementation

- Add optional studyStackId alongside sheetStackId; migrate the previous shared choice independently. Preserve session drafts and custom prompts; refresh composed prompts when identity/references change.
- Snapshot submissions so later edits affect only future runs.
- Strengthen project-neutral continuity of hair length, cut, silhouette, and texture across all panels. Apply explicit requested changes consistently. Preserve decisions in chat and avoid promising visually verified outcomes.
- Place refinements and continuity before layout boilerplate, inspect provider-bound length limits, upgrade only retired built-in templates, and preserve custom overrides.
- Retain shared trace lifecycle, exact safe prompts, references, provider/model, outcomes, and artifact provenance.

## Validation and ownership

- Cover empty/source/existing-sheet paths, live additions and custom references, independent models, legacy decoding, manual/automatic chat, zoom and historical inspection, failures and duplicate submissions.
- Run existing Swift suites, source hygiene and diff checks; add required unrelated counter-fixture coverage for inference changes, including deliberate hairstyle changes. Do not make paid provider calls.
- Shared source lives in /Users/kvnn/Projects/LitScenes-Public. Record requirements and work logs. No commits, publication, or submodule changes are authorized. Separately generated panels/compositing are deferred.
