# Shot prompt assistance

2026-09-07T21:05:09Z Started approved implementation; public checkout was clean. Diagnostic fixtures and source backups stay under /tmp.

2026-09-07T21:43:26Z Implementation and validation

- Replaced segment Beats/Raw and Draft All Beats UI with one shared direction editor in the modal and inline plan. The paid action reads Render new take…; compact Improve, Suggest, Revert and contextual Undo links own text assistance. Story Beats elsewhere remain unchanged.
- Improve includes the operator direction and preserves its intent. Suggest excludes it and uses available Frame descriptions/relationships, narration and executable segment settings. Responses validate as a nonempty structured prompt through the existing configured text client.
- Shared workflow admission and inference transport retain request, prompt, response, error, cancellation and artifact context. One segment cannot start duplicate assistance. Workflow records link to the owning Shot; provider traces identify the segment.
- Assistance does not change media. Typing remains available during requests. Changed text or segment inputs hold the result for Apply/Dismiss; closing rejects late application. Revert and Undo retain the previous draft and timing authority.
- Explicit edits save prompt and timing authority in one Shot transaction, including raw text equal to an old generated prompt. Untouched timed plans still compile with the current duration/model; Undo restores their authority. Removed obsolete local Beats bindings. The separate narration-video motion prompt retains its existing confirmation save.
- Scoped cream/dark-ink appearance to the continuation review, including native text editor/menu, labels, radio controls and Cancel, under a dark parent sheet or popover.

Validation:

- `swift build` passed; existing `swift test` passed all 1,274 tests. Source hygiene and `git diff --check` passed. REUSE CLI is unavailable. The existing unrelated trailing-closure warning in the shot-render path remains.
- Temporary compiled diagnostics exercised atomic saves, SQLite reopen, default-equal text, retained media/history/timing, Undo and duration recompilation. Generic sailboat and mountain-hiker contexts verified distinct Improve/Suggest contracts without fixture-specific production rules; the changed-source scan found no motivating fixture terms in new production logic/prompts.
- Offline intercepted responses exercised the real text client and engine: structured success, HTTP failure, duplicate rejection and cancellation. Actual Logs displayed each lifecycle and expanded the provider-bound direction, parsed result, model and identifiers from the canonical trace store.
- Native interactions exercised Improve, Suggest, Revert, Undo, Retry, Apply/Dismiss after typing or model changes, and closure before completion. The production Shot host displayed the three saved clips, passed the exact saved direction into retake review, and canceled without modifying takes. Review sheet and popover screenshots confirmed readable native controls under a dark parent.
- Development app packaged successfully at `dist/LitScenes Development.app`; strict deep signature verification passed. Previous package/iconset were retained as `dist/.deprecated_LitScenes_Development.app_20260907T213929Z` and the matching `.iconset_20260907T213929Z`; these obsolete build artifacts can be deleted.

Diagnostics and screenshots remain in temporary storage, outside the repository. No new repository tests, commits, branches, publication, schema changes, paid validation requests, or live-project data repairs were performed. Provider semantic quality was not evaluated with a paid live call.
