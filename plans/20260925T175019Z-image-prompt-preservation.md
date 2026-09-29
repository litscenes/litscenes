# Preserve full prompts first; add shortening second

## Delivery sequence

Implement and validate two independent diffs: first verified image limits and complete prompt provenance, then automatic OpenAI shortening only for verified over-limit requests. All image workflows are included; video is excluded. No commits, branches, pushes, releases, paid inference calls, or remote schema changes are authorized by this implementation task.

## First diff: constraints and preservation

Resolve constraints by actual provider endpoint, field and billing route after all composition and actual attachment selection. Store maximum, unit and evidence. Count Unicode scalar values for character limits. Verified maxima: direct FAL Nano Banana 2 50,000; Go image 10,000; FAL Outpaint 500 (empty allowed); Reve 2.1 4,000; MAI Image 2.5 5,000; Stability Ultra prompt and negative prompt 10,000 each; OpenAI GPT image create/edit 32,000. OpenAI Responses keeps its separate context contract. Flux, Seedream and CivitAI without verified maxima have no guessed ceiling.

Remove image composition, camera-turn and provider clipping, phantom defaults, and the character sheet override storage cutoff. Retain legacy configuration decoding without enforcing unverified prompt limits. Finalize image selection before producing a manifest; preserve actual attachment order and composite mappings and disclose omissions.

Add shared ImagePromptConstraint and PreparedImagePrompt types. Preserve authored, assembled, prepared and actually submitted fields distinctly, with exact transmitted text returned by adapters. Persist preparation before submission with additive optional workflow JSON. Keep provider request/trace IDs and structured failure provenance through success, failure, interruption and cancellation. Redact secrets and signed capabilities without dropping creative text. Historic uncaptured stages remain unknown.

Extend existing render and prompt disclosures with stages, counts, constraints and trace links. Saved instructions are distinct from successful output; clear stale rendering status on all terminal outcomes. Before the second diff, verified over-limit requests stop before image submission with full text retained and edit/change-model actions; unknown limits do not block.

## Second diff: shortening and disclosure

Use a dedicated structured OpenAI text request only when complete provider fields exceed verified constraints. Supply complete context, workflow purpose, maximum lengths and stable reference bindings. Return shortened prose, reference notes by stable IDs, any offending negative prompt, and a summary. The app owns IDs, order, roles, geometry and required structural instructions and validates the complete reassembled payload.

Allow initial generation plus one semantic correction. Invalid output, missing credentials, refusal, cancellation or mandatory structure too long stops recoverably before image spend. Never clip as fallback. Preserve the editable original; persist valid prepared text and reuse it on a compatible retry. Invalidate preparation when composition, references, model, billing route or constraints change.

Use compact project-neutral reference instructions with explicit creator edits taking precedence over established reference appearance. Preserve unspecified traits, custom templates and existing sheet layout. Trace shortening attempts and image lifecycle together, including usage and outputs.

Go's existing image-spend confirmation shows actual counts: Shortened X to Y characters, See what changed. The comparison is available before approval. Personal-key and automatic chat renders show the same notice during preparation without pausing. Keep comparison available during and after successful or failed runs. Preserve existing text-spend approval and uncertain-submission protections.

## Validation

Verify below/at/above boundaries, direct versus Go, unknown limits and legacy configurations, actual native/composite references, source/sheet/style roles, custom and nonhuman prompts, camera geometry, multipanel layout, Unicode and long labels, negative fields and empty outpaint prompts. Verify invalid rewrites and the one-correction ceiling, unavailable credentials, cancellation, duplicate clicks, edits during snapshot execution, retry and restart recovery. Preserve explicit provider length evidence for an explicit retry; generic 422 errors never imply length or safety and uncertain image submissions are never automatically repeated.

Use captured requests and mocked rewriting, include a materially different counter-fixture and rename-invariance check, and verify safe readable records in the canonical trace database and Traces UI without paid calls. Run existing relevant checks, swift build, swift test, public source hygiene and git diff --check. Update requirements and work logs. Existing generated artifacts stay unchanged.
