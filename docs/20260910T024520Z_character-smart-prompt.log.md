# Character smart prompt

2026-09-10T02:45:20Z Begin approved implementation; see the matching plan. Existing source inspected, including session-only image drafts, persistent character description, sheet overrides, chat response schema, image/sheet submission snapshots, and trace transport.

## Implemented

- SMART PROMPT now leads the existing left column. It is directly editable and shared with chat. The separate image-prompt editor and rewrite field are removed from this flow; image controls show the composed framing prompt read-only. The reference-sheet layout prompt remains inspectable.
- Save Version, blur, chat submission, generation, and leaving the workspace checkpoint manual edits. Chat receives the full saved prompt, returns its complete revision, and retains changes outside the requested scope. A response based on an older revision becomes a proposal when newer edits or restores exist.
- Character documents hold immutable prompt checkpoints, active revision identity, revision source/summary/time, parent and conversation links, and generated-media revision links. History previews do not select; Use this version restores as a new checkpoint. Unrelated background saves preserve newer text and stable version numbering.
- Adoption retains existing description, signature elements, and directives in the initial shared text. Previous custom sheet override text is archived in history before it stops overriding the shared prompt. Old images and their hashes remain unchanged. History starts with retained state at adoption; pre-feature unsaved drafts cannot be reconstructed.
- Image and sheet actions snapshot the saved subject before their asynchronous task starts. Queue recipes retain the creative text and revision; output records and inspectors link generated media to that revision. The canonical trace store merges creative/version provenance into existing safe request JSON without replacing the exact provider prompt or source evidence.
- Shared image generation uses the composed prompt without the prior extra inference rewrite. Framing, study/reference descriptors, drafting, chat, and built-in sheet instructions follow subject form. Full subject text is prepended even when a custom sheet layout omits its description placeholder. Recognized previous built-in templates migrate; custom layouts remain intact.

## Validation

- Final `swift build` passed.
- Final `swift test` passed all 1,287 tests. Focused lifecycle checks cover adoption and JSON reopen, manual/chat updates, stale chat proposals, restore, stale background saves, output revision links, and a custom layout lacking a description placeholder.
- Counter-fixtures from materially different human and nonhuman projects preserve full creative text. Renaming their subjects does not change generic composition. No motivating screenshot names or distinctive imagery occur in changed production source; no keyword classifier was introduced.
- Temporary native SwiftUI captures at 560 and 800 point widths showed readable prompt text, version/history controls, and saved status without overlap. The preview harness was moved out of the test tree after use.
- The Traces app's actual reader loaded four isolated local validation records and confirmed exact provider-bound text, shared prompt/version, workflow, source hash, and artifact identity. These are local fixture records; no provider was called to validate rendering.
- Public source hygiene, private hygiene for both the pinned consumer and canonical working tree, and whitespace checks passed. REUSE CLI is unavailable locally.

Implementation remains uncommitted in the canonical public checkout. Existing staged Shot work was preserved. No branch, commit, merge, push, provider spend, remote schema change, installation, or private submodule pin change occurred. The running installed app has not been replaced.
