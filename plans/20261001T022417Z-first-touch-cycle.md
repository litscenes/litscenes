# First Touch Cycle Refinement

Owner-approved doctrine for the cold-install first session, from stakeholder review of the current welcome, key setup, render status, and failure surfaces:

1. **Activation** — the first session must deliver a first rendered frame with three short-cutting verbs within reach: Animate, Restyle, Zoom Out. The welcome is a funnel to that moment.
2. **Key tiering** — setup reads as a two-key studio: OpenAI (understands media and story) and FAL (renders motion) as co-heroes, with ElevenLabs optional directly below as the voice key. The current single-hero claim understates the FAL dependency of default renders.
3. **Failure surfacing** — AI failures (analysis, render) land at the point of intent: on the media card or frame plate the user acted on, with a plain-language cause and one next action. No global health strip, no modal interrupts, no activity-center escalation.
4. **Credit exhaustion** — fail fast only. A billing/limit 429 is terminal, honestly worded, and never silently retried; no park-and-resume machinery and no balance gauge. The key probe must not report a limited provider as plainly verified.

## Phases

### Phase 1 — Honest 429s
- `CredentialProbe`: introduce a distinct outcome for HTTP 429 (auth passed, provider refusing work — throttle or exhausted balance) and render it honestly at all three probe surfaces: the welcome key row, the provider key sheet, and the settings credential row. The existing law stands: transport failures never read as a rejected key.
- Render path: verify where a FAL 429 at submit lands today; the frame record must transition to a failed state with the stored cause visible on the plate — never a perpetually active status. Fix any path that strands an active status.

### Phase 2 — Two-key studio setup
- `PersonalKeySetupView`: OpenAI and FAL hero rows, each with its provider key links; ElevenLabs optional row directly below; closing line keeps the promise that importing, browsing, editing, and exporting never need a key.
- `SelfServeOption` summary copy updated to match the two-key framing.

### Phase 3 — First-frame moment
- On completion of a render, surface Animate / Restyle / Zoom Out directly on or beside the completed frame plate, reusing the existing entry points (WAN animate, restyle flow, zoom-out stacks). Scope after tracing current anchors.

### Phase 4 — Status vocabulary
- Replace internal pipeline statuses leaking into first-touch surfaces ("preparing", "submitting"…) with stage language that promises correctly, and guarantee an immediate visible acknowledgment after Render Frame. Exact strings decided after reproducing the current sequence.

### Phase 5 — Analysis errors at point of intent
- A failed media analysis marks the media card itself with the cause and one action (retry, or open key settings when the cause is a credential).

## Verification
- `swift build`, full existing test suite, `scripts/check_source_hygiene.sh`, `git diff --check` before ending work. No commits, pushes, or paid provider calls without explicit owner consent.

## Outcome

- **Phase 1 — shipped.** The probe reports HTTP 429 as a distinct limited outcome at all three surfaces. The stuck state's verified mechanism was the shared transport's indefinite vendor hold (retry twice, then park on an unbounded continuation behind the LOGS panel, blocking every later job on that provider); provider refusals and unreachable-after-retries now throw a `ProviderFailure` carrying the provider's own body text, which the existing runner persists onto the frame row and the plate's failed card displays with RETRY. Acceptance-unknown submissions still pause for review — never auto-resubmitted. FAL's string `detail` body key now also surfaces in client failure summaries.
- **Phase 2 — shipped.** Two-key studio setup with per-provider key links and an optional ElevenLabs tier; self-serve summary copy matches.
- **Phase 4 — shipped (first pass).** Frame Creator hosts now pass the full render-blocker law to the modal, so pause/lane refusals disable Render with the reason instead of silently dropping the submission; "Preparing references…" shows only when composite sheets actually build; the shimmer caption no longer claims world continuity that Frame Creator takes do not attach.
- **Phase 5 — shipped.** A failed analysis marks the failing item: a rust badge with the cause on the library tile and a failure panel with the provider's explanation in the image preview, where the Analyze button is the retry.
- **Phase 3 — open, needs owner decisions.** On-card Animate / Restyle / Zoom Out requires resolving: Animate executes via CivitAI WAN (not a hero key) and its finished motion has no playback surface; the card's existing Animate play button is dead code (its `renderVersion == nil` condition never holds); new/completed cards land at the board's far end with no scroll-to or highlight (the NEW-ribbon + seen-set pattern from suggestion cards is reusable).
